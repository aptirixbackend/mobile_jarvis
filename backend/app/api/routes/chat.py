from fastapi import APIRouter
from pydantic import BaseModel
from app.core.agent import run_agent

router = APIRouter()


class ChatRequest(BaseModel):
    session_id: str = "default"
    message: str
    bot_name: str | None = None  # user's chosen name for their AI


class ChatResponse(BaseModel):
    session_id: str
    reply: str


@router.post("/", response_model=ChatResponse)
async def chat(req: ChatRequest):
    reply = await run_agent(req.session_id, req.message, bot_name=req.bot_name)
    return ChatResponse(session_id=req.session_id, reply=reply)
