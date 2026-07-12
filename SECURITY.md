# Security policy

## Reporting

Please report security issues privately to **huyidada@gmail.com** with the subject `MacPilot security report`.

Include the affected version or commit, macOS version and hardware, reproduction steps, impact, and any proposed mitigation. Please do not include real API keys, recordings, or unrelated personal data.

## Sensitive surfaces

Changes in these areas require additional review:

- the privileged fan helper and its code-signing requirement;
- SMC discovery, target validation, lease expiry, and automatic recovery;
- Accessibility-driven paste and keyboard-cleaning behavior;
- Keychain access and legacy-data migration;
- process execution and system actions.

MacPilot does not accept arbitrary executable paths, arguments, SMC keys, or unauthenticated helper requests through its public feature interfaces.

## Supported versions

Security fixes track the latest commit on `main` until tagged releases begin.

