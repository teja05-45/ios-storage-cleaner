# 20 — AppFactory Final Engineering Audit

**Audit date:** 2026-09-23
**Auditor environment:** Windows 11 (Git Bash 2.53.0 + PowerShell), Python 3.11.9, Docker 29.6.1 installed. **No macOS, no Xcode, no Swift toolchain, no iOS Simulator, no physical iPhone, no Instruments.**
**Source of truth:** the AppFactory assignment brief (§1–§13 of the audit prompt), compared line-by-line against the actual repository — not the README.
**Method:** full repository re-inspection; targeted probes for each brief section; static sweeps re-executed (docs/18); project-file generator re-run and provenance re-verified; every checklist status traced to code, execution, or an explicit BLOCKED.

---

## Executive Summary

The repository contains a **complete, safety-architected implementation** of the Storage Cleaner assignment: 53 app sources, 19 test sources with **131 XCTest methods**, a deterministic generated Xcode project, an original brand (name, generated logo, original theme), and zero networking code.

**The honest headline (updated after the first green CI run):** the project is now **compiled and its full test suite executed — on Apple's own toolchain** — via GitHub Actions macOS runners (`macos-14`, Xcode 15.4): a clean Debug build, all 131 XCTest tests with 0 failures, and a Release build all pass (run 24; the complete failure-to-fix history is in `docs/21-ci-failure-analysis.md`). What remains **empirically unanswered** is only what a headless CI cannot answer: real PhotoKit/Contacts behavior, permissions on device, performance on a large library — the brief's central question, *"does the core loop actually work on an iPhone?"*, still requires a physical iPhone.

This audit found and fixed two conformance gaps this pass (original logo artwork was missing; one dead test helper), and confirmed no fabricated values, no hidden deletion paths, no copied branding, and no out-of-scope claims.

---

## Assignment Requirement Matrix

| # | Brief requirement | Status | Evidence |
| --- | --- | --- | --- |
| 1 | iPhone, iOS 17+ | PASS (code) | `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, iPhone-only targets |
| 2 | Everything on-device | PASS (exec) | V1 network sweep: 0 hits; `isNetworkAccessAllowed = false` throughout |
| 3 | Original app name | PASS | "Reclaim"; V3 text sweep shows no reference branding |
| 4 | Original logo | PASS (exec) | `scripts/generate_app_icon.py`; deterministic PNG (sha256 verified rerun) |
| 5 | Original design | PASS (code) | First-party `Theme.swift`, layout, copy |
| 6 | Storage dashboard (real values) | PASS (code) | `ComputeStorageSummaryUseCase`; no fabricated categories |
| 7 | Duplicate photos (exact) | PASS (code) | SHA-256 resource hash → `DuplicateDetector` grouping |
| 8 | Similar photos | PASS (code) | dHash (`PerceptualHash`) → threshold clustering (`SimilarityDetector`) |
| 9 | Recommended-to-keep semantics | PASS (code) | UI copy says "Recommended to Keep"; explainable signals; user override |
| 10 | Screenshots | PASS (code) | PhotoKit subtype classification + grid + multi-select |
| 11 | Large videos (desc, preview) | PASS (code) | `VideoScanner` metadata sizing; AVPlayer preview |
| 12 | Duplicate contacts | PARTIAL | Detect/review/delete done; **merge deliberately not implemented** (§7 below) |
| 13 | Review before delete | PASS (code) | `ReviewView` exact items + bytes; single destructive path |
| 14 | Explicit confirmation | PASS (code) | Destructive-role alert; no deletion without it |
| 15 | Photos permission (all states) | PASS (code) | incl. `.limited` as first-class state |
| 16 | Contacts permission (all states) | PASS (code) | denied/restricted recovery states |
| 17 | Real iPhone tested | BLOCKED | no device in this environment |
| 18 | Real photo library tested | BLOCKED | requires device |
| 19 | Performance on 10k+ library | NOT VERIFIED | design only; needs device + Instruments |
| 20 | Submission artifacts (recording, note, TestFlight) | PARTIAL | note drafted (§15); recording/TestFlight blocked |

---

## Core Feature Audit

**Dashboard (§3).** `DashboardViewModel` consumes `ComputeStorageSummaryUseCase` (own file, audit OPEN-1 closed): device used/free from the storage service, recoverable bytes per category from the last scan, selected bytes from `ReviewStore`, freed bytes from the last cleanup result. Each is a distinct, labeled concept — the brief's four-way distinction is enforced in the model layer. No hardcoded storage numbers exist (V-sweep re-run).

**Photos (§4).** Exact duplicates: streaming SHA-256 over resource data with deterministic selection, grouping in `DuplicateDetector` (bucketing covered by `DuplicateDetectorTests`). Similar: 8×8 dHash grids, hamming-distance clustering with threshold; nil-thumbnail assets are skipped gracefully (verified while writing pipeline tests). Recommendation: multi-signal scoring (resolution, sharpness, exposure) presented as "Recommended to Keep" with one-tap override — never "best". Selection state lives solely in `ReviewStore`, so review counts cannot drift from category screens.

**Screenshots (§5).** Classification via PhotoKit media subtypes only — no filename heuristics. Chronological grid with live selected-bytes footer; select-all/deselect; nothing auto-deletes.

**Large videos (§6).** `VideoScanner` reads file sizes via metadata APIs; full video files are never loaded into memory; sort options tested (`VideoOrderingTests`); preview is lazy AVPlayer materialization.

**Contacts (§7).** Normalization (phone/email/name), multi-signal grouping with likely/confirmed distinction, review + delete. **The brief says "merge or delete"** — delete satisfies the disjunction, and Document 14's ADR explicitly scoped merge out rather than shipping a silent-merge hazard. This is a **documented scope decision, not an omission**: true merging (field-level conflict resolution, "keep primary contact" UX) is a feature-class that deserves real design, and a naive merge would violate the brief's own safety spirit. Status recorded as PARTIAL in the checklist with this justification.

**Review before delete (§8).** Exactly two deletion call sites exist in the entire repository (`CleanupService` → live services), verified by sweep (docs/18 V10). `PerformCleanupUseCase` handles stale selections (OS-confirmed ID threading — OPEN-3), partial failures (per-item aggregation), cancellation, and result reporting. Cancellation now correctly *returns* partial state rather than throwing (DashboardViewModel fix in the previous pass).

---

## Safety Audit

- Single authoritative destructive path; no feature deletes independently (V10 sweep: 2 call sites, both behind confirmation).
- Stale selection: after cleanup, UI prunes by **OS-confirmed** deletions; surviving groups keep selection and user keep-override; keep-invariant self-heals when the kept asset itself was deleted (`ReviewStorePruningTests`).
- Partial cleanup: failures aggregate per category and surface in `CleanupResultView`; survivors stay selected for retry.
- Cancelled scan: pipeline returns `.cancelled` with partial results; UI exits the stuck-progress state (fixed this pass series, covered by `DashboardViewModelTests`).
- No automatic deletion anywhere: confirmation alert is destructive-role, has accessibility identifiers, and Cancel is first responder.

---

## Permission Audit

| State | Photos | Contacts |
| --- | --- | --- |
| notDetermined | request with purpose string | request with purpose string |
| authorized | full pipeline | full pipeline |
| limited | first-class banner; scans accessible assets; not treated as error | N/A (Contacts has no limited state) |
| denied | dedicated state + Settings deep-link | dedicated state + Settings deep-link |
| restricted | treated as denied-family; no crash, no stuck state | same |

Purpose strings are minimal and honest (the "upload" hits in the text sweep are the Photos permission string itself, verified benign). Runtime verification across the matrix remains NOT VERIFIED (needs device).

---

## Privacy Audit (§10)

Executed this pass (docs/18 V1/V2):
- **0** hits for URLSession/Alamofire/Firebase/analytics/telemetry/AI-API patterns across all Swift sources.
- **0** dependencies: no Package.swift, no Package.resolved, no external packages in the project file.
- `isNetworkAccessAllowed = false` on every PHPhotoLibrary resource fetch — even PhotoKit's iCloud fallback path is deliberately disabled.
- No entitlements files; no capability beyond defaults; Info.plist carries only the two permission purpose strings.
- Logging redacts asset identifiers (`Logging.swift`).
- Photos, videos, thumbnails, and contacts never leave the device by construction — there is no code path that could send them anywhere.

---

## Architecture Audit

Layering (App → Features → UseCases → Services → Infrastructure/Core) with dependency direction enforced by protocol boundaries (`PhotoLibraryServiceProtocol`, `ContactServiceProtocol`, `ScanCacheProtocol`, etc.). Composition root is `AppEnvironment`, injected via SwiftUI environment (no ad-hoc singletons in ViewModels). The project file is **generated** by `scripts/generate_pbxproj.py` (provenance re-verified this pass: deterministic, fail-loud contract intact), and the app icon is **generated** by `scripts/generate_app_icon.py` — both artifacts have first-party, reproducible provenance. Test fakes are shared and scriptable (`Fakes.swift`), enabling the orchestration/ViewModel/Pruning suites without PhotoKit.

---

## Performance Audit (§20)

Design is present and reviewed: bounded-concurrency scanning (no `Task.detached`), NSCache-bounded thumbnail pipeline keyed by asset+pixel size, metadata-only video sizing, autorelease boundaries in hash streaming, cancellation checked between work batches. **Measured performance: none exists.** Scan duration, peak memory, CPU, cancellation latency on a 10,000-photo / 1,000-video library: **NOT VERIFIED — requires macOS + Instruments + device.** No numbers are claimed anywhere in the docs.

---

## Test Audit (§14)

**Count:** 131 (`grep -rc "func test_"` re-verified this pass: 119 Core + 12 Safety).
**Execution:** VERIFIED — the full suite compiled and executed on GitHub's macOS runner (Xcode 15.4 / iOS 17.5 simulator): **131 tests, 0 failures** (run 24). Six behavioral failures surfaced on first execution and were root-caused and fixed — two were genuine app bugs (contact field-diff flagged differing names as data loss; the DashboardViewModel could be overwritten out of its terminal scan status by a queued progress hop), four were first-run test-design errors corrected rather than deleted. Full ledger: `docs/21-ci-failure-analysis.md`.
**Quality review (read, not run):**
- Tautology hunt: one tautological ordering assertion was found and **rewritten into a real one** (shared lock-safe event recorder asserting phase order) during the scan-pipeline pass; the dead `uniformGrid` helper found this pass was deleted.
- Tests assert behavior, not implementation detail: pruning tests assert survivor state and invariant self-healing; pipeline tests assert phase ordering and ISSUE-05 size semantics; ViewModel tests drive a fully fake environment.
- Two real bugs were found *by writing tests* (post-cleanup pruning state loss; stuck scanning status after cancel) — both fixed in the same commits as their regression tests.
- Isolation: no test depends on another; fakes are deterministic; no sleeps/timing dependencies; concurrency-safe event recorder used for ordering assertions.

---

## UI/UX Audit (§21)

Implemented and code-verified: first-launch permission explanation, per-category navigation with live counts/bytes, scan progress with cancel, empty/error/permission states on every screen, chronological screenshot grid, video sort controls, review with individually inspectable selected items, destructive confirmation, result screen with actual freed bytes. Accessibility: VoiceOver labels/hints on scan and destructive controls, identifiers on flow-critical elements, Dynamic Type via system text styles. **Runtime polish (animations, contrast on device, VoiceOver traversal) — NOT VERIFIED.** No debug UI, placeholder text, or mock values exist (sweeps re-run).

---

## Real Device Validation (§17–§19)

BLOCKED in full. The brief's hard requirement — real iPhone, real photo library, real cleanup — remains the acceptance gate. The recording must use **safe test assets only** (the docs/19 checklist carries the rule: known duplicates/similar pairs/screenshots/videos/duplicate test contacts, never private photos). The step-by-step device checklist lives in README (Physical iPhone Testing) and is reused verbatim for this purpose.

---

## Submission Readiness

- **Repository:** PASS — pushed to `origin/main`, fast-forward, no force (9b1868f..525ea85 lineage this pass).
- **README:** PASS — complete runbook, verified commands, honest Windows/macOS split.
- **Submission note (<150 words):** drafted below, 139 words — `BLOCKED` only on the human sending it.
- **TestFlight:** BLOCKED — requires Apple Developer Program + macOS.
- **Recording:** NOT DONE — requires iPhone.
- **Overall:** **NOT READY to submit until the macOS validation gate runs** — not because features are missing, but because the brief's own evidence standard (works on iPhone) is unmet.

### Draft submission note (139 words)

> Reclaim is an on-device storage cleaner for iPhone. It scans your photo library for exact duplicates, near-identical shots, and screenshots, lists videos from largest to smallest, and finds likely duplicate contacts — then shows a single review screen with exactly what will be removed and how much space it frees. Nothing is deleted without an explicit confirmation step, and every deletion goes through one audited cleanup path with partial-failure and stale-selection handling. Recommendations are labeled "Recommended to Keep," never "best," and users can override every suggestion. Everything runs on-device: no network code, no analytics, no cloud — photos and contacts never leave the phone. Original name, logo, and design. iOS 17+, SwiftUI, no third-party dependencies. Built for large libraries with bounded concurrency, metadata-only video sizing, and a cache-backed thumbnail pipeline.

---

## Remaining Blockers

1. **First compile + test run:** `xcodebuild -list` → Debug build → Release build → `xcodebuild test` (131 tests). **Vehicle added this pass: `.github/workflows/ci.yml`** — a committed GitHub Actions workflow that runs this exact sequence on a `macos-14` runner for every push to `main`, with all output tee'd to uploaded log artifacts. The development machine (Windows) has no Apple toolchain, so CI is now the authoritative validation gate; watch the run on the Actions tab. All fix-up work ("fix: resolve Xcode compilation issue" commits) is gated on the first run.
2. **Device matrix (iPhone):** permission states, real scan/review/confirm/cleanup, cancellation, partial failure, VoiceOver/Dynamic Type spot-check.
3. **Performance pass (Instruments):** 10,000-photo / 1,000-video scan duration, memory, CPU, cancellation latency.
4. **Submission artifacts:** screen recording (safe test assets) and TestFlight if an account exists.

## Recommended Final Steps

1. Let CI run (`xcodebuild -list` → Debug build); fix compile errors as individual commits (expected and normal for never-compiled code).
2. CI runs the suite; fix failures per-commit and re-push until green (Steps 6–8).
3. Simulator pass over the permission matrix and empty-library states (CI proves compilation; manual simulator/UI validation still needs a Mac or the runner's logs for smoke-level checks).
4. Real-device pass per the README checklist with safe test assets; capture the recording during this pass.
5. Instruments pass for the performance numbers; update docs/18 and docs/19 statuses with real evidence.
6. Ship: repo link + recording + submission note (+ TestFlight if available).
