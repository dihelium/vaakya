# Vaakya Work Safe

Vaakya Work Safe is a deliberately reduced macOS dictation app for managed or employer-owned Macs. Hold Left Option, speak, and release. Local Parakeet ASR types the result at the cursor.

This branch contains dictation only. It has no meeting capture, imported recordings, transcript history, edit learning, Foundation Models cleanup, AI runners, remote APIs, analytics, telemetry, updater, or clipboard access.

## Fast install

Requirements: Apple Silicon, macOS 14+, and Xcode Command Line Tools.

```bash
git clone --branch work-safe --single-branch https://github.com/dihelium/vaakya.git
cd vaakya
make install
```

`make install` builds with SwiftPM's sandbox enabled, ad-hoc signs the app, installs it only to `~/Applications/Vaakya.app`, and opens it. It never uses a certificate from the Mac's keychain, writes to `/Applications`, or terminates another process.

On first launch, grant Microphone, Accessibility, and Input Monitoring, then approve the one-time ~450 MB speech-model download. Those macOS permissions cannot be automated or bypassed.

If Xcode Command Line Tools are missing, run `xcode-select --install`, finish Apple's installer, and repeat `make install`.

## Privacy boundary

- Hotkey audio exists in memory only and is discarded after transcription.
- Transcript text is injected directly as Unicode and is not stored.
- Vaakya does not inspect the focused text field or access the clipboard.
- The event tap subscribes only to modifier-change events and activates only for Left Option by itself.
- The only application state is model-download consent in `~/Library/Application Support/Vaakya Work Safe/config.json`.
- FluidAudio downloads the speech model after explicit consent and caches it under its own Application Support directory. Recognition is local afterward.

Local data may still be visible to employer MDM, EDR, backups, or administrators. Obtain company approval for the three macOS permissions when required by policy.

## Verify

```bash
make test
make audit
```

`make audit` builds the bundle, verifies its signature and microphone entitlement, and rejects work-unsafe source capabilities.

## Public binaries

There is currently no Developer ID certificate available for this project, so this branch intentionally does not claim that an ad-hoc binary is a trusted download. A frictionless downloadable app requires Developer ID signing and Apple notarization. Until then, the local source build above is the shortest trustworthy installation path.

License: MIT.
