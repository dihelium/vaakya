# Contributing

Bug reports and focused pull requests are welcome.

## Before opening a pull request

1. Explain the user-visible problem or improvement in an issue.
2. Keep changes scoped and preserve the local-first privacy model.
3. Add or update tests for logic in `VaakyaCore`.
4. Run `make test` and `make audit`.
5. Describe any manual macOS permission or app-integration testing.

## Privacy invariant

Do not add analytics, telemetry, accounts, automatic update checks, or networking to `Sources/`. FluidAudio's explicit-consent model download and the optional Apple Foundation Models path are the documented exceptions at the dependency and operating-system layers.

## Security reports

Follow [SECURITY.md](SECURITY.md) instead of opening a public issue for a vulnerability.
