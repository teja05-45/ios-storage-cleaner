# Reclaim — iOS Storage Cleaner

A native iOS app that finds duplicate/similar photos, screenshots, large videos, and duplicate contacts **on-device**, so you can review and delete what you don't need. Nothing is uploaded — there is no network code in the app at all (verified by audit: zero `URLSession`/analytics/SDK usage anywhere in the codebase).

> **Status: written and audited, never compiled.** This codebase was authored and audited in an environment without macOS/Xcode — the Swift code has not been compiled and the 73 unit tests have not been executed. The project generator, project file, and Info.plist **have** been mechanically verified. See [Known Limitations](#known-limitations) before treating this as a working build, and `docs/16-audit-report.md` for the full audit.

## Features

- **Similar & Duplicate Photos** — byte-identical duplicates (confirmed by streamed SHA-256 of actual content, never a thumbnail hash) and visually similar bursts (64-bit dHash + union-find clustering), with a heuristic "recommended keep" you can override.
- **Screenshots** — everything the OS itself flags via `PHAsset.mediaSubtypes`.
- **Large Videos** — sorted by real file size, resolved from asset resources.
- **Duplicate Contacts** — Exact tier (shared phone/email) and Probable tier (high name similarity **plus** a secondary signal — name similarity alone can never flag anyone), with a field-diff preview. Ships review-and-delete; automated merge is deliberately not implemented (ADR-02).

Every category feeds one **Review** screen. Nothing is ever deleted without an explicit, itemized confirmation — see [Safety Architecture](#safety-architecture).

## Architecture

```
Core/        — models, errors, pure algorithms. Foundation only, no Photos/Contacts/AVFoundation.
Services/    — the ONLY layer that imports Photos/Contacts/AVFoundation. Protocol-first, so
               everything above is testable with fakes and no entitlements.
UseCases/    — orchestration: scan pipelines + the safety-critical PerformCleanupUseCase.
Features/    — SwiftUI views + @Observable ViewModels/Store (iOS 17 Observation).
Infrastructure/ — ScanCache (on-disk, derived data only), ThumbnailCache, PII-safe Logging.
```

Dependencies flow one way: `Features → UseCases → Services → Core`. **Zero third-party dependencies** — Apple frameworks only (SwiftUI, Photos, Contacts, CryptoKit, Accelerate, Observation, os). Full decision log: `docs/14-implementation-decisions.md`.

## Safety Architecture

```
SCAN → RESULTS → SELECTION → REVIEW → EXPLICIT CONFIRMATION → REVALIDATE → CLEANUP → RESULT
```

Enforced structurally, not by convention:

- `PerformCleanupUseCase.execute(_:confirmed:)` is the **only** method in the codebase that can initiate deletion. It throws without explicit confirmation, re-checks current authorization (a permission revoked while backgrounded aborts the cleanup), and **revalidates every selected ID against the live library immediately before deleting** — vanished assets/contacts are dropped and reported as failures, never silently executed against.
- Deletion has exactly two call sites: `PhotoLibraryServiceLive.deleteAssets` (native OS "Delete X Photos" confirmation as a second net) and `ContactServiceLive.deleteContacts` (no OS equivalent — the in-app confirmation carries the weight).
- `PhotoGroup`/`ContactGroup` make it structurally impossible to select the recommended-keep/primary record — even a caller-seeded illegal state is corrected.
- Cleanup results are never fabricated: counts come from what the OS confirmed; `bytesFreed` comes from an independently re-read device-capacity before/after delta, never from the pre-cleanup estimate.
- `ReclaimTests/SafetyTests/` (18 tests, using protocol fakes, no PhotoKit/Contacts entitlement needed) proves each of these guarantees directly.

## Requirements

Versions are what the project's own configuration declares — **not guesses**:

| Requirement | Version | Source |
|---|---|---|
| macOS | 13.5+ (Ventura, for Xcode 15.2) | Xcode 15.2 release requirements |
| Xcode | **15.2+** | `CreatedOnToolsVersion = 15.2` in project |
| Swift | 5.0+ toolchain (Xcode-bundled) | `SWIFT_VERSION = 5.0` |
| iOS deployment target | **17.0** | `IPHONEOS_DEPLOYMENT_TARGET` |
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = 1`) | project settings |
| Python | 3.8+ (only for the optional project generator) | `scripts/generate_pbxproj.py` |
| CocoaPods / SPM / Carthage | **not used** | no manifests exist |
| Docker | **not applicable** — see [Docker Applicability](#docker-applicability) | audit |

Hardware: any Mac that runs Xcode 15.2. A physical iPhone is needed for real-library testing; the Simulator works for logic/permission flows but has a tiny photo library (see [Troubleshooting](#troubleshooting)).

## Local Setup

### 1. Clone

```bash
git clone <repository-url>
cd <repository-directory>
```

### 2. Open the project

Open **`Reclaim.xcodeproj`** (there is no workspace) in Xcode 15.2+:

```bash
open Reclaim.xcodeproj
```

**First open — what to expect:** this project has never been opened in Xcode. If anything fails to parse, the fallback is File → New → Project (iOS App, SwiftUI, iOS 17), then drag the `Reclaim/` and `ReclaimTests/` folders in — the source code does not depend on the project file. The project file is regenerated from source with the verified command in step 3.

### 3. Resolve dependencies

**Nothing to resolve** — there are no third-party packages. Xcode will not prompt for SPM resolution.

If you ever need to regenerate the Xcode project from source (e.g. after adding files):

```bash
python scripts/generate_pbxproj.py   # verified: detects 43 app + 10 test files,
                                     # deterministic output, runs from any directory,
                                     # exits non-zero if no sources found
```

### 4. Configure signing

1. Xcode → the `Reclaim` target → **Signing & Capabilities**.
2. Check **Automatically manage signing** (already set).
3. Select your **Team** (a free Apple ID works for running on your own device).
4. Change **Bundle Identifier** from `com.reclaim.app` to something unique to you (e.g. `com.yourname.reclaim`) — required for device installs.
5. No capabilities to add. The app intentionally has **no entitlements file** — no iCloud, push, keychain, or associated domains are needed (verified by audit).

### 5. Permissions (already configured — informational)

`Reclaim/Resources/Info.plist` contains exactly two usage descriptions, matching exactly what the app uses:

| Key | Why |
|---|---|
| `NSPhotoLibraryUsageDescription` | On-device scanning of photos for duplicates/similar/screenshots/large videos; deletion via PhotoKit. |
| `NSContactsUsageDescription` | On-device scanning of contacts for duplicates; review before any deletion. |

Deliberately absent: `NSPhotoLibraryAddUsageDescription` (the app only deletes, never adds — flagged for re-confirmation on first real build), camera, location, microphone, network multicast. There is no entitlements file.

### 6. Build

In Xcode: **⌘B** with the `Reclaim` scheme. From the command line:

```bash
xcodebuild \
  -project Reclaim.xcodeproj \
  -scheme Reclaim \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

> *Verification status: the exact invocation shape is standard, but **no xcodebuild command in this README has been executed** — this audit environment has no Xcode. `-scheme Reclaim` matches the target name in the project file; if the scheme differs, `xcodebuild -list -project Reclaim.xcodeproj` prints the actual list (run that first).*

### 7. Run tests

In Xcode: **⌘U** (runs the `ReclaimTests` bundle against the Simulator).

```bash
xcodebuild test \
  -project Reclaim.xcodeproj \
  -scheme Reclaim \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Priority order for a first run:** `ReclaimTests/SafetyTests/` (cleanup-safety guarantees) → `CoreTests/` (algorithms). All 73 tests are pure-logic and need no photo library or special entitlements. *Status: written, never executed — treat failures found here as normal first-build work, not as evidence of a broken design.*

### 8. Run on Simulator

Scheme → destination → pick an iPhone simulator → **⌘R**.

Works in Simulator: scan pipeline over the (small) seeded library, permission prompts and state handling, the confirmation dialog flow, all unit tests.
Does **not** work in Simulator: realistic 10k+ photo performance, real iCloud-synced libraries, the limited-library picker with a real partial selection, thermal/memory behavior at scale.

### 9. Run on a physical iPhone

1. Connect the iPhone; on the phone tap **Trust This Computer**.
2. On the phone: Settings → Privacy & Security → **Developer Mode** → on (requires a restart on iOS 16+).
3. Xcode → destination selector → your device.
4. Signing: your team + unique bundle ID from step 4; on first install the phone needs Settings → General → VPN & Device Management → trust your developer certificate.
5. **⌘R**.

Note: this app is most meaningful on a device with a real photo library — the Simulator cannot exercise its purpose.

### 10. Test permission states

Simulator or device: **Settings → Privacy & Security → Photos (or Contacts) → Reclaim**, then relaunch the app:

- **Denied / Restricted** — Dashboard shows an "Open Settings" prompt row; scanning is disabled; a cleanup attempt would be refused by revalidation (safety-tested).
- **Photos → Limited Access…** — the Dashboard shows the yellow "Only your selected photos are scanned" banner with a button opening the native limited-library picker. This state is a first-class case in the permission model (`.limited` is never collapsed into "authorized").
- To re-trigger the **first-launch** prompt: delete the app (resets to `.notDetermined`), or on the Simulator **Device → Erase All Content and Settings**.

### 11. Clean build

In Xcode: **Product → Clean Build Folder (⇧⌘K)**. From the CLI:

```bash
xcodebuild -project Reclaim.xcodeproj -scheme Reclaim clean
rm -rf ~/Library/Developer/Xcode/DerivedData/Reclaim-*
```

> *Status: shape is standard; not executed in this audit environment (no Xcode).*

## Test Runbook (summary)

| What | Command | Expected |
|---|---|---|
| All unit tests | `xcodebuild test -project Reclaim.xcodeproj -scheme Reclaim -destination 'platform=iOS Simulator,name=iPhone 15'` | 73 tests, all passing — *not yet verified* |
| Debug build | `xcodebuild -project Reclaim.xcodeproj -scheme Reclaim -configuration Debug -destination 'generic/platform=iOS Simulator' build` | `** BUILD SUCCEEDED **` — *not yet verified* |
| Release build | same with `-configuration Release` | *not yet verified* |
| Regenerate project file | `python scripts/generate_pbxproj.py` | "App files: 43, Test files: 10" — **verified** |
| Project-file provenance check | `python scripts/generate_pbxproj.py && git diff --exit-code Reclaim.xcodeproj` | no diff — **verified** |

## Docker Applicability

**Docker cannot build or run the iOS application because Apple's Xcode/iOS SDK/toolchain requires macOS.** Docker is therefore only applicable to auxiliary tooling/services — and this repository contains none: no backend, no server component, no documentation pipeline that needs containerizing. Accordingly, **this repo intentionally contains no Dockerfile, no `docker-compose.yml`, and no `.dockerignore`**. None should be added unless a real non-iOS service is introduced.

## Environment Variables

**This project uses no environment variables** — there are no API keys, no secrets, no `.env` file, and nothing to configure. (Verified by a secrets sweep of the working tree and git history during the audit.)

## Xcode Command-Line Runbook

```bash
xcodebuild -list -project Reclaim.xcodeproj        # discover schemes — run this first
xcodebuild -project Reclaim.xcodeproj -scheme Reclaim \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Reclaim.xcodeproj -scheme Reclaim test \
  -destination 'platform=iOS Simulator,name=iPhone 15'
xcodebuild -project Reclaim.xcodeproj -scheme Reclaim clean
```

> *Not executed in this audit environment (no Xcode). Project name, targets, deployment target (17.0), and bundle IDs above are read directly from the committed project file.*

## Troubleshooting

**"Signing for Reclaim requires a development team"** — Cause: no team selected. Fix: target → Signing & Capabilities → select your team and change the bundle ID to something unique (step 4 of setup).

**Provisioning error on device** — Cause: bundle ID collides with an existing App ID, or the device isn't registered with a free account. Fix: change the bundle ID; with a free Apple ID, remove the app from the device and re-run (free provisioning allows 3 apps per device per 7 days).

**Photos/Contacts permission denied at runtime** — Cause: prior denial persisted in Settings. Fix: Settings → Privacy & Security → Photos/Contacts → Reclaim → allow. The app surfaces this state as an "Open Settings" row rather than a dead end.

**Photos limited access — scan seems partial** — Cause: that is correct behavior, not a bug. Fix/expectation: the Dashboard's yellow banner states "Only your selected photos are scanned"; tap it to add more photos via the native picker.

**Build failure on first open** — Cause: this code has never been compiled; expect to fix something. Fix: start with errors in `Reclaim/Services/*.swift` (framework-API surface) and `ReclaimTests/` (test-target wiring). If the project file itself fails to parse, regenerate (`python scripts/generate_pbxproj.py`) or rebuild the project fresh and re-import the source folders (step 2).

**Package resolution failure** — Cause: none possible; there are no packages. If Xcode shows a resolution error, a stale cache is involved: File → Packages → Reset Package Caches (this should never occur in this repo).

**Simulator has no useful photos** — Cause: seeded Simulator libraries contain a handful of images. Fix: drag photos into the Simulator window to import them, or better, run on a physical device — the app's purpose (real duplicates, real screenshots, real large videos) can't be exercised meaningfully in the Simulator.

**`python` not found (for the generator)** — Cause: generator needs Python 3.8+. Fix: install from python.org or `brew install python`, then `python3 scripts/generate_pbxproj.py`.

**Docker unavailable / Docker questions** — Cause: not applicable. Fix: none needed — see [Docker Applicability](#docker-applicability).

## Known Limitations

Disclosed deliberately, per this project's "never fabricate" principle. Items marked **(audit-fixed)** were defects found and repaired by the audit in `docs/16-audit-report.md`.

- **Never compiled; tests never run.** No Xcode was available when this was written or audited. The project file is now structurally validated and reproducibly generated **(audit-fixed)**, but the first Xcode build may surface Swift compile errors.
- **The core loop is not user-reachable yet.** The scan pipeline, selection model, review store, cleanup use case, and result screen all exist and are safety-tested — but **no category browsing screen wires user taps to selection**, so on the Dashboard today a user cannot accumulate a selection to review. Building those screens against the existing `ReviewStore` API is the next slice of work (audit finding, now stated precisely).
- **No automated contact merge** — review-and-delete with field-diff preview only (ADR-02).
- **Phone normalization is a last-10-digit-suffix heuristic**, not full ITU E.164 parsing (Document 06 §6).
- **No real-device validation** (10k+ photo performance/Instruments, VoiceOver, Dynamic Type, cancellation mid-scan at scale): `Pending real-device validation`.
- **No Instruments memory profile** — static review found no retention paths; no measured numbers exist and none are claimed.
- **Accessibility labels are minimal** — system semantics only; explicit VoiceOver labels/hints on destructive controls remain to be added.
- **Performance numbers: none exist anywhere in this repo.** The algorithmic design (bucketing, bounded concurrency, streaming) is real; measurements proving it at scale are not.

## AI-Assisted Development

This codebase was written and audited by AI agents (Claude; audit by Buffy/Freebuff) from a specification package in `/docs`, with every non-obvious decision recorded as an ADR in `docs/14-implementation-decisions.md` and every audit finding traced in `docs/16-audit-report.md`.
