from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import chat, memory, voice, health, control, usage
from app.core.database import init_db
from app.core.http import aclose as close_http


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield
    await close_http()          # the shared keep-alive client


app = FastAPI(title="Nova AI", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(chat.router, prefix="/api/chat", tags=["chat"])
app.include_router(memory.router, prefix="/api/memory", tags=["memory"])
app.include_router(voice.router, prefix="/api/voice", tags=["voice"])
app.include_router(health.router, prefix="/api", tags=["health"])
app.include_router(control.router, prefix="/api/control", tags=["control"])
app.include_router(usage.router, prefix="/api/usage", tags=["usage"])
