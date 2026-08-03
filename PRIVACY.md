# Privacy

Vaakya is local-first dictation software. This document separates the default dictation path from optional features that can use a network service.

## Stored on this Mac

Vaakya stores these items in `~/Library/Application Support/Vaakya/`:

- Dictation text and timestamps
- Dictionary terms and replacement rules
- Corrections used for personalization
- App settings and model-download consent

Microphone samples are processed in memory and are not saved as audio recordings by the app.

Speech and voice-activity models are cached by FluidAudio in `~/Library/Application Support/FluidAudio/Models/`.

## Network behavior

The default speech path has one network event: after explicit consent, FluidAudio downloads the Parakeet TDT 0.6B v2 CoreML model from Hugging Face. Once cached, speech recognition runs locally.

Vaakya source does not implement analytics, telemetry, advertising, accounts, crash upload, an automatic updater, or general-purpose runtime networking.

Optional Stage 2 is off by default. It uses Apple Foundation Models for punctuation and casing cleanup. Depending on the Mac and Apple's availability policy, Apple may route a request through Private Cloud Compute. Do not enable Stage 2 if you require a strictly offline workflow.

## Permissions

- Microphone records speech while dictation is active.
- Accessibility types the transcript and observes edits during the short learning window.
- Input Monitoring detects the Left Option hotkey.

Vaakya does not use these permissions for keystroke logging or background audio capture.

## Export and deletion

Settings can export dictionary terms and rules as JSON. Dictation history is not included in that export.

To remove local data, quit Vaakya and delete `~/Library/Application Support/Vaakya/`. The separately cached speech model can be removed from `~/Library/Application Support/FluidAudio/Models/`.
