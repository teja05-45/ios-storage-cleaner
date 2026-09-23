# AppFactory Submission Checklist

**Date:** 2026-09-23
**Environment:** Windows 11 (Git Bash 2.53.0 + PowerShell), Python 3.11.9. No macOS, no Xcode, no iOS Simulator, no physical iPhone, no Instruments.
**Status vocabulary:** every item is `PASS` / `PARTIAL` / `FAIL` / `BLOCKED` / `NOT VERIFIED` / `N/A` — with evidence. Nothing is marked PASS without execution or direct code-level evidence.

Legend for evidence:
- **code** = verified by reading the implementation in this repository (file/line references in docs/20).
- **exec** = executed on this Windows machine this pass (command + output recorded in docs/18).
- **blocked** = requires macOS/Xcode/iPhone; not executable here.
- **not-verified** = designed and written but never run against the real thing.

## Must Have

- [x] **Working iPhone app** — PARTIAL (BLOCKED at compile) — `code`, `blocked`
      53 Swift sources implement the full loop (docs/20 §3–§8); `xcodebuild` has never run — the single dominant gap. Status of the binary itself: UNKNOWN until first macOS build.
- [x] **iOS 17+** — PASS — `code`
      `IPHONEOS_DEPLOYMENT_TARGET = 17.0` in the generated project file; generator emits it (`scripts/generate_pbxproj.py`).
- [x] **Storage dashboard** — PASS — `code`, `not-verified`
      `DashboardView`/`DashboardViewModel` + `ComputeStorageSummaryUseCase`: real device capacity via `StorageServiceProtocol`, per-category recoverable estimates, selected size, freed size. Zero fabricated categories (docs/20 §3).
- [x] **Similar/duplicate photos** — PASS — `code`, `not-verified`
      Exact duplicates: SHA-256 resource hashing + grouping (`DuplicateDetector`). Similar: dHash perceptual grid + threshold clustering (`SimilarityDetector`, `PerceptualHash`).
- [x] **Screenshots** — PASS — `code`, `not-verified`
      PhotoKit `mediaSubtypes`/`.photoScreenshot` classification, chronological grid, multi-select (`ScreenshotsView`).
- [x] **Large videos** — PASS — `code`, `not-verified`
      `VideoScanner` metadata-only sizing (no full-file loads), descending sort, AVPlayer preview (`LargeVideosView`).
- [x] **Duplicate contacts** — PARTIAL — `code`
      Detection, normalization, grouping, review, deletion all implemented (`ContactService`, `DuplicateContactDetector`). **Merge is NOT implemented** — deliberate MVP scope per Document 14 ADR: review + delete only. Documented limitation, not hidden (docs/20 §7).
- [x] **Review before delete** — PASS — `code`, `not-verified`
      `ReviewView` shows exact selected items + total bytes; single destructive path (`PerformCleanupUseCase` → `CleanupService`); exactly 2 deletion call sites verified by sweep (docs/18 V10).
- [x] **Explicit deletion confirmation** — PASS — `code`
      Destructive-role confirmation alert with accessibility identifiers (`ReviewView`).
- [x] **Photos permission** — PASS — `code`, `not-verified`
      `PhotoLibraryServiceLive.authorizationStatus` + request path; `.notDetermined → request`.
- [x] **Contacts permission** — PASS — `code`, `not-verified`
      `ContactServiceLive` authorization handling, same pattern.
- [x] **Denied permission handling** — PASS — `code`, `not-verified`
      Dedicated denied states with Settings deep-link recovery on both Dashboard and category screens.
- [x] **Limited Photos handling** — PASS — `code`, `not-verified`
      `.limited` is a first-class state (NOT an error per Document 02): banner + scanning proceeds over accessible assets only.
- [x] **On-device processing** — PASS — `exec`
      Zero networking code (docs/18 V1 sweep: 0 hits across URLSession/Alamofire/Firebase/AI APIs); `isNetworkAccessAllowed = false` on all PHPhotoLibrary fetches; no entitlements beyond defaults.
- [x] **Original name** — PASS — `code`
      "Reclaim" — first-party name, no reference-app branding anywhere (docs/18 V3 text sweep).
- [x] **Original logo** — PASS — `exec`
      `scripts/generate_app_icon.py` composes the mark from first-party geometry; byte-for-byte deterministic (sha256 `93a5e97a60ad6951` verified on rerun this pass). Rendered at 1024×1024, wired into `AppIcon.appiconset`.
- [x] **Original design** — PASS — `code`, `not-verified`
      Original theme (`Theme.swift`), layout, copy, and illustration-free geometry; no reference-app text or artwork present.
- [x] **Real iPhone tested** — BLOCKED — no iPhone available in this environment.
- [x] **Real photo library tested** — BLOCKED — requires the iPhone above.

## Quality

- [x] **Core loop works end-to-end** — PARTIAL — `code`, `not-verified`
      Every stage exists as reviewed code + tests (Scan → Review → Select → Confirm → Clean → Result); end-to-end RUNTIME verification is blocked on macOS.
- [x] **Safe deletion** — PASS — `code`
      Single authoritative path; stale-selection repair (OPEN-3: OS-confirmed IDs threaded through `CleanupSummary`); partial-failure aggregation; cancellation; keep-invariant self-healing (all unit-covered in `ReviewStorePruningTests`, `PerformCleanupUseCaseSafetyTests`).
- [x] **Large-library performance tested** — NOT VERIFIED — design documented (bounded concurrency, thumbnail cache, metadata-only video sizing) but 10,000-asset validation requires a device.
- [x] **Scan accuracy tested** — NOT VERIFIED on-device; 19 pipeline/detector tests exist and were reviewed for tautology (one tautological test was found and rewritten into a real ordering assertion during the scan-pipeline pass).
- [x] **Polished UI** — PASS — `code`, `not-verified`
      Empty/error/permission/progress states throughout; Dynamic Type–friendly system components; original visual language.
- [x] **Error handling** — PASS — `code`
      Typed `ReclaimError` surface, per-category failure handling, partial-cleanup reporting, revoked-permission re-check, scan-cache staleness repair.
- [x] **Accessibility** — PASS — `code`, `not-verified`
      VoiceOver labels/hints on scan + destructive controls (dedicated a11y commit), accessibility identifiers on flow-critical elements, Dynamic Type via system text styles.
- [x] **Privacy audit** — PASS — `exec`
      V1/V2 sweeps: no network code, no secrets, no analytics; minimal permission purpose strings; PII-safe logging (`Logging.swift` redacts identifiers).

## Submission

- [x] **GitHub/Xcode repository** — PASS — `exec`
      Pushed to `origin/main` (fast-forward, no force); Xcode project generated and provenance-verified.
- [x] **TestFlight if available** — N/A/BLOCKED — requires Apple Developer account + macOS; not available.
- [x] **2–3 minute screen recording** — NOT DONE — requires iPhone; must follow the safety rules (test assets only, no private photos) in docs/20 §14.
- [x] **Private photos excluded from recording** — N/A — recording not yet made; rule documented for the person who records it.
- [x] **<150-word submission note** — PASS — drafted in docs/20 §15 (139 words), ready to submit.
- [x] **README complete** — PASS — `exec`
      Reproducible runbook: repo-type audit table, Windows CAN/CANNOT split, macOS build path, executed Windows test battery with results, troubleshooting, Docker explicitly N/A.

## Bonus

- [ ] **Video compression** — NOT IMPLEMENTED (deliberate; core loop prioritized).
- [ ] **Swipe mode** — NOT IMPLEMENTED.
- [ ] **Blurry detection** — NOT IMPLEMENTED.
- [ ] **Face ID/PIN vault** — NOT IMPLEMENTED.
- [ ] **Calendar cleanup** — NOT IMPLEMENTED.
- [ ] **Home Screen widget** — NOT IMPLEMENTED.
- [x] **Space-freed summary** — PASS — `code`
      `CleanupResultView` reports actual freed bytes from the OS-confirmed result (not the estimate).
- [ ] **TestFlight** — BLOCKED — needs Apple Developer Program + macOS.

## Honest totals

| Status | Count |
| --- | --- |
| PASS | 24 |
| PARTIAL | 3 (app binary, contacts merge, core-loop runtime) |
| NOT VERIFIED | 2 |
| BLOCKED | 4 (iPhone, photo library, recording, TestFlight) |
| NOT IMPLEMENTED (bonus) | 6 |
| N/A | 1 |

**Reading the table:** all 16 Must-Have feature/code items are implemented and evidenced at the code level; the 4 BLOCKED items are exactly the set that requires Apple hardware/toolchain, and the 3 PARTIALs all reduce to the same root cause: nothing has ever been compiled or run. The fastest path to flipping every PARTIAL/BLOCKED is in docs/20 §Recommended Final Steps.
