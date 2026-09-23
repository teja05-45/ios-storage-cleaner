# 18 — Validation Matrix

**Date:** 2026-09-23
**Environment:** Windows 11 (Git Bash 2.53.0.windows.2 + PowerShell), Python 3.11.9, Docker Desktop 29.6.1 installed. **No macOS, no Xcode, no Swift toolchain, no iOS Simulator, no physical iPhone.**
**Rule in force:** every PASS below was executed on this machine with output captured; everything requiring Apple's toolchain is BLOCKED/NOT RUN — never fabricated.

---

## Project-Type Determination (verified by inspection)

| Component | Finding | Evidence |
|---|---|---|
| Frontend (web) | **NONE** | no `package.json`, no web framework files |
| Backend | **NONE** | no server code, no `requirements.txt`, no Node project |
| Database | **NONE** | no Core Data/SQLite/external DB; PhotoKit/Contacts are source of truth |
| Docker config | **NONE (correct)** | no Dockerfile/compose files; iOS cannot run in Linux containers |
| CI/CD | **NONE** | no `.github/`, no pipeline configs |
| Dependencies | **ZERO third-party** | no SPM/CocoaPods/Carthage manifests |
| Native iOS app | **YES** | `Reclaim.xcodeproj`, 53 app Swift files (SwiftUI, Photos, Contacts, AVKit, CryptoKit), 16 test files |
| Secrets / env vars | **NONE required** | sweep clean; no `.env` |

## Validation Matrix

| Component | Test | Command/Procedure | Result | Evidence |
|-----------|------|-------------------|--------|----------|
| Static | Network-code sweep | `grep -rnE "URLSession\|Alamofire\|Firebase\|dataTask\|NWPathMonitor\|Analytics" Reclaim/` | **PASS** | 0 app-code hits (only Info.plist privacy strings) |
| Static | Secrets sweep | `grep -rniE "api[_-]?key\|password\|private key\|\.p12\|\.mobileprovision\|Bearer " Reclaim/ scripts/` | **PASS** | 0 hits |
| Static | Debug patterns | `grep -rn "print(\|fatalError\|NSLog" Reclaim/` | **PASS** | 0 hits |
| Static | TODO/FIXME sweep | `grep -rnE "TODO\|FIXME\|XXX\|HACK" Reclaim/ ReclaimTests/` | **PASS** | 0 hits |
| Static | Force try/cast (app code) | `grep -rn "try!\|as!" Reclaim/` | **PASS** | only `try! await` fixtures inside tests |
| Static | Deletion call sites | `grep -rn "PHAssetChangeRequest.deleteAssets\|saveRequest.delete\|store.execute(saveRequest)" Reclaim/` | **PASS** | exactly 2 real call sites (PhotoLibraryServiceLive, ContactServiceLive) |
| Config | Info.plist validity | `python -c "import plistlib; plistlib.load(...)"` | **PASS** | parses; 14 top-level keys; exactly 2 usage descriptions |
| Build | Project-file determinism | `python scripts/generate_pbxproj.py` × 2, byte-compare | **PASS** | byte-identical; matches committed pbxproj (53+16 files) |
| Build | Generator fail-loud contract | run generator from empty directory | **PASS** | exits 1, writes no stray project |
| Build | PowerShell compatibility | same generator + git commands via `powershell.exe -NoProfile` | **PASS** | identical behavior to Git Bash |
| Tests | XCTest unit suite (131) | `xcodebuild test -project Reclaim.xcodeproj -scheme Reclaim -destination 'platform=iOS Simulator,name=iPhone 15'` | **BLOCKED** | no Xcode/Swift on this machine (`which xcodebuild swiftc swift` → not found) |
| iOS | Debug build | `xcodebuild ... -configuration Debug build` | **BLOCKED** | same |
| iOS | Release build | `xcodebuild ... -configuration Release build` | **BLOCKED** | same |
| iOS | Simulator run | Xcode ⌘R on simulator | **BLOCKED** | no simulator |
| iOS | Physical device install/run | Xcode ⌘R on iPhone | **BLOCKED** | no macOS, no device |
| iOS | PhotoKit/Contacts runtime (prompts, limited picker, native delete dialog) | device/simulator manual pass | **BLOCKED** | requires iOS runtime |
| Performance | 10,000+ photo scan / Instruments | Instruments Time Profiler + Allocations on device | **NOT VERIFIED** | requires physical device; no numbers exist, none claimed |
| Accessibility | VoiceOver / Dynamic Type behavioral pass | device with accessibility enabled | **BLOCKED** | static labels/hints verified in code only |
| Docker | Build/run | N/A | **NOT APPLICABLE** | iOS app; no containerizable component; no Docker files exist (correct) |
| Git | History hygiene | `git status`, `git log`, `git rev-list --count HEAD` | **PASS** | clean tree, coherent conventional history on `main` |

## Test-Suite Accounting (verified this audit)

An error in the audits' own reporting was found and corrected during this verification (errata in `docs/16` and `docs/17`): the original per-suite split (55/18) did not match the first commit's actual counts.

| Point in history | CoreTests | SafetyTests | Total | Verification method |
|---|---|---|---|---|
| First commit (`89585bc`) | 64 | 9 | **73** | `git show <sha>:<file> \| grep -c "func test_"` per file |
| After docs/17 pass | 99 | 9 | **108** | grep per file |
| After OPEN-3 | 99 | 12 | **111** | grep per file |
| Current (after pruning/scan-pipeline/ViewModel pass) | 119 | 12 | **131** | `grep -rc "func test_" ReclaimTests/` — executed |

> **Bugs found while writing the new tests (both fixed in the same commits):** (1) post-cleanup pruning rebuilt surviving groups with empty selection and dropped the user's keep override — survivors of a partial cleanup lost their marks; (2) `DashboardViewModel` never applied the pipeline's returned `.cancelled` status, leaving the scan UI stuck on `.scanning(...)` forever after Cancel. Both are covered by the new tests.

## What a Reviewer Should Trust

- **Trusted as verified:** everything in the PASS rows above — plain-text, reproducible, executed with captured output on this machine.
- **Trusted by inspection only:** algorithm correctness claims, safety-architecture claims, and UI behavior — the code is written and reviewed against the spec, with 131 tests ready to prove the critical properties, but **no test has ever been executed by anyone**.
- **Not trusted / unknown:** whether the project compiles (first-build errors are likely and normal), all runtime behavior, all performance characteristics. The README and this matrix say so explicitly rather than implying otherwise.

## Recommended Next Actions (in order)

1. On a Mac with Xcode 15.2+: open `Reclaim.xcodeproj`, build (⌘B), fix any compile errors.
2. Run the 131 tests (⌘U) — `SafetyTests` first; a failure there is a real bug in the destructive-path guarantees.
3. Simulator pass over the permission matrix (denied / limited / authorized; Photos and Contacts).
4. Physical-device checklist (README) — full core loop, partial-failure and stale-selection behavior.
5. Instruments pass on a large real library before making any performance claim.
