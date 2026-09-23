# Reclaim — iOS Storage Cleaner

A native iOS app that finds duplicate/similar photos, screenshots, large videos, and duplicate contacts **entirely on-device**, so you can review and delete what you don't need. There is no network code in the app at all (verified by audit: zero `URLSession`/analytics/SDK usage anywhere in the codebase) and no backend behind it.

> **Status: core loop complete as code; never compiled.** All four category selection screens, the inspectable Review flow, and the safety-critical cleanup pipeline exist and are unit-tested (111 tests) — but no Xcode has ever been available where this was written, so **the Swift code has never been compiled and no test has ever been executed**. The project file, Info.plist, and all static audits **have** been mechanically verified on Windows. See [Validation Status](#validation-status) and [Known Limitations](#known-limitations) before treating this as a working build. Full audit trail: `docs/16-audit-report.md`, `docs/17-final-engineering-audit.md`, `docs/18-validation-matrix.md`.

---

## What This Repository Is (and Is Not)

| Question | Answer (verified by repository inspection) |
|---|---|
| Project type | **Native iOS application only** — Swift 5, SwiftUI, iOS 17+, iPhone only |
| Frontend (web) | None. No `package.json`, no web framework, no build tooling |
| Backend | None. No server, no API, no `requirements.txt`, no Node project |
| Database | None. No Core Data, no SQLite, no external DB — PhotoKit/Contacts are the source of truth; a JSON scan cache (IDs, hashes, sizes) is derived data only |
| Docker | Not applicable — see [Docker](#docker) |
| CI/CD | None configured (no `.github/`, no pipelines) |
| Third-party dependencies | **Zero.** No SPM/CocoaPods/Carthage manifests exist. Apple frameworks only |
| Environment variables / secrets | **None required.** No `.env`, no API keys (verified by secrets sweep of tree + history) |

Because the product is a native iOS app, **the application cannot be built or run on Windows** — Apple's Xcode and iOS SDK exist only on macOS. Windows is used here for everything that *doesn't* require Apple's toolchain; see [Windows Support](#windows-support) for the exact split and [Windows Testing](#windows-testing) for what was actually executed.

## Features

- **Exact Duplicates** — byte-identical copies confirmed by streamed SHA-256 over actual content (bucketed by dimensions → file size first; a thumbnail hash is never treated as proof).
- **Similar Photos** — visually similar bursts via 64-bit dHash + Hamming distance + union-find clustering, with an explainable, overridable "Suggested to keep" (never "best"; no ML/face-detection claims).
- **Screenshots** — everything the OS itself flags via `PHAsset.mediaSubtypes`; flat grid, most recent first, Select All / Deselect All.
- **Large Videos** — ranked by real file size with duration/resolution/date, sort options, and full in-app playback preview **before** selection (a thumbnail is not sufficient evidence to delete a video).
- **Duplicate Contacts** — Exact tier (shared phone/email) and Probable tier (high name similarity **plus** a secondary signal — name similarity alone can never flag anyone), with a per-field would-be-lost preview. Review-and-delete only; automated merge deliberately not implemented (ADR-02).
- **One Review screen** aggregates every category's selection with per-item inspection/removal, then one explicit confirmation gate.

Every item goes through the same pipeline, with no shortcuts:

```
SCAN → RESULTS → SELECTION → REVIEW → EXPLICIT CONFIRMATION → REVALIDATE → CLEANUP → RESULT
```

## Safety Architecture

Enforced structurally, not by convention:

- `PerformCleanupUseCase.execute(_:confirmed:)` is the **only** method in the codebase that can initiate deletion. It throws without explicit confirmation and on empty selection, re-checks current authorization (a permission revoked while backgrounded aborts the cleanup), and **revalidates every selected ID against the live library immediately before deleting** — vanished assets/contacts are dropped from the executable set and reported as failures, never silently executed against.
- Deletion has exactly **two** call sites: `PhotoLibraryServiceLive.deleteAssets` (triggers the native OS "Delete X Photos" confirmation as a second safety net) and `ContactServiceLive.deleteContacts` (no OS equivalent exists — the in-app confirmation carries the weight). Verified by grep during audit.
- `PhotoGroup`/`ContactGroup` make it structurally impossible to select the recommended-keep/primary record — even a caller-seeded illegal state is corrected.
- After cleanup, the UI prunes exactly the IDs the OS confirmed deleted (`CleanupSummary.deletedPhotoAssetIDs` / `deletedContactIDs`) — survivors of a partial deletion stay visible alongside their reported failure.
- Results are never fabricated: counts come from what the OS confirmed; `bytesFreed` comes from an independently re-read device-capacity before/after delta, never the pre-cleanup estimate.
- `ReclaimTests/SafetyTests/` (12 tests, protocol fakes, no entitlements needed) proves each of these guarantees directly.

## Architecture

```
Reclaim/
├── App/                 — entry point + AppEnvironment (composition root)
├── Core/                — models, errors, pure algorithms. Foundation only.
│                          No Photos/Contacts/AVFoundation imports.
├── Services/            — the ONLY layer that imports Photos/Contacts/AVFoundation.
│                          Protocol-first: everything above is testable with fakes.
├── UseCases/            — orchestration: scan pipelines + PerformCleanupUseCase.
├── Features/            — SwiftUI views + @Observable ViewModels (iOS 17 Observation),
│                          one folder per screen area (Dashboard, PhotoCleanup,
│                          Screenshots, LargeVideos, Contacts, Review, CleanupResult).
├── Infrastructure/      — ScanCache (on-disk, derived data only), ThumbnailCache, PII-safe logging.
├── UI/                  — shared components (AssetThumbnailView), theme, modifiers.
└── Resources/           — Info.plist, Assets.xcassets.
ReclaimTests/            — CoreTests (99) + SafetyTests (12). All pure logic; no device needed.
scripts/                 — generate_pbxproj.py (deterministic Xcode project generator).
docs/                    — 01–12 spec package, 13–15 analysis/decisions/validation,
                          16–18 audit reports and validation matrix.
```

Dependencies flow one way: `Features → UseCases → Services → Core`. Every non-obvious decision is recorded as an ADR in `docs/14-implementation-decisions.md`.

## Requirements

Versions are what the project's own configuration declares — not guesses:

| Requirement | Version | Source |
|---|---|---|
| macOS (to build/run the app) | 13.5+ (Ventura) | Xcode 15.2 release requirements |
| Xcode | **15.2+** | `CreatedOnToolsVersion = 15.2` in the project file |
| Swift | 5.0+ toolchain (Xcode-bundled) | `SWIFT_VERSION = 5.0` |
| iOS deployment target | **17.0** | `IPHONEOS_DEPLOYMENT_TARGET` |
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = "1"`, portrait) | project settings |
| Physical iPhone | Needed for meaningful testing (real photo library); Simulator works for logic/permission flows | see [Simulator Testing](#ios-simulator-testing) |
| Git | Any recent version (verified with 2.53 on Windows) | this audit |
| Python | 3.8+ — **only** for the optional project-file generator (verified with 3.11.9) | `scripts/generate_pbxproj.py` |

## Windows Support

### What Windows CAN be used for

All of the following are verified working in this repository's audit environment (Windows 11, Git Bash and PowerShell):

- **Cloning and all Git operations** — commit, log, diff, push (used throughout the audit trail).
- **Reading and reviewing the complete source** — all 53 app + 16 test Swift files, docs, and project configuration are plain text.
- **Repository validation** — the static audits in [Windows Testing](#windows-testing) (network/secrets/debug-pattern/TODO sweeps, deletion-call-site checks, test counts).
- **Regenerating the Xcode project file** — `python scripts/generate_pbxproj.py` (verified from both Git Bash and PowerShell; deterministic, byte-identical output, fail-loud on empty source trees).
- **Info.plist validation** — parsed with Python's `plistlib` (verified).
- **Documentation work and CI inspection** (if CI is added later).

### What Windows CANNOT do

- Build the `.app` or compile any Swift — no `swiftc`/`xcodebuild` exists on Windows.
- Run the iOS Simulator or an iOS target.
- Sign or install the application on an iPhone.
- Execute PhotoKit/Contacts against a real device — therefore no scan, permission, or deletion behavior can be exercised.
- Run the 111 unit tests — they are XCTest, which requires Xcode's toolchain.

This is an Apple platform restriction, not a project limitation. Nothing in this repository pretends otherwise; there are no fake `npm`/`pytest` commands because there is no Node/Python project here.

## macOS / iOS Setup (the real build path)

### 1. Clone

```bash
git clone https://github.com/teja05-45/ios-storage-cleaner.git
cd ios-storage-cleaner
```

```bash
git status   # should report a clean working tree on branch main
```

### 2. Open the project

Open **`Reclaim.xcodeproj`** (there is no workspace) in Xcode 15.2+:

```bash
open Reclaim.xcodeproj
```

First-open expectations: this project has never been opened in Xcode (see Known Limitations). If anything fails to parse, the project file is reproducible from source:

```bash
python scripts/generate_pbxproj.py    # verified: 53 app + 16 test files,
                                      # deterministic, runs from any directory,
                                      # exits non-zero if no sources found
```

### 3. Resolve dependencies

**Nothing to resolve** — there are no third-party packages. Xcode will not prompt for SPM resolution.

### 4. Configure signing

1. Target `Reclaim` → **Signing & Capabilities** → **Automatically manage signing** (already set).
2. Select your **Team** (a free Apple ID works for personal-device installs).
3. Change **Bundle Identifier** from `com.reclaim.app` to something unique (e.g. `com.yourname.reclaim`) — required for device installs.
4. No capabilities to add. The app intentionally ships **no entitlements file** (no iCloud, push, keychain, associated domains — verified).

### 5. Permissions (pre-configured — informational)

`Reclaim/Resources/Info.plist` contains exactly two usage descriptions, matching exactly what the app uses:

| Key | Why |
|---|---|
| `NSPhotoLibraryUsageDescription` | On-device scanning (duplicates/similar/screenshots/videos) and PhotoKit deletion. |
| `NSContactsUsageDescription` | On-device duplicate-contact detection; review before any deletion. |

Deliberately absent: `NSPhotoLibraryAddUsageDescription` (the app only deletes, never adds), camera, location, microphone.

### 6. Environment variables

**No environment variables are required** — no API keys, no secrets, no `.env` file, nothing to configure. Verified by a secrets sweep of the working tree and git history.

## Build

In Xcode: **⌘B** with the `Reclaim` scheme (created from the single `Reclaim` target; run `xcodebuild -list -project Reclaim.xcodeproj` if in doubt). From the CLI:

```bash
xcodebuild -project Reclaim.xcodeproj -scheme Reclaim \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

> *Verification status: **not executed** (this documentation was produced on a machine without Xcode). Target/scheme names are read from the committed project file; the invocation shape is the standard one. Treat first-build compiler output as normal work, not a design failure.*

Release:

```bash
xcodebuild -project Reclaim.xcodeproj -scheme Reclaim \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Clean build: **Product → Clean Build Folder (⇧⌘K)**, or:

```bash
xcodebuild -project Reclaim.xcodeproj -scheme Reclaim clean
rm -rf ~/Library/Developer/Xcode/DerivedData/Reclaim-*
```

## Testing

### iOS unit tests (XCTest)

```bash
xcodebuild test \
  -project Reclaim.xcodeproj \
  -scheme Reclaim \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Status: NOT RUN — no Xcode has been available where this repository was written or audited.** The suite is 111 pure-logic tests needing no photo library or entitlements:

| Suite | Tests | Covers |
|---|---|---|
| `CoreTests` | 99 | dHash determinism, Hamming distance + transitive clustering, best-photo scoring, contact normalization (phone suffix/email), name similarity (reordering), duplicate-contact false-positive guard + oversized-group demotion, selection invariants, `ReviewStore` aggregation math, duplicate-detector bucketing (incl. "no hash without candidate partners"), screenshot/video ordering contracts, media formatting, contact field-diff |
| `SafetyTests` | 12 | no confirmation → no deletion, empty selection throws, stale asset skipped **and reported**, photos/contacts permission revoked → zero delete calls, partial framework failure accurately reported, complete failure, success path with independent `bytesFreed`, all-stale, summary carries exactly the OS-confirmed IDs |

Priority for a first run: `SafetyTests` first (cleanup guarantees), then `CoreTests`. Any failure there is a real bug to fix before anything else.

**What these tests cannot cover:** anything requiring the PhotoKit/Contacts runtime (permission prompts, limited-library picker, native delete dialog, real hashing of real assets). That is what the simulator and device passes below are for.

### iOS Simulator Testing

Scheme → destination → an iPhone simulator → **⌘R** (status: not executed here).

Works in Simulator: launch, permission prompts and state handling, scan over the small seeded library, category screens, selection → Review → confirmation dialog flow, all 111 unit tests.

Does **not** work in Simulator: realistic 10k+ photo performance, iCloud-synced libraries, the limited-library picker with a real partial selection, thermal/memory behavior at scale, real screenshots/videos/contacts content.

To test permission states: Settings → Privacy & Security → Photos (or Contacts) → Reclaim → change, then relaunch the app. **Denied/Restricted** renders an "Open Settings" prompt row; **Limited Photos** renders a yellow "Only your selected photos are scanned" banner that opens the native picker. To re-trigger the first-launch prompt, delete the app (resets to `.notDetermined`).

### Physical iPhone Test Checklist

This checklist has **not been executed** — it is the runbook for whoever has a device. Do not mark boxes without doing them.

```
[ ] Connect iPhone; Trust This Computer
[ ] Enable Developer Mode (Settings → Privacy & Security, iOS 16+; requires restart)
[ ] Configure signing (team + unique bundle ID)
[ ] Select device in Xcode; Build (⌘B); Install and launch (⌘R)
[ ] Grant Photos permission; Grant Contacts permission
[ ] Test denied/restricted state (Open Settings prompt)
[ ] Test limited Photos access (banner + native picker)
[ ] Scan photos; scan screenshots; scan videos; scan duplicate contacts
[ ] Review each category screen; select; deselect; use keep override
[ ] Use Select All Recommended (photos) and Select All (screenshots)
[ ] Preview a video before selecting it
[ ] Open Review; remove an item; verify totals update
[ ] Cancel cleanup from Review; verify selections are preserved
[ ] Confirm cleanup; accept native OS delete dialog; verify Cleanup Result
[ ] Decline native OS delete dialog; verify honest partial-failure reporting
[ ] Delete an asset externally between scan and confirm; verify stale handling
[ ] Revoke a permission in Settings while backgrounded; foreground; verify re-check
[ ] Verify Photos/Contacts state in their own apps after cleanup
[ ] VoiceOver pass over scan + destructive controls
[ ] Dynamic Type at accessibility sizes
```

### Frontend / Backend / API / Database / Integration / E2E testing

**Not applicable.** This repository contains no web frontend, no backend, no API, and no database — those test layers have nothing to run against. The iOS app is self-contained: its "integration surface" is PhotoKit/Contacts on a device, covered by the simulator/device passes above.

## Docker

**Docker is not applicable to this component.** The iOS application cannot be built or run in any Linux container because Apple's Xcode/iOS SDK/toolchain requires macOS. This repository contains no backend or auxiliary service that could meaningfully be containerized, and deliberately ships **no Dockerfile, no `docker-compose.yml`, no `.dockerignore`**. None should be added unless a real non-iOS component is introduced. (Docker Desktop 29.6.1 is installed on the audit machine; no container was built because there is nothing to build — a fake Dockerfile would violate this repo's no-fabrication rule.)

## Windows Testing (executed)

Every check below was actually executed on Windows during the final audit. Results are reproduced verbatim; nothing is marked PASS that wasn't run.

| # | Check | Command (PowerShell-compatible) | Result |
|---|---|---|---|
| V1 | No network code | `grep -rnE "URLSession\|Alamofire\|Firebase\|dataTask\|NWPathMonitor\|Analytics" Reclaim/` | **PASS — 0 app-code hits** |
| V2 | No secrets | `grep -rniE "api[_-]?key\|password\|private key\|\.p12\|\.mobileprovision" Reclaim/ scripts/` | **PASS — 0 hits** |
| V3 | No debug prints / fatal errors | `grep -rn "print(\|fatalError\|NSLog" Reclaim/` | **PASS — 0 hits** |
| V4 | No TODO/FIXME/XXX/HACK | `grep -rnE "TODO\|FIXME\|XXX\|HACK" Reclaim/ ReclaimTests/` | **PASS — 0 hits** |
| V5 | No force try / force cast in app code | `grep -rn "try!\|as!" Reclaim/` | **PASS — only test-file `try! await` fixtures** |
| V6 | Info.plist validity | `python -c "import plistlib; plistlib.load(open('Reclaim/Resources/Info.plist','rb'))"` | **PASS — parses, 14 keys, correct usage strings** |
| V7 | Project-file provenance + determinism | `python scripts/generate_pbxproj.py` twice, compare | **PASS — byte-identical, matches committed file** |
| V8 | Deletion call-site count | `grep -rn "PHAssetChangeRequest.deleteAssets\|saveRequest.delete\|store.execute(saveRequest)" Reclaim/` | **PASS — exactly 2 real call sites** |
| V9 | Test count | `grep -rc "func test_" ReclaimTests/` | **PASS — 111 (99 Core + 12 Safety)** |
| V10 | Generator fail-loud contract | run from empty directory | **PASS — exits 1, writes nothing** |
| V11 | Git hygiene | `git status`, `git log --oneline` | **PASS — clean tree, coherent history on `main`** |

Blocked on Windows (requires macOS): Xcode Debug/Release builds, the 111-test XCTest run, Simulator run, device install, PhotoKit/Contacts runtime behavior, performance measurement. See `docs/18-validation-matrix.md` for the complete matrix with statuses.

## Performance Testing

**No performance numbers exist anywhere in this repository — none are claimed.** The design targets 10,000+ photos / 1,000+ videos via metadata-only enumeration, time-window bucketing (never all-pairs similarity over the library), bounded `TaskGroup` concurrency (`min(core count, 4)`, a named tunable), streamed hashing (never full buffering), and cooperative cancellation at every phase boundary. **10,000-asset validation: NOT VERIFIED** — it requires a physical device and Instruments, per `docs/18`.

## Security & Privacy

- **On-device only:** zero network code (V1), `isNetworkAccessAllowed = false` on every PhotoKit request (no iCloud fetches), no analytics/telemetry SDKs (there are no third-party SDKs at all).
- **No secrets:** no API keys, tokens, certificates, or credentials anywhere in the tree or history (V2). No `.env` needed; do not add one.
- **PII-safe logging:** the `Log` API accepts only primitives/aggregates — no call site can interpolate a contact name, phone number, email, or asset identifier.
- **Minimal data at rest:** the on-disk cache stores IDs/hashes/sizes/timestamps only — never thumbnails, never contact field values; contacts are never cached across launches.
- **Minimal permissions:** exactly two usage descriptions; no entitlements file; screenshots identified via the OS's own subtype flag rather than heuristics.

## Troubleshooting

**"Signing for Reclaim requires a development team"** — No team selected. Fix: target → Signing & Capabilities → select your team and change the bundle ID (setup step 4). Verification: build succeeds.

**Provisioning error on device** — Bundle ID collides with an existing App ID, or the device isn't registered with a free account. Fix: change the bundle ID; with a free Apple ID remove the app and re-run (free provisioning allows 3 apps per device per 7 days).

**Photos/Contacts permission denied at runtime** — Prior denial persisted. Fix: Settings → Privacy & Security → Photos/Contacts → Reclaim → allow. The app surfaces this state as an "Open Settings" row, not a dead end.

**"Photos limited access — scan seems partial"** — That is correct behavior. The Dashboard's yellow banner states "Only your selected photos are scanned"; tap it to add photos via the native picker.

**Build failure on first open** — Expected possibility: this code has never been compiled. Start with `Reclaim/Services/*.swift` (framework API surface) and `ReclaimTests/` (test-target wiring). If the project file itself fails to parse: `python scripts/generate_pbxproj.py` from the repo root (verified fail-loud: it refuses to emit an empty project).

**Line-ending warnings on Windows (`LF will be replaced by CRLF`)** — Expected: the repository stores LF; Git for Windows' default `core.autocrlf` converts on checkout. Harmless. Do not "fix" by committing CRLF — keep `git config core.autocrlf true` locally or add a `.gitattributes` if the team prefers pinning.

**`python` not found (generator only)** — Install Python 3.8+ (`python3 scripts/generate_pbxproj.py` also works on macOS).

**Simulator has no useful photos** — Seeded simulator libraries are tiny. Drag photos into the simulator window, or better, test on a physical device — the app's purpose (real duplicates, screenshots, videos, contacts) can't be exercised meaningfully otherwise.

**Docker questions** — Not applicable; see [Docker](#docker). Nothing to install or run.

## Release Validation

Before any release, on a Mac with Xcode 15.2+:

1. Debug build succeeds (`xcodebuild ... -configuration Debug build`).
2. Release build succeeds (`-configuration Release`).
3. All 111 tests pass (`xcodebuild test ...`).
4. Physical-device checklist (above) completed — permission matrix, full cleanup loop, partial-failure and stale-selection behavior, VoiceOver/Dynamic Type.
5. Performance pass recorded on a real library (Instruments Time Profiler + Allocations) — until then, no performance claim may be made.
6. Re-run the Windows static battery (V1–V11) — all must remain PASS.

## Git Workflow

Single-branch (`main`) history; every commit is one coherent engineering unit (feat/fix/test/docs/refactor/chore) with a body explaining the *why* and citing the governing spec/audit item. Verify provenance of the project file any time with:

```bash
python scripts/generate_pbxproj.py && git diff --exit-code Reclaim.xcodeproj/project.pbxproj
```

(verified: no diff). Current commit count: see `git rev-list --count HEAD`.

## Known Limitations

- **Never compiled; tests never executed.** The single largest open item. Everything else below is smaller than this.
- **No real-device validation** (permission prompts, limited picker, native delete dialog, 10k+ performance/Instruments, VoiceOver/Dynamic Type behavior): `Pending real-device validation`.
- **No automated contact merge** — review-and-delete with field-diff preview only (ADR-02, deliberate: a botched merge has no Recently-Deleted-style undo).
- **Phone normalization is a last-10-digit-suffix heuristic**, not full ITU E.164 parsing (Document 06 §6).
- **App icon artwork is intentionally absent** — the asset catalog ships a placeholder manifest with no PNG (a non-fatal build warning). Fabricating artwork was judged worse than shipping the warning.
- **On-disk scan cache is constructed but unwired** into the scan read path (ADR-07 keeps it to derived data only; incremental rescans are future work, documented at the composition root).

## Validation Status

| Layer | Status |
|---|---|
| Static audits (network, secrets, debug patterns, TODOs, call sites, plist, provenance) | **PASS — executed on Windows** (V1–V11 above) |
| Xcode Debug/Release build | **BLOCKED — no macOS toolchain available** |
| Unit tests (111) | **NOT RUN — requires Xcode** |
| Simulator pass | **NOT RUN — requires macOS** |
| Physical iPhone validation | **NOT RUN — requires device** |
| Performance (10k+ assets) | **NOT VERIFIED — requires device** |

Full matrix with commands and evidence: `docs/18-validation-matrix.md`. Audit narrative: `docs/16-audit-report.md`, `docs/17-final-engineering-audit.md`.

## AI-Assisted Development

This codebase was written, audited, and extended by AI agents (Claude; audit/continuation by Buffy/Freebuff) from the specification package in `docs/01–12`, with every non-obvious decision recorded as an ADR in `docs/14-implementation-decisions.md` and every audit finding — including errors found in the audits' own reporting — traced in `docs/16`–`18`.
