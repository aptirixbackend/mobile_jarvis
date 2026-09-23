# Cloud Run image for the Jarvis backend.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DB_PATH=/data/nova.db

WORKDIR /app

# deps first so code edits do not rebuild the wheel layer
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
# voice preview clips are served by the API, so they ship with the image
COPY data/previews ./data/previews

# the database lives here; state_sync restores it from Cloud Storage on boot
RUN mkdir -p /data

# Cloud Run sets $PORT; uvicorn must bind it on all interfaces
ENV PORT=8080
CMD exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --timeout-keep-alive 75
