from app.config import settings
from app.core.http import client

SARVAM_STT_URL = "https://api.sarvam.ai/speech-to-text"


async def transcribe_audio(audio_bytes: bytes, mime_type: str = "audio/wav") -> str:
    """Sarvam STT: audio bytes → transcript text."""
    ext = "wav" if "wav" in mime_type else "mp3" if "mp3" in mime_type else "wav"
    filename = f"audio.{ext}"

    # shared client: the connection is already open from the previous turn,
    # so there is no TLS handshake to pay for here
    response = await client().post(
        SARVAM_STT_URL,
        headers={"api-subscription-key": settings.sarvam_api_key},
        files={"file": (filename, audio_bytes, mime_type)},
        data={
            "model": "saaras:v3",
            "language_code": settings.sarvam_language,
            "with_timestamps": "false",
            "with_disfluencies": "false",
        },
    )
    response.raise_for_status()
    return response.json().get("transcript", "").strip()
