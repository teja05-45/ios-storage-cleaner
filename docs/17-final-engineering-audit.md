# 17 — Final Engineering Audit

**Audit date:** 2026-09-23 (continuation pass following `docs/16-audit-report.md`)
**Auditor environment:** Windows 11 (Git Bash), Python 3.11.9. **No macOS, no Xcode, no Swift toolchain, no iOS Simulator, no physical iPhone, no Docker execution.**
**Audit method:** full repository re-inspection, static sweeps (network, secrets, debug patterns, deletion call sites, force unwraps), generator/provenance re-verification by execution, and a line-by-line review of every change made in this pass. Nothing is claimed "passing" unless it was executed here.

---

## Executive Summary

The previous audit (`docs/16`) left one dominant open item: **ISSUE-09 — no UI mutated selection, so the product's core loop (scan → select → review → confirm → clean → result) was unreachable for a user.** This pass closed it. All four category selection surfaces now exist and write through `ReviewStore`: photo group list + detail with keep override, screenshots grid, large-videos list with playback preview, and duplicate contacts with a per-field would-be-lost preview. The Review screen was upgraded from count-only rows to individually inspectable, removable items. The Dashboard's category cards navigate into all of it.

Two more audit items closed (**OPEN-1**, and the static half of **OPEN-4**), plus one build-config defect that predated both audits (a set `ASSETCATALOG_COMPILER_APPICON_NAME` build setting with **no asset catalog in the project at all**) — fixed by adding the catalog and teaching the generator to place it in the Resources copy phase.

The unchanged headline, stated as plainly as before: **this project still has never been compiled.** The environment has no Xcode. What changed is scope: the remaining risk is now ordinary first-build Swift compilation, not missing product functionality.

---

## What This Pass Changed

| # | Change | Closes | Commit |
|---|---|---|---|
| 1 | Landed `docs/16-audit-report.md`, README runbook, `.gitignore` additions, AppEnvironment note | pending audit artifacts | `193f4e8`, `05b5718`, `607d7bd`, `0362d4d` |
| 2 | Asset catalog + generator Resources-phase support (app icon/accent color now actually ship) | new build-config defect | `d811a1c` |
| 3 | `requestDisplayImage` protocol method + live impl + fake; `AssetThumbnailView` shared component; SwiftUI environment exposure of the composition root | enabler for ISSUE-09 | `339d459` |
| 4 | `MediaFormatting` (duration/resolution/date) + 8 unit tests | enabler | `8aa5a21` |
| 5 | Photo group list + detail, keep override, bulk actions | ISSUE-09 (photos) | `63d8517` |
| 6 | Screenshots grid, select all/deselect all, live total, newest-first ordering | ISSUE-09 (screenshots) | `4b137d2` |
| 7 | Large-videos list, sort options + tests, on-demand `AVPlayer` preview | ISSUE-09 (videos) | `78d7fdf` |
| 8 | Contacts tier list + field-diff preview detail + 5 unit tests | ISSUE-09 (contacts) | `b90f164` |
| 9 | Dashboard cards → NavigationLinks into all category screens | ISSUE-09 (wiring) | `34013f1` |
| 10 | Review screen: per-item inspectable/removeable sections | ISSUE-09 UX / Doc 02 §4.8 | `406bc48` |
| 11 | Explicit accessibility labels/hints on scan + destructive confirm controls | OPEN-4 (static part) | `38c3923` |
| 12 | `ComputeStorageSummaryUseCase` moved to its own file | OPEN-1 | `f446023` |
| 13 | Test-coverage pass: `ReviewStore` aggregation, `DuplicateDetector` bucketing (+ hash-boundedness), screenshot ordering (+ 3 new suites, fake extended) | Doc-16 coverage gaps | `539efd3` |
| 14 | Code-quality cleanup of two awkward patterns in the new screens | self-review | `0612310` |

---

## Architecture Audit

- **Dependency direction unchanged and preserved in all new code:** Features → UseCases → Services → Core. The new screens import SwiftUI + the models; the only new service surface (`requestDisplayImage`, `playerItem`) lives on the existing protocols, so nothing above Services gained a framework import. `AVKit` crosses the protocol boundary deliberately (Services own AVFoundation per Document 04 §2).
- **New composition-root exposure:** leaf components reach `AppEnvironment` via a SwiftUI environment value (`UI/Components/AppEnvironmentKey.swift`) with a `nil` default — a missing root is a visible programming error, not a silently-global fallback. ViewModels still receive the environment explicitly; the environment value serves stateless leaf views (thumbnail cells) that would otherwise require threading it through every level.
- **Selection still has exactly one source of truth.** Every new screen reads and writes through `ReviewStore`; no new `Set<String>` selection state exists anywhere in `Features/`. Two group-level bulk mutations (`selectAllExceptKeep` / `deselectAll` in the photo detail) mutate the store's own arrays in place via index lookup — still funneled through `PhotoGroup`'s guarded mutating methods.
- **The keep-invariant held without new guards.** The UI never needs to defend "the keep cannot be selected" — `PhotoGroup.toggleSelection` refuses it structurally, and the detail screen simply renders no Select button for the keep. The invariant tests in `GroupSelectionInvariantTests` cover the model; the UI cannot bypass it.
- **File placement:** `ComputeStorageSummaryUseCase` now lives in its own file (OPEN-1 closed). No other misplacements were introduced.

## Swift / Concurrency Audit (new code)

- **Continuation safety hardened, not just used.** Both new PhotoKit bridges guard against double-resume: the hashing thumbnail path resumes on the *first* callback, the display path on the *final non-degraded* callback (`PHImageResultIsDegradedKey`), since opportunistic delivery can call back multiple times. This fixes a latent crash class that existed in the pre-existing `requestThumbnail` (single-resume assumption against a multi-callback API).
- **`@MainActor` correctness:** `requestDisplayImage` is `@MainActor` on the protocol (UI images belong there); the fake conforms. `ReviewStore` remains `@MainActor`; the new aggregation tests are `@MainActor` test classes. No new `Task.detached`, no unbounded concurrency — thumbnails fetch per visible cell via `.task(id:)`, bounded by the grid's visible area and `NSCache`'s 500-entry limit.
- **No force unwraps, no `try!`, no `as!` added.** Sweep result: clean (see Verification Log).
- **Recycling guard:** `AssetThumbnailView` re-checks `assetID` after its `await` before adopting a fetched image — grid cells are recycled aggressively while scrolling, and a stale adoption would show the wrong photo.

## PhotoKit Audit (new surface)

- **Display thumbnails** request at cell-size × display scale, `isNetworkAccessAllowed = false` preserved (on-device only, also the privacy stance). Never full-resolution outside the explicit full-screen preview.
- **Video preview** materializes `AVPlayerItem` only when the user actually opens a preview — the scan and list passes instantiate no `AVAsset`/player objects (Document 09 §2), preserved from the original design and now actually reachable.
- **Deletion call sites unchanged: exactly two** (`PhotoLibraryServiceLive.deleteAssets`, `ContactServiceLive.deleteContacts` via `CNSaveRequest`), verified by grep this pass. All new UI funnels into `PerformCleanupUseCase` through `ReviewViewModel.confirmCleanup()` — the only ViewModel call site, unchanged.

## Contacts Audit (new surface)

- Field-diff preview fetches display fields **live** per member (`fetchDisplayFields`) — never cached, per Document 05 §5 — and degrades honestly: a fetch failure renders a visible "comparison may be incomplete" notice instead of a silently-empty diff.
- The diff computation is extracted as a pure static function and unit-tested, including the two loss cases (unique field on the to-be-deleted record; differing values on both sides) and the non-loss case (shared fields).
- Contact photos remain deliberately unfetched (minimal key set, Document 07 §5); avatars are initials.

## UX Audit (new screens)

- All four category screens implement selection-only interactions; none offers any destructive action. The only destructive path in the app remains Review → confirmationDialog → "Delete Forever" → `PerformCleanupUseCase`.
- Honest states everywhere: `ContentUnavailableView` empty states per category; disabled (not hidden) Dashboard cards for empty categories; a stale-group empty state if a group vanishes post-cleanup; visible load-failure notice on the contacts diff.
- Wording constraints held: "Suggested to keep" / "Your chosen keep" (never "best"), "similarity is an algorithmic suggestion" footer, contacts labeled "Certain match" / "Likely match" per the Exact/Probable tier contract.
- Review now satisfies Document 02 §4.8's "individually inspectable" requirement: thumbnails, byte sizes, dates, match reasons, per-item remove with live total updates.

## Testing Audit

| Suite | Before this pass | After | Executed? |
|---|---|---|---|
| CoreTests | 55 | 71 (3 new suites) | **NO — no Xcode in this environment** |
| SafetyTests | 18 | 18 | **NO** |
| Total | 73 | **89** | **0 executed — environment** |

The three new suites close the exact gaps Doc-16 documented (recoverable-bytes aggregation, DuplicateDetector bucketing) plus screenshot ordering. The fake `PhotoLibraryService` gained scriptable byte-size/hash fixtures and a hash-call counter, which is what makes the detector's "no hash without candidate partners" performance contract assertable. **No test in this repository has ever been run by anyone.** That remains the single largest verification gap, unchanged by this pass.

## Static Audit Results (executed this pass)

- Network sweep across `Reclaim/`: **zero hits** (the only matches are the Info.plist privacy strings saying "Nothing is uploaded").
- Secrets sweep: **zero hits** ("token" matches are name-tokenization code; "password"/"secret"/key material: none).
- `print(` / `fatalError` / TODO/FIXME/XXX in app code: **zero**.
- `try!` / `as!`: **zero**.
- Info.plist: parses cleanly (`plistlib`).
- Generator: fail-loud contract re-verified by execution in an empty directory (exit 1, no stray project written).
- Provenance: regenerated pbxproj is byte-identical across consecutive runs (53 app + 16 test files).

## Git Audit

- History grew from 6 commits (2 substantive) to **23 commits** at this audit's close. Every commit in this pass maps to exactly one row in the table above; no empty, whitespace, formatting-only, or count-padding commits were created. Commit bodies state the *why* and cite the governing spec/audit item.
- Working tree clean at audit close; branch `main`; no secrets or generated artifacts committed (`__pycache__` is ignored).

---

## Remaining Issues (honest list)

1. **Never compiled; 89 tests never executed.** Unchanged, environment-blocked. First action for anyone with a Mac: open in Xcode 15.2+, build, run `⌘U`. Treat first-build errors as normal work, not a design failure.
2. **Real-device validation matrix still not run** (permission prompts, limited-library picker, native delete dialog, 10k+ performance/Instruments, VoiceOver/Dynamic Type behavior). The static accessibility half of OPEN-4 is done; behavioral verification requires a device.
3. **OPEN-3 unchanged:** post-cleanup pruning removes all requested IDs rather than only OS-confirmed-deleted IDs (`CleanupSummary` carries counts, not IDs). Harmless — the next cleanup revalidates — and documented.
4. **Merge-preview only for contacts** (ADR-02, deliberate): a user must manually copy a unique field from the doomed record before deleting it; the field-diff preview shows exactly what that is.
5. **App icon artwork intentionally absent** — the catalog ships a single-size placeholder manifest with no PNG (non-fatal build warning). Fabricating artwork was judged worse than shipping the warning.

## Verification Log (commands executed in this audit)

```
python -m py_compile scripts/generate_pbxproj.py        # generator syntax after edits: PASS
python scripts/generate_pbxproj.py && diff run1 run2    # determinism: byte-identical (53+16 files)
cp script to empty dir && run                           # fail-loud: exit 1, no stray project
python -c "plistlib.load(...)"                          # Info.plist parses
grep -rniE "URLSession|Alamofire|Firebase|dataTask|upload|Analytics" Reclaim/   # 2 hits, both plist privacy strings
grep -rniE "api_key|secret|password|private key|token|\.p12|\.mobileprovision"  # only name-tokenization code
grep -rn "print(\|fatalError\|TODO\|FIXME\|XXX" Reclaim/ ReclaimTests/          # zero
grep -rn "try!\|as!" Reclaim/                           # zero
grep -rn "deleteAssets|saveRequest.delete|store.execute" Reclaim/               # exactly 2 real delete call sites
grep -rc "func test_" ReclaimTests/                     # 89 test methods
git rev-list --count HEAD                               # 23 (this audit's close)
```

## Final Readiness Assessment

**Not production ready — same reason as before, narrower scope now.** The product loop is now *complete as code* end to end with the safety architecture intact; the gap between "written" and "verified" is exactly: one Xcode build, one test run, one device pass. Recommended order: (1) build + fix compile errors; (2) run the 89 tests — SafetyTests first; (3) simulator pass over the permission matrix; (4) real-device pass per the README runbook.
