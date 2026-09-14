---
schema_version: 1
id: voice-surface
domain: 08-voice
status: draft
title: "TODO-02 -- Voice Surface"
depends_on: ["voice-engines"]
track: V1
---

# TODO-02 -- Voice Surface

> **Goal:** The voice UI on the editor: read any text aloud with follow and MP3 export, dictate and transcribe with consent-first cloud, and set provider and voice in one place.

> [!IMPORTANT]
> **Current state:** No voice UI exists. The `D08 T01` engines (open, filed together) carry speech; the `D02 T01` buffer and caret model (open) is the text source and sink; the `D01 T02 §2` store (open) carries provider and voice choice. Filed 2026-09-14 with T01, scheduled Phase 3 by domain order.

## Inputs

- [`08-voice/TODO-01-voice-engines.md`](./TODO-01-voice-engines.md) -- the engines this surface drives
- [`02-editor/TODO-01-editing-surface.md`](../02-editor/TODO-01-editing-surface.md) -- the buffer being read and written
- [`01-notepad-core/TODO-02-menus-settings-status.md`](../01-notepad-core/TODO-02-menus-settings-status.md) -- §1 owns the menus, §2 the store
- -> XREF: D04 T02 §1 -- the platform credential-store pattern the OpenRouter key follows; no behavior deferred

## Outcome

- Read-aloud plays, pauses, follows the sentence, and saves MP3.
- Dictation inserts at the caret and files transcribe with progress and cancel.
- Provider and voice settings persist with per-send cloud consent.
- Voice menus and shortcuts behave with honest disabled states.

**Adjacency:** list=applicable @ D08 T02 §3; document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (progress stays inline; no notification surface in this file); permissions=not-applicable (the OS mic grant is handled inline in §2; no app roles); audit=not-applicable (no app roles; no audit trail in this file); exchange=not-applicable (MP3 writing is owned at D08 T01 §2); reverse=applicable @ D02 T01 §4

**Adjacency rationale:** Pickers are the list; provider choice persists in the D01 store; inserted transcripts undo as text.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Read-aloud UI with MP3 | D08 T01 §1, D08 T01 §2, D02 T01 §2 |  [ ]   |
|   2   |   §2    | Dictate and transcribe UI | D08 T01 §3, D02 T01 §2 |  [ ]   |
|   3   |   §3    | Provider settings and consent | D08 T01 §4, D01 T02 §2 |  [ ]   |
|   4   |   §4    | Voice menus and shortcuts | §1, §2, D01 T02 §1 |  [ ]   |

---

## 1. Read-Aloud UI with MP3

Why this section exists: writers review by ear. Play, follow, and MP3 export make the voice a daily surface instead of a demo.

**Fidelity:** new build, no baseline (stock Notepad reads nothing aloud).

**Job:** The user can listen to any text and keep the audio. Consumer: the buffer, which follows the spoken sentence.

**Treatment:** Play, pause, and stop with sentence-follow highlight, plus a save-MP3 action through the file dialog. Cheaper substitute that fails the checkpoint: playback with no follow.

**Chrome:** Consume the shared editor styles. Do not invent a second transport treatment.

**Needs:** Windows host (build/test)

- [ ] Read-aloud plays, pauses, and stops the selection or document. Done when: the transport is driven.
- [ ] The spoken sentence highlights as it plays. Done when: follow is driven.
- [ ] Save-MP3 writes through the file dialog. Done when: the export is driven end to end.
- [ ] Voice and rate apply from the settings. Done when: the application is driven.
- [ ] Commit: `"voice: read aloud with MP3"`

**Test checkpoint:** Transport, follow, export, and settings application driven; capture comparison passes. Cheaper substitute that fails: audio with no visible state.

## 2. Dictate and Transcribe UI

Why this section exists: capture must be one gesture with honest failure: denied mic, long files, and dead network each read clearly.

**Fidelity:** new build, no baseline (stock Notepad takes no dictation).

**Job:** The user can speak text into the buffer and transcribe audio files. Consumer: the buffer, which receives the transcript as undoable text.

**Treatment:** Record and stop with live state, insert at the caret, import-transcribe with progress and cancel. Cheaper substitute that fails the checkpoint: transcription with no cancel.

**Chrome:** Consume the shared editor styles. Do not invent a second capture treatment.

**Needs:** Windows host (build/test)

- [ ] Dictation records, stops, and inserts at the caret. Done when: the capture is driven.
- [ ] A denied mic reads as guidance, never a hang or a crash. Done when: the denied path is driven.
- [ ] Audio file import transcribes with progress and cancel. Done when: the import is driven.
- [ ] Long captures stay cancellable and partial text is never lost. Done when: the cancel fixtures pass.
- [ ] Commit: `"voice: dictate and transcribe"`

**Test checkpoint:** Capture, denied path, import, and cancel driven. Cheaper substitute that fails: dictation that eats the first second.

## 3. Provider Settings and Consent

Why this section exists: the key and the cloud choice are the trust surface. They persist safely, confirm loudly, and degrade to local when the network dies.

**Fidelity:** new build, no baseline (extends the settings surface with voice rows).

**Job:** The user can choose provider and voice with full knowledge of where audio goes. Consumer: the settings store, which the engines read.

**Treatment:** Provider radio with local default, key field that writes only to the platform credential store, per-send cloud confirm, voice picker. Cheaper substitute that fails the checkpoint: a key field that persists to disk.

**Chrome:** Consume the shared settings styles. Do not invent a second secret-field treatment.

**Needs:** Windows host (build/test)

- [ ] The provider radio and key field persist with the key only in the platform store. Done when: the settings are driven and the key appears in no log or file.
- [ ] Every cloud send confirms first with a decline path. Done when: accept and decline are driven.
- [ ] Dead cloud falls back to local with notice. Done when: the fallback is driven.
- [ ] The voice picker lists the available voices and applies the choice to read-aloud immediately. Done when: the picker is driven.
- [ ] Commit: `"voice: provider settings and consent"`

**Test checkpoint:** Settings, consent, fallback, and picker driven; key hygiene asserted. Cheaper substitute that fails: consent remembered forever.

## 4. Voice Menus and Shortcuts

Why this section exists: surfaces nobody can find may as well not exist. Voice entries sit in the existing menus with shortcuts and honest disabled states.

**Fidelity:** new build, no baseline (extends the View menu).

**Job:** The user can reach every voice action from menu or keys. Consumer: the menus, which stay stock-shaped plus voice rows.

**Treatment:** Entries under View (no new top-level menu); shortcuts for read-aloud and dictate; disabled without mic, models, or provisioned voice. Cheaper substitute that fails the checkpoint: entries that fail silently when models are missing.

**Chrome:** Consume the shared menu styles. Do not invent a second menu treatment.

**Needs:** Windows host (build/test)

- [ ] The View menu carries read-aloud, dictate, and transcribe entries. Done when: the entries are driven.
- [ ] Shortcuts trigger read-aloud and dictate. Done when: the shortcuts are driven.
- [ ] Missing mic, models, or cloud reachability disables honestly with reasons. Done when: the disabled states are driven.
- [ ] Commit: `"voice: menus and shortcuts"`

**Test checkpoint:** Menus, shortcuts, and disabled states driven; capture comparison passes. Cheaper substitute that fails: shortcuts that collide with stock bindings.

## Verification

- [ ] `dotnet test` green
- [ ] Consent and disabled-state paths driven
- [ ] `python3 scripts/todo-graph.py validate` clean
