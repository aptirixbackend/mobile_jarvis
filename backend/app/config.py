from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # Gemini (LLM only)
    gemini_api_key: str = ""
    # flash-lite is the quickest of the family and the phone work is nearly
    # all short tool calls. Override with GEMINI_MODEL in .env.
    gemini_model: str = "gemini-3.5-flash-lite"

    # Sarvam (STT + TTS) — key belongs in .env, never here
    sarvam_api_key: str = ""
    sarvam_language: str = "en-IN"

    # DB
    db_path: str = "data/nova.db"

    # Persona
    persona_name: str = "Jarvis"
    persona_tone: str = "witty, warm, direct — like a smart best friend, not a corporate assistant"

    # Server
    host: str = "0.0.0.0"
    port: int = 8000


settings = Settings()
