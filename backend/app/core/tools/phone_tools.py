"""
Phone control tools — speed-optimised for gemini-2.0-flash.
Key optimisations:
  - After every action the screen comes back as text with tap coordinates
  - Screenshots only on request (take_screenshot), for canvas/video screens
  - Short delays tuned to real UI animation timings
  - Layout cache: familiar screens (WhatsApp search, etc.) skip re-analysis
  - read_screen returns text only — no screenshot needed
"""

import asyncio
import base64
from google.genai import types
from app.core.phone_manager import phone_manager

# ─── Layout cache (app → known element positions) ─────────────────────────────
# After first visit, we know where things are — skip full re-analysis
_layout_cache: dict[str, dict] = {}

# ─── Gemini tool declarations ──────────────────────────────────────────────────

PHONE_TOOLS = types.Tool(function_declarations=[
    types.FunctionDeclaration(
        name="open_app",
        description=(
            "Open any app on the phone by its Android package name. "
            "Common: com.whatsapp, in.swiggy.android, com.application.zomato, "
            "com.instagram.android, com.google.android.youtube, com.spotify.music, "
            "com.google.android.gm (Gmail), com.android.chrome"
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "package_name": types.Schema(type=types.Type.STRING,
                    description="Android package name e.g. com.whatsapp")
            },
            required=["package_name"],
        ),
    ),
    types.FunctionDeclaration(
        name="tap_text",
        description="Find and tap a UI element by its visible text. Case-insensitive.",
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "text": types.Schema(type=types.Type.STRING,
                    description="Visible text of the element to tap")
            },
            required=["text"],
        ),
    ),
    types.FunctionDeclaration(
        name="tap_description",
        description="Tap a UI element by its content description (accessibility label). Use when tap_text fails on icon buttons.",
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "description": types.Schema(type=types.Type.STRING,
                    description="Content description of the element (e.g. 'Send', 'Search', 'More options')")
            },
            required=["description"],
        ),
    ),
    types.FunctionDeclaration(
        name="tap_at",
        description="Tap screen at pixel coordinates. Use when tap_text can't find an element.",
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "x": types.Schema(type=types.Type.INTEGER, description="X pixels"),
                "y": types.Schema(type=types.Type.INTEGER, description="Y pixels"),
            },
            required=["x", "y"],
        ),
    ),
    types.FunctionDeclaration(
        name="long_press_text",
        description="Long-press a UI element by text (context menus, select text).",
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "text": types.Schema(type=types.Type.STRING)
            },
            required=["text"],
        ),
    ),
    types.FunctionDeclaration(
        name="type_text",
        description="Type text into the currently focused input field.",
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "text": types.Schema(type=types.Type.STRING, description="Text to type")
            },
            required=["text"],
        ),
    ),
    types.FunctionDeclaration(
        name="focus_and_type",
        description=(
            "Find an input field, tap it to focus and open keyboard, then type text. "
            "More reliable than type_text when field might not be focused. "
            "Use this for WhatsApp message input, search boxes, or any text field that needs explicit focus."
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "text": types.Schema(type=types.Type.STRING, description="Text to type")
            },
            required=["text"],
        ),
    ),
    types.FunctionDeclaration(
        name="clear_and_type",
        description="Clear the currently focused field then type new text.",
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "text": types.Schema(type=types.Type.STRING)
            },
            required=["text"],
        ),
    ),
    types.FunctionDeclaration(
        name="press_back",
        description="Press the Android back button.",
        parameters=types.Schema(type=types.Type.OBJECT, properties={}),
    ),
    types.FunctionDeclaration(
        name="press_home",
        description="Press the Android home button.",
        parameters=types.Schema(type=types.Type.OBJECT, properties={}),
    ),
    types.FunctionDeclaration(
        name="scroll",
        description="Scroll the screen. direction: up, down, left, right.",
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "direction": types.Schema(type=types.Type.STRING,
                    description="up | down | left | right")
            },
            required=["direction"],
        ),
    ),
    types.FunctionDeclaration(
        name="read_screen",
        description=(
            "What is on screen right now: every button, field and label with its "
            "tap coordinates, e.g. \"Play\" [btn] (540,1120). This comes back after "
            "every action anyway — call it only when you need a fresh look. "
            "Tap anything in the list with tap_at using those coordinates."
        ),
        parameters=types.Schema(type=types.Type.OBJECT, properties={}),
    ),
    types.FunctionDeclaration(
        name="read_messages",
        description=(
            "Recent incoming messages (WhatsApp, SMS, Telegram, anything that "
            "notifies) with who sent them and whether they can be replied to "
            "directly. Use this for 'what did X say' or before replying."
        ),
        parameters=types.Schema(type=types.Type.OBJECT, properties={}),
    ),
    types.FunctionDeclaration(
        name="reply_message",
        description=(
            "Reply to someone straight from their notification — the app is "
            "never opened, so this takes about a second. Use it whenever the "
            "person has messaged recently."
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "who": types.Schema(type=types.Type.STRING,
                    description="Sender name as it appears in the message list"),
                "text": types.Schema(type=types.Type.STRING, description="What to send"),
            },
            required=["who", "text"],
        ),
    ),
    types.FunctionDeclaration(
        name="find_contact",
        description="Look up a phone number by name from Contacts. Use before messaging or calling someone by name.",
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={"name": types.Schema(type=types.Type.STRING)},
            required=["name"],
        ),
    ),
    types.FunctionDeclaration(
        name="send_message",
        description=(
            "Send a new message to a phone number: opens that chat with the "
            "text already filled in and presses send. app: whatsapp, sms or "
            "telegram. Use find_contact first when you only have a name."
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "app": types.Schema(type=types.Type.STRING, description="whatsapp | sms | telegram"),
                "phone": types.Schema(type=types.Type.STRING, description="Phone number"),
                "text": types.Schema(type=types.Type.STRING, description="Message body"),
            },
            required=["app", "phone", "text"],
        ),
    ),
    types.FunctionDeclaration(
        name="take_screenshot",
        description=(
            "Look at the actual pixels. Slow and expensive — use ONLY when the "
            "screen list is empty or unhelpful (games, video, canvas, image-only "
            "screens, or a layout you cannot make sense of from the text)."
        ),
        parameters=types.Schema(type=types.Type.OBJECT, properties={}),
    ),
    types.FunctionDeclaration(
        name="wait",
        description="Wait N seconds for an app or animation to load (max 4).",
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "seconds": types.Schema(type=types.Type.NUMBER, description="Seconds to wait")
            },
            required=["seconds"],
        ),
    ),
    types.FunctionDeclaration(
        name="check_installed_apps",
        description=(
            "Check if specific apps are installed on the phone. "
            "Useful to detect if user has WhatsApp, WhatsApp Business, or other alternatives."
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "package_names": types.Schema(
                    type=types.Type.ARRAY,
                    items=types.Schema(type=types.Type.STRING),
                    description="List of package names to check, e.g. ['com.whatsapp', 'com.whatsapp.w4b']"
                )
            },
            required=["package_names"],
        ),
    ),
    # ═══ FAST INTENTS (Siri-Speed Actions) ═══
    types.FunctionDeclaration(
        name="play_media_fast",
        description=(
            "⚡ ULTRA FAST: Play music/video using Android media intent (1-2 seconds, like Siri). "
            "Works with: YouTube Music, Spotify, Apple Music, any media app. "
            "Use this FIRST for music/video requests before trying screen automation. "
            "Example: play_media_fast('Orum Blood Song', 'com.spotify.music')"
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "query": types.Schema(
                    type=types.Type.STRING,
                    description="Song name, artist, or search query"
                ),
                "app_package": types.Schema(
                    type=types.Type.STRING,
                    description="Optional: App package (e.g. com.spotify.music, com.google.android.apps.youtube.music). If omitted, uses default music app."
                )
            },
            required=["query"],
        ),
    ),
    types.FunctionDeclaration(
        name="search_web_fast",
        description=(
            "⚡ INSTANT: Search the web using Android intent (opens default browser with search). "
            "Faster than opening Chrome and typing."
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "query": types.Schema(type=types.Type.STRING, description="Search query")
            },
            required=["query"],
        ),
    ),
    types.FunctionDeclaration(
        name="open_url_fast",
        description=(
            "⚡ INSTANT: Open a URL in default browser using Android intent."
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "url": types.Schema(type=types.Type.STRING, description="URL to open (must include http:// or https://)")
            },
            required=["url"],
        ),
    ),
    types.FunctionDeclaration(
        name="send_sms_fast",
        description=(
            "⚡ FAST: Open SMS app with pre-filled message (user must confirm send). "
            "Faster than opening messages app and typing manually."
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "phone": types.Schema(type=types.Type.STRING, description="Phone number"),
                "message": types.Schema(type=types.Type.STRING, description="SMS message text")
            },
            required=["phone", "message"],
        ),
    ),
    types.FunctionDeclaration(
        name="make_call_fast",
        description=(
            "⚡ INSTANT: Open phone dialer with number ready (user must tap call). "
            "For emergency use ACTION_CALL permission (auto-dials)."
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "phone": types.Schema(type=types.Type.STRING, description="Phone number to dial")
            },
            required=["phone"],
        ),
    ),
    types.FunctionDeclaration(
        name="set_alarm_fast",
        description=(
            "⚡ INSTANT: Set an alarm using Android Clock intent. "
            "Much faster than opening Clock app and tapping."
        ),
        parameters=types.Schema(
            type=types.Type.OBJECT,
            properties={
                "hour": types.Schema(type=types.Type.INTEGER, description="Hour (0-23, 24-hour format)"),
                "minute": types.Schema(type=types.Type.INTEGER, description="Minute (0-59)"),
                "message": types.Schema(type=types.Type.STRING, description="Alarm label/message")
            },
            required=["hour", "minute", "message"],
        ),
    ),
])

# ─── Seeing the screen ─────────────────────────────────────────────────────────

async def _screenshot(delay: float = 0.5) -> str | None:
    await asyncio.sleep(delay)
    try:
        result = await phone_manager.send_command("screenshot", timeout=8)
        img = result.get("image")
        return img if img else None
    except Exception:
        return None


async def _look(delay: float = 0.2) -> str:
    """The screen as text with tap coordinates.

    This is what follows every action now, instead of a screenshot: the
    accessibility tree is a few hundred characters rather than a ~200 KB
    image, there is no bitmap encode or upload, and the coordinates are exact
    instead of estimated from pixels. Falls back to the plain text read if the
    phone app is older and does not know ui_tree.
    """
    if delay:
        await asyncio.sleep(delay)
    try:
        result = await phone_manager.send_command("ui_tree", max=60, timeout=8)
        ui = (result.get("ui") or "").strip()
        if ui:
            return ui
    except Exception:
        pass
    try:
        result = await phone_manager.send_command("read_screen", timeout=8)
        text = (result.get("screen_text") or "").strip()
        return text or "(nothing readable on screen — use take_screenshot to look)"
    except Exception:
        return "(could not read the screen)"

# ─── Tool executor ─────────────────────────────────────────────────────────────

async def execute_phone_tool(name: str, args: dict) -> tuple[str, str | None]:
    """
    Returns (status_text, screenshot_base64_or_None).
    Screenshot is auto-taken after every screen-changing action.
    OPTIMIZED FOR SPEED: Minimal delays, fast screenshot compression.
    """
    # Check cancellation before each tool call
    if phone_manager.cancelled:
        return "Task cancelled by user.", None

    try:
        if name == "open_app":
            pkg = args["package_name"]
            await phone_manager.send_command("open_app", package=pkg, timeout=10)
            # Apps need time to open, but reduced from 1.2s to 0.7s
            ui = await _look(0.7)
            return f"Opened {pkg}"+ f"\n--- screen ---\n{ui}", None

        elif name == "tap_text":
            text = args["text"]
            result = await phone_manager.send_command("tap_text", text=text, timeout=8)
            status = result.get("status", "tapped")
            # Reduced from 0.4s to 0.2s - UI responds fast on modern phones
            ui = await _look(0.2)
            return f"{status}\n--- screen ---\n{ui}", None

        elif name == "tap_description":
            desc = args["description"]
            result = await phone_manager.send_command("tap_description", description=desc, timeout=8)
            status = result.get("status", "tapped")
            ui = await _look(0.2)
            return f"{status}\n--- screen ---\n{ui}", None

        elif name == "tap_at":
            x, y = int(args["x"]), int(args["y"])
            await phone_manager.send_command("tap_at", x=x, y=y, timeout=8)
            ui = await _look(0.2)
            return f"Tapped ({x},{y})"+ f"\n--- screen ---\n{ui}", None

        elif name == "long_press_text":
            text = args["text"]
            result = await phone_manager.send_command("long_press_text", text=text, timeout=8)
            ui = await _look(0.2)
            return f"{result.get("status", "long-pressed")}\n--- screen ---\n{ui}", None

        elif name == "type_text":
            text = args["text"]
            result = await phone_manager.send_command("type_text", text=text, timeout=8)
            status = result.get("status", "failed")
            # Reduced from 0.3s to 0.15s - typing is instant
            ui = await _look(0.15)
            if status == "failed":
                return (f"✗ Failed to type '{text[:30]}' - no input field is focused. "
                        f"Try focus_and_type or tap the field first.\n--- screen ---\n{ui}"), None
            return f"✓ Typed: {text[:40]}\n--- screen ---\n{ui}", None

        elif name == "focus_and_type":
            text = args["text"]
            result = await phone_manager.send_command("focus_and_type", text=text, timeout=10)
            status = result.get("status", "error")
            # Reduced from 0.4s to 0.2s
            ui = await _look(0.2)

            status_messages = {
                "typed": f"✓ Typed: {text[:40]}",
                "typed_after_focus": f"✓ Found and focused input field, typed: {text[:40]}",
                "error:no_window": "✗ Error: No active window",
                "error:no_input_field": "✗ No input field found on screen. Try scrolling or checking if you're on the right screen.",
                "error:tap_failed": "✗ Found input field but couldn't tap it",
                "error:set_text_failed": "✗ Field focused but typing failed",
                "error:still_failed": "✗ Focused field but still couldn't type",
                "error:service_not_enabled": "✗ Accessibility service not enabled"
            }
            
            msg = status_messages.get(status, f"✗ Unknown status: {status}")
            return f"{msg}\n--- screen ---\n{ui}", None

        elif name == "clear_and_type":
            text = args["text"]
            await phone_manager.send_command("clear_field", timeout=5)
            await asyncio.sleep(0.1)  # Reduced from 0.15s
            await phone_manager.send_command("type_text", text=text, timeout=8)
            ui = await _look(0.15)
            return f"Cleared+typed: {text[:40]}"+ f"\n--- screen ---\n{ui}", None

        elif name == "press_back":
            await phone_manager.send_command("press_back", timeout=5)
            ui = await _look(0.2)
            return "Pressed back"+ f"\n--- screen ---\n{ui}", None

        elif name == "press_home":
            await phone_manager.send_command("press_home", timeout=5)
            ui = await _look(0.2)
            return "Pressed home"+ f"\n--- screen ---\n{ui}", None

        elif name == "scroll":
            direction = args.get("direction", "down")
            await phone_manager.send_command("scroll", direction=direction, timeout=8)
            ui = await _look(0.2)
            return f"Scrolled {direction}"+ f"\n--- screen ---\n{ui}", None

        elif name == "read_screen":
            # elements with their tap coordinates, not just loose text
            return await _look(0), None

        elif name == "read_messages":
            res = await phone_manager.send_command("recent_messages", limit=15, timeout=6)
            if not res.get("listener_enabled"):
                return ("Message access is off. Turn on Jarvis Messages under "
                        "Settings > Notifications > Device & app notifications."), None
            msgs = res.get("messages") or []
            if not msgs:
                return "No recent messages.", None
            lines = [f"{m.get('from','?')} ({m.get('app','')}): {m.get('text','')[:120]}"
                     f"{'' if m.get('can_reply') else '  [cannot reply directly]'}"
                     for m in msgs]
            return chr(10).join(lines), None

        elif name == "reply_message":
            res = await phone_manager.send_command(
                "reply_message", who=args.get("who", ""), text=args["text"], timeout=8)
            status = res.get("status")
            if status == "sent":
                return f"Replied to {res.get('to') or args.get('who')}.", None
            if status == "listener_off":
                return ("Message access is off — turn on Jarvis Messages in "
                        "notification access, or send it the slow way."), None
            return ("No recent conversation with that person, so there is nothing "
                    "to reply to. Use find_contact + send_message instead."), None

        elif name == "find_contact":
            res = await phone_manager.send_command("find_contact", name=args["name"], timeout=6)
            matches = res.get("matches") or []
            if matches and matches[0].get("error") == "no_contacts_permission":
                return "Contacts permission is not granted to the app.", None
            if not matches:
                return f"No contact matching '{args['name']}'.", None
            return chr(10).join(f"{m['name']}: {m['phone']}" for m in matches), None

        elif name == "send_message":
            res = await phone_manager.send_command(
                "message_app_send", app=args.get("app", "whatsapp"),
                phone=args["phone"], text=args["text"], timeout=8)
            if res.get("status") == "opened":
                return f"Sent to {args['phone']} on {args.get('app', 'whatsapp')}.", None
            return "Could not open that chat — is the app installed?", None

        elif name == "take_screenshot":
            # the expensive fallback — only when the screen list was no help
            img = await _screenshot(0.1)
            if not img:
                return "Screenshot not available on this phone.", None
            return "Screenshot attached.", img

        elif name == "wait":
            secs = min(float(args.get("seconds", 1)), 4)
            await asyncio.sleep(secs)
            ui = await _look(0.1)
            return f"Waited {secs}s"+ f"\n--- screen ---\n{ui}", None

        elif name == "check_installed_apps":
            packages = args.get("package_names", [])
            result = await phone_manager.send_command("check_installed", packages=packages, timeout=5)
            installed = result.get("installed", {})
            status = "\n".join([f"{pkg}: {'✓ installed' if inst else '✗ not found'}" 
                               for pkg, inst in installed.items()])
            return status, None

        # ═══ FAST INTENTS (Siri-speed) ═══

        elif name == "play_media_fast":
            query = args["query"]
            app_package = args.get("app_package")
            result = await phone_manager.send_command(
                "play_media_fast", 
                query=query, 
                app_package=app_package,
                timeout=5
            )
            status = result.get("status", "failed")
            if status == "launched":
                return f"⚡ Instantly launched media player for: {query[:50]}", None
            else:
                return f"✗ Failed to launch media intent. Try screen automation instead.", None

        elif name == "search_web_fast":
            query = args["query"]
            result = await phone_manager.send_command("search_web_fast", query=query, timeout=5)
            status = result.get("status", "failed")
            if status == "launched":
                return f"⚡ Instantly opened web search for: {query[:50]}", None
            else:
                return f"✗ Failed to launch web search. Try open_app + focus_and_type.", None

        elif name == "open_url_fast":
            url = args["url"]
            result = await phone_manager.send_command("open_url_fast", url=url, timeout=5)
            status = result.get("status", "failed")
            if status == "launched":
                return f"⚡ Instantly opened URL: {url[:50]}", None
            else:
                return f"✗ Failed to open URL. Try open_app('com.android.chrome').", None

        elif name == "send_sms_fast":
            phone = args["phone"]
            message = args["message"]
            result = await phone_manager.send_command("send_sms_fast", phone=phone, message=message, timeout=5)
            status = result.get("status", "failed")
            if status == "launched":
                return f"⚡ Opened SMS to {phone} with message pre-filled. User must tap Send.", None
            else:
                return f"✗ Failed to launch SMS. Try screen automation.", None

        elif name == "make_call_fast":
            phone = args["phone"]
            result = await phone_manager.send_command("make_call_fast", phone=phone, timeout=5)
            status = result.get("status", "failed")
            if status == "launched":
                return f"⚡ Opened dialer with {phone}. User must tap Call button.", None
            else:
                return f"✗ Failed to launch dialer.", None

        elif name == "set_alarm_fast":
            hour = int(args["hour"])
            minute = int(args["minute"])
            message = args.get("message", "Alarm")
            result = await phone_manager.send_command(
                "set_alarm_fast",
                hour=hour,
                minute=minute,
                message=message,
                timeout=5
            )
            status = result.get("status", "failed")
            if status == "set":
                return f"⚡ Alarm set for {hour:02d}:{minute:02d} - {message}", None
            else:
                return f"✗ Failed to set alarm.", None

        else:
            return f"Unknown tool: {name}", None

    except RuntimeError as e:
        return f"Error: {e}", None
    except Exception as e:
        return f"Error executing {name}: {e}", None


def make_image_part(b64_png: str) -> types.Part:
    return types.Part(
        inline_data=types.Blob(
            mime_type="image/jpeg",
            data=base64.b64decode(b64_png),
        )
    )
