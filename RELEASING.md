# Releasing Vaakya

This project builds with SwiftPM and assembles the app bundle without an Xcode project.

## Public release requirements

A friend-friendly macOS download requires:

- An Apple Developer Program membership
- A `Developer ID Application` certificate in the login keychain
- Hardened runtime and the audio-input entitlement
- Apple notarization and a stapled ticket
- A public GitHub repository with Releases enabled

Apple documents Developer ID and notarization here:

- https://developer.apple.com/help/account/certificates/create-developer-id-certificates
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

An ad-hoc or local self-signed build is useful for development, but Gatekeeper will not treat it as a trusted public download.

## One-time Apple setup

1. Enroll in the Apple Developer Program.
2. Create and install a Developer ID Application certificate.
3. Create an app-specific password for notarization.
4. Store the credentials in the login keychain:

```bash
xcrun notarytool store-credentials vaakya-notary \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

The password is stored in Keychain. Never put it in this repository or a shell script.

## Local release gate

Run the test, build, audit, package, notarize, staple, and Gatekeeper checks with:

```bash
VAAKYA_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VAAKYA_NOTARY_PROFILE="vaakya-notary" \
Scripts/release.sh 0.2.0
```

Successful output is written to `dist/`:

- `Vaakya-0.2.0-macOS.dmg`
- `Vaakya-0.2.0-macOS.zip`
- `Vaakya-0.2.0-SHA256SUMS.txt`

## Public repository boundary

The development checkout may live inside a larger private repository. Do not publish the parent repository. After the release-prep commit is clean, export only this project:

```bash
Scripts/export-public.sh /tmp/vaakya-public
cd /tmp/vaakya-public
git init -b main
git add .
git commit -m "Initial public release"
gh repo create vaakya --public --source=. --remote=origin --push
```

If you do not want a personal email in public Git history, configure your GitHub noreply email in the exported repository before committing.

## Publish the binaries

From the development checkout:

```bash
gh release create v0.2.0 \
  dist/Vaakya-0.2.0-macOS.dmg \
  dist/Vaakya-0.2.0-macOS.zip \
  dist/Vaakya-0.2.0-SHA256SUMS.txt \
  --repo OWNER/vaakya \
  --title "Vaakya 0.2.0" \
  --generate-notes
```

Repository creation, pushing, tagging, and publishing a release are external actions. Review the exported tree and artifacts before running them.

## Final checklist

- Version in `Resources/Info.plist` matches the tag.
- `make test` passes.
- `make audit` passes.
- The app has a custom icon before the first polished public release.
- A project license has been selected and added.
- The DMG and ZIP are signed and notarized.
- Install from each downloaded artifact on a clean macOS user account.
- Verify Microphone, Accessibility, Input Monitoring, dictation, suggestions, export, and relaunch.
- Verify the model download disclosure and optional Stage 2 disclosure.
