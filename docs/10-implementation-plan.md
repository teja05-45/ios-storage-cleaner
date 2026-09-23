# 10 — Implementation Plan

Each phase lists: files touched, dependencies on prior phases, acceptance criteria, and tests added. Phases are designed to be shippable/demoable checkpoints, not arbitrary chunks — after most phases, the app builds and runs, just with less coverage.

## Phase 1 — Project Foundation
**Files:** Xcode project/target setup, `App/ReclaimApp.swift`, `App/RootTabView.swift`, `App/AppEnvironment.swift`, `Info.plist` (usage description placeholders), folder scaffolding per Document 04.
**Depends on:** nothing.
**Acceptance criteria:** clean build, empty tab bar (Dashboard/Clean Up/Review) launches on simulator with no crash.
**Tests:** none yet (smoke build only).

## Phase 2 — Design System
**Files:** `Core/Extensions` color/typography tokens, reusable components (`Card`, `PrimaryButton`, `DestructiveButton`, `EmptyStateView`, `LoadingStateView`, `PermissionDeniedView`) per Document 02.
**Depends on:** Phase 1.
**Acceptance criteria:** components render correctly in light/dark, support Dynamic Type up to at least Accessibility XL sizes without truncation/overlap, pass a manual VoiceOver pass.
**Tests:** SwiftUI preview coverage for each component's states (default/loading/empty/error).

## Phase 3 — Permission Handling
**Files:** `Services/PhotoLibraryService.swift` (auth methods only), `Services/ContactService.swift` (auth methods only), shared `PermissionState` model, permission-prompt UI.
**Depends on:** Phase 1, 2.
**Acceptance criteria:** all five PhotoKit/Contacts authorization states (Document 01 §3.7) correctly mapped to UI states; Settings deep link works.
**Tests:** unit tests for auth-state → `PermissionState` mapping (fake service); manual test of grant/deny/limited on simulator.

## Phase 4 — Storage Dashboard
**Files:** `Services/StorageService.swift`, `Core/Models/StorageSummary.swift`, `Features/Dashboard/*`.
**Depends on:** Phase 1–3.
**Acceptance criteria:** dashboard shows real OS-reported total/used/available storage on a physical device; category cards show "Not scanned yet" pre-scan.
**Tests:** unit test for `StorageService` capacity-key parsing (against a fake `FileManager`/`URLResourceValues` provider where feasible, or documented as device-only-verifiable where not); UI test for pre-scan empty state.

## Phase 5 — Photo Scanner (Enumeration)
**Files:** `Services/PhotoScanner.swift`, `Core/Models/PhotoAsset.swift`, `Core/Models/VideoAsset.swift`, `UseCases/ScanPhotosUseCase.swift` (enumeration phase only).
**Depends on:** Phase 3.
**Acceptance criteria:** enumerates full seeded library into `PhotoAsset`/`VideoAsset` models off-main-thread; phase reports progress.
**Tests:** integration test against seeded simulator library verifying expected asset counts; unit test for batching/autoreleasepool behavior via a large fake asset set.

## Phase 6 — Duplicate Detection (Exact)
**Files:** `Services/DuplicateDetector.swift`, `Core/Models/PhotoGroup.swift`, extends `ScanPhotosUseCase`.
**Depends on:** Phase 5.
**Acceptance criteria:** correctly identifies exact duplicates in a seeded library containing known duplicate pairs; does not misclassify same-size/different-content assets as exact.
**Tests:** unit tests per Document 08 §1 (bucketing + SHA-256 verification); integration test against seeded fixtures.

## Phase 7 — Similar Photo Detection
**Files:** `Core/Utilities/PerceptualHash.swift`, `Core/Utilities/HammingDistance.swift`, `Services/SimilarityDetector.swift`, `Core/Models/PhotoCandidate.swift`.
**Depends on:** Phase 5, 6.
**Acceptance criteria:** correctly clusters a known seeded burst sequence into one group at the calibrated threshold; unrelated seeded singles produce no groups; best-photo scoring produces a `recommendedKeepID` with a correct `reason` string.
**Tests:** full Document 08 §1 unit test set for hashing/clustering/scoring; integration test against seeded burst fixtures.

## Phase 8 — Screenshot Detection
**Files:** `Services/ScreenshotDetector.swift`, `Features/Screenshots/*`.
**Depends on:** Phase 5.
**Acceptance criteria:** correctly flags seeded screenshot assets via `mediaSubtypes`; grid UI with Select All/Deselect All functions correctly and updates recoverable size live.
**Tests:** unit test for the filter predicate; UI test for select-all/deselect-all and running total.

## Phase 9 — Large Video Scanner
**Files:** `Services/VideoScanner.swift`, `Features/LargeVideos/*` including `VideoPreviewView.swift`.
**Depends on:** Phase 5.
**Acceptance criteria:** list sorted correctly by size descending; preview player opens and plays a real seeded video; no full `AVAsset` instantiated for every video during list-scan (verified via Instruments during Phase 13).
**Tests:** unit test for sort order given fixture data; manual test of preview playback on device.

## Phase 10 — Contact Duplicate Detection
**Files:** `Core/Utilities/ContactNormalizer.swift`, `Core/Utilities/NameSimilarity.swift`, `Services/ContactService.swift` (fetch/delete), `Services/DuplicateContactDetector.swift`, `Core/Models/ContactCandidate.swift`, `Core/Models/ContactGroup.swift`, `Features/Contacts/*`.
**Depends on:** Phase 3.
**Acceptance criteria:** correctly separates seeded exact vs. probable duplicate contacts per Document 06 §6; false-positive guard (name-only match, no field overlap) produces zero groups for that case; per-group field-diff preview renders correctly.
**Tests:** full Document 08 §1 contact normalization/matching unit tests; integration test against seeded contacts.

## Phase 11 — Review and Cleanup
**Files:** `Features/Review/ReviewStore.swift`, `Features/Review/ReviewView.swift`, `UseCases/PerformCleanupUseCase.swift`, `Services/CleanupService.swift`, `Core/Models/CleanupSelection.swift`, `Core/Models/CleanupSummary.swift`, `Features/CleanupResult/*`.
**Depends on:** Phase 6–10 (needs all categories producing selectable items).
**Acceptance criteria:** Review screen aggregates real selections across all four categories with live-accurate totals; Confirm is disabled when empty; confirmed cleanup actually deletes the exact selected set (verified against seeded, disposable test content) and Cleanup Result reflects real OS-confirmed counts, including any partial-failure case.
**Tests:** the full Document 08 §4 safety test suite — this phase is where every safety test becomes executable, since it's the first point all pieces exist together.

## Phase 12 — Testing (consolidation pass)
**Files:** fills any gaps across `ReclaimTests` (unit/integration) and `ReclaimUITests` not already covered incrementally in Phases 1–11.
**Depends on:** all prior phases.
**Acceptance criteria:** full Document 08 test plan passes; code-coverage reviewed manually for any untested branch in Services/UseCases (100% coverage is not the goal — coverage of every safety-relevant and algorithm-relevant path is).
**Tests:** itself is the testing phase.

## Phase 13 — Performance Optimization
**Files:** targeted changes across `Services`, `Infrastructure/ThumbnailCache.swift`, `Infrastructure/ScanCache.swift` based on Instruments findings.
**Depends on:** Phase 5–11 (needs a feature-complete pipeline to profile meaningfully).
**Acceptance criteria:** Document 09 §9 measurements recorded against the 10,000+/1,000+/500+ target library on a physical device; no main-thread hangs during scan; memory stays within a reasonable bound with no leaks (verified via Leaks instrument).
**Tests:** performance measurements documented in README; regression-guard unit tests added for any bug found during profiling (e.g., a missing autoreleasepool causing unbounded growth).

## Phase 14 — Polish
**Files:** touches across all `Features/*` views — spacing, animation, haptics, accessibility labels, empty/error copy pass per Document 02.
**Depends on:** Phase 1–13 (polish happens once functionality is stable, per the assignment's explicit sequencing).
**Acceptance criteria:** full Document 02 §2.6–2.8 checklist satisfied; VoiceOver walkthrough of the entire core loop is coherent; Dynamic Type extremes don't break layout anywhere; dark/light appearance both look intentional, not just "doesn't crash."
**Tests:** manual accessibility audit checklist (documented, not automated) + UI test additions for any accessibility-label regression found.

## Phase 15 — Real-Device Validation
**Files:** none (validation phase) — any bugs found are patched with small, targeted fixes and covered by a regression test.
**Depends on:** Phase 1–14.
**Acceptance criteria:** full Document 01 §"Quality Bar" real-device checklist passes: real photos/duplicates/similar/screenshots/large videos/duplicate contacts, denied permissions, limited permissions, empty states, and the large-library performance pass, all on a physical iPhone, not simulator-only.
**Tests:** this phase's output *is* the test — results recorded in the README's Performance/Testing sections and this repo's demo script (Document 11).
