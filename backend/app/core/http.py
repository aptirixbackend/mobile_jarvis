"""One HTTP client for the whole process.

A fresh httpx.AsyncClient per request means a fresh TLS handshake per request —
roughly 200-500 ms each, paid twice on every voice turn (speech in, speech
out). Keeping one client alive keeps the connections open, so the second turn
onwards pays nothing for setup.
"""
import httpx

_client: httpx.AsyncClient | None = None


def client() -> httpx.AsyncClient:
    global _client
    if _client is None or _client.is_closed:
        _client = httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=5.0),
            limits=httpx.Limits(max_keepalive_connections=8, max_connections=16,
                                keepalive_expiry=300),
        )
    return _client


async def aclose() -> None:
    global _client
    if _client is not None and not _client.is_closed:
        await _client.aclose()
    _client = None
