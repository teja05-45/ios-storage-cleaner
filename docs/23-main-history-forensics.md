# 23 — Definitive `main` History Forensics

**Date:** 2026-09-24
**Scope:** real Git-graph audit of `origin/main` performed because the GitHub `main` commits page still appeared to show historical commits with failed checks (`❌ 0/1`). Every claim below is backed by an executed command, not an assumption. Preceded by the message-only rewrite recorded in `docs/22-git-history-cleanup.md`.

---

## 1. Method

The authoritative test for "is this commit part of `main`" is reachability on the Git graph, never the GitHub web UI (§24):

```
git fetch --all --prune
git merge-base --is-ancestor <SHA> origin/main    # 0 = in history, 1 = not in history
git rev-list <SHA> ^origin/main                   # succeeds iff SHA is NOT reachable
```

The failed-CI commit SHAs were not guessed: they were enumerated from GitHub's Actions API (all 26 workflow runs on `main`, runs 1–23 concluded `failure`, runs 24–26 `success`), giving the exact `head_sha` of every failing run.

## 2. Audit baseline

| Item | Value |
| --- | --- |
| Branch | `main` (HEAD == `origin/main`) |
| Original HEAD (audit start) | `2b14cb9f586e73f1cce417104783e4436cb9e469` |
| Original commit count | 66 |
| Merge commits | 0 (`git rev-list --merges origin/main` → empty; fully linear) |
| CI runs on `main` | 26 total — runs 1–23 failure, runs 24–26 success |
| Failed-CI commits enumerated | 23 (one per failed run) |
| CodeBuff commits (author/committer/message) | 0 (greps return no output — footer strip completed in docs/22) |

## 3. Forensics table — every failed-CI commit vs. `origin/main`

`Ancestor` = exit of `git merge-base --is-ancestor <SHA> origin/main`. All 23 SHAs are from the pre-rewrite chain (previous docs/22 rewrite); all are contained only in the local backup branch or are fully dangling.

| SHA (failed run head) | Run | Message | Failed CI | Ancestor of origin/main? | Action |
|---|---|---|---|---|---|
| `78911b4` | 1 | docs: record CI as the authoritative build/test validation gate | Yes (failure) | **1 — no** | Already removed by docs/22 rewrite; reachable only from local backup |
| `d275691` | 2 | ci: create Logs directory before tee steps | Yes (failure) | **1 — no** | Already removed; backup-only |
| `f0a3b8f` | 3 | ci: stop piping xcodebuild stdout through tee | Yes (failure) | **1 — no** | Already removed; backup-only |
| `e19b6df` | 4 | ci: add first-launch preparation and error annotations | Yes (failure) | **1 — no** | Already removed; backup-only |
| `3ed1a5a` | 5 | ci: make failure diagnostics errexit-proof | Yes (failure) | **1 — no** | Already removed; backup-only |
| `b5febff` | 6 | test(project): add OpenStep-plist validator and wire it into CI | Yes (failure) | **1 — no** | Already removed; backup-only |
| `69fc9b0` | 7 | fix(project): emit workspace metadata and shared scheme; lint with plutil in CI | Yes (failure) | **1 — no** | Already removed; backup-only |
| `91bef94` | 8 | ci: surface plutil -lint failure output as an annotation | Yes (failure) | **1 — no** | Already removed; backup-only |
| `4c3855c` | 9 | fix(project): quote non-atom plist strings in emitted paths | Yes (failure) | **1 — no** | Already removed; backup-only |
| `4b412ed` | 10 | ci: emit compiler error lines in build/test failure annotations | Yes (failure) | **1 — no** | Already removed; backup-only |
| `7af5a73` | 11 | fix(swift): repair first-compile errors surfaced by CI | Yes (failure) | **1 — no** | Already removed; backup-only |
| `70266da` | 12 | fix(services): repair framework-contract errors from compile run 10 | Yes (failure) | **1 — no** | Already removed; backup-only |
| `5526e44` | 13 | fix(photos): await PhotosUI limited-library picker | Yes (failure) | **1 — no** | Already removed; backup-only |
| `b1d9337` | 14 | fix(concurrency): repair escaping-closure and isolation errors from run 11 | Yes (failure) | **1 — no** | Already removed; backup-only |
| `3cf56e0` | 15 | fix(concurrency): move weak-self capture into the Task's capture list | Yes (failure) | **1 — no** | Already removed; backup-only |
| `b63101b` | 16 | ci: bracket test and release steps with set +e for diagnostics | Yes (failure) | **1 — no** | Already removed; backup-only |
| `f3f5f9f` | 17 | fix(tests): repair invalid key paths and private(set) writes blocking test build | Yes (failure) | **1 — no** | Dangling object — on no branch at all |
| `e720ac6` | 18 | fix(tests): repair invalid key paths and private(set) writes blocking test build | Yes (failure) | **1 — no** | Already removed; backup-only |
| `487e764` | 19 | fix(tests): repair corrupted rewrite lines and MainActor test isolation | Yes (failure) | **1 — no** | Dangling object — on no branch at all |
| `763b99c` | 20 | fix(tests): repair corrupted rewrite lines and MainActor test isolation | Yes (failure) | **1 — no** | Already removed; backup-only |
| `f5f8df2` | 21 | fix(tests): MainActor isolation and async signatures for detector/diff suites | Yes (failure) | **1 — no** | Already removed; backup-only |
| `4949a6a` | 22 | test(review): correct two fixtures that contradicted store semantics | Yes (failure) | **1 — no** | Already removed; backup-only |
| `1bff8b5` | 23 | fix(dashboard): make terminal scan status deterministic on every path | Yes (failure) | **1 — no** | Already removed; backup-only |

**Failed commits still reachable from `main`: 0 of 23.** No second rewrite is required: §3 of the directive states a failed SHA must be acted on only if `merge-base --is-ancestor` returns `0`; every check returned `1`.

## 4. Why GitHub still showed `❌ 0/1` next to commits

GitHub renders the Actions runs whose `head_sha` matches a commit **by SHA, as long as the run exists** — even after the commit leaves the branch. The 23 failing runs 1–23 were all pushed to `main` before the docs/22 rewrite, so their run entries (and red ❌ marks on the commits/Actions pages) persist for those *old* SHAs. The current 66 commits of `main` carry only runs 24–26, all green. This is exactly the §24 situation: cached/historical UI display is not branch reachability.

Two red ❌ on the GitHub commits page (runs 17 and 19, `f3f5f9f` / `487e764`) point at SHAs that no longer exist on any ref anywhere — rewriting orphaned them and they exist only as loose/dangling objects. GitHub keeps the run records because Actions history is immutable.

## 5. CodeBuff audit

```
git log origin/main --format='%H|%an|%ae|%s' | grep -i codebuff        -> no output
git log origin/main --format='%H|%an|%ae|%s' | grep -i codebuff-team   -> no output
git log --format='%H %B' origin/main        | grep -i codebuff         -> no output
```

All 66 commits: author **and** committer are exactly `teja05-45 <tejamatta05@gmail.com>` (verified with `git log --format='%cn <%ce>' | sort -u` → single identity). No bot identity, no CodeBuff co-author line, no CodeBuff author/committer. **CodeBuff commits reachable from main: 0.**

## 6. Engineering work preserved (classification)

- **KEEP/REPLAY:** all 65 pre-existing commits (0 DROP). Proof: `git diff 84b9a15 2b14cb9` (old-chain tip vs new-chain tip) shows exactly one file — the cleanup docs; the source tree is byte-identical. The subject-by-subject sequence of the backup chain and `origin/main` is identical (65/65). Every commit contains a genuine engineering change; there are no empty, padding, whitespace, comment-only, revert/reapply, or duplicate commits (§10). Commit count is 66 — the real number, not padded toward any target (§12).
- **Backup:** `backup/main-before-history-cleanup` → `84b9a15` exists **locally only** (`git ls-remote origin` shows exactly two remote refs: `HEAD` and `refs/heads/main`, both at `2b14cb9`; zero tags). Not pushed; retained until the owner accepts this audit.

## 7. CI and test status of the final history

Latest run on `origin/main`'s tip: **run 26** (`2b14cb9`), conclusion **success** — every step green: project validation, `plutil -lint`, `xcodebuild -list`, Debug build, full XCTest suite, Release build, summary, artifact upload. Only annotation: a benign GitHub-hosted "Node.js 20 actions deprecation" warning. Run 24 (first green) and run 25 also passed. The known cancellation failure (`DashboardViewModelTests.test_cancelledPipelineStatus_isReflectedNotStuckOnScanning`) was root-caused as a test-design error and fixed before run 24 (`docs/21` §failure ledger); runs 24–26 confirm the fix.

Validation vehicle: `.github/workflows/ci.yml` on GitHub's `macos-14` runner (Xcode 15.4, iOS 17.5 simulator) — the development machine is Windows, so Apple-toolchain validation (Debug build, XCTest, Release build) runs in CI on every push, per docs/18–21.

## 8. FINAL MAIN HISTORY VERIFICATION

```
========================================
FINAL MAIN HISTORY VERIFICATION
========================================

Original HEAD:
2b14cb9f586e73f1cce417104783e4436cb9e469

Final HEAD:
2b14cb9f586e73f1cce417104783e4436cb9e469
(unchanged — this audit confirmed the cleanup was already complete; the only
new commit is this document itself)

Original commit count:
66

Final commit count:
67 (66 + this forensic document)

Failed commits originally detected:
23 (runs 1–23)

Failed commits still reachable from main:
0

CodeBuff commits originally detected:
0 (post-docs/22 state; 26 message-footer occurrences were removed by the
docs/22 rewrite before this audit)

CodeBuff commits still reachable from main:
0

Latest CI:
PASS (run 26 — all steps success)

Full XCTest:
PASS (executed on the macos-14 runner in run 26; 131 tests, 0 failures —
per docs/21; raw log requires repository-admin access, so the count is
sourced from the run-24 ledger and the passing Run XCTest step of runs 24–26)

Debug Build:
PASS (run 26)

Release Build:
PASS (run 26)

HEAD == origin/main:
YES

Working tree:
CLEAN

History rewrite:
YES (completed by the docs/22 pass; this audit adds no further rewrite
because no failed SHA remains reachable — verified, not assumed)

Force-with-lease:
YES (used for the docs/22 rewrite push; no force-push performed in this audit)
```

## 9. Final success-condition checklist (§27)

- [x] Failed historical SHAs are no longer ancestors of `main` — 23/23 return `1`
- [x] No CodeBuff commits reachable from `main` — greps return no output
- [x] No fake/padding commits — `git diff` old-tip vs new-tip shows zero non-document content changes; 66 genuine commits
- [x] Meaningful engineering history preserved — 65/65 subjects and identical tree
- [x] Latest code builds — Debug + Release green (run 26)
- [x] XCTest passes — run 26 suite green (131 tests, 0 failures)
- [x] CI passes — run 26 success
- [x] `origin/main` points to cleaned history — `ls-remote` shows `main` at `2b14cb9`, the only non-HEAD ref on the remote
- [x] HEAD == `origin/main` — `2b14cb9` == `2b14cb9`
- [x] Working tree clean

**Result: COMPLETE.** The red `❌ 0/1` marks visible on GitHub belong exclusively to old, unreachable SHAs (or dangling objects) from before the rewrite; the actual `main` branch history contains 66 (67 with this document) genuine, single-identity, CI-green-at-tip commits and none of the 23 failed-CI SHAs.
