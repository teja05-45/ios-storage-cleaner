# 22 — Git History Cleanup

**Date:** 2026-09-23
**Scope:** remove CodeBuff attribution from the final `main` history and ensure no failed-CI historical SHAs remain reachable from `main`, while preserving every genuine engineering commit, its authorship, dates, diffs, and the 65-commit structure. Executed only after the repository owner explicitly requested the history cleanup.

---

## Audit before rewriting

| Item | Value |
| --- | --- |
| Original commit count | 65 |
| Merge commits | 0 (fully linear) |
| Author identities | exactly one: `teja05-45 <tejamatta05@gmail.com>` |
| Committer identities | exactly one: `teja05-45 <tejamatta05@gmail.com>` |
| Commits with CodeBuff attribution | 26 — footer lines only, in commit message bodies |
| CodeBuff footer patterns | `Co-Authored-By: Codebuff <noreply@codebuff.com>` (26), `Generated with Codebuff 🤖` (21), `🤖 Generated with Codebuff` (5) |
| CodeBuff as author/committer | **0** — attribution was never in the identity fields |
| Failed-CI commits | 23 GitHub Actions runs failed across runs 1–23 (full ledger: `docs/21-ci-failure-analysis.md`); every one of those commits is a genuine engineering increment |

## Classification (§8)

- **KEEP / REPLAY:** all 65 commits. Every commit is real engineering work — none was padding, none was dropped. "Replay" here took the form of a message-only rewrite: each commit's diff, author, author date, and position in the linear chain are unchanged; only the CodeBuff footer lines were removed from 26 messages.
- **DROP:** none.
- **MERGE:** none.

## Method

```
git branch backup/main-before-history-cleanup main   # recovery reference, kept local
git filter-branch --msg-filter <footer-stripper> -- main
```

The filter strips exactly the three footer-line patterns (byte-safe, UTF-8 preserved). A first attempt corrupted non-ASCII characters in 32 messages (Windows text-mode encoding); it was detected by a byte-level comparison of every rewritten message against the backup, `main` was reset to the backup, and the rewrite was redone with a binary-safe filter.

## Verification performed

| Check | Result |
| --- | --- |
| Commit count after rewrite | 65 (unchanged) |
| CodeBuff matches in messages | 0 (`git log main --format=%B \| grep -ci codebuff` → 0) |
| Message content vs backup | 65/65 commit pairs identical after excluding the stripped footer lines (byte-level comparison) |
| Non-ASCII integrity | old 231 non-ASCII bytes → new 127; delta = exactly the 104 bytes of 🤖 emojis inside the removed footers |
| Authors / committers | single identity `teja05-45` on all 65 |
| Dates + subjects | byte-identical to backup |
| Source tree | `git diff main backup/...` → empty (identical tree) |
| Secrets sweep | none found (prior sweeps re-verified; no tree change) |

## Push and final state

- Published with `git push --force-with-lease origin main` (never raw `--force`), after `git fetch origin` confirmed the remote had not moved.
- The backup branch `backup/main-before-history-cleanup` preserves the original SHAs locally and is intentionally **not** pushed.
- Old commit SHAs (including the 23 failing-CI ones) are no longer reachable from `origin/main`. GitHub's UI may still serve cached old commit URLs for a time — reachability is judged with `git log origin/main`, per §22.
- **History rewritten: YES · Force-with-lease used: YES · Final commit count: 66** (this document). CodeBuff commits remaining on main: **0**. Failed-CI commits reachable from main: **0**.
