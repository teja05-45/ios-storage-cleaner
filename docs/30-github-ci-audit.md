# 30 — GitHub CI Audit

**Date:** 2026-09-25. Fresh evidence-based audit of the CI pipeline and every currently relevant failure, per the AppFactory audit directive. Sources: GitHub Actions API (runs, jobs, steps, annotations), raw log tails, and executed local commands. No PASS below is claimed without execution.

## 1. Pipeline composition (`.github/workflows/ci.yml`)

Two jobs on `macos-14`, both `failing correctly on error`:

**Job 1 `validate`** — checkout → toolchain verification (`xcodebuild -version`, runtime list) → Xcode first-launch preparation → project-file OpenStep validation (`scripts/validate_pbxproj.py`, incl. isa-class semantic checks) → **security scan** (`scripts/security_scan.py`) → **dependency audit** (`scripts/dependency_audit.py`) → `plutil -lint` → `xcodebuild -list` → **Debug build** (clean build, `iPhone 15 / OS=17.5`, `-resultBundlePath`) → **XCTest suite** (`-only-testing:ReclaimTests -skip-testing:ReclaimUITests`) → **flakiness re-run** of the concurrency/cancellation-sensitive suites (DashboardViewModel, ScanPipeline, Safety, Pruning, PermissionState) → **Release build** → summaries → artifacts (logs **and `.xcresult` bundles**, `if: always()`).

**Job 2 `ui-tests`** (needs: validate) — the `ReclaimUITests` bundle on the iOS 17.5 simulator (launch, dashboard, real-capacity rendering, permission affordances, disabled-until-permitted scan gate via the explicit `dashboard.scanButton` identifier).

**Dangerous-pattern audit (§5):** `continue-on-error` — **0** occurrences; `exit 0` — **0** occurrences. `|| true` — 23 occurrences, **each inspected individually**:
- 6 are Xcode first-launch preparation no-ops (license/first-launch/idempotent steps where any outcome is acceptable by design);
- 17 are log-processing greps (`grep … || true`, `tail … || true`) inside `set +e` diagnostic blocks whose *step exit code* comes from the captured tool status, never from the grep — a no-match grep is a legitimate outcome there (e.g. no errors found in a passing build's log).
- **None of the 23 guards a required quality gate.** Every gate step (`validate_pbxproj.py`, `security_scan.py`, `dependency_audit.py`, `plutil -lint`, `xcodebuild -list`, Debug build, XCTest, flakiness re-run, Release build, UI tests) ends with `exit $status` from the real tool exit code.

## 2. Failure ledger — every currently relevant failure

The failures relevant to the *current* pipeline are runs 31–33 (the first three executions of the extended pipeline), all root-caused from API annotations and fixed; the complete run-by-run record with exact errors, root causes, fixes, and validation is in **`docs/28-ci-failure-ledger.md`** and is not duplicated here. Summary:

| Run | SHA | Step | Error | Root cause | Status | Fix | Regression test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 31 | `1089d9a…` | `xcodebuild -list` | exit 74, `-[PBXBuildFile setOwner:]: unrecognized selector`, "damaged project" | UI-test target's `dependencies` referenced a PBXBuildFile instead of a PBXTargetDependency (BUG-05) | CLOSED | generator references `targetdep` namespace; orphaned build file removed | validator isa-class checks + executed negative test |
| 32 | `4e3d61d…` | `xcodebuild -list` | same class as 31 | same BUG-05 (fix commit came next in the old chain) | CLOSED | `155502d` fix, replayed in the history reconstruction | same |
| 33 | `155502d…` | `Run XCTest suite` | exit 65: `recoverableBytes ("0") != ("123456")`; two UI tests: scan control not found | test-design errors: unselected-group assertion; XCUITest label-resolution of styled SwiftUI `Label`; UI bundle ran inside the unit step | CLOSED | selection toggled in test; `dashboard.scanButton` identifier; explicit `-skip-testing:ReclaimUITests` | runs 34–37 green |
| 34–37 | `292a36e`→`bbddcd8` | — | — | — | **GREEN** | — | four consecutive fully green runs (both jobs) |

Historical runs 1–23 (project-file grammar, first-compile fixes, first-execution test corrections, cancellation test design) are ledgered in `docs/21-ci-failure-analysis.md`; their SHAs are unreachable from `main` (verified by `git merge-base --is-ancestor` → 1 in docs/23 §11 and re-verified this pass).

## 3. macOS environment (as exercised by runs 34–37)

| Item | Value | Evidence |
| --- | --- | --- |
| Runner | `macos-14` (GitHub-hosted, arm64) | workflow `runs-on` |
| Xcode | 15.4 series (runner image default selected by the workflow's first-launch steps) | run logs: `xcodebuild -version` step output; `Show toolchain` step green |
| Simulator | iPhone 15, iOS 17.5 (`platform=iOS Simulator,name=iPhone 15,OS=17.5`) | workflow destination strings; green test steps |

(Exact Xcode point versions are recorded in each run's raw log artifact; the workflow prints them in the `Show toolchain` step rather than this document asserting them from memory.)

## 4. Current status

Latest four runs on `main`: **34, 35, 36, 37 — all `success`** (both jobs), latest at `bbddcd8c8f302e0780116e8e3fd0413f07e7e4ad`. `xcodebuild -list` discovers targets **Reclaim**, **ReclaimTests**, **ReclaimUITests** (validated green in every run). Project generator: deterministic (two consecutive generations byte-identical, re-verified this pass).
