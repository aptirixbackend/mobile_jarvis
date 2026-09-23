from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException
from app.core.phone_manager import phone_manager

router = APIRouter()


@router.websocket("/ws")
async def phone_ws(ws: WebSocket):
    """Persistent WebSocket connection from the Android phone."""
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
