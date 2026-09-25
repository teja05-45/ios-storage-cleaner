# 32 — Bug Audit (cumulative index + fresh findings)

**Date:** 2026-09-25. Full per-bug records (reproduction, root cause, fix, regression test) live in `docs/27-bug-audit.md` (BUG-01…BUG-05); this document indexes the complete set and records the fresh finding from this pass. Every "FIXED" below is validated by a named test that failed before the fix and passes in CI runs 34–37 (or, for BUG-06, will gate the next run).

## Cumulative bug register

| ID | Severity | One-line summary | Where | Status |
| --- | --- | --- | --- | --- |
| BUG-01 | MEDIUM | Duplicate/similar group members carried the 0-byte enumeration placeholder — recoverable-bytes estimates under-reported | docs/27 | **FIXED** — detectors fold resolved sizes into members; regressions: `DetectionPipelineTests` (incl. selected-member size flow) |
| BUG-02 | LOW | Security-scanner allow-list failed on Windows path separators | docs/27 | **FIXED** — normalized paths; scan green on Windows + CI |
| BUG-03 | LOW | Security scanner flagged its own rule table | docs/27 | **FIXED** — self-exclusion |
| BUG-04 | LOW | Generator emitted two PBXBuildFile entries on one physical line | docs/27 | **FIXED** — template separator; validator + determinism check |
| BUG-05 | HIGH | UI-test target's `dependencies` referenced a PBXBuildFile instead of a PBXTargetDependency (Xcode loader rejected the project) | docs/27, docs/28 | **FIXED** — generator + validator isa-class checks with executed negative test |
| BUG-06 | LOW | `creationDate!` force-unwraps on PhotoKit-derived data in similarity bucketing (crash class on future refactor; safe today only by a filter invariant) | docs/31 §3 | **FIXED** — `compactMap` date-carrying candidates; regression test `test_similarityDetector_realImplementation_skipsAssetsWithNilCreationDate` |

## Fresh-pass audit trail (BUG-06)

```
Reproduction:   code inspection per §25 sweep (no runtime crash observed —
                the two force-unwraps are currently shielded by the
                !$0.isScreenshot && $0.creationDate != nil filter two lines
                above; the defect is the unprotected invariant, not a
                live crash)
Root cause:     bucketing code reached through optional chaining elsewhere
                but force-unwrapped here; a filter refactor or a PhotoKit
                anomaly would turn the invariant violation into a crash
Fix:            SimilarityDetector.detectSimilarGroups builds candidates via
                compactMap { asset in asset.creationDate.map { (asset, $0) } },
                sorts and buckets on the carried (non-optional) date — the
                force-unwrap no longer exists to be misused
Regression:     test_similarityDetector_realImplementation_skipsAssetsWithNilCreationDate
                — a nil-dated asset between two dated, visually identical
                assets must be excluded (no crash, no membership) while the
                dated pair still clusters
Status:         FIXED (gates the next CI run)
```

## Totals

| Severity | Found (all passes) | Fixed | Remaining |
| --- | --- | --- | --- |
| CRITICAL | 0 | 0 | 0 |
| HIGH | 1 (BUG-05, introduced and fixed within one audit pass; never in a released state) | 1 | 0 |
| MEDIUM | 1 (BUG-01) | 1 | 0 |
| LOW | 4 (BUG-02, BUG-03, BUG-04, BUG-06) | 4 | 0 |

**Remaining known bugs: 0.** Open items in this repository are physical-device validation gaps (docs/25 ledger, docs/29), not defects.
