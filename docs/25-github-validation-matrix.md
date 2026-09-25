# 25 — GitHub Validation Matrix

**Date:** 2026-09-25. Companion to `docs/24` and `docs/26`. Statuses use exactly: `PASS`, `FAIL`, `PARTIAL`, `NOT VERIFIED`, `BLOCKED`, `N/A`. A row's automated evidence links to the CI job that proves it; the **Physical iPhone** column is uniformly NOT VERIFIED because no device exists in this environment — this is the honest state of the project, not a gap in the table.

**Validation vehicle:** GitHub Actions `macos-14` runners (Xcode 15.4, iOS 17.5 simulator) — the development machine is Windows and has no Apple toolchain. Two jobs per push: `validate` (builds + 144 XCTests + quality gates) and `ui-tests` (simulator UI bundle). Latest green runs: **[run 24](https://github.com/teja05-45/ios-storage-cleaner/actions/runs/35891727358)** (first fully green), **run 30** (`4030be8`) — see the repository's Actions tab for the run on the current tip.

| Requirement | Implementation | Automated Test | Simulator | Physical iPhone | Status |
| --- | --- | --- | --- | --- | --- |
| Storage dashboard (real capacity, honest estimates) | `StorageServiceLive` + `FileManager.deviceCapacity()` (ImportantUsage key); Dashboard renders real numbers, error state when unavailable; no fabricated values (§17 sweep clean) | `DashboardViewModelTests` (3); UI test `test_storageCard_showsRealCapacity_notABlankOrPlaceholder` | **VERIFIED** (UI test renders real sim capacity) | NOT VERIFIED | **PASS** (code+tests+sim); device reconciliation NOT VERIFIED |
| Similar photos (dHash + clustering + scoring) | `SimilarityDetector` (rolling 2-min buckets, bounded TaskGroup), `PerceptualHash`, `HammingDistance` (threshold 5), `PhotoClustering`, `BestPhotoScoring`; BUG-01 size fix | 26+ tests incl. new `DetectionPipelineTests` (BUG-01 regression, 2,000-hash cluster envelope, exact 100-cluster count) | Unit-level only (thumbnails are injected fakes) | NOT VERIFIED (real bursts/retakes) | **PASS** (code+tests); real-content behavior NOT VERIFIED |
| Screenshots (OS-flagged, sizes resolved) | `ScreenshotDetector` via `PHAsset.mediaSubtypes`; sizes folded at scan time | `ScanPhotoLibraryUseCaseTests` (size resolution + fallback), `ScreenshotOrderingTests` | Unit-level only | NOT VERIFIED | **PASS** (code+tests); real-content behavior NOT VERIFIED |
| Large videos (size-ranked, preview-before-select) | `VideoScanner` (metadata-only, ADR-01 sizes), `AVKit` player item lazy-loaded | `VideoOrderingTests`, `ScanPhotoLibraryUseCaseTests` | Unit-level only (no real videos in CI sim) | NOT VERIFIED | **PASS** (code+tests); playback on real content NOT VERIFIED |
| Duplicate contacts (2-tier, field-diff, review-only) | `DuplicateContactDetector` (Exact + Probable with secondary signal), `ContactNormalizer`, per-field diff preview; no merge by design (ADR-02) | `DuplicateContactDetectorTests`, `ContactNormalizerTests`, `NameSimilarityTests`, `ContactFieldDiffTests`, 2,000-contact performance envelope | Unit-level only (no real contacts in CI sim) | NOT VERIFIED | **PASS** (code+tests); real-content behavior NOT VERIFIED |
| Review before delete (aggregate + per-item remove) | `ReviewStore` single source of truth; ReviewView lists every item with remove buttons; counts cannot drift | `ReviewStoreAggregationTests`, `ReviewStorePruningTests`, `GroupSelectionInvariantTests`, `CleanupSelectionTests` | UI flow beyond dashboard not automatable on empty sim | NOT VERIFIED | **PASS** (code+tests) |
| Explicit confirmation gate | `PerformCleanupUseCase.execute(_:confirmed:)` — sole destructive entry; throws without `confirmed: true`; `confirmationDialog` in ReviewView | `PerformCleanupUseCaseSafetyTests` (12) — no-confirmation, empty-selection, stale, partial-failure paths | Not exercisable in UI tests (no selection constructed, by design) | NOT VERIFIED (native OS dialog) | **PASS** (code+tests); native dialog NOT VERIFIED |
| Permissions (photos + contacts, 5-state matrix) | `PermissionState` (`.limited` first-class, ADR-04); gates before enumeration; foreground re-check; cleanup re-gating | **NEW** `PermissionStateTests` (8): truth table, scan gating, limited honesty, revoked-permission cleanup re-gating with zero delete calls | UI test: prompt rows + Allow affordance render; **system dialog NOT automatable** | NOT VERIFIED (system dialogs, limited picker) | **PARTIAL** — automated + simulator portions PASS; system-dialog/device portions NOT VERIFIED |
| Cancellation (scan → cancel → terminal state) | `ScanPhotoLibraryUseCase` cooperative checks + partial results; `DashboardViewModel` epoch guard + terminal transition ownership | `DashboardViewModelTests.test_cancelledPipelineStatus…` (regression), pipeline cancellation tests, flakiness re-run in CI | Unit-level only | NOT VERIFIED | **PASS** (code+tests) |
| On-device privacy (nothing leaves the phone) | Zero network code (V1); `isNetworkAccessAllowed = false` ×4; no SDKs; PII-safe Log; cache = IDs/hashes/sizes only | `scripts/security_scan.py` (14 patterns) CI gate; dependency audit (no packages); full sweeps in docs/26 | N/A (static property) | N/A | **PASS** |
| Original branding (no third-party assets) | Generated app icon + accent color (`scripts/generate_app_icon.py`); named "Reclaim" | Asset catalog compiled in CI builds (actool step green) | Icon renders in simulator springboard (not screenshot-audited in CI) | NOT VERIFIED | **PASS** (code+build) |
| iOS 17+ (Observation, modern SwiftUI) | Deployment target 17.0; `@Observable` store/ViewModels; `ContentUnavailableView`; Swift 5 toolchain | Compiles in CI on Xcode 15.4 / iOS 17.5 | Launches on iOS 17.5 simulator (UI tests) | NOT VERIFIED (device iOS version) | **PASS** |
| Core loop (launch→scan→review→confirm→cleanup→result) | Full pipeline wired through single use cases; structural guards at every step | 144 unit tests incl. SafetyTests; UI tests cover launch→dashboard segment | Launch/dashboard segment VERIFIED; deeper loop needs granted permissions + content | NOT VERIFIED (real deletion end-to-end) | **PARTIAL** — code+tests PASS; end-to-end with real content NOT VERIFIED |
| Accessibility (labels/hints/Dynamic Type) | Explicit labels/hints on scan + destructive controls (OPEN-4); combined elements on rows | Code-audited (grep for accessibilityLabel/Hint on destructive controls) | Automatable identifier checks only in UI tests | NOT VERIFIED (VoiceOver, Dynamic Type manual passes) | **PARTIAL** — code audit PASS; manual device passes NOT VERIFIED |
| Performance (10k+ photos target) | Streamed hashing, metadata-only enumeration, bounded concurrency, NSCache bound | **NEW** deterministic envelopes (2,000-hash clustering, 2,000-grid encoding, 2,000-contact normalization) as regression tripwires | N/A (no real large library in CI) | NOT VERIFIED (Instruments impossible in CI) | **PARTIAL** — algorithmic tripwires PASS; large-library performance NOT VERIFIED |

## Legend / reading the table

- **PASS** in the Status column means: implemented, unit-tested, and every automatable layer verified green in CI. It never implies the Physical iPhone column.
- **PARTIAL** rows name exactly which portion is unverified — those portions are the real-device runbook (README §Physical iPhone Test Checklist), not hidden failures.
- **NOT VERIFIED** is the honest state for anything requiring a physical device, real user content, or Apple's system UI: the simulator and unit layers cannot produce that evidence, and this project does not fabricate it.

## Real-device-only ledger (unchanged by this audit)

```
Physical iPhone:            NOT VERIFIED
Real Photos library:        NOT VERIFIED
Real Contacts database:     NOT VERIFIED
Actual device storage:      NOT VERIFIED
Physical-device profiling:  NOT VERIFIED
```
