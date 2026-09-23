import aiosqlite
from app.config import settings


async def get_history(session_id: str, limit: int = 20) -> list[dict]:
    async with aiosqlite.connect(settings.db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            "SELECT role, content FROM conversations "
            "WHERE session_id = ? ORDER BY created_at DESC LIMIT ?",
            (session_id, limit),
        ) as cur:
            rows = await cur.fetchall()
    return [{"role": r["role"], "content": r["content"]} for r in reversed(rows)]


async def save_message(session_id: str, role: str, content: str):
    async with aiosqlite.connect(settings.db_path) as db:
        await db.execute(
            "INSERT INTO conversations (session_id, role, content) VALUES (?, ?, ?)",
            (session_id, role, content),
        )
        await db.commit()


async def upsert_memory(key: str, value: str):
    async with aiosqlite.connect(settings.db_path) as db:
        await db.execute(
            "INSERT INTO memories (key, value) VALUES (?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=CURRENT_TIMESTAMP",
            (key, value),
        )
        await db.commit()


async def get_memories() -> list[dict]:
    async with aiosqlite.connect(settings.db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute("SELECT key, value FROM memories") as cur:
            rows = await cur.fetchall()
    return [{"key": r["key"], "value": r["value"]} for r in rows]


async def clear_history(session_id: str):
    async with aiosqlite.connect(settings.db_path) as db:
        await db.execute(
            "DELETE FROM conversations WHERE session_id = ?", (session_id,)
        )
        await db.commit()
