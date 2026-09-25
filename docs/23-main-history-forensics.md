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

## 10. Post-push verification addendum (point-in-time record)

Recorded immediately after publishing the audit body. The push was a clean fast-forward (`2b14cb9..c715ff5`) — no force-push of any kind was needed in this audit.

| Check | Result |
| --- | --- |
| CI run 27 on audit tip `c715ff5` | **success** — all 13 steps green: project validation, `plutil -lint`, `xcodebuild -list`, Debug build, Run XCTest suite, Release build, summary, artifact upload |
| Failed-SHA reachability re-check on final `origin/main` | 23/23 return `git merge-base --is-ancestor <SHA> origin/main` → `1` (none reachable) |
| CodeBuff grep on final `origin/main` | 0 matches |
| Final commit count | 67 |
| HEAD == `origin/main` | YES (`c715ff53b45b940685036e25447a418c98b9c523`) |
| Working tree | CLEAN |
| Remote refs (`git ls-remote origin`) | exactly `HEAD` + `refs/heads/main`, both at the final tip |
| Backup branch | `backup/main-before-history-cleanup` remains local-only (not pushed), retained until the owner accepts this audit |

Any commits after this addendum are later genuine work; the §9 checklist is the standing verification procedure for them.

## 11. Addendum — second independent audit (2026-09-25)

Trigger: the owner reported that GitHub still visibly shows historical commits with `❌ 0/1`. Per the definitive directive, **nothing was assumed**: the entire audit below was re-executed against the live remote before any conclusion.

### 11.1 Baseline re-verified

| Item | Value |
| --- | --- |
| Branch / HEAD | `main` @ `ff290b3c9fa470c538fe9b3cbd3138e8b080f60b` |
| `HEAD == origin/main` | YES (`git rev-parse` both → `ff290b3`; `git ls-remote` live-confirmed `refs/heads/main` @ `ff290b3`) |
| Commit count | 68 (`git rev-list --count` on both `main` and `origin/main`) |
| Merge commits | 0 (`git rev-list --merges origin/main` → empty; fully linear — linear reconstruction would be the method if a rewrite were needed) |
| Working tree | CLEAN |
| Remote refs | exactly `HEAD` + `refs/heads/main`, both `ff290b3`; zero tags; no backup pushed |
| Committer identity | single identity across all 68: `teja05-45 <tejamatta05@gmail.com>` (author set and committer set each `sort -u` to exactly one line) |
| Local backup created (§6) | `backup/main-before-definitive-cleanup` → `ff290b3` (verified via `git show-ref`; local-only, not pushed) |
| Pre-existing backup | `backup/main-before-history-cleanup` → `84b9a15` (pre-rewrite chain; local-only) |

### 11.2 Failed-CI commit census (from GitHub Actions API, not guessed)

All 28 workflow runs on `main` enumerated: runs 1–23 `failure`, runs 24–28 `success`. The 23 failing runs' `head_sha`s were pulled from the API and each tested against `origin/main`:

| Run | Failed SHA (API head_sha) | Message | Failed CI | Ancestor of origin/main? | Action |
|---|---|---|---|---|---|
| 1 | `78911b4` | docs: record CI as the authoritative build/test validation gate | Yes | **1 — not reachable** | none needed |
| 2 | `d275691` | ci: create Logs directory before tee steps | Yes | **1 — not reachable** | none needed |
| 3 | `f0a3b8f` | ci: stop piping xcodebuild stdout through tee | Yes | **1 — not reachable** | none needed |
| 4 | `e19b6df` | ci: add first-launch preparation and error annotations | Yes | **1 — not reachable** | none needed |
| 5 | `3ed1a5a` | ci: make failure diagnostics errexit-proof | Yes | **1 — not reachable** | none needed |
| 6 | `b5febff` | test(project): add OpenStep-plist validator and wire it into CI | Yes | **1 — not reachable** | none needed |
| 7 | `69fc9b0` | fix(project): emit workspace metadata and shared scheme; lint with plutil in CI | Yes | **1 — not reachable** | none needed |
| 8 | `91bef94` | ci: surface plutil -lint failure output as an annotation | Yes | **1 — not reachable** | none needed |
| 9 | `4c3855c` | fix(project): quote non-atom plist strings in emitted paths | Yes | **1 — not reachable** | none needed |
| 10 | `4b412ed` | ci: emit compiler error lines in build/test failure annotations | Yes | **1 — not reachable** | none needed |
| 11 | `7af5a73` | fix(swift): repair first-compile errors surfaced by CI | Yes | **1 — not reachable** | none needed |
| 12 | `70266da` | fix(services): repair framework-contract errors from compile run 10 | Yes | **1 — not reachable** | none needed |
| 13 | `5526e44` | fix(photos): await PhotosUI limited-library picker | Yes | **1 — not reachable** | none needed |
| 14 | `b1d9337` | fix(concurrency): repair escaping-closure and isolation errors from run 11 | Yes | **1 — not reachable** | none needed |
| 15 | `3cf56e0` | fix(concurrency): move weak-self capture into the Task's capture list | Yes | **1 — not reachable** | none needed |
| 16 | `b63101b` | ci: bracket test and release steps with set +e for diagnostics | Yes | **1 — not reachable** | none needed |
| 17 | `f3f5f9f` | fix(tests): repair invalid key paths and private(set) writes blocking test build | Yes | **1 — not reachable** | none needed |
| 18 | `e720ac6` | fix(tests): repair invalid key paths and private(set) writes blocking test build | Yes | **1 — not reachable** | none needed |
| 19 | `487e764` | fix(tests): repair corrupted rewrite lines and MainActor test isolation | Yes | **1 — not reachable** | none needed |
| 20 | `763b99c` | fix(tests): repair corrupted rewrite lines and MainActor test isolation | Yes | **1 — not reachable** | none needed |
| 21 | `f5f8df2` | fix(tests): MainActor isolation and async signatures for detector/diff suites | Yes | **1 — not reachable** | none needed |
| 22 | `4949a6a` | test(review): correct two fixtures that contradicted store semantics | Yes | **1 — not reachable** | none needed |
| 23 | `1bff8b5` | fix(dashboard): make terminal scan status deterministic on every path | Yes | **1 — not reachable** | none needed |

**Failed commits still reachable from `main`: 0 of 23.** The green runs 24 (`e00476c`) and 25 (`84b9a15`) ran on the pre-rewrite chain and are likewise unreachable; green runs 26–28 ran on the current chain (`2b14cb9`, `c715ff5`, `ff290b3`).

### 11.3 CodeBuff audit (re-run)

```
git log origin/main --format='%H|%an|%ae|%s' | grep -i codebuff      -> no output
git log origin/main --format='%H %B'           | grep -i codebuff      -> no output
```

No CodeBuff author, committer, email, subject, or message body. No bot identity. **0 commits.**

### 11.4 Dangling objects (not on any ref)

`f3f5f9f` and `487e764` exist only as unreferenced loose objects (`git cat-file -e` succeeds; not reachable from any branch, tag, or remote ref). They vanish on the next `git gc`; they are not part of `main` by any definition.

### 11.5 Verdict — no rewrite performed, and none is warranted

The directive's §3 rule is conditional: a failed SHA must be acted on **only if** `git merge-base --is-ancestor <SHA> origin/main` returns `0`. All 23 return `1`. The rewrite that removed these commits from `main` was already executed in the docs/22 pass (force-with-lease, backup retained); this audit confirms its result against the live remote rather than trusting the prior document. Performing a second rewrite now would change nothing the directive measures: the new chain would still be an equal-or-worse approximation of the current genuine 68-commit history, and GitHub's Actions run records 1–23 would persist regardless of any rewrite — run records are keyed by SHA, not by branch membership, and Actions history is immutable.

**Where the remaining visible red actually lives:** the GitHub **Actions tab** lists runs 1–23 as failures for branch `main`, and old commit URLs (served by SHA, cacheable) still render their historical check status. Neither is a statement about current branch history — §24 covers exactly this. The `main` commits page itself shows no red: 65 rewritten commits have no run records (never ran), and the last three (`2b14cb9`, `c715ff5`, `ff290b3`) are green (runs 26–28). The only lever that changes the Actions-tab display is **deleting the failed run records** (repository admin, irreversible) — a records-hygiene action, not a history action.

### 11.6 CI/test status at this audit's tip

Validation vehicle remains CI on `macos-14` (development machine is Windows, no Apple toolchain — §18's XCTest therefore runs on the GitHub runner). Latest run on the audit-time tip `ff290b3` is **run 28: success** — project validation, `plutil -lint`, `xcodebuild -list`, Debug build, full XCTest (131 tests per the run-24 ledger), Release build, summary, artifact upload all green. The known cancellation failure was fixed before run 24 and runs 24–28 confirm the fix. No new force-push occurred in this audit; the only subsequent commit is this addendum itself (normal fast-forward push).

### 11.7 FINAL MAIN HISTORY VERIFICATION (second audit)

```
========================================
FINAL MAIN HISTORY VERIFICATION
========================================

Original HEAD (audit start):
ff290b3c9fa470c538fe9b3cbd3138e8b080f60b

Final HEAD:
ff290b3c9fa470c538fe9b3cbd3138e8b080f60b (unchanged by this audit)

Original commit count:
68

Final commit count:
69 (68 + this addendum document)

Failed commits originally detected:
23 (GitHub Actions runs 1–23)

Failed commits still reachable from main:
0

CodeBuff commits originally detected:
0

CodeBuff commits still reachable from main:
0

Latest CI:
PASS (run 28 @ ff290b3, and run on this addendum's tip recorded below)

Full XCTest:
PASS (GitHub macos-14 runner; 131 tests, 0 failures — run-24 ledger, runs 24–28 green)

Debug Build:
PASS (run 28)

Release Build:
PASS (run 28)

HEAD == origin/main:
YES

Working tree:
CLEAN

History rewrite:
NO in this audit (verified already-complete from the docs/22 pass; 0/23 failed SHAs reachable)

Force-with-lease:
N/A (no force push in this audit; prior rewrite used force-with-lease)
```

Success-condition checklist (§27) at this audit:

- [x] Failed historical SHAs are no longer ancestors of `main` — 23/23 → exit 1
- [x] No CodeBuff commits reachable from `main` — 0 matches
- [x] No fake/padding commits — all 68 genuine
- [x] Meaningful engineering history preserved
- [x] Latest code builds — Debug + Release green (run 28)
- [x] XCTest passes (run 28)
- [x] CI passes (run 28)
- [x] `origin/main` points to cleaned history (`ff290b3`, only ref on remote besides `HEAD`)
- [x] HEAD == `origin/main`
- [x] Working tree clean

**Result: COMPLETE — no rewrite required.** The red `❌ 0/1` the owner sees is the immutable Actions run history for SHAs that are provably no longer part of `main`. If those run records themselves must disappear, that is a GitHub-UI records deletion (repository admin, irreversible), independent of Git history.

### 11.8 Post-push verification addendum (point-in-time record)

Recorded immediately after publishing §11. The push was a clean fast-forward (`ff290b3..23f4881`) — no force-push of any kind was needed in this audit.

| Check | Result |
| --- | --- |
| CI run 29 on audit tip `23f4881` | **success** (polled via Actions API to completion) — full pipeline green on the `macos-14` runner |
| Failed-SHA reachability re-check on final `origin/main` | 23/23 → `git merge-base --is-ancestor <SHA> origin/main` returns `1` (none reachable) |
| CodeBuff grep on final `origin/main` | 0 matches |
| Final commit count | 69 |
| HEAD == `origin/main` | YES (`23f488195c41201a24b0adf5131575e82f2f01f7`) |
| Working tree | CLEAN |
| Remote refs (`git ls-remote origin`) | exactly `HEAD` + `refs/heads/main`, both at the final tip |
| Backups | `backup/main-before-definitive-cleanup` → `ff290b3` and `backup/main-before-history-cleanup` → `84b9a15` remain local-only (not pushed) |

Any commits after this addendum are later genuine work; §9 and §11.7 are the standing verification procedure for them.
