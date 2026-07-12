<div align="center">

# MacPilot

### One icon. Your whole Mac.

**A native menu-bar cockpit for system health, dual-fan control, voice dictation, calendar launch reminders, and the small actions that keep a Mac flowing.**

[![macOS](https://img.shields.io/badge/macOS-12%2B-111111?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org/)
[![Tests](https://img.shields.io/github/actions/workflow/status/YidaHu/MacPilot/ci.yml?style=flat-square&label=tests)](https://github.com/YidaHu/MacPilot/actions)
[![License](https://img.shields.io/badge/license-MIT-63C174?style=flat-square)](LICENSE)

[Features](#why-macpilot) · [Build](#build-it) · [Safety](#fan-control-safety) · [Architecture](#architecture) · [Contribute](CONTRIBUTING.md)

</div>

---

Your menu bar should not feel like a crowded toolbox.

MacPilot folds the utilities that usually live in separate apps into one calm, native surface. Open it to understand the machine at a glance. Close it and everything disappears back into a single status item.

```text
┌────────────────────────── MacPilot ──────────────────────────┐
│  CPU  38%  ▁▂▅▃▆▇▅        LEFT FAN  2,160 RPM   AUTO         │
│  MEM  19.2 / 64 GB         RIGHT FAN 2,004 RPM   AUTO        │
│  SSD  897 GB FREE          NETWORK   3.4 MB/s    SAFE        │
├──────────────────────────────────────────────────────────────┤
│  ⚡ LOW POWER   ☕ AWAKE   ◐ DARK   🔒 LOCK   🚀 MEETING     │
└──────────────────────────────────────────────────────────────┘
```

## Why MacPilot

| Surface | What it gives you |
| --- | --- |
| **Live overview** | CPU, memory, startup disk, active network, traffic rate, connection risk, and real fan RPM. |
| **Dual-fan control** | Automatic mode, safe presets, and per-fan sliders constrained to the verified SMC range. |
| **Voice cockpit** | A non-activating floating capsule with recording levels, transcription, structured dictation, AI polish, and safe paste recovery. |
| **Meeting rocket** | EventKit watches the calendar and launches a lightweight rocket reminder ten minutes before a meeting. |
| **Quick actions** | Low power, keep awake, screen lock, dark mode, desktop/Dock visibility, cleaning sessions, and Trash cleanup. |
| **One menu-bar icon** | Four focused views—Overview, Fans, Tools, Voice—with a twelve-section settings center. |

## The details that matter

### A voice UI that stays out of the way

Press the global shortcut and a small capsule appears at the bottom of the screen. It never steals focus from the document you are writing. The capsule moves through visible states—recording, transcribing, structuring, complete—and returns the result to the active text field. If Accessibility permission is missing, your words remain available to copy or retry.

Structured dictation has its own editable prompt, while protected rules prevent the prompt from inventing facts or overriding output safety. A bounded retry policy falls back to the raw transcript instead of losing a long recording.

### A reminder you actually notice

MacPilot reads only the calendar information it needs to decide *when* to remind you. Ten minutes before a timed event, a rocket crosses the screen. Turn the feature off and the scheduler stops; turn it on and it resumes without duplicating reminders.

### Native all the way down

The interface is SwiftUI, with AppKit used where macOS-specific window behavior matters. Metrics come from Mach, `host_statistics64`, `getifaddrs`, and filesystem APIs. Calendar reminders use EventKit. Secrets live in Keychain. There is no embedded browser runtime.

## Fan control safety

> [!IMPORTANT]
> Fan *reading* is broadly useful, but the current write path is intentionally scoped to supported **Intel Macs** with verified AppleSMC keys. Apple Silicon fan writing is not advertised or enabled.

MacPilot treats fan control as a privileged, failure-sensitive operation:

- only a closed request contract can reach the helper—never arbitrary SMC keys;
- every target is clamped to the freshly discovered minimum/maximum range;
- manual control uses a short renewable lease;
- timeout, app termination, or XPC invalidation restores Apple automatic mode;
- an independent recovery executable is included for emergencies.

Read [SECURITY.md](SECURITY.md) before changing the helper or SMC code.

## Build it

### Requirements

- macOS 12 or newer
- Xcode Command Line Tools
- Swift 5.7 or newer (Swift 5.9 recommended)

### Test and run

```bash
git clone https://github.com/YidaHu/MacPilot.git
cd MacPilot
swift test
swift run MacPilotApp
```

`swift run` is the fastest development path. To create the signed `.app` bundle and privileged fan helper, add a local `.macpilot-local.env`:

```bash
MACPILOT_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

Then build and verify:

```bash
bash scripts/build-app.sh
codesign --verify --deep --strict build/MacPilot.app
open build/MacPilot.app
```

The local signing file is ignored by Git.

## Permissions and privacy

MacPilot asks for capabilities only when the related feature needs them:

- **Microphone** — voice capture.
- **Accessibility** — one constrained paste action and keyboard-cleaning mode.
- **Calendar** — upcoming timed-event reminders.
- **Keychain** — STT and optional AI-provider secrets.
- **Administrator authorization** — installation of the signed fan helper.

Voice history and migration records live in `~/Library/Application Support/MacPilot`. API keys are never stored there; they remain in the macOS Keychain. The OpenTypeless importer is copy-only and leaves the original data untouched.

## Architecture

```text
MacPilotApp
├── MacPilotCore             presentation state and system-tool model
├── MacPilotMetrics          CPU, memory, disk, network samplers
├── MacPilotFan              SMC discovery, validation, client
│   └── MacPilotFanHelper    privileged lease and automatic recovery
├── MacPilotSystemActions    closed, reversible macOS actions
├── MacPilotCalendar         EventKit scheduler and rocket overlay
└── MacPilotVoice            capture → STT → structure → output → history
```

The Swift package also contains diagnostic and recovery executables so low-level fan behavior can be inspected independently of the menu-bar UI.

## Project status

MacPilot is an active, personal open-source project. The current implementation has automated coverage for metrics math, reminder decisions, SMC codecs and request validation, helper lease recovery, voice pipeline transitions, prompt boundaries, migration idempotency, and clipboard restoration.

Still on the runway:

- Apple notarization and a public binary release;
- broader hardware validation;
- realtime WebSocket STT providers;
- longer sleep/wake soak testing.

## Contributing

Issues and focused pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), and keep fan-control changes narrow, testable, and recoverable.

## License

MIT © 2026 [YidaHu](https://github.com/YidaHu)

