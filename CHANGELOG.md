# Changelog

## 0.2.0

- Added meeting capture, imported audio transcription, offline speaker diarization, transcript editing, lenses, and Archive Ask.
- Added Local, Codex CLI, and remote inference runners with explicit text-egress consent.
- Made Local the fresh-install inference default and kept all text egress off by default.
- Removed personal interview context and replaced bundled normalization examples with generic guidance.
- Hardened Codex runs with ephemeral mode, ignored user configuration, disabled tools and web search, a read-only sandbox, and no persisted Codex prompt or console log.
- Added a one-command user install that does not inspect Keychain signing identities or write to `/Applications`.
- Added no-cost, ad-hoc-signed GitHub release artifacts with checksums and explicit first-launch instructions.

## 0.1.1

- Added persisted speech-model consent and cached-model preparation at startup.
- Fixed modifier-only hotkey handling.
- Fixed correction learning crashes for empty and imbalanced token sequences.
- Fixed Accessibility edit-window baseline timing.
- Fixed latch stop behavior and Settings persistence.
- Preserved punctuation in phrase replacement and made conflicts reviewable.
- Preserved the full clipboard during paste fallback.
- Added the recording and transcription indicator.
- Fixed indicator label clipping and menu spacing.
- Added public release packaging, notarization, privacy, and CI infrastructure.
