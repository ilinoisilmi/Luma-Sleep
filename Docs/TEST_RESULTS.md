# Verification record — 10 November 2026

## Automated checks actually passed

| Check | Result | Scope |
| --- | --- | --- |
| Swift core XCTest suite | **40 tests passed; 0 failures** | Real Swift 6.2.1 compilation/execution on x86_64 Linux; no Apple SDK |
| Structural project audit | **76 checks passed** | Required files, plists, entitlements, sources, schemes, assets, local document links and deterministic regeneration |
| Basic app/core source syntax | Passed | Swift frontend parse only; not Apple-framework type checking |
| Health-enabled app/core source syntax | Passed | Same parse check with `HEALTH_ENABLED` set |
| Widget and native UI-test syntax | Passed | Parse only; native tests not executed |
| Generated Xcode project plist lint | Passed | OpenStep project syntax; not an Xcode build |

The 40 tests cover overlapping intervals, source precedence, awake overrides, gaps, midnight, spring/fall daylight saving, travel offsets, missing/unconfirmed days, naps, sleep-day boundaries, efficiency prerequisites, circular regularity, planning, energy minimum-data behavior, session persistence/repeated start/end, import validation/deduplication/round trips, quoted CSV, revisions/undo, Health tombstones, failed writes, malformed backups, v1 migration, future-version refusal, duplicate identifiers and unsafe audio paths.

The logs in `Verification/core-tests.txt` and `Verification/project-audit.txt` record the actual runs. The Swift Testing runner's final “0 tests” line is an additional empty runner; the XCTest summary above it reports the **40 executed tests**.

## Visual checks actually performed

The original 1024-pixel app icon was rendered and visually inspected. Native SwiftUI screens have **not** been rendered in Simulator or on an iPhone. Accessibility, chart layout and small-screen appearance remain checklist items; source-level accessibility provisions are not a completed visual audit.

## Not run / unavailable here

- `xcodebuild` app, widget or simulator builds: no macOS/Xcode/Apple SDK in this environment.
- Native UI tests: three smoke tests are supplied but not executed.
- Signing, provisioning, installation, renewal or upgrade over an existing iPhone app.
- Real HealthKit/Motion permissions and records; background audio, interruptions, storage pressure, battery impact; AlarmKit delivery under lock/Focus/termination; Shortcuts and widget refresh.
- Physical-device behavior: **none verified**. No signed or unsigned iOS binary or IPA is delivered.

## Windows build workflow

The manual GitHub Actions workflow builds `LumaBasic` on a hosted Mac and packages an unsigned device IPA for local Windows signing. It has **not been run on GitHub**. The Bash script syntax, workflow structure and four Python packaging checks were verified locally; their log is in `Verification/windows-workflow.txt`. The packaging tests use synthetic temporary fixtures, not real iOS binaries, and prove only archive layout, executable permissions and rejection of simulator/source/extension inputs. Test archives are deleted and are not delivered.

## Next acceptance gate

Follow `WINDOWS_START_HERE.md`: run **Build Luma for iPhone**, resolve any actual Apple SDK compile errors, then sign/install the successful build through Sideloadly and complete `DEVICE_TESTING.md` on the iPhone. Neither a workflow file nor successful core tests establish an iOS build. If a Mac is later available, `Scripts/verify_on_mac.sh` and the native simulator smoke tests provide additional checks. Enabled hardware-dependent features remain development features until their checklist passes.
