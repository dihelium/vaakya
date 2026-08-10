# Contributing

Bug reports and focused pull requests are welcome.

## Before opening a pull request

1. Explain the user-visible problem or improvement in an issue.
2. Keep changes scoped and preserve the local-first privacy model.
3. Add or update tests for logic in `VaakyaWorkSafeCore`.
4. Run `make test` and `make audit`.
5. Describe any manual macOS permission or app-integration testing.

## Privacy invariant

Do not add recording persistence, imported audio, meeting capture, edit watching, clipboard access, analytics, telemetry, accounts, subprocesses, automatic update checks, Foundation Models, or application networking. FluidAudio's explicit-consent speech-model download is the only network exception.

## Security reports

Follow [SECURITY.md](SECURITY.md) instead of opening a public issue for a vulnerability.
