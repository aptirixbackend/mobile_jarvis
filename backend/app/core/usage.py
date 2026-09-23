"""What each answer cost, in tokens.

Every Gemini call reports how many tokens went in and came back. Those numbers
are written here so the app can show a running total: today, this week, and
since the day it was installed, split by model and by what the call was for
(a chat reply, a step of phone control, an intent decision).

Writes are fire-and-forget: counting must never slow down or break an answer.
"""
import asyncio
from datetime import datetime

import aiosqlite

from app.core.database import DB_PATH

_ready = False
_lock = asyncio.Lock()

# ₹/₹ per million tokens, so the app can show money as well as counts.
# Override per model as prices change; unknown models simply show no cost.
PRICE_PER_MTOK = {
    "gemini-3.5-flash-lite": (0.10, 0.40),
    "gemini-3.1-flash-lite": (0.10, 0.40),
    "gemini-2.5-flash-lite": (0.10, 0.40),
    "gemini-2.0-flash":      (0.10, 0.40),
    "gemini-2.5-flash":      (0.30, 2.50),
}


async def _ensure() -> None:
    global _ready
    if _ready:
        return
    async with _lock:
        if _ready:
            return
        async with aiosqlite.connect(DB_PATH) as db:
            await db.executescript("""
                CREATE TABLE IF NOT EXISTS token_usage (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    at            DATETIME DEFAULT CURRENT_TIMESTAMP,
                    day           TEXT NOT NULL,
                    model         TEXT NOT NULL,
                    kind          TEXT NOT NULL,
                    calls         INTEGER NOT NULL DEFAULT 1,
                    input_tokens  INTEGER NOT NULL DEFAULT 0,
                    output_tokens INTEGER NOT NULL DEFAULT 0,
                    total_tokens  INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS idx_usage_day ON token_usage(day);
            """)
            await db.commit()
        _ready = True


async def record(response, model: str, kind: str = "chat") -> None:
    """Store one call's usage. Never raises."""
    try:
        meta = getattr(response, "usage_metadata", None)
        if meta is None:
            return
        pin = int(getattr(meta, "prompt_token_count", 0) or 0)
        out = int(getattr(meta, "candidates_token_count", 0) or 0)
        # thinking tokens are billed as output on the models that report them
        out += int(getattr(meta, "thoughts_token_count", 0) or 0)
        total = int(getattr(meta, "total_token_count", 0) or 0) or (pin + out)
        await _ensure()
        async with aiosqlite.connect(DB_PATH) as db:
            await db.execute(
                "INSERT INTO token_usage (day, model, kind, input_tokens, output_tokens, total_tokens) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (datetime.now().strftime("%Y-%m-%d"), model, kind, pin, out, total),
            )
            await db.commit()
    except Exception:
        pass            # counting is never worth failing a reply over


def _cost(model: str, pin: int, out: int) -> float | None:
    price = PRICE_PER_MTOK.get(model)
    if not price:
        return None
    return round(pin / 1_000_000 * price[0] + out / 1_000_000 * price[1], 4)


async def summary() -> dict:
    """Totals for the app: today, last 7 days, all time, plus a breakdown."""
    await _ensure()
    today = datetime.now().strftime("%Y-%m-%d")
    out: dict = {"today": today}
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row

        async def totals(where: str, args: tuple = ()) -> dict:
            row = await (await db.execute(
                "SELECT COALESCE(SUM(calls),0) c, COALESCE(SUM(input_tokens),0) i, "
                "COALESCE(SUM(output_tokens),0) o, COALESCE(SUM(total_tokens),0) t "
                f"FROM token_usage {where}", args)).fetchone()
            return {"calls": row["c"], "input": row["i"], "output": row["o"], "total": row["t"]}

        out["today_totals"] = await totals("WHERE day = ?", (today,))
        out["week_totals"] = await totals("WHERE day >= date('now', '-6 days')")
        out["all_time"] = await totals("")

        rows = await (await db.execute(
            "SELECT model, COALESCE(SUM(calls),0) c, COALESCE(SUM(input_tokens),0) i, "
            "COALESCE(SUM(output_tokens),0) o, COALESCE(SUM(total_tokens),0) t "
            "FROM token_usage GROUP BY model ORDER BY t DESC")).fetchall()
        out["by_model"] = [
            {"model": r["model"], "calls": r["c"], "input": r["i"], "output": r["o"],
             "total": r["t"], "cost_usd": _cost(r["model"], r["i"], r["o"])}
            for r in rows
        ]

        rows = await (await db.execute(
            "SELECT kind, COALESCE(SUM(calls),0) c, COALESCE(SUM(total_tokens),0) t "
            "FROM token_usage GROUP BY kind ORDER BY t DESC")).fetchall()
        out["by_kind"] = [{"kind": r["kind"], "calls": r["c"], "total": r["t"]} for r in rows]

        rows = await (await db.execute(
            "SELECT day, COALESCE(SUM(total_tokens),0) t, COALESCE(SUM(calls),0) c "
            "FROM token_usage GROUP BY day ORDER BY day DESC LIMIT 14")).fetchall()
        out["daily"] = [{"day": r["day"], "total": r["t"], "calls": r["c"]} for r in rows]

    out["cost_usd_all_time"] = round(
        sum(m["cost_usd"] or 0 for m in out["by_model"]), 4) or 0.0
    return out


async def reset() -> int:
    """Wipe the counters. Returns how many rows went."""
    await _ensure()
    async with aiosqlite.connect(DB_PATH) as db:
        cur = await db.execute("DELETE FROM token_usage")
        await db.commit()
        return cur.rowcount or 0
