# mobile_jarvis

A voice assistant that can actually operate an Android phone: talk to it, and it
plays music, replies to messages, opens apps and works through screens on your
behalf.

```
Flutter app  ──WebSocket──  FastAPI backend  ──  Gemini (tools + chat)
   mic, chat, glow overlay        agent loop        Sarvam (speech in / out)
   accessibility service          fast intents
```

## How it does things quickly

- **One-shot intents first.** "play …", "call …", "open …", "set alarm …",
  "search …" map straight onto Android intents and never reach the model —
  about a second, and zero tokens.
- **Messages without opening apps.** A notification listener answers from the
  notification itself, the way a watch does. New chats use a contact lookup and
  a deep link with the text pre-filled.
- **The screen as text.** After every action the accessibility tree comes back
  as `"Play" [btn] (540,1120)` lines, so the model taps exact coordinates
  instead of studying a screenshot. Screenshots are a fallback for canvas and
  video screens.
- **Endpointing on the device.** Recording stops when you stop talking, judged
  against the room's own noise level rather than a fixed threshold.

## Running it

```bash
# backend
cd backend
python -m venv venv && venv/Scripts/activate      # or source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env                               # add your own API keys
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

```bash
# app
cd mobile
flutter pub get
flutter build apk --debug
```

The app talks to the backend over HTTPS, so for a real phone put a tunnel in
front of it (ngrok or similar) and set that URL in
`mobile/lib/core/api/nova_client.dart` and
`mobile/lib/core/services/phone_control_service.dart`.

## Deploying to Cloud Run

```bash
gcloud config set project YOUR_PROJECT_ID
bash deploy/gcp-deploy.sh                # build, secrets, deploy — run again to ship updates
```

The script enables the APIs, stores the keys from `backend/.env` in Secret
Manager, creates a bucket, builds with Cloud Build and deploys to
`asia-south1` with one always-warm instance. It prints the service URL, a
generated API token, and the two constants to set in the app.

Cloud Run resets the disk on every restart, so `state_sync.py` restores
`nova.db` from the bucket on boot and copies it back every few minutes — the
conversation history and token counts survive restarts without a database
migration.

## Permissions the phone needs

| Permission | Why |
|---|---|
| Accessibility — "Jarvis Phone Control" | reading the screen and tapping |
| Notification access — "Jarvis Messages" | reading and replying to messages |
| Contacts | "message amma" without opening the contacts app |
| Display over other apps | the glowing border while it is working |

## Layout

```
backend/app/core/     agent loop, fast intents, phone tools, speech, token usage
backend/app/api/      chat, voice, memory, control websocket, usage
mobile/lib/features/  chat, voice (talk button, service), settings, control
mobile/android/…/     accessibility service, notification listener, overlay
```

## Notes

- Keys live in `backend/.env` and are never committed.
- The backend has no authentication of its own — do not expose it publicly
  without putting something in front of it.
- Token usage is recorded per call and shown in the app's Settings screen.
