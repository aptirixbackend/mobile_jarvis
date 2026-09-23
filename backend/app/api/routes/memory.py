from fastapi import APIRouter
from pydantic import BaseModel
from app.core.memory import get_memories, upsert_memory, get_history, clear_history

router = APIRouter()


class MemoryItem(BaseModel):
    key: str
    value: str


@router.get("/")
async def list_memories():
    return await get_memories()


@router.post("/")
async def save_memory(item: MemoryItem):
    await upsert_memory(item.key, item.value)
    return {"status": "saved"}


@router.get("/history/{session_id}")
async def conversation_history(session_id: str, limit: int = 50):
    return await get_history(session_id, limit)


@router.delete("/history/{session_id}")
async def clear_conversation(session_id: str):
    await clear_history(session_id)
    return {"status": "cleared"}
