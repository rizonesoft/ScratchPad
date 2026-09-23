---
schema_version: 1
id: voice-engines
domain: 08-voice
status: draft
title: "TODO-01 -- Voice Engines"
depends_on: []
track: V1
---

# TODO-01 -- Voice Engines

> **Goal:** Offline-first speech engines behind one provider interface: embedded Kokoro text-to-speech and Whisper speech-to-text with MP3 export and pinned hashed model provisioning, plus an opt-in OpenRouter cloud route over the same calls.

> [!IMPORTANT]
> **Current state:** No speech exists. `D08 T02` (open, filed together) is the surface consuming these engines; the `D01 T02 §2` store (open) carries provider and voice choice through that file. No models vendored. Filed 2026-09-14 from the operator brainstorm as beyond-parity scope, scheduled Phase 3 (last build phase) by domain order per operator instruction.
>
> **Corrected 2026-09-17 (groom):** the `D01 T02 §2` store shipped 2026-09-16; only its provider and voice keys are future. The `D08 T02` marker still holds.

## Inputs

- [Kokoro (hexgrad/kokoro, MIT)](https://github.com/hexgrad/kokoro) -- the ONNX text-to-speech voice §1 embeds
- Whisper.net (whisper.cpp binding for .NET, NuGet) -- the transcriber §3 embeds
- [OpenRouter audio docs](https://openrouter.ai/docs) -- the `/audio/speech` and `/audio/transcriptions` endpoints §4 calls
- [`08-voice/TODO-02-voice-surface.md`](./TODO-02-voice-surface.md) -- the surface consuming these engines

**Groomed 2026-09-23:** License corrected: GitHub reports `hexgrad/kokoro` as Apache-2.0 and Hugging Face reports `hexgrad/Kokoro-82M` and `onnx-community/Kokoro-82M-v1.0-ONNX` as apache-2.0; read every "Kokoro (MIT)" claim here as Kokoro-82M (Apache-2.0, ONNX).

## Outcome

- Any text synthesizes to speech offline through the embedded voice.
- Speech transcribes offline from mic audio and audio files.
- MP3 exports and model provisioning run pinned, hashed, and offline after provisioning.
- Callers pick local or OpenRouter per call over one interface, cloud never the default.

**Adjacency:** list=not-applicable (pickers live in D08 T02 §3); document=not-applicable (no printed output in this file); settings=not-applicable (engines take params; D08 T02 §3 owns the voice and provider settings); reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (no app roles; the OS mic grant is handled in D08 T02 §2); audit=not-applicable (no audit trail in this file); exchange=applicable @ D08 T01 §2; reverse=not-applicable (synthesis and transcode produce new files; nothing to undo)

**Adjacency rationale:** MP3 writing is the exchange owned here; settings and pickers live across the file boundary by their edges.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Kokoro TTS embedded | -- |  [ ]   |
|   2   |   §2    | Audio transcode and provisioning | §1 |  [ ]   |
|   3   |   §3    | Whisper STT embedded | §2 |  [ ]   |
|   4   |   §4    | Provider interface with OpenRouter | §1, §3 |  [ ]   |

---

## 1. Kokoro TTS Embedded

Why this section exists: the voice is the product surface of read-aloud. A small offline neural voice keeps speech private, instant, and free.

**Decided 2026-09-14:** Kokoro-82M (MIT, ONNX) through the ONNX Runtime NuGet package: the best small offline open voice that embeds in a desktop app. Alternative recorded: the Windows platform voice (zero dependencies, download-on-demand Natural voices, not open-source). Cost of changing voices: re-pin the model plus re-record the fixture clips; the synth API stays.

**Groomed 2026-09-23:** Model placement corrected: the pin manifest (URL plus SHA) lives under `resources/voices/kokoro/`; model bytes provision into app data and are never committed (matches the first-run fetch and §2's no-models-in-git rule).

- [ ] The ONNX Runtime plus the pinned hashed Kokoro-82M model live under `resources/voices/kokoro/`. Done when: the model loads offline from the pinned bytes.
- [ ] `src/Notepad.Core/SpeechSynth.cs` synthesizes text to WAV with voice and rate params. Done when: the fixture clips render deterministically.
- [ ] First-run model fetch is pinned by URL plus SHA into app data with progress. Done when: the fetch contract is tested with a mocked transport.
- [ ] Synthesis meets the CPU-only budget on long documents. Done when: the perf test measures it.
- [ ] Long-document synthesis is cancellable mid-stream and emits sentence boundaries with timing, so D08 T02 §1 can pause, stop, and follow sentences. Done when: a cancel stops within one sentence and the timing list matches the sentence count (Groomed 2026-09-23.)
- [ ] Commit: `"voice: embed Kokoro TTS"`

**Test checkpoint:** `dotnet test --filter SpeechSynth` green on synth and perf fixtures. Cheaper substitute that fails: cloud TTS as the only path.

## 2. Audio Transcode and Provisioning

Why this section exists: WAV is the engine lingua franca but MP3 is what users keep. One transcode path serves export and the transcriber's file input, and one provision flow fetches every model byte.

**Needs:** Windows host (build/test)

**Groomed 2026-09-23:** Placement corrected: `Notepad.Core` targets plain `net10.0` (in `Notepad.Neutral.slnf`) and WinRT `MediaTranscoder` needs a Windows TFM, so `AudioTranscode` is an interface in Notepad.Core with the MediaTranscoder implementation in `src/ScratchPad` (`net10.0-windows10.0.19041.0`).

- [ ] `src/Notepad.Core/AudioTranscode.cs` transcodes WAV to MP3 and decodes MP3 and M4A to WAV through the platform MediaTranscoder. Done when: round-trip fixtures pass.
- [ ] `tools/provision-voices.ps1` fetches every pinned model by URL plus SHA, mirroring `tools/provision.ps1`. Done when: a clean machine provisions and verifies.
- [ ] Provisioned engines run with the network disabled. Done when: the offline proof test passes.
- [ ] Commit: `"voice: transcode audio and provision models"`

**Test checkpoint:** Transcode, provision, and offline-proof fixtures green. Cheaper substitute that fails: models committed to git.

## 3. Whisper STT Embedded

Why this section exists: transcription is the capture engine. A local Whisper turns mic audio and audio files into text with progress and cancel, private by construction.

- [ ] Whisper.net pinned via NuGet plus the pinned hashed GGML model under `resources/voices/whisper/`. Done when: the model loads offline from the pinned bytes.
- [ ] `src/Notepad.Core/SpeechTranscribe.cs` transcribes 16 kHz mono PCM with progress, cancel, and a language param. Done when: the clip fixtures transcribe within budget.
- [ ] MP3 and M4A files decode through the §2 path before transcribing. Done when: the file fixtures pass.
- [ ] First-run model fetch follows the §2 provision flow. Done when: the fetch is tested with a mocked transport.
- [ ] Commit: `"voice: embed Whisper STT"`

**Test checkpoint:** `dotnet test --filter SpeechTranscribe` green on clip, file, and cancel fixtures. Cheaper substitute that fails: server-side transcription as the only path.

## 4. Provider Interface with OpenRouter Cloud

Why this section exists: local is the default but choice beats dogma. One interface serves embedded engines and the cloud route, with the key and consent handled where they belong.

- [ ] `src/Notepad.Core/VoiceProviders.cs` serves local TTS and STT over one interface with local the default. Done when: the interface fixtures pass with the embedded engines.
- [ ] The OpenRouter route calls `/audio/speech` and `/audio/transcriptions` with the same voice ids where they exist. Done when: the fixtures pass against a mocked transport.
- [ ] The key arrives only via callback and is never stored or logged here. Done when: the key-handling fixtures pass.
- [ ] Every cloud call carries a per-send consent token the engine refuses to skip. Done when: the refusal fixtures pass.
- [ ] Cloud errors map to distinct results: bad or expired key (401), rate limit (429), and oversized upload each carry their own error, never a silent fall back to local. Done when: each status is driven against a stub (Groomed 2026-09-23.)
- [ ] Commit: `"voice: add the provider interface"`

**Test checkpoint:** Interface, cloud-shape, key-handling, and consent fixtures green. Cheaper substitute that fails: the key in a config file.

## Verification

- [ ] `dotnet test` green
- [ ] Offline-after-provisioning proof passes
- [ ] `python3 scripts/todo-graph.py validate` clean
