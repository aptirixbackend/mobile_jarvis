"""Keep the SQLite file alive across Cloud Run restarts.

Cloud Run gives each instance a fresh disk, so conversations, memories and
token counts would vanish every time it restarts. Rather than migrating to a
managed database, the file is restored from a Cloud Storage bucket on boot and
copied back periodically and on shutdown.

That is safe here because the service runs single-instance (max-instances=1),
so there is only ever one writer. Worst case after a hard crash is losing the
minutes since the last upload.

Off unless NOVA_STATE_BUCKET is set, so local runs are untouched.
"""
import asyncio
import os
import shutil
import tempfile

from app.core.database import DB_PATH

BUCKET = os.getenv("NOVA_STATE_BUCKET", "")
OBJECT = os.getenv("NOVA_STATE_OBJECT", "nova.db")
INTERVAL = int(os.getenv("NOVA_STATE_INTERVAL", "300"))    # seconds

_task: asyncio.Task | None = None
_last_size = -1


def _client():
    from google.cloud import storage          # imported late: optional dependency
    return storage.Client()


def enabled() -> bool:
    return bool(BUCKET)


async def restore() -> str:
    """Pull the database down before the app opens it."""
    if not enabled():
        return "state sync off (no NOVA_STATE_BUCKET)"
    try:
        def _pull():
            blob = _client().bucket(BUCKET).blob(OBJECT)
            if not blob.exists():
                return "no saved database yet — starting fresh"
            os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
            blob.download_to_filename(DB_PATH)
            return f"restored {blob.size or 0} bytes from gs://{BUCKET}/{OBJECT}"
        msg = await asyncio.to_thread(_pull)
        print(f"[STATE] {msg}", flush=True)
        return msg
    except Exception as e:
        print(f"[STATE] restore failed: {type(e).__name__}: {e}", flush=True)
        return "restore failed"


async def save(force: bool = False) -> bool:
    """Copy the database up. Skips when nothing has changed."""
    global _last_size
    if not enabled() or not os.path.exists(DB_PATH):
        return False
    try:
        def _push():
            global _last_size
            size = os.path.getsize(DB_PATH)
            if not force and size == _last_size:
                return False
            # copy first: uploading a file SQLite is writing can tear
            with tempfile.NamedTemporaryFile(delete=False, suffix=".db") as tmp:
                snapshot = tmp.name
            shutil.copy2(DB_PATH, snapshot)
            try:
                _client().bucket(BUCKET).blob(OBJECT).upload_from_filename(snapshot)
            finally:
                os.unlink(snapshot)
            _last_size = size
            return True
        saved = await asyncio.to_thread(_push)
        if saved:
            print(f"[STATE] saved to gs://{BUCKET}/{OBJECT}", flush=True)
        return saved
    except Exception as e:
        print(f"[STATE] save failed: {type(e).__name__}: {e}", flush=True)
        return False


async def _loop():
    while True:
        await asyncio.sleep(INTERVAL)
        await save()


def start() -> None:
    global _task
    if enabled() and _task is None:
        _task = asyncio.create_task(_loop())


async def stop() -> None:
    global _task
    if _task is not None:
        _task.cancel()
        _task = None
    await save(force=True)
