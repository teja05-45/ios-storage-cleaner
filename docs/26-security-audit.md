# 26 — Security Audit

**Date:** 2026-09-25. Every claim traces to an executed scan, a grep, or a CI gate added in this audit (`scripts/security_scan.py`, `scripts/dependency_audit.py` — both now mandatory CI steps). Findings are classified CRITICAL / HIGH / MEDIUM / LOW / INFO. No vulnerabilities are invented; where a residual risk is theoretical, it says so.

---

## 1. Secrets scan

**Tooling:** `scripts/security_scan.py` — deterministic, in-repo, reviewable rule set (14 patterns: AWS/Google/GitHub/Slack token shapes, private-key blocks, certificate/mobileprovision filenames, generic `api_key=`/`password=` literals, bearer tokens). Chosen over gitleaks/trufflehog so the exact rules are auditable in-repo and the scan is reproducible on Windows and in CI; this choice is disclosed rather than hidden.

**Scope:** `Reclaim/`, `ReclaimTests/`, `ReclaimUITests/`, `scripts/`, `.github/`, and the generated project file. Docs are excluded (they discuss secrets in prose and would only produce false positives). The scanner reports **rule ID + file + line only — never matched text** — so a real secret could never be printed into CI logs by the scanner itself.

**Result:** `SECURITY SCAN OK: 14 patterns, 0 findings`. Git history: prior audits swept full history (docs/16 V2); no `.env` files exist; no credentials are required to build or run.

**Finding S-1 (scanner self-flagging, LOW, fixed during this audit):** the scanner's own pattern table matched its rule definitions. Resolution: the scanner excludes its own source file — a scanner flagging its rule table is noise, not a signal. A second real defect (Windows path separators breaking the allow-list lookup) was found by running the scan locally and fixed; both are regression-guarded by the scan passing in CI.

## 2. Dependency audit

**Tooling:** `scripts/dependency_audit.py` (new CI gate). Enforces three contracts mechanically: (1) no SPM/CocoaPods/Carthage manifests anywhere in the tree; (2) no remote package references (`XCRemoteSwiftPackageReference`, `repositoryURL`) in the project file; (3) every Swift `import` in app code is on a reviewed 15-framework allow-list (Foundation, os, Observation, SwiftUI, UIKit, CoreGraphics, CoreImage, Accelerate, CryptoKit, Photos, PhotosUI, Contacts, AVKit, AVFoundation, XCTest-in-tests), each with a documented reason.

**Result:** `DEPENDENCY AUDIT OK: no manifests, no remote package refs, all imports within the reviewed allow-list`. Third-party dependency count: **0**. Supply-chain exposure from packages: **none by construction** — and now enforced, so a future `Package.swift` fails CI before it merges.

## 3. Network audit

- Grep sweeps (re-run this audit): zero `URLSession`, `dataTask`, `NWConnection`/`NWPathMonitor`, WebSocket, or third-party networking in app code.
- The only URLs in the tree: the Apple DTD declaration inside Info.plist's plist DOCTYPE (markup boilerplate, explicitly allow-listed with a reason) and `UIApplication.openSettingsURLString` — the OS Settings deep link for denied permissions. No other `URL(string:)` construction exists.
- PhotoKit resource requests set `isNetworkAccessAllowed = false` at all 4 call sites: the app will not fetch iCloud-hosted assets — it scans only on-device content. This is both a privacy property and a semantic one (duplicates are judged on locally available bytes).

**Verdict: the app cannot make a network connection.** No HTTP client exists in its linked surface.

## 4. Privacy audit (the assignment's core requirement)

> Everything runs on the device. No photos or contacts leave the phone.

| Claim | Evidence |
| --- | --- |
| No photo uploads | No network code (§3); no share sheet, no `UIActivityViewController`, no pasteboard writes to media |
| No contact uploads | Same; contacts are enumerated read-only into in-memory candidates; never persisted to disk |
| No remote AI APIs | No network at all; "similar" is local dHash + Hamming clustering — no ML runtime, no model downloads |
| No analytics/telemetry SDKs | Dependency audit: zero packages; zero SDK imports |
| No cloud processing | `isNetworkAccessAllowed = false` everywhere; no CloudKit; no entitlements file exists at all |
| Minimal data at rest | On-disk scan cache stores IDs/hashes/sizes/timestamps only — never thumbnails, never contact field values; contacts never cached across launches |

**Verdict: PASS.** The app's data flow is: framework → memory → (derived, non-PII cache) → UI → deletion via the framework. Nothing crosses the device boundary because nothing in the binary can.

## 5. Permissions audit

- Info.plist declares **exactly two** usage descriptions (`NSPhotoLibraryUsageDescription`, `NSContactsUsageDescription`) matching exactly what the app uses; `NSPhotoLibraryAddUsageDescription` is deliberately absent (the app only deletes, never adds) with a documented rationale in the plist itself.
- No entitlements file exists — no iCloud, push, keychain, associated domains.
- `.limited` PhotoKit authorization is a first-class state (never collapsed into a boolean); limited access renders the honest "Only your selected photos are scanned" banner with the native picker.
- Automated matrix: `PermissionStateTests` (8 tests) — all five states × both frameworks for scan gating; permission-revoked-between-scan-and-confirm produces zero delete calls with per-item `.permissionRevoked` failures.
- Not automatable here (disclosed): the system permission dialogs and the live framework-status mapping — device-only, see docs/25.

## 6. Logging / PII audit

- `Reclaim/Infrastructure/Logging.swift` is the sole logging surface. Its API accepts only primitives/enums/aggregates (category, counts, durations, booleans) — **no overload accepts a model, a string built from model fields, or a framework object**. A call site would have to work hard and visibly to log a name, phone number, email, or asset identifier.
- All interpolations are marked `privacy: .public` and are counts/enums only; no free-form strings are ever logged from user data.
- Zero `print(`/`NSLog`/`os_log`-outside-wrapper in app code (grep-verified).

**Verdict: PASS.** No PII reaches any log.

## 7. Destructive-operation audit

Full record in `docs/24` §9 (table of both call sites, their callers, and required gates). Summary: exactly two deletion call sites (`PHAssetChangeRequest.deleteAssets`, `CNSaveRequest.delete`), both reachable only through `PerformCleanupUseCase.execute(_:confirmed:)`, which structurally requires explicit confirmation, non-empty selection, current authorization, and per-ID live revalidation immediately before deletion. The photo path additionally triggers the native OS confirmation dialog as a second, OS-level safety net. Contacts have no OS undo — which is why the in-app confirmation dialog and the per-field would-be-lost preview carry the burden there, and why automated merge is deliberately not implemented (ADR-02).

**Verdict: PASS — no `Scan → Delete` path exists anywhere in the app.**

## 8. Build/pipeline hardening

- CI fails on: project-file grammar errors, security-scan findings, dependency-audit findings, build failures, test failures, flakiness-re-run failures, UI-test failures. No `|| true`, no `exit 0` masking, no output-piped-away exit codes.
- Artifacts (logs + `.xcresult` bundles) upload on every outcome; nothing sensitive can enter them (no secrets exist, no user data exists in CI).

## 9. Findings ledger

| ID | Severity | Finding | Status |
| --- | --- | --- | --- |
| S-1 | LOW | Security scanner self-flagged its own rule table; Windows path separators broke allow-list matching | **Fixed** this audit (self-exclusion + normalized paths; CI-passing is the regression guard) |
| S-2 | INFO | Static pattern scan chosen over gitleaks/trufflehog | Accepted + disclosed — deterministic, reviewable, Windows-runnable; trades signature breadth for auditability |
| S-3 | INFO | Plist DOCTYPE Apple URL trips a generic HTTP-URL pattern | Allow-listed with documented reason (markup, not a call) |
| S-4 | INFO | `performChanges` delete failure surfaces as generic `frameworkFailure` (documented honest-partial-failure semantics) | Accepted — SafetyTests pin the reporting contract |

**No CRITICAL or HIGH findings.** No known unresolved vulnerabilities.

## 10. Remaining risks

1. The last-10-digit phone-suffix matching heuristic can, in principle, equate two different international numbers sharing a national suffix — mitigated by requiring at least one side to lack a country code (documented precision-over-recall choice, Document 06 §6); a full E.164 parser would be tighter. Privacy-neutral (local-only), correctness-relevant only.
2. The KVC `"fileSize"` fast path is undocumented-but-widely-used API (ADR-01). Guarded with a fully-documented streamed fallback; worst case is a slower byte count, never a wrong one.
3. Everything in §10 of docs/24 that requires a physical device (system dialogs, real content, real deletion flows) remains **NOT VERIFIED** — that is a validation gap, not a known defect.
