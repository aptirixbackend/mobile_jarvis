import asyncio
import json
from typing import Optional
from fastapi import WebSocket


class PhoneManager:
    """Manages the single WebSocket connection from the Android phone."""

    def __init__(self):
        self._ws: Optional[WebSocket] = None
        self._pending: dict[str, asyncio.Future] = {}
        self._counter = 0
        self._cancelled = False

    # ─── Connection ────────────────────────────────────────────────────────────

    @property
    def connected(self) -> bool:
        return self._ws is not None

    async def connect(self, ws: WebSocket):
        await ws.accept()
        self._ws = ws

    def disconnect(self):
        self._ws = None
        for fut in self._pending.values():
            if not fut.done():
                fut.cancel()
        self._pending.clear()

    # ─── Command / response ────────────────────────────────────────────

    async def send_command(self, action: str, timeout: float = 30.0, **params) -> dict:
        if not self._ws:
            raise RuntimeError("Phone not connected to Jarvis backend")

        self._counter += 1
        cmd_id = str(self._counter)
        cmd = {"id": cmd_id, "action": action, **params}

        await self._ws.send_text(json.dumps(cmd))

        loop = asyncio.get_event_loop()
        fut: asyncio.Future = loop.create_future()
        self._pending[cmd_id] = fut

        try:
            return await asyncio.wait_for(fut, timeout=timeout)
        except asyncio.TimeoutError:
            self._pending.pop(cmd_id, None)
            raise RuntimeError(f"Phone timed out on: {action}")

    async def handle_message(self, raw: str):
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return

        # Cancel signal from phone (user pressed Cancel in the overlay)
        if data.get("type") == "cancel":
            self._cancelled = True
            return

        cmd_id = data.get("id")
        if cmd_id and cmd_id in self._pending:
            fut = self._pending.pop(cmd_id)
            if not fut.done():
                fut.set_result(data)

    # ─── One-way notifications to phone (no response expected) ────────────────

    async def notify(self, event_type: str, **data):
        """Push a notification to the phone's overlay (task_started, task_ended, etc.)."""
        if self._ws:
            try:
                msg = {"type": event_type, **data}
                await self._ws.send_text(json.dumps(msg))
            except Exception:
                pass

    # ─── Cancel ────────────────────────────────────────────────────────────────

    @property
    def cancelled(self) -> bool:
        return self._cancelled

    def reset_cancel(self):
        self._cancelled = False


# Singleton — shared across the app
phone_manager = PhoneManager()
