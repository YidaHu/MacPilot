# Contributing to MacPilot

Thank you for helping make MacPilot safer and more useful.

## Before opening a pull request

1. Open an issue for changes that alter behavior, permissions, persistence, or privileged operations.
2. Keep each pull request focused on one problem.
3. Add or update tests for behavior changes.
4. Run `swift test` and `swift build` locally.
5. Never commit API keys, signing identities, provisioning data, recordings, databases, or machine identifiers.

## Engineering principles

- Prefer native macOS APIs and small, explicit interfaces.
- Keep UI state separate from sampling and system mutation.
- Treat every privileged action as reversible.
- Preserve the user's last known-good state when sampling fails.
- Do not broaden the SMC helper contract without a concrete safety argument and automated tests.
- Respect reduced motion, keyboard navigation, and VoiceOver labels.

## Commit style

Use concise imperative commits such as:

```text
feat: add network risk detail
fix: restore automatic fan mode on disconnect
test: cover structured dictation fallback
```

## Reporting a security issue

Do not open a public issue for vulnerabilities involving the privileged helper, Keychain, permissions, or arbitrary command execution. Follow [SECURITY.md](SECURITY.md).

