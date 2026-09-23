import os

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException
from app.core.phone_manager import phone_manager

router = APIRouter()


@router.websocket("/ws")
async def phone_ws(ws: WebSocket):
    """Persistent WebSocket connection from the Android phone."""
    # HTTP middleware never sees websockets, so the shared token is checked
    # here as well — this socket can drive the phone, so it must not be open.
    token = os.getenv("NOVA_API_TOKEN", "")
    if token:
        sent = ws.query_params.get("token") or ws.headers.get("x-nova-token", "")
        if sent != token:
            await ws.close(code=4401)          # unauthorised
            return
    await phone_manager.connect(ws)
    try:
        while True:
            msg = await ws.receive_text()
            await phone_manager.handle_message(msg)
    except WebSocketDisconnect:
        phone_manager.disconnect()


@router.get("/status")
async def control_status():
    return {"connected": phone_manager.connected}


@router.post("/execute")
async def execute_command(action: str, params: dict = {}):
    """Debug endpoint: send a raw command to the phone."""
    if not phone_manager.connected:
        raise HTTPException(status_code=503, detail="Phone not connected")
    result = await phone_manager.send_command(action, **params)
    return result
