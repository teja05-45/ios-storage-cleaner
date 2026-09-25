# 33 — Validation Matrix (fresh verification)

**Date:** 2026-09-25. Fresh evidence-based matrix per the AppFactory assignment. Statuses: `PASS` / `FAIL` / `PARTIAL` / `BLOCKED` / `NOT VERIFIED` / `N/A` only. Evidence = the CI run (34–37, all success) or the executed command; the Physical iPhone column is uniformly NOT VERIFIED because no device exists — that is the honest state, not a table gap. Supersedes the per-requirement detail in `docs/25` where they overlap; `docs/25` remains the historical record.

| Requirement | Implementation | Automated evidence | Simulator | Physical iPhone | Status |
| --- | --- | --- | --- | --- | --- |
| Storage dashboard — real capacity/used/free, no fabricated values | `FileManager.deviceCapacity()` (ImportantUsage key); error state when unavailable; estimates labeled as estimates | UI test: real-capacity rendering, unavailable-state rejected; `DashboardViewModelTests`; §16 sweep: 0 placeholder/mock hits | VERIFIED | NOT VERIFIED (reconciliation over real deletions) | **PASS** (automated layers) |
| Exact duplicates — bucketing, streamed SHA-256, recommended keep, override | Dimensions→size→hash pipeline; keep = earliest creation date, id-tiebreak | `DuplicateDetectorTests` (bucketing gates, hash-bounded-to-candidates), BUG-01 size regressions | unit-level only | NOT VERIFIED (real duplicates) | **PASS** (code+tests) |
| Similar photos — dHash, clustering, scoring, exclusion rules | Rolling 2-min windows, bounded TaskGroup, threshold 5, screenshots + exact-dup members excluded; nil-date assets now excluded safely (BUG-06) | `HammingDistanceAndClusteringTests`, `PerceptualHashTests`, `BestPhotoScoringTests`, nil-thumbnail + **new nil-date** tolerance tests, cluster envelope | unit-level only | NOT VERIFIED (real bursts) | **PASS** (code+tests) |
| Screenshots — PhotoKit subtype, sizes, ordering | `mediaSubtypes.contains(.photoScreenshot)`; sizes folded at scan | `ScanPhotoLibraryUseCaseTests` (size resolution + degradation), `ScreenshotOrderingTests` | unit-level only | NOT VERIFIED | **PASS** (code+tests) |
| Large videos — metadata sizing, descending order, preview-before-select | ADR-01 resource sizes, no AVAsset at scan; lazy player item | `VideoOrderingTests`, pipeline tests | unit-level only (no real videos in CI) | NOT VERIFIED | **PASS** (code+tests) |
| Duplicate contacts — normalization, 2-tier detection, field-diff, review-only (merge deliberately NOT implemented, ADR-02) | Last-10-digit suffix + secondary-signal Probable tier; oversized-group demotion; per-field would-be-lost preview | `ContactNormalizerTests`, `NameSimilarityTests`, `DuplicateContactDetectorTests`, `ContactFieldDiffTests`, normalization envelope | unit-level only | NOT VERIFIED (real contacts DB) | **PASS** (code+tests); merge absence documented, not a failure |
| Review before delete — full gated loop | Single destructive entry (`PerformCleanupUseCase.execute(_:confirmed:)`); Review aggregates from one store | `PerformCleanupUseCaseSafetyTests` (12), ReviewStore suites; UI tests cover the launch→dashboard segment | launch/dashboard VERIFIED; deeper loop needs granted permissions + content | NOT VERIFIED (native dialog, real deletion) | **PASS** (code+tests); end-to-end real content NOT VERIFIED |
| Permissions — 5-state matrix, `.limited` first-class, revoked-mid-flow | `PermissionState` truth table; gates before enumeration; cleanup re-gating | `PermissionStateTests` (8): all states × both frameworks, zero-delete-calls on revocation; UI: prompt affordances render | UI affordances VERIFIED; system dialog NOT automatable | NOT VERIFIED (system dialogs, limited picker) | **PARTIAL** — automated+simulator PASS; system-dialog/device portions NOT VERIFIED |
| Cancellation — cancel → pipeline stops → terminal state → UI recovers | Cooperative checks + partial results; epoch guard owns terminal transitions | `DashboardViewModelTests` cancellation regression, pipeline cancellation tests, flakiness re-run green (runs 34–37) | unit-level only | NOT VERIFIED | **PASS** (code+tests) |
| Stale data — vanished assets/contacts, permission change, repeated scans | Revalidation drops + reports stale IDs; cache never read in production (0 `.load()` call sites — verified fresh this pass) | `PerformCleanupUseCaseSafetyTests` (stale/partial paths), `ReviewStorePruningTests` | unit-level only | NOT VERIFIED | **PASS** (code+tests) |
| On-device privacy — nothing leaves the phone | No network code; `isNetworkAccessAllowed=false` ×4; no SDKs; PII-safe Log | `security_scan.py` 0 findings; `dependency_audit.py` clean; sweep table docs/31 §2 | N/A (static property) | N/A | **PASS** |
| Security — no secrets, no unsafe unwraps of external data, gated destructive ops | Scanner + dependency gate in CI; BUG-06 fixed; 5 subscript sites audited with guards | docs/31 §1, §3 | N/A | N/A | **PASS** |
| Accessibility — labels/hints/identifiers, no brittle tests | Explicit a11y labels/hints on scan + destructive controls; `dashboard.scanButton` identifier for observable-state testing | Code audit (docs/24 §12); UI tests assert behavior (disabled gate), not implementation details | identifiers VERIFIED | NOT VERIFIED (VoiceOver, Dynamic Type manual passes) | **PARTIAL** — code+identifier audit PASS; manual device passes NOT VERIFIED |
| Performance — algorithmic envelopes only (no device claims) | 2,000-grid dHash, 2,000-hash clustering (exact 100 clusters), 2,000-contact normalization | `DetectionPipelineTests` green in CI | N/A (no real library in CI) | NOT VERIFIED (Instruments impossible here) | **PASS** (tripwires); **Real-device large-library performance: NOT VERIFIED** |
| CI quality gates — fail on any required failure | 0 `continue-on-error`, 0 `exit 0`; all 23 `|| true` audited as no-ops/log-greps, 0 guarding gates | docs/30 §1 | N/A | N/A | **PASS** |

## Real-device-only ledger (unchanged)

```
Physical iPhone:                   NOT VERIFIED
Real Photo Library:                NOT VERIFIED
Real Contacts:                     NOT VERIFIED
Real Device Storage:               NOT VERIFIED
10k+ Real Device Performance:      NOT VERIFIED
```
