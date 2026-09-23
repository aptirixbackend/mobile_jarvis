#!/usr/bin/env bash
# Deploy the Jarvis backend to Cloud Run (asia-south1).
#
# Run it from Cloud Shell or anywhere with gcloud installed:
#     cd nova-ai && bash deploy/gcp-deploy.sh
#
# It is safe to run again — every step is create-or-skip, so this is also how
# you ship an update.
set -euo pipefail

PROJECT="${PROJECT:-}"                       # e.g. jarvis-470112
REGION="${REGION:-asia-south1}"              # Mumbai
SERVICE="${SERVICE:-jarvis-backend}"
BUCKET="${BUCKET:-}"                         # defaults to ${PROJECT}-jarvis-state
REPO="${REPO:-jarvis}"                       # Artifact Registry repo

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

command -v gcloud >/dev/null || die "gcloud not found. Install the SDK, or run this in Cloud Shell."

[ -n "$PROJECT" ] || PROJECT="$(gcloud config get-value project 2>/dev/null)"
[ -n "$PROJECT" ] && [ "$PROJECT" != "(unset)" ] || die "No project. Run: gcloud config set project YOUR_PROJECT_ID"
BUCKET="${BUCKET:-${PROJECT}-jarvis-state}"

say "Project $PROJECT · region $REGION · service $SERVICE"
gcloud config set project "$PROJECT" >/dev/null

say "Enabling the APIs this needs (first run takes a minute)"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  --quiet

say "Bucket for the database backup: gs://$BUCKET"
gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 \
  || gcloud storage buckets create "gs://$BUCKET" --location="$REGION" --uniform-bucket-level-access

say "Artifact Registry repo: $REPO"
gcloud artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1 \
  || gcloud artifacts repositories create "$REPO" --repository-format=docker --location="$REGION" \
       --description="Jarvis backend images"

# ── Secrets ────────────────────────────────────────────────────────────────
# Read from backend/.env so the keys never sit in this script or in shell
# history. Created once; re-run adds a new version only when the value changed.
ENV_FILE="$(dirname "$0")/../backend/.env"
[ -f "$ENV_FILE" ] || die "backend/.env not found — it holds the API keys this reads."

put_secret() {                                # name, value
  local name="$1" value="$2"
  [ -n "$value" ] || { echo "   (skipping $name — empty)"; return; }
  if gcloud secrets describe "$name" >/dev/null 2>&1; then
    local current
    current="$(gcloud secrets versions access latest --secret="$name" 2>/dev/null || true)"
    [ "$current" = "$value" ] && { echo "   $name unchanged"; return; }
    printf '%s' "$value" | gcloud secrets versions add "$name" --data-file=- >/dev/null
    echo "   $name updated"
  else
    printf '%s' "$value" | gcloud secrets create "$name" --data-file=- --replication-policy=automatic >/dev/null
    echo "   $name created"
  fi
}

read_env() { grep -E "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'"'"'\r'; }

say "Secrets in Secret Manager"
put_secret jarvis-gemini-key "$(read_env GEMINI_API_KEY)"
put_secret jarvis-sarvam-key "$(read_env SARVAM_API_KEY)"

# The shared token the phone sends. Generated once, then reused.
if gcloud secrets describe jarvis-api-token >/dev/null 2>&1; then
  API_TOKEN="$(gcloud secrets versions access latest --secret=jarvis-api-token)"
  echo "   jarvis-api-token reused"
else
  API_TOKEN="$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | xxd -p | tr -d '\n')"
  put_secret jarvis-api-token "$API_TOKEN"
fi

say "Letting Cloud Run read the secrets and the bucket"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
for s in jarvis-gemini-key jarvis-sarvam-key jarvis-api-token; do
  gcloud secrets add-iam-policy-binding "$s" --member="serviceAccount:$SA" \
    --role=roles/secretmanager.secretAccessor --quiet >/dev/null
done
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:$SA" --role=roles/storage.objectAdmin --quiet >/dev/null

# ── Build and deploy ───────────────────────────────────────────────────────
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/${SERVICE}:$(date +%Y%m%d-%H%M%S)"

say "Building the image (Cloud Build — no local Docker needed)"
gcloud builds submit "$(dirname "$0")/../backend" --tag "$IMAGE" --quiet

say "Deploying to Cloud Run"
# min-instances=1 keeps it warm, because a cold start on a voice command is
# painful. max-instances=1 keeps a single SQLite writer.
gcloud run deploy "$SERVICE" \
  --image "$IMAGE" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --min-instances 1 \
  --max-instances 1 \
  --cpu 1 --memory 1Gi \
  --concurrency 20 \
  --timeout 3600 \
  --set-env-vars "NOVA_STATE_BUCKET=${BUCKET},GEMINI_MODEL=gemini-3.5-flash-lite,SARVAM_LANGUAGE=en-IN,PERSONA_NAME=Jarvis" \
  --set-secrets "GEMINI_API_KEY=jarvis-gemini-key:latest,SARVAM_API_KEY=jarvis-sarvam-key:latest,NOVA_API_TOKEN=jarvis-api-token:latest" \
  --quiet

URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')"

say "Done"
cat <<EOF

  Backend URL : $URL
  Health      : $URL/api/health
  Token       : $API_TOKEN

  Build the app against it:

    cd mobile
    flutter build apk --debug \\
      --dart-define=NOVA_API_TOKEN=$API_TOKEN

  and set these two constants to $URL first:
    lib/core/api/nova_client.dart              baseUrl  ->  $URL/api
    lib/core/services/phone_control_service.dart  _wsUrl ->  ${URL/https:/wss:}/api/control/ws

  The URL never changes again, so this is the last time you edit them.

EOF
