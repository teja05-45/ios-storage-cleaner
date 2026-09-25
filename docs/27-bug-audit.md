# 27 — Bug Audit

**Date:** 2026-09-25. Every bug below was reproduced, root-caused, fixed, and covered by a regression test that failed before the fix and passes after. The prior 23 CI runs' failure ledger lives in `docs/21-ci-failure-analysis.md` (project-file grammar, first-compile fixes, first-execution test corrections, the cancellation test-design error) and is not duplicated here; this document covers the current full-audit pass (`docs/24`).

---

## BUG-01 — Duplicate/similar group members reported 0 bytes

```
Bug:            Exact-duplicate and similar-photo groups carried members with
                the enumeration-time byteSize placeholder (0). Real sizes were
                resolved during duplicate bucketing and similarity scoring but
                discarded instead of folded back into the group's members.
Severity:       MEDIUM (user-visible misinformation; no data-loss or safety impact —
                deletion correctness and confirmation flows were unaffected)
Root Cause:     PhotoAsset is a value type. DuplicateDetector.fetchPhotoAssets
                emits assets with byteSize: 0 (deliberately, per Document 09 §3 —
                the fast enumeration pass must not pay for per-asset resource
                reads). DuplicateDetector resolved real sizes into the
                sizeBuckets dictionary and SimilarityDetector into
                BestPhotoScoring.RawSignals — but both built PhotoGroup.members
                from the ORIGINAL asset values. PhotoAsset.withByteSize(_:)
                existed for exactly this purpose and was used by the
                screenshots/videos paths, but not by the two detectors.
Reproduction:   Scan any library with a byte-identical duplicate (or a similar
                pair) → the group row, the Dashboard "could be recovered"
                figure, and the Review total all report "0 bytes" for those
                categories, regardless of the items' true sizes.
Fix:            DuplicateDetector keeps a resolvedSizes map and folds sizes into
                members via withByteSize before constructing each PhotoGroup;
                SimilarityDetector builds sizesByID from the scoring signals and
                does the same in processBucket. No thresholds, ordering, or
                grouping behavior changed.
Regression Test: DetectionPipelineTests.test_exactDuplicateGroup_membersCarryRealByteSizes_notZero
                (asserts per-member sizes AND group.recoverableBytes == the
                scripted real size);
                DetectionPipelineTests.test_similarGroup_membersCarryRealByteSizes_notZero
                (drives the real SimilarityDetector via scripted deterministic
                thumbnails; asserts both members carry their resolved sizes).
Status:         FIXED (pending CI green on the fix commit)
```

## BUG-02 — Security scanner allow-list failed on Windows paths

```
Bug:            scripts/security_scan.py allow-listed the Info.plist DOCTYPE
                false positive using a forward-slash relative path, but
                os.path.relpath on Windows produces backslashes — the allowed
                entry never matched, so the scanner failed on its own repo.
Severity:       LOW (tooling-only; no app impact; caught immediately by the
                scanner's first local run — which is what it is for)
Root Cause:     Platform-dependent path separators in the ALLOWED table keys.
Reproduction:   python scripts/security_scan.py on Windows →
                "SECURITY SCAN FAILED: [NETWORK_HTTP_URL] Reclaim\Resources\Info.plist:2".
Fix:            Normalize to forward slashes at finding time; allow-list keys
                are canonical forward-slash paths on every OS.
Regression Test: The scan passing locally on Windows and in CI (macOS) on every
                push — both platforms exercise the normalization path.
Status:         FIXED
```

## BUG-03 — Security scanner flagged its own rule table

```
Bug:            The scanner's NETWORK_LIBRARY and CLOUD_SERVICE patterns matched
                their own literal definitions inside security_scan.py, producing
                two self-referential findings.
Severity:       LOW (tooling-only)
Root Cause:     The scanner's source was inside its own scan scope — the rule
                table necessarily contains the literals the rules match.
Reproduction:   First execution of the new scanner (this audit).
Fix:            Explicit self-exclusion of the scanner's own file, documented
                in the file header.
Regression Test: Scan passes in CI on every push.
Status:         FIXED
```

## BUG-04 — Project generator emitted two PBXBuildFile entries on one line

```
Bug:            When the new ReclaimUITests target was added to the generator,
                the template joined the unit-test and UI-test build-file
                blocks without a separating newline, concatenating the last
                unit-test entry and the first UI-test entry onto one physical
                line.
Severity:       LOW (caught before commit by diff inspection; OpenStep's
                whitespace-insensitive parser would have accepted it, but
                shipping a malformed-by-convention project file contradicts
                the generator's formatting contract)
Root Cause:     Missing \n between two adjacent f-string interpolations in the
                PBXBuildFile section template.
Reproduction:   python scripts/generate_pbxproj.py with a UI-test target present;
                grep for two "in Sources */ = {isa = PBXBuildFile" on one line.
Fix:            Separator added to the template; generator output re-validated
                with scripts/validate_pbxproj.py (212 objects, all references
                resolve) and the determinism check (regenerate → byte-identical).
Regression Test: validate_pbxproj.py + the regenerate-and-diff provenance check
                in CI and README.
Status:         FIXED
```

## BUG-05 — UI-test target's `dependencies` referenced a PBXBuildFile instead of a PBXTargetDependency

```
Bug:            The generator's ReclaimUITests target listed
                uuid_for("dependency:uitest-on-app") — a PBXBuildFile object —
                in its `dependencies` array. Xcode's project loader requires
                PBXTargetDependency objects there and rejected the whole
                project at `xcodebuild -list` (CI run 32, job validate).
Severity:       HIGH (CI-blocking; no project could load) — introduced and
                fixed within this audit; never present in a released state
Root Cause:     Two parallel UUID namespaces in the generator ("dependency:*"
                for the unit-test target's PBXBuildFile app link vs
                "targetdep:*" for PBXTargetDependency objects). The new
                target referenced the wrong namespace; scripts/
                validate_pbxproj.py verified reference EXISTENCE but not
                the isa CLASS of referenced objects — the same class of
                blind spot as docs/21 run 5 (regex audits can't see what a
                real parser, or a real loader, enforces).
Reproduction:   CI run 32 step `xcodebuild -list` failed after the
                ReclaimUITests project changes; local reproduction is the
                same file on any Xcode.
Fix:            The UI-test target now references
                uuid_for("targetdep:uitest-on-app") (the PBXTargetDependency);
                the erroneous "Reclaim.app in Frameworks" PBXBuildFile for
                the UI target was removed (a UI-test bundle links the app
                via TEST_TARGET_NAME + the target dependency, not a
                Frameworks build file — that's the unit-test target's
                mechanism). Regenerated project: 211 objects, validates.
Regression Test: validate_pbxproj.py gained isa-class semantic checks —
                PBXNativeTarget.dependencies must reference
                PBXTargetDependency; PBXTargetDependency.targetProxy must be
                a PBXContainerItemProxy; PBXBuildFile.fileRef must be a
                PBXFileReference. Negative test executed: re-introducing the
                exact defect makes the validator exit 1 with a message
                naming the object; the check is now a permanent CI step.
Status:         FIXED (validator + generator; verified by negative test)
```

## Verified non-bugs (audited, correct as written)

These were specifically hunted during `docs/24` and confirmed NOT to be bugs — recorded so future audits don't re-litigate them:

1. **Cancellation terminal state** (`test_cancelledPipelineStatus…`): the run 22–23 era failure was a test-design error, already root-caused and fixed before run 24; the production epoch-guard/terminal-transition design is correct (docs/21).
2. **`performChanges` throw-on-decline**: returning zero confirmations on the native dialog's decline is the documented honest-failure contract, pinned by SafetyTests — not swallowed success.
3. **Contacts have no `.limited` case**: `CNAuthorizationStatus` genuinely lacks one in the SDK this project builds against; the mapping comment documents this rather than inventing a state.
4. **Continuation resume-once guards** on both `PHImageManager` request paths: multi-callback delivery is handled on both the fast-format (first callback) and opportunistic (final non-degraded callback) variants.
5. **Stale-asset handling**: revalidation drops vanished IDs and reports them; `ReviewStore.prunedGroup` keeps survivor state (selection, user keep) — pinned by `ReviewStorePruningTests`.

## Bug totals for this audit

| Severity | Found | Fixed | Remaining |
| --- | --- | --- | --- |
| CRITICAL | 0 | 0 | 0 |
| HIGH | 0 | 0 | 0 |
| HIGH | 1 (BUG-05, introduced + fixed within this audit, never in a released state) | 1 | 0 |
| MEDIUM | 1 (BUG-01) | 1 | 0 |
| LOW | 3 (BUG-02, BUG-03, BUG-04) | 3 | 0 |

**Remaining known bugs: 0.** The open items in this repository are validation gaps that require a physical device (docs/24 §13, docs/25 ledger) — not bugs.
