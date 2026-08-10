# Privacy - Work Safe branch

This branch implements only hold-to-dictate with local speech recognition.

## Data handling

- Microphone samples stay in memory for one dictation and are discarded immediately afterward.
- Recognized text is typed directly at the cursor and is not persisted by Vaakya.
- Vaakya does not read the target application's text, watch subsequent edits, or access the clipboard.
- No audio, transcript, history database, recording job, lens output, prompt, or log is created.
- The sole Vaakya state file is `~/Library/Application Support/Vaakya Work Safe/config.json`, containing only speech-model consent. Its directory and file modes are set to `0700` and `0600`.

FluidAudio caches the separately downloaded speech model under `~/Library/Application Support/FluidAudio/Models/`.

## Network behavior

After explicit consent, FluidAudio downloads Parakeet TDT 0.6B v2 from Hugging Face. Once cached, dictation runs locally.

Vaakya itself has no HTTP client, remote runner, Codex subprocess, analytics, telemetry, account, crash upload, advertising, or automatic updater. It does not use Apple Foundation Models or Private Cloud Compute.

## Permissions

- Microphone captures only while Left Option is actively held.
- Accessibility types Unicode at the cursor. It does not inspect UI contents.
- Input Monitoring observes modifier-change events only for the Left Option hotkey.

The app has no Screen and System Audio Recording feature.

## Deletion

Quit Vaakya, then delete `~/Library/Application Support/Vaakya Work Safe/`. Remove the FluidAudio model cache separately if desired.

On an employer-owned Mac, administrators and device-management software may still access local memory, files, processes, or injected text.
