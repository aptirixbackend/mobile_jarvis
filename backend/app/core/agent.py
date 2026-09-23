from app.core.llm import chat_gemini, chat_gemini_with_tools
from app.core.memory import get_history, save_message
from app.core.persona import build_system_prompt

# cached answer to "is the accessibility service on?" (see _run_with_phone)
_service_ok = False
_service_ok_until = 0.0


async def run_agent(session_id: str, user_message: str, bot_name: str | None = None) -> str:
    await save_message(session_id, "user", user_message)

    system_prompt = await build_system_prompt(bot_name=bot_name)
    history = await get_history(session_id, limit=20)

    from app.core.phone_manager import phone_manager
    if phone_manager.connected:
        # "play X", "open whatsapp", "set alarm 6:30" → straight to the Android
        # intent, no model call, about a second end to end.
        from app.core.fast_intents import try_fast_intent
        quick = await try_fast_intent(user_message)
        if quick:
            await save_message(session_id, "assistant", quick)
            return quick
        reply = await _run_with_phone(system_prompt, history[:-1], user_message)
    else:
        reply = await chat_gemini(system_prompt, history[:-1], user_message)

    await save_message(session_id, "assistant", reply)
    return reply


async def _run_with_phone(
    system_prompt: str, history: list[dict], user_message: str
) -> str:
    from app.core.tools.phone_tools import PHONE_TOOLS, execute_phone_tool
    from app.core.phone_manager import phone_manager

    # Is the accessibility service on? Asking the phone costs a round trip, so
    # remember the answer for a minute — it only changes when the user goes
    # into Android settings.
    import time
    global _service_ok_until, _service_ok
    try:
        if time.time() > _service_ok_until:
            status_check = await phone_manager.send_command("is_service_enabled", timeout=3)
            _service_ok = bool(status_check.get("enabled", False))
            _service_ok_until = time.time() + 60
        if not _service_ok:
            return (
                "⚠️ **Accessibility Service is OFF**\n\n"
                "I can't control your phone right now because the Jarvis Phone Control "
                "accessibility service is disabled.\n\n"
                "📱 **To enable it:**\n"
                "1. Go to Settings → Accessibility\n"
                "2. Find 'Jarvis Phone Control'\n"
                "3. Turn it ON\n\n"
                "Once it's enabled, try your command again!"
            )
    except Exception:
        # If check fails, assume it's off
        return (
            "❌ **Can't connect to phone control service**\n\n"
            "Please make sure:\n"
            "1. Accessibility service is enabled in Settings\n"
            "2. The app has all required permissions\n\n"
            "Then try again."
        )

    # Kept deliberately short: this prompt is re-sent on every round of the
    # tool loop, so every line here is paid for again and again.
    phone_system = f"""{system_prompt}

You are Jarvis and you control this Android phone. Do the task, then reply in
one short sentence.

SPEED RULES
1. One-shot intents first — about a second each, no screen work needed:
     play_media_fast(query, app_package)   music or video
     make_call_fast(phone)  ·  send_sms_fast(phone, message)
     set_alarm_fast(hour, minute, message) · search_web_fast(query) · open_url_fast(url)
2. Otherwise open_app, then work from the screen list that comes back after
   every action. Each line is  "label" [kind] (x,y). Tap with tap_text when the
   label is exact, otherwise tap_at with those coordinates. Type with
   focus_and_type.
3. take_screenshot only when the screen list is empty or makes no sense
   (video, games, canvas). It is slow — avoid it.
4. Stop as soon as the task is done; do not re-check your own work.

PACKAGES  whatsapp com.whatsapp · gmail com.google.android.gm
chrome com.android.chrome · youtube com.google.android.youtube
yt music com.google.android.apps.youtube.music · spotify com.spotify.music
instagram com.instagram.android · settings com.android.settings
messages com.google.android.apps.messaging · dialer com.android.dialer

Before anything irreversible — sending a message, paying, deleting — say what
you are about to do and wait for a yes."""

    phone_manager.reset_cancel()
    await phone_manager.notify("task_started", message=user_message[:80])

    try:
        result = await chat_gemini_with_tools(
            system_prompt=phone_system,
            history=history,
            user_message=user_message,
            tools=[PHONE_TOOLS],
            execute_tool=execute_phone_tool,
            max_rounds=20,  # Increased from 12 to allow more complex tasks
        )
    except Exception as e:
        result = f"Something went wrong while controlling the phone: {e}"
    finally:
        await phone_manager.notify("task_ended")

    return result
