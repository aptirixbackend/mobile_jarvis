"""Straight-through commands — no model call at all.

"play despacito", "call amma", "open whatsapp", "set alarm 6:30" are the
things people say most, and every one of them maps onto an Android intent the
phone can fire in about a second. Sending them through the model first costs
two to five seconds and buys nothing, so they are matched here and executed
directly. Anything that does not match falls through to the normal agent.

Matching is deliberately conservative: if the phrase is not clearly one of
these, return None and let the model handle it.
"""
import re

from app.core.phone_manager import phone_manager

# app name as people say it → Android package
APPS = {
    "whatsapp": "com.whatsapp",
    "whats app": "com.whatsapp",
    "gmail": "com.google.android.gm",
    "mail": "com.google.android.gm",
    "chrome": "com.android.chrome",
    "browser": "com.android.chrome",
    "youtube": "com.google.android.youtube",
    "yt": "com.google.android.youtube",
    "youtube music": "com.google.android.apps.youtube.music",
    "yt music": "com.google.android.apps.youtube.music",
    "spotify": "com.spotify.music",
    "instagram": "com.instagram.android",
    "insta": "com.instagram.android",
    "telegram": "org.telegram.messenger",
    "settings": "com.android.settings",
    "camera": "com.android.camera",
    "gallery": "com.google.android.apps.photos",
    "photos": "com.google.android.apps.photos",
    "maps": "com.google.android.apps.maps",
    "google maps": "com.google.android.apps.maps",
    "calculator": "com.google.android.calculator",
    "clock": "com.google.android.deskclock",
    "phone": "com.android.dialer",
    "dialer": "com.android.dialer",
    "messages": "com.google.android.apps.messaging",
    "sms": "com.google.android.apps.messaging",
    "facebook": "com.facebook.katana",
    "swiggy": "in.swiggy.android",
    "zomato": "com.application.zomato",
}

MUSIC_APPS = {
    "spotify": "com.spotify.music",
    "youtube music": "com.google.android.apps.youtube.music",
    "yt music": "com.google.android.apps.youtube.music",
    "youtube": "com.google.android.youtube",
    "gaana": "com.gaana",
    "wynk": "com.bsbportal.music",
    "jiosaavn": "com.jio.media.jiobeats",
    "saavn": "com.jio.media.jiobeats",
}

# "play X", "play X on spotify", "song X", Tamil/Hindi-English mixes included
_PLAY = re.compile(
    r"^(?:hey\s+)?(?:jarvis[,\s]+)?(?:please\s+)?"
    r"(?:play|put on|start playing|paatu?\s*podu|gaana bajao|song)\s+"
    r"(?P<what>.+?)"
    r"(?:\s+(?:on|in|using)\s+(?P<app>[a-z ]+?))?\s*$", re.I)
_CALL = re.compile(r"^(?:hey\s+)?(?:jarvis[,\s]+)?(?:call|dial|phone)\s+(?P<who>[+\d][\d\s\-()]{5,}|[a-z][\w .]{1,30})\s*$", re.I)
_OPEN = re.compile(r"^(?:hey\s+)?(?:jarvis[,\s]+)?(?:open|launch|start)\s+(?P<app>[\w .]+?)(?:\s+app)?\s*$", re.I)
_ALARM = re.compile(
    r"^(?:hey\s+)?(?:jarvis[,\s]+)?set\s+(?:an?\s+)?alarm\s+(?:for\s+|at\s+)?"
    r"(?P<h>\d{1,2})(?::(?P<m>\d{2}))?\s*(?P<ampm>am|pm|a\.m\.|p\.m\.)?\s*$", re.I)
_SEARCH = re.compile(r"^(?:hey\s+)?(?:jarvis[,\s]+)?(?:search|google|look up)\s+(?:for\s+)?(?P<q>.+?)\s*$", re.I)
# "reply to priya saying on my way" / "reply priya: on my way"
_REPLY = re.compile(
    r"^(?:hey\s+)?(?:jarvis[,\s]+)?reply\s+(?:to\s+)?(?P<who>[\w .]{1,30}?)"
    r"\s*(?:saying|say|that|with|:)\s+(?P<text>.+)$", re.I)
# "whatsapp arun kumar that the file is ready" — a separator marks where the
# name ends, so multi-word names stay intact
_MESSAGE_SEP = re.compile(
    r"^(?:hey\s+)?(?:jarvis[,\s]+)?(?:message|msg|whatsapp|text|tell)\s+"
    r"(?P<who>[+\d][\d\s\-()]{5,}|[\w .]{1,40}?)"
    r"\s*(?:\bsaying\b|\bsay\b|\bthat\b|\bwith\b|:)\s+(?P<text>.+)$", re.I)
# "message amma I will call later" — no separator, so the name is one word
_MESSAGE = re.compile(
    r"^(?:hey\s+)?(?:jarvis[,\s]+)?(?:message|msg|whatsapp|text|tell)\s+"
    r"(?P<who>[+\d][\d\s\-()]{5,}|\w+)\s+(?P<text>.+)$", re.I)
_OPEN_URL = re.compile(r"^(?:hey\s+)?(?:jarvis[,\s]+)?(?:open|go to)\s+(?P<url>(?:https?://|www\.)\S+)\s*$", re.I)

# Phrases that mean this is a question or a multi-step task, so the model
# should handle it. "reply" and "message" are NOT here — they have their own
# patterns below and are the two most common commands there are.
_NOT_SIMPLE = re.compile(r"\b(and then|after that|,\s*then\b|why |how |when |where )", re.I)


def _match_app(name: str, table: dict) -> str | None:
    name = re.sub(r"\s+", " ", (name or "")).strip().lower().rstrip(".")
    if not name:
        return None
    if name in table:
        return table[name]
    for key, pkg in table.items():           # "spotify app", "the youtube"
        if key in name:
            return pkg
    return None


async def try_fast_intent(text: str) -> str | None:
    """Run the obvious ones directly. Returns the spoken reply, or None when
    this is not a straight-through command."""
    if not phone_manager.connected:
        return None
    t = re.sub(r"\s+", " ", (text or "")).strip().rstrip(".!")
    if not t or len(t) > 120 or _NOT_SIMPLE.search(t):
        return None

    m = _OPEN_URL.match(t)
    if m:
        url = m.group("url")
        if url.lower().startswith("www."):
            url = "https://" + url
        await phone_manager.send_command("open_url_fast", url=url, timeout=5)
        return "Opening it."

    m = _PLAY.match(t)
    if m:
        what = m.group("what").strip()
        pkg = _match_app(m.group("app") or "", MUSIC_APPS)
        # "play spotify" is really "open spotify"
        if not pkg and _match_app(what, MUSIC_APPS) and len(what.split()) <= 2:
            pkg = _match_app(what, MUSIC_APPS)
            await phone_manager.send_command("open_app", package=pkg, timeout=8)
            return f"Opening {what}."
        res = await phone_manager.send_command(
            "play_media_fast", query=what, app_package=pkg, timeout=6)
        if res.get("status") == "launched":
            return f"Playing {what}."
        return None                           # let the agent try the slow way

    # "reply to X ..." — answers straight from the notification, no app opened
    m = _REPLY.match(t)
    if m:
        who, text = m.group("who").strip(), m.group("text").strip()
        res = await phone_manager.send_command("reply_message", who=who, text=text, timeout=8)
        if res.get("status") == "sent":
            return f"Replied to {res.get('to') or who}."
        return None                           # no such conversation → let the agent try

    # "message X ..." — reply from the notification if they wrote recently,
    # otherwise look the number up and open the chat with the text filled in
    m = _MESSAGE_SEP.match(t) or _MESSAGE.match(t)
    if m:
        who, text = m.group("who").strip(), m.group("text").strip()
        if len(text) < 2:
            return None
        res = await phone_manager.send_command("reply_message", who=who, text=text, timeout=8)
        if res.get("status") == "sent":
            return f"Sent to {res.get('to') or who}."
        number = re.sub(r"[^\d+]", "", who) if re.fullmatch(r"[+\d][\d\s\-()]{5,}", who) else None
        if not number:
            found = await phone_manager.send_command("find_contact", name=who, timeout=6)
            matches = [x for x in (found.get("matches") or []) if x.get("phone")]
            if len(matches) != 1:             # nobody, or ambiguous → ask the agent
                return None
            number = matches[0]["phone"]
        sent = await phone_manager.send_command(
            "message_app_send", app="whatsapp", phone=number, text=text, timeout=8)
        return f"Sending to {who}." if sent.get("status") == "opened" else None

    m = _CALL.match(t)
    if m:
        who = m.group("who").strip()
        if re.fullmatch(r"[+\d][\d\s\-()]{5,}", who):
            await phone_manager.send_command(
                "make_call_fast", phone=re.sub(r"[^\d+]", "", who), timeout=5)
            return f"Calling {who}."
        return None                           # a name needs the contacts app

    m = _ALARM.match(t)
    if m:
        h, mins = int(m.group("h")), int(m.group("m") or 0)
        ampm = (m.group("ampm") or "").lower().replace(".", "")
        if ampm.startswith("p") and h < 12:
            h += 12
        if ampm.startswith("a") and h == 12:
            h = 0
        if 0 <= h <= 23 and 0 <= mins <= 59:
            await phone_manager.send_command(
                "set_alarm_fast", hour=h, minute=mins, message="Alarm", timeout=5)
            return f"Alarm set for {h:02d}:{mins:02d}."
        return None

    m = _OPEN.match(t)
    if m:
        pkg = _match_app(m.group("app"), APPS)
        if pkg:
            await phone_manager.send_command("open_app", package=pkg, timeout=8)
            return f"Opening {m.group('app').strip()}."
        return None

    m = _SEARCH.match(t)
    if m:
        q = m.group("q").strip()
        await phone_manager.send_command("search_web_fast", query=q, timeout=5)
        return f"Searching for {q}."

    return None
