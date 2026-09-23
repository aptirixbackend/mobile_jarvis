from google import genai
from google.genai import types
from app.config import settings
from app.core import usage

_client = genai.Client(api_key=settings.gemini_api_key)


def _build_contents(history: list[dict], user_message: str) -> list:
    contents = []
    for m in history:
        role = "model" if m["role"] == "assistant" else "user"
        contents.append(types.Content(role=role, parts=[types.Part(text=m["content"])]))
    contents.append(types.Content(role="user", parts=[types.Part(text=user_message)]))
    return contents


async def chat_gemini(system_prompt: str, history: list[dict], user_message: str) -> str:
    """Simple chat — no tool calling."""
    contents = _build_contents(history, user_message)
    response = await _client.aio.models.generate_content(
        model=settings.gemini_model,
        contents=contents,
        config=types.GenerateContentConfig(
            system_instruction=system_prompt,
            temperature=0.9,
            max_output_tokens=1024,
        ),
    )
    await usage.record(response, settings.gemini_model, "chat")
    return response.text or ""


async def chat_gemini_with_tools(
    system_prompt: str,
    history: list[dict],
    user_message: str,
    tools: list,
    execute_tool,  # async (name, args) -> (result_str, screenshot_b64_or_None)
    max_rounds: int = 10,
) -> str:
    """
    ReAct loop with Gemini function calling.
    Gemini decides which tool to call → we execute it → pass result + optional
    screenshot back → Gemini plans next step → repeat until text response.
    """
    from app.core.tools.phone_tools import make_image_part

    contents = _build_contents(history, user_message)

    for _ in range(max_rounds):
        response = await _client.aio.models.generate_content(
            model=settings.gemini_model,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                temperature=0.7,
                max_output_tokens=512,  # tool-call decisions are short — faster
                tools=tools,
            ),
        )
        await usage.record(response, settings.gemini_model, "phone")

        candidate = response.candidates[0]
        parts = candidate.content.parts

        # Collect any function calls in this response
        fn_calls = [p for p in parts if p.function_call and p.function_call.name]

        if not fn_calls:
            # Pure text — we're done
            return response.text or ""

        # Add model message (with function calls) to history
        contents.append(types.Content(role="model", parts=parts))

        # Execute each tool call and build the response parts
        tool_response_parts: list[types.Part] = []
        for part in fn_calls:
            fc = part.function_call
            args = dict(fc.args) if fc.args else {}
            result_text, screenshot_b64 = await execute_tool(fc.name, args)

            tool_response_parts.append(
                types.Part(
                    function_response=types.FunctionResponse(
                        name=fc.name,
                        response={"result": result_text},
                    )
                )
            )

            # If the tool returned a screenshot, include it so Gemini can see the screen
            if screenshot_b64:
                tool_response_parts.append(make_image_part(screenshot_b64))

        contents.append(types.Content(role="user", parts=tool_response_parts))

    return "I wasn't able to complete that task on the phone."
