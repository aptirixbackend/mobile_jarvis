import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes import chat, memory, voice, health, control, usage
from app.core.database import init_db
from app.core.http import aclose as close_http
from app.core import state_sync


@asynccontextmanager
async def lifespan(app: FastAPI):
    await state_sync.restore()      # bring the database back before opening it
    await init_db()
    state_sync.start()              # then keep copying it up in the background
    yield
    await state_sync.stop()         # last save on the way out
    await close_http()              # the shared keep-alive client


app = FastAPI(title="Nova AI", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# A shared token, because a public URL with no auth means anyone who finds it
# can spend your model quota — or drive your phone. Set NOVA_API_TOKEN and the
# app sends it as X-Nova-Token. Unset (local development) means no check.
API_TOKEN = os.getenv("NOVA_API_TOKEN", "")
OPEN_PATHS = ("/api/health", "/docs", "/openapi.json", "/redoc")


@app.middleware("http")
async def require_token(request: Request, call_next):
    if API_TOKEN and not request.url.path.startswith(OPEN_PATHS):
        sent = request.headers.get("x-nova-token") or request.query_params.get("token", "")
        if sent != API_TOKEN:
            return JSONResponse({"detail": "Not authorised"}, status_code=401)
    return await call_next(request)


app.include_router(chat.router, prefix="/api/chat", tags=["chat"])
app.include_router(memory.router, prefix="/api/memory", tags=["memory"])
app.include_router(voice.router, prefix="/api/voice", tags=["voice"])
app.include_router(health.router, prefix="/api", tags=["health"])
app.include_router(control.router, prefix="/api/control", tags=["control"])
app.include_router(usage.router, prefix="/api/usage", tags=["usage"])
