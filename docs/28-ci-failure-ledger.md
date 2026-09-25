# 28 — CI Failure Ledger (runs 31–35)

**Date:** 2026-09-25. Covers the five runs triggered by the full GitHub-based audit (`docs/24`–`27`). Sources of truth: GitHub Actions API (run records, job steps, failure annotations) and raw log tails — never commit titles. Every failed run's root cause was fixed and revalidated; the final state is green (runs 34 and 35).

## Run-by-run ledger

### Run 31 — `1089d9a8dfbf1c03cb2a2dac8a5d9d10cd258c3e` — FAILURE

| Field | Value |
| --- | --- |
| Run ID | 36133254596 |
| Job / step | `Build + Test (macOS)` / `xcodebuild -list` |
| Exact error | `-[PBXBuildFile setOwner:]: unrecognized selector sent to instance` → `Unable to read project 'Reclaim.xcodeproj' … The project 'Reclaim' is damaged and cannot be opened.` (exit 74) |
| Root cause | **BUG-05**: the newly generated `ReclaimUITests` target's `dependencies` array referenced a **PBXBuildFile** object (`uuid_for("dependency:uitest-on-app")`) instead of the **PBXTargetDependency** object (`uuid_for("targetdep:uitest-on-app")`). Xcode's project loader requires `PBXTargetDependency` there and rejected the entire project. `validate_pbxproj.py` verified reference *existence* but not the *isa class* of referenced objects — the same class of blind spot as the docs/21 run-5 lesson (regex-level checks cannot see what a real parser/loader enforces). |
| Fix | Generator: UI-test target now references the `targetdep` namespace; the erroneous "Reclaim.app in Frameworks" PBXBuildFile for the UI target removed (a UI-test bundle links its host app via `TEST_TARGET_NAME` + target dependency, not a Frameworks build file). Validator: isa-class semantic checks added (see run 32). |
| Validation | CI run 33 progressed past `xcodebuild -list` for the first time with the UI-test target present. |

### Run 32 — `4e3d61d1bc2fcc3ed5696a9f466565d3f157e83e` — FAILURE

| Field | Value |
| --- | --- |
| Run ID | 36133511290 |
| Job / step | `Build + Test (macOS)` / `xcodebuild -list` |
| Exact error | Same exit-74 "damaged project" class as run 31 (the run-31 SHA's tree still contained the defect; this commit only carried the UI-test accessibilityHint fixup) |
| Root cause | Same BUG-05 — this commit did not include the generator fix |
| Fix | `155502d` (next commit in the old chain) carried the generator + validator fix |
| Validation | run 33 |

### Run 33 — `155502db9cea549c82f72c273a1f2ebdf7854bf3` — FAILURE

| Field | Value |
| --- | --- |
| Run ID | 36133983268 |
| Job / step | `Build + Test (macOS)` / `Run XCTest suite` (project finally loaded; two new, different failure classes) |
| Exact errors | (1) `DetectionPipelineTests.swift:63: XCTAssertEqual failed: ("0") is not equal to ("123456") — selecting one member must report the real bytes, not 0`; (2) `ReclaimUITests.swift:57 + :98: XCTAssertTrue failed — the scan control must exist on first launch` |
| Root causes | (1) **Test-design error in the new BUG-01 regression**: `recoverableBytes` counts *selected* members only — a freshly detected group legitimately reports 0; the assertion never toggled a selection. Production behavior was correct. (2) **XCUITest could not resolve the styled SwiftUI scan `Label` by label text** (`Label` + `.borderedProminent` automatic label joining); the other label queries in the same tests passed, proving the dashboard rendered. (3) Also observed: `ReclaimUITests` was built *and executed* inside the unit-suite step despite `-only-testing:ReclaimTests` — on this scheme the UI bundle needs an explicit `-skip-testing` too. |
| Fix | `d26df9b`: scan button gains an explicit `dashboard.scanButton` accessibility identifier (standard testability hook; user-visible label/hint unchanged); the size regression now toggles a member selection first and asserts the real resolved size flows into `recoverableBytes`; the UI tests no longer read `accessibilityHint` (not exposed through the XCUITest element graph — the on-device disclosure remains covered by the docs/24 §12 code audit). `292a36e`: both test steps pass `-skip-testing:ReclaimUITests` explicitly; the UI bundle runs in its own dependent job. |
| Validation | **CI run 34 — full success** (both jobs: validate + ui-tests). |

### Run 34 — `292a36ea2ba523275207295b61a8087063aff99e` — SUCCESS

First fully green run of the extended pipeline: project validation → security scan (14 patterns, 0 findings) → dependency audit (0 packages, allow-list clean) → `plutil -lint` → `xcodebuild -list` → Debug build → XCTest suite → flakiness re-run → Release build (job 1); UI tests on the iOS 17.5 simulator (job 2).

### Run 35 — `32e9de596a50b11f2b0e19d391711be3cf627b65` — SUCCESS

Green on the **reconstructed history** (see below): identical tree, replayed commits, no failed SHAs reachable from `main`.

## History reconstruction (runs 31–33's failed SHAs removed from main)

The owner requires no `❌ 0/1` commits to remain reachable from `main`. Runs 31–33 ran on SHAs that **were** ancestors of `main` — a green tip (run 34) did not remove them. Reconstruction, per the directive (preserve genuine work, remove failed SHAs, no fake commits):

1. Backups: `backup/main-before-final-cleanup` and `backup/main-before-final-history-cleanup` → `292a36e` (local-only, not pushed).
2. `git reset --hard 4030be8` — the last green SHA that remains an ancestor (runs 29/30 green, run 35 green later).
3. Replay of the five old-chain commits:
   - `8ecdbb4` ← cherry-pick of `1089d9a` (docs/24–27) — identical content;
   - `9f01a93` ← the unit-test suites (Fakes + DetectionPipelineTests + PermissionStateTests) materialized from the validated tree;
   - `236ac27` ← the platform increment (detectors' size fix folded here with its tests already present, Dashboard identifier, ReclaimUITests, scanners, generator + validator with isa checks, project file, workflow) — byte-identical to the run-34-validated tree;
   - `32e9de5` ← BUG-05 record restored into docs/27.
   - Dropped: `4e3d61d` (obsolete accessibilityHint fixup — superseded by the rewrite in the replayed platform increment) and the old tip-fixup SHAs, whose content is fully contained in `236ac27`.
4. Identity proof: `git diff 292a36e HEAD` → **empty** — the final tree is byte-identical to the state CI run 34 validated green. No engineering work lost, nothing fabricated.
5. Failed-SHA reachability on the new chain: `1089d9a…` → 1, `4e3d61d…` → 1, `155502d…` → 1 (none reachable).
6. Pushed with `git push --force-with-lease origin main` (never raw `--force`), after local gates: generator determinism, OpenStep validation (211 objects), security scan, dependency audit — all green.

## Verification matrix after reconstruction

| Check | Result |
| --- | --- |
| CI run 35 on new tip `32e9de5` | **success** (both jobs) |
| Failed SHAs reachable from main | **0 of 3** |
| CodeBuff grep (authors/emails/subjects/bodies) | 0 matches |
| Commit count | 74 (was 75; one superseded fixup legitimately collapsed) |
| HEAD == origin/main | YES (`32e9de596a50b11f2b0e19d391711be3cf627b65`) |
| Working tree | CLEAN |
| Test counts (from run 34/35 logs) | 144 XCTests executed, 0 failures; 4 UI tests executed, 0 failures |

Note on GitHub UI: runs 31–33 remain listed in the Actions tab as failed run records — Actions history is immutable and keyed by SHA, not branch membership. The `main` commits page now shows no red: every commit reachable from `main` either has a green run (29/30/34/35 + all runs 24–28 on their SHAs' chain) or never ran (docs-only/history-only commits below the first CI workflow).
