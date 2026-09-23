import asyncio
from pathlib import Path
from fastapi import APIRouter, UploadFile, File, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel
from app.core.stt import transcribe_audio
from app.core.tts import text_to_speech, get_voices_by_gender, VOICES, VOICE_LABELS
from app.core.agent import run_agent

router = APIRouter()

PREVIEW_DIR = Path("data/previews")
PREVIEW_TEXTS = {
    # Female
    "priya":   "Hey there! I'm Priya. I'll be your Jarvis — warm, friendly, and always here for you.",
    "neha":    "Hello! I'm Neha. Clear, professional, and ready to help you get things done.",
    "simran":  "Hi! I'm Simran. Soft, calm, and here whenever you need me.",
    "kavya":   "Hey! I'm Kavya. Energetic and bright — let's make things happen together!",
    # Male
    "aditya":  "Hey there! I'm Aditya. Deep, calm, and always in your corner.",
    "rahul":   "Hi! I'm Rahul. Friendly and warm — think of me as your smart best friend.",
    "rohan":   "Hello! I'm Rohan. Confident, professional, and ready to help you out.",
}


class TTSRequest(BaseModel):
    text: str
    speaker: str = "priya"


@router.get("/voices")
async def list_voices():
    return VOICES


@router.get("/voices/{gender}")
async def voices_by_gender(gender: str):
    return {"gender": gender, "voices": get_voices_by_gender(gender)}


@router.get("/preview/{speaker}")
async def preview_voice(speaker: str):
    """Return a short pre-generated (cached) sample clip for a voice."""
    if speaker not in PREVIEW_TEXTS:
        raise HTTPException(status_code=404, detail=f"Unknown speaker: {speaker}")

    cache_path = PREVIEW_DIR / f"{speaker}.wav"

    if not cache_path.exists():
        PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
        sample = PREVIEW_TEXTS[speaker]
        audio_bytes = await text_to_speech(sample, speaker=speaker)
        cache_path.write_bytes(audio_bytes)

    return Response(
        content=cache_path.read_bytes(),
        media_type="audio/wav",
        headers={"Cache-Control": "max-age=86400"},
    )


@router.post("/preview/generate-all")
async def generate_all_previews():
    """Pre-generate all voice preview clips (call once after deploy)."""
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    results = {}
    for speaker, text in PREVIEW_TEXTS.items():
        path = PREVIEW_DIR / f"{speaker}.wav"
        if not path.exists():
            try:
                audio = await text_to_speech(text, speaker=speaker)
                path.write_bytes(audio)
                results[speaker] = "generated"
            except Exception as e:
                results[speaker] = f"error: {e}"
        else:
            results[speaker] = "cached"
    return results


@router.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    audio_bytes = await file.read()
    mime = file.content_type or "audio/wav"
    try:
        transcript = await transcribe_audio(audio_bytes, mime_type=mime)
        return {"transcript": transcript}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/speak")
async def speak(req: TTSRequest):
    try:
        audio_bytes = await text_to_speech(req.text, speaker=req.speaker)
        return Response(content=audio_bytes, media_type="audio/wav")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/process")
async def voice_process(
    file: UploadFile = File(...),
    session_id: str = Query(default="default"),
    speaker: str = Query(default="priya"),
    bot_name: str = Query(default=""),
):
    audio_bytes = await file.read()
    mime = file.content_type or "audio/wav"
    try:
        transcript = await transcribe_audio(audio_bytes, mime_type=mime)
        reply = await run_agent(session_id, transcript, bot_name=bot_name or None)
        audio_response = await text_to_speech(reply, speaker=speaker)
        safe_transcript = " ".join(transcript.encode("ascii", "replace").decode("ascii").splitlines())
        safe_reply = " ".join(reply.encode("ascii", "replace").decode("ascii").splitlines())
        return Response(
            content=audio_response,
            media_type="audio/wav",
            headers={"X-Transcript": safe_transcript, "X-Reply": safe_reply},
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
