# Luma Sleep

An original native SwiftUI sleep diary and planner for **Ilmi's iPhone 14 Pro Max on iOS 27.2**, with a deployment target of **iOS 17.0**. No wearable, account, subscription or cloud service is needed for the core app.

**Delivery status:** source project, generated Xcode project, assets, examples and tests. This is a development build candidate. The core Swift tests ran successfully on Linux; **the iOS targets have not been compiled, signed, run in Simulator, or tested on an iPhone** in this environment. There is no installable IPA in this package. Read `Docs/TEST_RESULTS.md` before relying on sensor or alarm behavior.

## Start from Windows — no Mac ownership required

Follow **[WINDOWS_START_HERE.md](WINDOWS_START_HERE.md)** for the complete click-by-click route:

1. Upload this folder's contents, including `.github`, to your own **private GitHub repository**.
2. Open **Actions → Build Luma for iPhone → Run workflow**. GitHub's hosted Mac runs the tests and compiles `LumaBasic` for an actual iPhone.
3. After a successful run, download **LumaSleep-unsigned-ipa** under Artifacts and extract its ZIP to obtain the `.ipa`.
4. Use **Sideloadly on Windows**, your own Apple Account and a USB cable to sign and install that IPA. Enable Developer Mode and trust your developer profile when the phone requests them.
5. Test a short diary session, then renew signing within seven days using the same account and bundle ID. Do not uninstall to refresh; export backups regularly.

The workflow needs no Apple signing secrets. It uses GitHub's Actions allowance, with potential overage charges if billing is enabled. It has been prepared and structurally checked here, **not executed on GitHub**; the first Xcode compile and device installation remain acceptance steps. The included IPA packager rejects simulator/source inputs and preserves executable permissions; it does not sign the app.

Optional direct Mac installation, the Health scheme, renewal and diagnostic commands are in **[BUILD_AND_INSTALL.md](Docs/BUILD_AND_INSTALL.md)**.

## What's here

- Today, Track, History, Insights and Settings in SwiftUI; adaptive midnight/daylight colors, semantic text sizes, labeled controls and a low-glare bedside display.
- Manual diary, naps, awakenings, subjective quality, notes/tags, revision history and persistent bedtime sessions.
- Read-only incremental HealthKit integration in the optional `LumaHealth` scheme; preserved provenance and deleted-record handling.
- Conservative Core Motion history suggestions for human review; no fabricated sleep detection.
- Explicit optional microphone sessions: on-device level events, no raw audio retained by default, bounded opt-in full recordings, interruptions and deletion.
- CSV/JSON preview, row errors, duplicate detection, exports, versioned backup/restore and local deletion.
- Interval reconciliation, known-stage timelines, source priority, day/week/month history, regularity, coverage-aware shortfall and qualified habit comparisons.
- A labeled, unvalidated planning curve with cautious check-in adjustment. Not a medical or performance prediction.
- Weekday/weekend planning, wind-down/bedtime/habit notifications and a fixed wake alarm through AlarmKit on iOS 26+.
- App Shortcuts and an optional App Group widget showing only your plan. Demo data is separate and external integrations are disabled in demo mode.

Some requested experiments are deliberately unavailable: mattress mode, smart light-sleep wake, snore classification, apnea detection, global unlock history, direct vendor logins and Apple Health XML import. Supported alternatives and precise verification limits are documented in **[FEATURE_STATUS.md](Docs/FEATURE_STATUS.md)**.

## Project map

| Location | Purpose |
| --- | --- |
| `App/` | App state, native screens, integrations and design system |
| `Core/` | Dependency-free Swift package with models, persistence, reconciliation and calculations |
| `Widget/` | Optional WidgetKit extension |
| `Config/` | iOS target, signing settings, permissions and entitlements |
| `Scripts/` | Reproducible project generation, asset generation and packaging audit |
| `.github/workflows/` | Manually started hosted-Mac build producing an unsigned iPhone IPA |
| `Examples/` | Valid CSV/JSON and a rejection example |
| `Tests/` | Native UI smoke tests; not run here |
| `Docs/` | Installation, feature matrix, data formats, testing and sources |

## Development commands

From this folder on a Mac:

```bash
swift test --package-path Core -j 1 -Xswiftc -disable-batch-mode
python3 Scripts/audit_project.py
xcodebuild -project LumaSleep.xcodeproj -scheme LumaBasic \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project LumaSleep.xcodeproj -scheme LumaHealth \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The generated project is already included. When you add or remove Swift files, run `python3 Scripts/generate_project.py`. Use `Config/User.xcconfig` for signing overrides you want the generator to preserve; see the example file. No third-party runtime libraries are needed. Python's standard library is sufficient for project generation and audit. Pillow is needed only to regenerate the included icon.

Read **[ARCHITECTURE.md](ARCHITECTURE.md)** and **[ADDING_FEATURES.md](ADDING_FEATURES.md)** before modifying persistence or adding an integration.
