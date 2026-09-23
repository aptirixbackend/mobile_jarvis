# Nova AI — Architecture

## Overview

```
┌─────────────────────────────┐        ┌──────────────────────────────┐
│      Flutter Mobile App     │◄──────►│      FastAPI Backend         │
│                             │  HTTP  │                              │
│  - Chat UI                  │  SSE   │  - Agent (ReAct loop)        │
│  - Voice input (mic)        │        │  - LLM Router                │
│  - Local cache (drift/SQLite│        │  - Memory (SQLite)           │
│  - Riverpod state           │        │  - Persona / System prompt   │
└─────────────────────────────┘        │  - REST API                  │
                                       └──────────┬───────────────────┘
                                                  │
                          ┌───────────────────────┤
                          │                       │
                   ┌──────▼──────┐        ┌───────▼──────┐
                   │  LLM API    │        │  SQLite DB   │
                   │  Anthropic  │        │  nova.db     │
                   │  OpenAI     │        │  - messages  │
                   │  Ollama     │        │  - memories  │
                   └─────────────┘        │  - profile   │
                                          └──────────────┘
```

## Storage Strategy

### Backend (source of truth)
- `conversations` table — full chat history per session
- `memories` table — key/value facts about the user (name, preferences, habits)
- `user_profile` table — structured user profile

### Mobile (cache only)
- `drift` SQLite — caches recent messages for fast load + offline viewing
- `shared_preferences` — app settings, theme, session ID
- Syncs from backend on app start

## LLM Providers

| Provider | Config value | Notes |
|---|---|---|
| Anthropic Claude | `anthropic` | Default, best quality |
| OpenAI | `openai` | GPT-4o, GPT-4o-mini |
| Ollama (local) | `ollama` | 100% offline, privacy-first |

Change `LLM_PROVIDER` in `.env` to switch.

## Phases

### Phase 1 (current)
- [x] FastAPI backend with streaming chat
- [x] SQLite memory (conversation history + key facts)
- [x] Friendly persona system prompt
- [x] Flutter chat UI with Riverpod state
- [x] Local drift cache on mobile

### Phase 2 (next)
- [ ] Voice input → Whisper STT → chat
- [ ] Voice output → ElevenLabs TTS → play audio
- [ ] Gmail integration (read/send)
- [ ] Google Calendar integration
- [ ] Proactive notifications (push)

### Phase 3
- [ ] WhatsApp / Telegram channel
- [ ] Vector memory (sqlite-vec)
- [ ] On-device model (Ollama on phone via local server)
- [ ] Contact awareness (who user talks to)
- [ ] Mood / tone detection
