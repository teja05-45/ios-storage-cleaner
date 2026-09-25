# 31 — Security Audit (fresh verification)

**Date:** 2026-09-25. Re-verification of the security posture established in `docs/26`, executed fresh this pass. No findings are recycled without re-running their check; nothing is invented to fill the report.

## 1. Secrets scan

- `scripts/security_scan.py` (14 patterns: AWS/Google/GitHub/Slack token shapes, private-key blocks, certificate filename extensions, generic `api_key=`/`password=` literals, bearer tokens) — **executed this pass: `SECURITY SCAN OK: 14 patterns, 0 findings`**. The scanner reports rule ID + file + line, never matched text, so it cannot leak a secret into CI logs.
- Scope: `Reclaim/`, `ReclaimTests/`, `ReclaimUITests/`, `scripts/`, `.github/`, project file. Docs excluded (prose would false-positive; disclosed).
- No `.env`, no `Package.resolved`, no service-account files exist in the tree (verified by directory listing and the dependency audit).

## 2. Network / privacy audit (§18)

Re-ran the sweeps and reviewed every match:

| Pattern | App-code matches | Verdict |
| --- | --- | --- |
| `URLSession`, `NWConnection`, `dataTask`, WebSocket | **0** | no HTTP/network client exists in the linked surface |
| `http://` / `https://` | Info.plist DOCTYPE Apple DTD (markup boilerplate, allow-listed with reason); `UIApplication.openSettingsURLString` (OS Settings deep link) | both legitimate; zero app-initiated endpoints |
| `isNetworkAccessAllowed` | set to `false` at all **4** PhotoKit call sites | no iCloud fetches even where the API offers them |
| analytics/telemetry/cloud SDKs | **0** (dependency audit enforces the import allow-list) | no tracking surface exists |

**Privacy verdict: PASS** — data flow is framework → memory → (IDs/hashes/sizes cache, never contact fields or thumbnails) → UI → framework deletion. Nothing can cross the device boundary because no transport exists.

## 3. Crash / error-path audit (§25)

Executed sweep of `try!`, `fatalError`, `preconditionFailure`, `as!`, and force-unwraps in app code:

| Finding | Count | Disposition |
| --- | --- | --- |
| `try!` / `fatalError` / `preconditionFailure` / `as!` | **0** | clean |
| Force-unwraps of **external/system data** (`creationDate!` in `SimilarityDetector` bucketing) | **2** | **FIXED this pass (BUG-06)** — replaced with a `compactMap` that carries non-nil dates beside assets; regression test added (`test_similarityDetector_realImplementation_skipsAssetsWithNilCreationDate`) |
| Subscript `[0]` sites (5: `BestPhotoScoring.reasons[0]` after empty-check, `ReviewStore` keep-fallbacks after `remaining.count > 1` guard, `DuplicateContactDetector.members[0]` fallback after structurally ≥2-member clusters with `?.id ?? ` fallback, `DuplicateDetector.sorted[0]` after `count > 1` guard) | 5 | audited one-by-one: every site is preceded by a same-scope emptiness/size guard or a nil-coalescing fallback — reachable-unsafe: **0**. Documented rather than blindly rewritten (per §25). |

`[0]`-subscript audit detail per §25 ("inspect each occurrence, do not blindly remove"):

1. `BestPhotoScoring.reasons[0]` — guarded by `if reasons.isEmpty { return … }` immediately above.
2. `ReviewStore.prunedGroup: remaining[0].id` — guarded by `guard remaining.count > 1`.
3. `ReviewStore.pruneDeletedContacts: remaining[0].id` — same guard shape.
4. `DuplicateContactDetector.members[0].id` — `members.max {…}?.id ?? members[0].id`: clusters are structurally built from 2+ members; the `??` fallback additionally tolerates any future refactor.
5. `DuplicateDetector.sorted[0].id` — guarded by `exactMatches.count > 1` in the enclosing `where` clause.

## 4. Findings ledger (fresh pass)

| ID | Severity | Finding | Status |
| --- | --- | --- | --- |
| SEC-7 | LOW | `creationDate!` force-unwraps on PhotoKit-derived data in similarity bucketing (safe today via a filter invariant; crash class on future refactor or framework anomaly) | **FIXED** this pass (BUG-06) + regression test |
| SEC-8 | INFO | 23 `|| true` occurrences in the workflow | Audited individually — all are first-launch no-ops or diagnostic log-greps; **0 guard required gates** (docs/30 §1) |

No CRITICAL/HIGH/MEDIUM findings. Carried from docs/26 (unchanged, re-verified): no secrets, no network code, no third-party packages, PII-safe logging, minimal data at rest, two gated destructive call sites.

## 5. Destructive-operation audit (§17)

Re-verified: exactly **3 grep matches = 2 real call sites** (`PhotoLibraryServiceLive.deleteAssets` → `PHAssetChangeRequest.deleteAssets`; `ContactServiceLive.deleteContacts` → `CNSaveRequest.delete` + `store.execute`). Both reachable only through `PerformCleanupUseCase.execute(_:confirmed:)` ← `ReviewViewModel.confirmCleanup()` behind the Review screen's `confirmationDialog`. Revalidation + confirmation-guarantee table: docs/24 §9. No hidden delete path exists.

## 6. Concurrency audit (§21)

Re-verified this pass: `@MainActor` on all UI state owners; bounded TaskGroup (`min(cores, 4)`); resume-once continuations on multi-callback `PHImageManager` APIs; epoch-guarded terminal scan transitions; `nonisolated(unsafe)` observer token deregistered in `deinit`; no `Task.detached`; no unbounded task creation. Flakiness re-run (DashboardViewModel, ScanPipeline, Safety, Pruning, PermissionState suites) green in runs 34–37.

## 7. Memory audit (§22)

Streamed SHA-256 (never full buffering); metadata-only enumeration in `autoreleasepool`; thumbnails at cell size × scale only; `AVPlayerItem` materialized only when a preview opens; NSCache countLimit 500; no full-resolution image loads and no full-video loads anywhere in the codebase (video byte sizes come from resource metadata, ADR-01).
