# 08 Voice

> **Phase 3**

Beyond-parity speech: embedded offline engines behind one provider interface, read aloud, dictate, and transcribe on the editor surface.

## TODOs

| TODO | Title | Status |
| ---- | ----- | :----: |
| [TODO-01](./TODO-01-voice-engines.md) | Voice Engines | `draft` |
| [TODO-02](./TODO-02-voice-surface.md) | Voice Surface | `draft` |

## In scope

- Embedded Kokoro speech synthesis and Whisper transcription
- MP3 export, audio transcode, and hashed model provisioning
- Provider interface with local default and OpenRouter cloud
- Read-aloud, dictate, transcribe, and voice settings UI

## Out of scope

- Agent chat and turns (05-ai-surface owns the conversation)
- Code editing surfaces (the product is a writing tool)
- Cloud-only speech paths (local-first; cloud is opt-in)

---

Format spec: [../README.md](../README.md) · Root index: [../TODO-00-INDEX.md](../TODO-00-INDEX.md)
