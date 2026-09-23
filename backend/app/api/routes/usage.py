from fastapi import APIRouter

from app.core import usage

router = APIRouter()


@router.get("/")
async def get_usage():
    """Token counts: today, the last 7 days, all time, by model and by kind."""
    return await usage.summary()


@router.post("/reset")
async def reset_usage():
    removed = await usage.reset()
    return {"status": "cleared", "rows_removed": removed}
