import asyncio
import base64
from app.config import settings
from app.core.http import client

SARVAM_TTS_URL = "https://api.sarvam.ai/text-to-speech"

VOICES = {
    "female": ["priya", "neha", "simran", "kavya"],
    "male":   ["aditya", "rahul", "rohan"],
}

VOICE_LABELS = {
    "priya":   {"label": "Priya",   "desc": "Warm & friendly"},
    "neha":    {"label": "Neha",    "desc": "Professional & clear"},
    "simran":  {"label": "Simran",  "desc": "Soft & gentle"},
    "kavya":   {"label": "Kavya",   "desc": "Energetic & bright"},
    "aditya":  {"label": "Aditya",  "desc": "Deep & calm"},
    "rahul":   {"label": "Rahul",   "desc": "Friendly & warm"},
    "rohan":   {"label": "Rohan",   "desc": "Confident & professional"},
}

DEFAULT_VOICE = "priya"


async def _speak_chunk(chunk: str, speaker: str) -> bytes:
    resp = await client().post(
        SARVAM_TTS_URL,
        headers={
            "api-subscription-key": settings.sarvam_api_key,
            "Content-Type": "application/json",
        },
        json={
            "inputs": [chunk],
            "target_language_code": settings.sarvam_language,
            "speaker": speaker,
            "pitch": 0,
            "pace": 1.0,
            "loudness": 1.5,
            "speech_sample_rate": 22050,
            "enable_preprocessing": True,
            "model": "bulbul:v3",
        },
    )
    resp.raise_for_status()
    return base64.b64decode(resp.json()["audios"][0])


async def text_to_speech(text: str, speaker: str = DEFAULT_VOICE) -> bytes:
    """All chunks at once instead of one after another — a three-chunk reply
    now costs one round trip's wait, not three."""
    chunks = _split_text(text, limit=500)
    if len(chunks) == 1:
        return await _speak_chunk(chunks[0], speaker)
    parts = await asyncio.gather(*(_speak_chunk(c, speaker) for c in chunks))
    return b"".join(parts)


def get_voices_by_gender(gender: str) -> list[str]:
    return VOICES.get(gender.lower(), VOICES["female"])


def _split_text(text: str, limit: int = 500) -> list[str]:
    if len(text) <= limit:
        return [text]
    parts, current = [], ""
    for sentence in text.replace(". ", ".|").replace("? ", "?|").replace("! ", "!|").split("|"):
        if len(current) + len(sentence) > limit:
            if current:
                parts.append(current.strip())
            current = sentence
        else:
            current += " " + sentence
    if current.strip():
        parts.append(current.strip())
    return parts or [text[:limit]]
