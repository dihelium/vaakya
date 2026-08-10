# Privacy

Vaakya is local-first dictation software. This document separates the default dictation path from optional features that can use a network service.

## Stored on this Mac

Vaakya stores these items in `~/Library/Application Support/Vaakya/`:

- Dictation text and timestamps
- Dictionary terms and replacement rules
- Corrections used for personalization
- App settings and model-download consent
- Imported and meeting audio copies, diarized transcripts, optional notes/context, and lens drafts under `transcription-jobs/`

Microphone samples for **hotkey dictation** are processed in memory and are not saved as audio recordings by the app. **Imported audio** is copied under Application Support so jobs can resume after restart. A user-started **meeting notes** session records microphone and system audio into local files, mixes them into the managed job audio after Stop, and removes the temporary source streams after the job is safely created.

Speech, voice-activity, and (with separate consent) diarization models are cached by FluidAudio in `~/Library/Application Support/FluidAudio/Models/`.

## Network behavior

The default speech path has one network event: after explicit consent, FluidAudio downloads the Parakeet TDT 0.6B v2 CoreML model from Hugging Face. Once cached, speech recognition and offline diarization run locally.

Vaakya does not implement analytics, telemetry, advertising, accounts, crash upload, or an automatic updater.

Optional Stage 2 is off by default. It uses Apple Foundation Models for punctuation and casing cleanup. Depending on the Mac and Apple's availability policy, Apple may route a request through Private Cloud Compute. Do not enable Stage 2 if you require a strictly offline workflow.

Optional **AI runners** power **lenses** and **Archive Ask**. Settings choose one shared engine:

- **Local** (loopback Ollama / LM Studio) is the default. Text stays on this Mac at the transport layer and no egress toggle is required. Vaakya cannot guarantee that a local server never proxies further.
- **Codex CLI** is B1 text egress. It requires the egress toggle and a confirmation that names the selected recordings. Vaakya passes the approved text over stdin from a temporary working directory. The run is ephemeral and ignores user config and rules. Shell tools, project instructions, agents, web search, history, memories, analytics, and startup update checks are disabled. Model-generated commands also use Codex's read-only sandbox. Authentication still comes from the Codex account signed in on this Mac, and provider-side retention follows that account's policy.
- **Remote** OpenAI-compatible, including Ollama Cloud presets, is B1 text egress. It requires HTTPS, a Keychain API key, and confirmation.

**Vaakya does not upload audio** on the lens or Ask path. Only approved text is passed into runners. Archive Ask **whole-archive** mode is Local-only. Codex and Remote require **pinned recordings** plus a confirmation listing those jobs. Ask conversations live in the local SQLite database. B1 Ask rows write a small local egress log with job IDs, runner, and byte counts, not the full payload.

Codex output is written to a temporary result file by the CLI, read by Vaakya, and removed with the temporary directory. The reviewed lens draft or Ask answer is then stored in Vaakya's normal local database and job folder. Vaakya does not copy or bundle `~/.codex/`.

## Permissions

- Microphone records speech while dictation or a user-started meeting notes session is active.
- Screen and System Audio Recording captures Mac and call audio during a meeting notes session. The minimal ScreenCaptureKit video frames required by macOS are discarded immediately, never stored or inspected, and Vaakya excludes its own audio.
- Accessibility types the transcript and observes edits during the short learning window.
- Input Monitoring detects the Left Option hotkey.

Vaakya does not use these permissions for keystroke logging or capture outside an active, user-started dictation or meeting notes session.

## Export and deletion

Settings can export dictionary terms and rules as JSON. Dictation history is not included in that export.

To remove local data, quit Vaakya and delete `~/Library/Application Support/Vaakya/`. The separately cached speech model can be removed from `~/Library/Application Support/FluidAudio/Models/`.

Installing from the public source repository does not migrate data from another Mac. For a clean work-laptop setup, do not copy the Vaakya Application Support folder, personal dictionary exports, Keychain items, or the personal Mac's Codex home directory.
