# Contributing

Bug reports and focused pull requests are welcome.

## Before opening a pull request

1. Explain the user-visible problem or improvement in an issue.
2. Keep changes scoped and preserve the local-first privacy model.
3. Add or update tests for logic in `VaakyaCore`.
4. Run `make test` and `make audit`.
5. Describe any manual macOS permission or app-integration testing.

## Privacy invariant

Do not add analytics, telemetry, accounts, or automatic update checks. Runtime networking is limited to the reviewed local and remote inference clients in the app target. Remote text egress must remain off by default and require an explicit per-run confirmation. `VaakyaCore` must remain free of networking and AppKit dependencies.

## Security reports

Follow [SECURITY.md](SECURITY.md) instead of opening a public issue for a vulnerability.
