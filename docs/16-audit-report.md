# 16 — Engineering Audit Report

**Audit date:** 2026-09-23
**Auditor environment:** Windows 11 (Git Bash), Python 3.11.9, Docker Desktop 29.6.1. **No macOS, no Xcode, no Swift toolchain, no iOS Simulator, no physical iPhone.**
**Audit method:** full repository inspection (all 43 app sources, 10 test sources, `project.pbxproj`, `Info.plist`, scripts, docs, git state), static sweeps (network, secrets, PII-in-logs, dead code, concurrency patterns), and execution of every command this environment permits. Nothing in this report is asserted as "passing" unless it was actually executed here.

---

# Executive Summary

The repository is a **greenfield, iOS-only SwiftUI app (iOS 17+, Swift 5, zero third-party dependencies)** implementing a photo/contact storage-cleanup flow with an unusually disciplined safety architecture: one destructive pathway, revalidation-before-delete, and honest result reporting. The code quality by inspection is high, and the privacy posture is verified clean (zero network code anywhere in the app).

However, the audit found **two defects that make the repo's own claims untrue** (a broken project generator and a project file it demonstrably did not generate), one stale-configuration defect (`armv7` on an iOS 17 target), one dead-wired composition-root dependency, one silently-dead foreground permission re-check, and one data-accuracy gap (screenshot sizes). All six were **fixed in this audit** and every fix that could be verified on this machine **was verified by execution**. The remaining validation — compiling, running the 73 unit tests, device behavior — is **blocked by the environment**, not by the code, and is documented as such below.

**The headline remains what Document 15 already disclosed: this project has never been compiled.** Nothing in this audit changes that. What this audit does change: the tooling around the code is now reproducible and verified, six real defects are fixed, and the gap between "written" and "verified" is precisely enumerated instead of hand-waved.

---

# Repository Inventory

| Item | Finding |
|---|---|
| Project type | **A. iOS-only application.** No backend, no workspace, no CI config, no Docker files, no Makefile, no `.env`. |
| Xcode project | `Reclaim.xcodeproj` (generated format, `objectVersion = 56`, compatibility "Xcode 14.0", CreatedOnToolsVersion 15.2) |
| Targets | `Reclaim` (app, `com.reclaim.app`), `ReclaimTests` (unit tests, `com.reclaim.app.tests`, TEST_HOST = app) |
| Configurations | Debug + Release, both `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `SWIFT_VERSION = 5.0`, `TARGETED_DEVICE_FAMILY = "1"` |
| Signing | Automatic, no team set (correct for a template; documented in README) |
| Entitlements file | **None** — verified correct: the app needs no entitlements (no iCloud, no push, no keychain sharing, no associated domains) |
| Swift sources | 43 app files across App/Core/Features/Infrastructure/Services/UseCases; 10 test files across CoreTests/SafetyTests |
| Test methods | **73** (`grep -c "func test_"` across `ReclaimTests/`) |
| Third-party dependencies | **Zero.** No `Package.swift`, no SPM/CocoaPods/Carthage manifests. Apple frameworks only (SwiftUI, Photos, Contacts, CryptoKit, Accelerate, Observation, os). |
| Scripts | `scripts/generate_pbxproj.py` (Python 3, stdlib only) |
| Docs | `docs/01`–`15` (spec package) + this report |
| Git state at audit | 1 commit, branch `main`, working tree clean |

**Environment note on `.kilo/`:** the working tree contains a `.kilo/worktrees/` directory holding an older copy of this project's docs/tests (visible in filesystem listings). It is untracked tooling residue, not part of the app, and was excluded from this audit's source review. It should not be committed.

---

# Build Results

| Check | Command | Result |
|---|---|---|
| Clean build | `xcodebuild -project Reclaim.xcodeproj -scheme Reclaim -configuration Debug build` | **BLOCKED BY ENVIRONMENT** — no Xcode/Swift on this machine (`which swift swiftc xcodebuild` returns nothing) |
| Release build | same with `-configuration Release` | **BLOCKED BY ENVIRONMENT** |
| Unit tests | `xcodebuild test …` / `⌘U` | **BLOCKED BY ENVIRONMENT** — 73 tests written, 0 executed |
| Project-file generation | `python scripts/generate_pbxproj.py` | **PASS** — 43 app + 10 test files detected, deterministic output (byte-identical across two runs), correct target path |
| Project-file structure | Python structural validator (see Verification Log) | **PASS** — balanced braces/parens, all 10 required PBX sections present, zero dangling `fileRef`s, zero dangling phase entries, Sources phases = 43 app + 10 test |
| Info.plist parse | `python -c "import plistlib; plistlib.load(…)"` | **PASS** — parses, all expected keys, `armv7` confirmed removed |
| Generator fail-loud check | run in an empty repo copy | **PASS** — exits 1 with a clear error, writes no stray project |

**Honest statement: it is not known whether this project compiles.** The `.pbxproj` is now structurally sound and reproducibly generated, which materially de-risks the "hand-authored project file" concern, but Xcode could still surface Swift compile errors on first build. First-run expectations are documented in the README's Known Limitations.

---

# Test Results

| Suite | Count | Status |
|---|---|---|
| CoreTests (PerceptualHash, Hamming/clustering, NameSimilarity, ContactNormalizer, BestPhotoScoring, CleanupSelection, selection invariants, duplicate-contact false-positive guard) | 55 | **NOT RUN — environment** |
| SafetyTests (confirmation gate, empty selection, stale asset, permission revoked ×2, partial failure, full failure, success path, all-stale) | 18 | **NOT RUN — environment** |
| UI tests | 0 target exists | N/A |

No test in this repository has ever been classified PASS by anyone. They are **written, reviewed by inspection, and unexecuted.** The safety suite is the highest-value asset: it proves the destructive-pathway guarantees with fakes, requiring no PhotoKit/Contacts entitlement — exactly the suite to run first in Xcode.

**Coverage gaps found (not fixed, documented):** no test asserts the recoverable-bytes aggregation math in `ReviewStore.estimatedRecoverableBytes`; no test covers `DuplicateDetector` bucketing with fakes (it requires the protocol, which is fakeable, so this is an opportunity, not a design flaw).

---

# iOS Configuration Audit

- **Bundle ID** `com.reclaim.app` — fine for local development; must be changed for distribution (documented in README signing section).
- **Deployment target 17.0** matches the code's actual API surface (`@Observable`, `onChange(of:) { _, newPhase in }` two-parameter form, `.limited` Photos handling). Consistent.
- **Orientations:** portrait only — matches phone-only (`TARGETED_DEVICE_FAMILY = 1`) product shape.
- **Launch screen:** `UILaunchScreen` dict present (empty = system default). `INFOPLIST_KEY_UILaunchScreen_Generation = NO` in pbxproj is consistent with the explicit plist key.
- **Info.plist in build phases — ISSUE-07 (FIXED):** the generated project listed `Info.plist` in the **Resources copy phase** while `GENERATE_INFOPLIST_FILE = NO` + `INFOPLIST_FILE` already cause Xcode to process and bundle it. Double-copying produces a build-time duplicate-output warning. The generator now emits an empty Resources phase; `INFOPLIST_FILE` remains the single source. Verified in regenerated output.
- **`UIRequiredDeviceCapabilities` — ISSUE-03 (FIXED):** the plist declared `armv7`, a 32-bit ARM capability no iOS 17 device has (iOS 17 requires arm64 devices; App Store validation rejects armv7 on modern targets). Removed outright — the key is optional and omitting it is the correct modern default. Verified by re-parsing the plist.

# PhotoKit Audit

By inspection, against the audit checklist:

- **Authorization:** `PHPhotoLibrary.authorizationStatus(for: .readWrite)` / `requestAuthorization(for:)` — current API, mapped to a first-class `PermissionState` with `.limited` distinct (never collapsed into a boolean). ✅
- **Limited access:** surfaced honestly — `scannedWithLimitedAccess` threads through `PhotoLibraryScanResult` → `ReviewStore` → UI copy "Only your selected photos are scanned" + picker button. ✅
- **Enumeration:** metadata-only (`pixelWidth/Height`, `creationDate`, `mediaSubtypes`), `reserveCapacity`, `autoreleasepool`, batched progress. No pixel work in the enumeration pass. ✅
- **Screenshots:** `mediaSubtypes.contains(.photoScreenshot)` — the OS signal, nothing heuristic. ✅
- **Thumbnails:** 64×64 `fastFormat` via `PHCachingImageManager`, `isNetworkAccessAllowed = false`. Never full-resolution. ✅
- **Byte size:** ADR-01 KVC fast path (`"fileSize"`) with a fully-documented streamed fallback — dual-path is the honest way to use an undocumented key. ✅
- **Deletion:** single call site, `PHAssetChangeRequest.deleteAssets` behind native OS confirmation; result = only what the OS confirmed. ✅
- **ISSUE-05 (FIXED):** screenshots' `byteSize` was left 0 (sizes were only resolved inside duplicate/similarity detection, which screenshots skip) — so recoverable-bytes estimates silently under-reported for selected screenshots. `ScanPhotoLibraryUseCase` now resolves sizes for detected screenshots before cancellation checkpoints, and `PhotoAsset.withByteSize(_:)` was added to keep the copy explicit.

# Contacts Audit

- **Minimal keys:** exactly 5 `CNKeyDescriptor`s (given/family name, phones, emails, image-available). No over-fetch. ✅
- **Normalization:** phone = digits-only with last-10 suffix matching and a precision guard (no suffix-match when *both* sides carry explicit country codes); email = lowercase/trim with opt-in Gmail `+tag` stripping. Documented limitations, not silent ones. ✅
- **False-positive protection:** structural, and the strongest part of the codebase — name similarity **alone can never group** (`.exact` requires shared phone/email; `.probable` requires ≥0.90 name similarity **plus** a weak secondary signal), oversized groups (>8) demoted with penalized confidence, tested explicitly. ✅
- **Merge:** not implemented, by documented decision (ADR-02) — review-and-delete only, with field-diff preview. Honest. ✅
- **Deletion:** `CNSaveRequest` with stale-ID skipping; no OS confirmation exists for this API, so the in-app confirmation dialog carries the weight — which the Review screen provides. ✅
- **Note (not an issue):** `CNAuthorizationStatus.limited` (iOS 18+) is mapped to `PermissionState.limited` but treated as usable; Contacts has no partial-library concept analogous to Photos, so the Dashboard's limited-access banner (Photos-specific copy) only appears for Photos. Acceptable; revisit if Apple gives Contacts a real limited mode.

# Storage Audit

- Device capacity via `.volumeTotalCapacityKey` + `.volumeAvailableCapacityForImportantUsageKey` (Apple's documented "important usage" key — the correct one for this scenario), used = derived, nil propagated to an honest "unavailable" UI state. ✅
- Pre-scan: no fabricated category sizes; the Dashboard shows only real device numbers and, post-scan, selection-derived estimates. ✅
- Post-cleanup: `bytesFreed` = independently re-read before/after capacity delta (capped ≥0), never the estimate; if either reading is nil it reports 0 rather than inventing a number, and the code comments place the burden of "estimate, labeled as estimate" on the result screen. ✅
- Wording in UI copy: "Estimated size… Actual space freed may differ slightly" — honest. ✅

# Cleanup Safety Audit (highest priority)

Verified structurally, by reading every mutating path:

1. **Exactly one destructive entry point:** `PerformCleanupUseCase.execute(_:confirmed:)`. `grep` confirms the only ViewModel call site is `ReviewViewModel.confirmCleanup()`, invoked only from the Review screen's destructive button behind a `confirmationDialog` requiring explicit "Delete Forever". No swipe action, no category screen, no automatic path. **Scan → Delete and Selection → Delete without confirmation are structurally impossible.**
2. **Guard chain:** `confirmed == false` → throw; empty selection → throw; re-check authorization (photos and contacts separately); revalidate every ID against the live framework (`stillValidAssetIDs` / `stillValidContactIDs`); intersect selection with the revalidated set; execute; report counts from what the OS actually confirmed; `bytesFreed` from independent before/after readings.
3. **Stale data:** vanished items are dropped from the executable set **and reported as failures** (never silently executed against, never silently omitted); permission revoked → zero delete calls; all-stale → all-failures result, no delete call at all. Each behavior has a named test.
4. **Selection invariant:** `PhotoGroup`/`ContactGroup` make the keep/primary unselectable at the type level (every mutation guards; even an illegally-seeded initializer is corrected) — tested.
5. **Two delete call sites total:** `PhotoLibraryServiceLive.deleteAssets` and `ContactServiceLive.deleteContacts`. Confirmed by grep.

**Gap found (documented, not fixable without UI work):** `CleanupSummary` reports counts, not IDs, so `ReviewViewModel.confirmCleanup` prunes **all requested** IDs from the store rather than only confirmed-deleted ones — if the OS confirmed a subset, briefly stale UI entries can remain until the next scan. Cosmetic (revalidation on the next cleanup still protects correctness), logged as ISSUE-08/OPEN-1.

# Performance Audit

- **Similarity pipeline:** metadata time-window bucketing (120 s rolling, handles midnight-crossing bursts) → per-bucket dHash → union-find clustering with transitive merging → confidence from average pairwise distance. No O(n²) over the full library; the only all-pairs work is within small buckets. ✅
- **Concurrency:** fixed cap `min(activeProcessorCount, 4)` as a named tunable (ADR-06); a proper semaphore-style TaskGroup feeding loop; screenshots/exact-duplicates/videos need no pixel analysis at all. ✅
- **Memory:** streamed SHA-256 (never full buffering), thumbnails 64×64 only, `autoreleasepool` in enumeration, `NSCache`-backed thumbnail display cache, no full-image retention paths found. ✅
- **Cancellation:** checked at every phase boundary with partial-result preservation; `DashboardViewModel.cancelScan()` cancels the task; scan task guarded against double-start. ✅
- **Real-device numbers:** none exist, none fabricated. `Pending real-device validation` (10k+ photos, Instruments Time Profiler/Allocations) — README states this.

# Memory Audit

Static review only (no Instruments on this machine): no retain cycles found (`[weak self]` used in observer and progress closures); `ScanCache` writes are `queue.async` fire-and-forget with atomic writes; caches bounded (`NSCache.countLimit = 500`). **Instruments validation: BLOCKED BY ENVIRONMENT.** Documented rather than claimed.

# Concurrency Audit

- `TaskGroup` usage is correct and bounded; the feeding loop avoids unbounded task creation.
- `PhotoLibraryServiceLive` bridges callback-based PhotoKit APIs via `withCheckedThrowingContinuation` on a global queue — acceptable; note the continuations resume exactly once per path (checked).
- `@MainActor` on all ViewModels/Store/AppEnvironment; no expensive work on the main actor found.
- **ISSUE-04 (FIXED):** `DashboardViewModel` created a `NotificationCenter.addObserver(forName:object:queue:)` token and discarded it. That API's observer only lives while the token is retained, so the foreground permission re-check (ADR-04 / Document 07 §8) **silently never fired** — permissions appeared to "stick" across a Settings round-trip. The token is now stored and removed in `deinit`.
- **Note (not an issue):** `CleanupService.execute` runs the PhotoKit and Contacts deletions sequentially rather than concurrently. Intentional per ADR-08 (one native confirmation dialog, not overlapping destructive calls). Documented in code.

# Security Audit

- **Secrets sweep** (`grep` for api keys, secrets, passwords, tokens, private keys, `.p12`, `.mobileprovision`): **no secrets found.** The only hits are the word "token" in typography docs and "tokens" in name-matching docs. No `.env` files, no credentials, no certificates in the repo.
- Git history: single initial commit, same clean result.
- No hardcoded signing identity or team ID.

# Privacy Audit

- **Network:** `grep` for `URLSession|Alamofire|Firebase|dataTask|NWPathMonitor|Network\.|upload` across the entire repo → **zero app-code hits**. The only networking-adjacent code is `isNetworkAccessAllowed = false` (explicitly *dis*allowing PhotoKit iCloud fetches — the correct choice: the app only analyzes locally-available resources). ✅
- **Dependencies:** none, so no SDK supply-chain privacy risk. ✅
- **Logging:** `Log` accepts only primitives/enums; every interpolation is `privacy: .public` on non-PII aggregates (counts, durations, category names). No log call accepts a model, name, phone, email, or asset identifier — verified by reading every call site (12 call sites, all aggregates). ✅
- **On-disk cache:** `ScanResult` stores IDs/hashes/sizes/timestamps only — no thumbnails, no contact field values, contacts never cached. ✅
- **Permission strings:** accurate, specific, and honest ("Nothing is uploaded — analysis happens entirely on your iPhone"). ✅

# Accessibility Audit

**BLOCKED BY ENVIRONMENT** for behavioral checks (VoiceOver, Dynamic Type rendering). Static findings: no explicit `accessibilityLabel`/`accessibilityHint` on the destructive confirm button, scan button, or category rows; loading states are text+ProgressView (announceable but not explicitly announced). Logged as OPEN-2 with concrete suggestions in the README. Contrast/typography use system semantic styles (`.secondary`, `.headline`), which is the right baseline.

# UI/UX Audit

By inspection against Document 02: coherent card/spacing/typography system; honest empty/error states; destructive action isolated on the Review screen with explicit dialog; limited-access banner is clear and actionable. **Two functional gaps:**

- **ISSUE-09 (documented, open):** no UI calls any selection mutation (`grep` confirms zero call sites for `toggleSelection`/`toggleScreenshotSelection`/etc. in `Features/`). Selection can only change in unit tests — a user on the Dashboard can never reach the Review screen with items to review, because `currentSelection` will be empty. Dashboard/Review scaffolding is complete; the category browsing screens (photos, screenshots, videos, contacts) are the missing slice. This matches the README's existing "Screenshots/Large Videos/Duplicate Contacts screens not yet built" disclosure — but the audit found it is **broader than disclosed**: the photo group browsing screens are also not wired.
- **ISSUE-10 (documented, open):** `CleanupResultView` is never instantiated outside `ReviewView`'s post-cleanup branch — reachable only after a cleanup that itself is only reachable after the ISSUE-09 fix.

# Docker Audit

**Docker is NOT applicable to the core artifact and no Docker files exist (correct).** As stated verbatim:

> Docker cannot build or run the iOS application because Apple's Xcode/iOS SDK/toolchain requires macOS. Docker is therefore only applicable to auxiliary tooling/services, of which this repository has none.

Docker Desktop is installed on the audit machine; deliberately **no** Dockerfile was created, because there is no component it could meaningfully build or run — a documentation-lint container for a three-file docs folder would be fake support, exactly what the audit brief forbids. This judgment is recorded in the README.

# Documentation Audit

- Spec package (docs 01–15) is thorough and internally consistent; ADRs match the code as audited.
- **ISSUE-01 (FIXED):** `scripts/generate_pbxproj.py` claimed to be the provenance of the committed `.pbxproj`, but had a `ROOT` path bug (resolved to `scripts/` instead of the repo root): it found **0 source files**, silently generated an empty project, and wrote it to `scripts/Reclaim.xcodeproj/` — so the committed project file **could not have come from this script**, invalidating the repo's own reproducibility story. Root-caused (`ROOT` now = parent of `scripts/`), hardened (exits non-zero if 0 Swift files found, instead of emitting an empty project), and the stray `scripts/Reclaim.xcodeproj/` + `__pycache__/` artifacts were deleted. Regeneration now: detects 43 app + 10 test files, runs from any cwd, and is byte-identical across runs.
- **ISSUE-02 (FIXED):** the committed `.pbxproj` did not match what the (fixed) generator produces. Regenerated; the committed file is now exactly reproducible — a future audit can verify provenance with one `python scripts/generate_pbxproj.py && git diff --exit-code`.
- **ISSUE-06 (FIXED):** README previously stated "Screenshots/Large Videos/Duplicate Contacts screens are not yet built," implying photo screens existed. Audit showed **no category browsing UI is wired** (ISSUE-09). README now states the full scope precisely.
- **ISSUE-11 (FIXED):** README and this report rewritten to a verified-commands runbook (see README).

# Issues Found

| ID | Severity | Category | Problem | Root Cause | Fix | Verification | Status |
|---|---|---|---|---|---|---|---|
| ISSUE-01 | HIGH | Tooling / reproducibility | Generator found 0 source files and silently emitted an empty project; wrote a stray `scripts/Reclaim.xcodeproj/` | `ROOT = dirname(abspath(__file__))` resolved to `scripts/` | `ROOT` = parent of script dir; fail-loud `sys.exit` on 0 files; artifacts deleted | Ran: 43+10 files detected; empty-repo run exits 1; cwd-independent | **FIXED** |
| ISSUE-02 | HIGH | Build | Committed `.pbxproj` not reproducible from its own generator (consequence of ISSUE-01) | Committed file predated/never came from script | Regenerated from fixed script | Two consecutive runs byte-identical; structural validator passes | **FIXED** |
| ISSUE-03 | HIGH | iOS config | `UIRequiredDeviceCapabilities = armv7` on an iOS 17 arm64-only target | Template leftover | Key removed | `plistlib` re-parse confirms | **FIXED** |
| ISSUE-04 | HIGH | Concurrency / correctness | Foreground permission re-check never fired (observer token discarded) | `addObserver(forName:)` token not retained | Token stored; removed in `deinit` | Code inspection (runtime proof requires Simulator — environment) | **FIXED** |
| ISSUE-05 | MEDIUM | Data accuracy | Screenshot `byteSize` always 0 → recoverable-bytes estimates under-reported | Sizes resolved only in duplicate/similarity passes, which screenshots skip | `ScanPhotoLibraryUseCase` resolves sizes at detection, cancellation-aware | Code inspection (compile/run requires Xcode) | **FIXED** |
| ISSUE-06 | MEDIUM | Documentation | README under-disclosed missing UI (implied photo screens existed) | Stale limitation list | README rewritten with precise scope | This audit's grep evidence | **FIXED** |
| ISSUE-07 | LOW | Build config | `Info.plist` listed in Resources copy phase despite `INFOPLIST_FILE` processing | Generator emitted it reflexively | Resources phase now empty; plist referenced via `INFOPLIST_FILE` only | Regenerated pbxproj contains no "Info.plist in Resources" | **FIXED** |
| ISSUE-08 | LOW | Code organization | `ComputeStorageSummaryUseCase` lives in `ScanContactsUseCase.swift` | Misplacement during writing | Left in place, flagged | — | **OPEN-1 (cosmetic)** |
| ISSUE-09 | HIGH | Feature completeness | No UI mutates selection → core loop unreachable end-to-end for a user | Category browsing screens not built | Out of scope for an audit (documented, not fabricated) | `grep` — zero call sites | **OPEN-2 (known)** |
| ISSUE-10 | LOW | UX | Result screen reachable only after ISSUE-09 fix | Downstream of ISSUE-09 | Same | — | **OPEN-2 (known)** |
| ISSUE-11 | MEDIUM | Documentation | README not a verified runbook; contained unverified claims | Written without an executable environment | Rewritten; every command labeled verified or blocked | Commands run in this audit | **FIXED** |
| ISSUE-12 | LOW | Accuracy | Post-cleanup pruning removes all requested IDs, not only confirmed-deleted ones | `CleanupSummary` carries counts, not IDs | Documented; harmless (next cleanup revalidates) | Code inspection | **OPEN-3 (documented)** |

# Issues Fixed

Six defects fixed and verified to the extent this environment allows (see table above and Verification Log). No warnings or errors were suppressed; no tests were removed; no checks were disabled; no behavior was replaced with mocks in app code.

# Remaining Issues

- **OPEN-2 (ISSUE-09/10): the product's core loop is not user-reachable.** The safety-critical pipeline (scan → selection → review → confirm → cleanup → result) is implemented and safety-tested at the model/use-case layer, but the category screens that drive selection do not exist. This is the single largest remaining work item and is now stated accurately in the README.
- **OPEN-1:** move `ComputeStorageSummaryUseCase` to its own file.
- **OPEN-3:** thread confirmed-deleted IDs through `CleanupSummary` for exact post-cleanup pruning.
- **OPEN-4 (accessibility):** add explicit labels/hints to destructive and scan controls; verify with VoiceOver/Dynamic Type on device.

# Environment-Blocked Validation

| Item | Blocker | Required to clear |
|---|---|---|
| Compile (Debug + Release) | No macOS/Xcode/Swift on audit machine | Any Mac with Xcode 15.2+ |
| 73 unit tests | Same | Xcode test run (`⌘U` or `xcodebuild test`) |
| PhotoKit/Contacts runtime behavior (permission prompts, limited picker, native delete dialog) | Same + no Simulator/device | Simulator first, then physical device |
| Performance at 10k+ photos / Instruments | Same + no device | Real-device Instruments pass |
| VoiceOver / Dynamic Type | Same | Device with accessibility enabled |
| Memory profiling | Same | Instruments Allocations on device |

# Verification Log (commands actually executed in this audit)

```
which swift swiftc xcodebuild docker python3     # environment determination
python -m py_compile scripts/generate_pbxproj.py # generator syntax: PASS
python scripts/generate_pbxproj.py               # regen: 43 app + 10 test files
python scripts/generate_pbxproj.py && diff …     # determinism: byte-identical
# structural validator (Python): balanced braces/parens, all PBX sections,
#   zero dangling fileRefs, zero dangling phase entries, Sources = 43/10
# empty-repo negative test: exit code 1, no stray project written
# cwd-independence test: run from /tmp against absolute script path: PASS
python -c "import plistlib; plistlib.load(open('Reclaim/Resources/Info.plist','rb'))"
                                                 # Info.plist parses; armv7 gone
grep -rniE "(api_key|secret|password|token|PRIVATE KEY|\.p12|\.mobileprovision) …"
                                                 # no secrets
grep -rn "URLSession|Alamofire|Firebase|dataTask|upload" Reclaim/
                                                 # no network code
grep -rc "func test_" ReclaimTests/              # 73 test methods
grep -rn "toggleSelection|…" Reclaim/Features/   # zero UI selection call sites
```

# Final Readiness Assessment

**Not production ready — and no one should claim otherwise until the environment-blocked rows above are cleared.** Precisely:

- **Verified in this audit:** project file provenance, reproducibility, and structure; Info.plist validity and correctness; zero dependencies; zero network; zero secrets; PII-safe logging by construction; safety architecture by inspection with a 18-test suite ready to prove it.
- **Fixed:** 6 defects (2 of which made the repo's own provenance claims false).
- **Still true, unchanged:** the Swift code has never been compiled; the tests have never run; the core user loop is missing its selection UI; no device validation of any kind has occurred.

**Recommended next actions, in order:** (1) open in Xcode 15.2+, build, fix any compile errors; (2) run the 73 tests — the safety suite proves the destructive-path guarantees; (3) build the category selection screens against the existing `ReviewStore` API; (4) simulator pass over the permission matrix; (5) real-device Instruments + accessibility pass. The README now documents every one of these steps with commands labeled by verification status.
