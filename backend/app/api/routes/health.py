from fastapi import APIRouter
from app.config import settings

router = APIRouter()


@router.get("/health")
async def health():
    return {
        "status": "ok",
        "persona": settings.persona_name,
        "llm": "gemini",
        "model": settings.gemini_model,
        "sarvam_language": settings.sarvam_language,
    }
