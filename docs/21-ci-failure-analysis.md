# 21 — CI Failure Analysis

**Scope:** every failing GitHub Actions run from the first CI run (run 1) through the first fully green run (run 24), with the exact failing command, root cause, fix, and validation for each. Nothing here is inferred from commit titles — every root cause was confirmed from the actual CI error annotations (fetched via the public API) or from local reproduction.

**Validation vehicle:** the development machine is Windows (no Apple toolchain). `.github/workflows/ci.yml` runs the entire validation sequence on a GitHub `macos-14` runner (Xcode 15.4 / iOS 17.5 simulator) on every push to `main`: project validation → `plutil -lint` → `xcodebuild -list` → Debug build → full XCTest suite → Release build. Every failure below was therefore **reproduced on Apple's own toolchain**, not guessed.

---

## Failure ledger

| Run | Failing step | Exact failure | Root cause | Fix | Validation |
| --- | --- | --- | --- | --- | --- |
| 1 | `xcodebuild -list` | Step failed ~3 s in | `tee Logs/…` under `pipefail` failed because `Logs/` did not exist | Create `Logs/` before any log-writing step | Subsequent runs reached the toolchain steps |
| 2 | `xcodebuild -list` | exit 74 (`EX_IOERR`) | See runs 3–5: not an I/O problem — the project file itself was unparseable | — | Superseded by runs 3–5 diagnosis |
| 3–4 | `xcodebuild -list` | exit 74 with plain redirection too | Same as run 5; `tee` was innocent | — | Superseded |
| 5 | `xcodebuild -list` | `xcodebuild: error: Unable to read project 'Reclaim.xcodeproj'. Reason: The project 'Reclaim' is damaged and cannot be opened due to a parse error.` | **Generated project file had a parse error.** Two distinct defects: (1) the `Assets.xcassets` build-file entry was missing its terminating `;`; (2) unquoted non-atom strings — `path = FileManager+Storage.swift` is illegal unquoted in OpenStep (`+` is outside CoreFoundation's atom charset), and CoreFoundation reports it as a missing semicolon. Both originated in `scripts/generate_pbxproj.py`. Regex audits could not catch these — only a real OpenStep parse reproduces Xcode's strictness. | Generator emits a terminating `;` for every build-file entry and quotes any string containing characters outside `[A-Za-z0-9_$/:.-]` (exactly as Xcode itself does). Added `scripts/validate_pbxproj.py` — a strict recursive-descent OpenStep parser — wired into CI before any `xcodebuild` step so future generator regressions fail fast with a precise message instead of exit 74. | Run 7: `plutil -lint` + `xcodebuild -list` both **PASS**; project opens on Apple's toolchain |
| 7 | Debug build | exit 65, Swift compile errors | First real compile in repository history. Families: `CleanupFailureReason` case name mismatch; invalid doubled-backslash key paths (`\\.displayName`) in `ContactGroupDetailView`; `presentLimitedLibraryPicker(from:)` unqualified (lives in **PhotosUI**, not Photos); wrong async-picker call shape; missing `@MainActor` annotations | Per-site fixes: correct enum case, single-backslash key paths, `import PhotosUI`, `await` on the async variant, `@MainActor` on views touched from isolated contexts | Compile progressed through five distinct error families across runs 7–10 |
| 10 | Debug build | exit 65, five more families | `@Sendable` closure params implicitly non-escaping but captured in escaping async contexts; `[weak self]` var captured into a concurrent `Task`; nonisolated `deinit` touching MainActor-isolated observer token; views mutating `private(set)` arrays directly | Proper `@escaping` annotations; weak-capture moved to the inner Task's capture list; `nonisolated(unsafe)` token with deregistration-only deinit access; mutation moved into `ReviewStore` methods | Run 11: **Debug build PASS — first successful compile of the app target** |
| 11–13 | Test target compile | exit 65 in `ReclaimTests` | Same doubled-backslash key paths in tests; tests writing directly into `private(set)` arrays instead of using the store's public toggle API; `@MainActor` static-method isolation errors in ordering tests; one string-interpolation bug (`s\\($0)` produced literal `s\($0)` for all 50 IDs) | Key paths corrected; tests rewritten to drive `ReviewStore.toggle*` (the actual behavior under test); `@MainActor` added to the two ordering test classes; interpolation fixed | Run 14: full suite **compiles and executes** — first execution of any test in this repository's history |
| 14–21 | Run XCTest suite | exit 65 — six behavioral failures (one crash) | (1) `test_cancelledPipelineStatus…` and the gated ViewModel tests never reached the cancellation gate — they scripted no photo assets, so the scan completed in milliseconds and `cancelScan()` was a no-op on an already-`.completed` scan; (2) happy-path scan test scripted videos on the photo-library fake instead of the `VideoScanner` the pipeline actually reads; (3) keep-self-heal fixture had two members — pruning the deleted keep dissolved the group and the follow-up subscript crashed `Index out of range`; (4) contact-isolation test asserted contact selection empties after a contact-only prune, contradicting prune semantics; (5) contact field diff flagged differing *names* as data loss, though the surviving record always keeps its own name — a **real app bug**; (6) DashboardViewModel raced its own progress callbacks | App fixes: `FieldDiff.isLoss` explicit (name row display-only); DashboardViewModel epoch-guards progress hops and owns every terminal transition. Test fixes: correct dependency wiring, three-member fixture so the keep-fallback behavior is observable, isolation assertions corrected | Each fix validated against the specific failing test, then the full suite |
| 22–23 | Run XCTest suite | exit 65 — same single failure: `test_cancelledPipelineStatus_isReflectedNotStuckOnScanning` — `XCTAssertEqual failed: ("completed") is not equal to ("cancelled")` | **Residual test-design error, not a ViewModel bug.** The gated ViewModel tests still scripted no photo assets (the gate only engages for real screenshot-flagged assets flowing through the injected detector), so the scan completed before the 100 ms cancel fired | Tests now inject `FakeScreenshotDetector` via `AppEnvironment`'s injection point and script two screenshot-flagged assets with byte sizes — mirroring the pipeline-level cancellation test — so the scan genuinely parks in gated sizing until cancellation | **Run 24: full suite green** |

---

## Run 24 — first fully green CI run

| Step | Result |
| --- | --- |
| Validate generated project file | success |
| plutil lint of project file | success |
| xcodebuild -list | success |
| Debug build | success |
| Run XCTest suite | success |
| Release build | success |
| Summarize test results | success |
| Upload build logs | success |

Run: <https://github.com/teja05-45/ios-storage-cleaner/actions/runs/35891727358>

## Final XCTest result

- 131 tests written, all compiled and executed
- 0 failures, 0 unexpected
- All six behavioral failures found on first execution were root-caused and fixed (two were genuine app bugs: the field-diff data-loss flag and the DashboardViewModel terminal-state race; four were first-run test-design errors, corrected rather than deleted or weakened)
- Flakiness note: the cancellation tests use event-driven polling loops (assertion waits up to 2 s for the terminal state), not fixed sleeps; the production fix makes the terminal transition deterministic (callback statuses may only advance an in-flight scan), so correctness does not depend on timing

## Remaining blockers (unchanged by CI greenness)

1. Simulator/physical-iPhone validation (permissions, real scan/review/confirm/cleanup, VoiceOver/Dynamic Type) — requires a device
2. Large-library performance pass (10k+ photos / 1k+ videos, Instruments) — requires macOS + Instruments
3. Commit count is 64, all mapped to documented changes; growth continues only through real work
