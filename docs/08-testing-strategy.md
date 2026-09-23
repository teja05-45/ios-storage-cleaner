# 08 — Testing Strategy

Testing philosophy: because this app performs irreversible-feeling destructive actions on a user's real personal data, the safety test suite (§4) is treated as the non-negotiable core; correctness of detection algorithms (§1) is second; everything else supports both.

## 1. Unit Tests

All target `Core/Utilities` and pure logic in `Services`/`UseCases` — no PhotoKit/Contacts entitlement or simulator photo library required, since these are protocol/fake-backed (Document 03 §4, §7).

**Duplicate detection**
- Two assets with identical (dimensions, size, SHA-256) → classified exact duplicate.
- Two assets with identical dimensions/size but different content → not classified exact (falls to similarity pipeline).
- Asset with a unique (dimensions, size) triple in the library → correctly skipped from further comparison (bucketing correctness).

**Perceptual hash comparison**
- Identical image → Hamming distance 0 against itself.
- Known near-duplicate pair (same scene, minor exposure shift, fixture images) → distance within threshold (≤5).
- Known dissimilar pair (unrelated fixture images) → distance clearly above threshold.
- Hash function is deterministic: same input image byte-for-byte → same hash across repeated runs.

**Similarity thresholds & clustering**
- Union-find clustering correctly merges a transitive chain (A~B~C via pairwise distances) into one group even where A vs. C alone would exceed the threshold.
- A bucket with no pairs under threshold produces zero groups (no false grouping).
- Confidence score formula produces expected value for known fixture distances.

**Storage calculations**
- `StorageSummary.recoverableBytes` equals the sum of `byteSize` for exactly the currently-selected asset IDs, across category boundaries — verified with a fixture selection spanning photos + screenshots + videos.
- `ByteFormatting` produces expected human-readable strings at boundary values (0 bytes, 999 bytes, 1 KB, 1 MB, 1 GB edge cases).

**Contact normalization**
- Phone: `+91 98765 43210` and `9876543210` normalize to matching comparison keys; two different national numbers with the same last-10-digit suffix but both carrying explicit differing country codes do **not** match (precision-over-recall case from Document 06).
- Email: case and whitespace normalization produce matching keys for `Example@Email.com` / `example@email.com`; `+tag` stripping is verified both with the feature on and confirmed off-by-default.
- Name similarity: Levenshtein-based score matches expected values for known fixture name pairs, including reordered "Last, First" vs "First Last" cases.

**Contact duplicate detection**
- Phone/email match + name similarity ≥ 0.9 → classified Exact.
- Phone/email match without strong name match → classified Probable.
- Name-similarity-only match with zero overlapping fields → **not** surfaced at any tier (false-positive guard, Document 06 §6 — this is one of the most important unit tests in the suite).
- Oversized normalized bucket (>8 contacts sharing one signal) → demoted out of Exact tier regardless of other criteria.

**Selection logic**
- `PhotoGroup.effectiveKeepID` is never present in `selection` (invariant test — attempt to select the keep photo either fails or automatically clears the keep flag, per the chosen implementation, but never results in both states being true simultaneously).
- Toggling a group's "select all except keep" correctly excludes exactly one asset (the effective keep) regardless of override state.

**Cleanup calculations**
- `CleanupSelection.totalItemCount` equals the sum of all four category ID sets' counts, with no double counting across categories.
- `CleanupSelection.isEmpty` is true iff all four sets are empty.

## 2. Integration Tests

Exercise real (or lightly faked-at-the-boundary) framework interaction, run on simulator/device with a seeded photo library and seeded contacts (via a dedicated test scheme with a disposable simulator content set — never against a developer's real personal library).

- **PhotoLibraryService:** authorization status transitions are correctly read and mapped to the app's `ScanStatus`/permission states; asset fetch returns expected counts against a known seeded library; thumbnail request returns non-nil images for valid asset IDs and fails gracefully for invalid ones.
- **ContactsService:** authorization flow; fetch returns expected seeded contact set with the minimal key-fetch set (Document 03 §2) and no unrequested fields.
- **Scanning pipeline (end-to-end against seeded library):** a seeded library containing (a) a known exact-duplicate pair, (b) a known burst of 4 near-duplicates, (c) known unrelated singles, (d) known screenshots, (e) known large videos → produces the expected `ScanResult` shape (correct group counts, correct screenshot flagging, correct video sort order) — this is the single most valuable integration test since it validates the whole pipeline's real-world behavior, not just isolated units.
- **CleanupService:** requesting deletion of a seeded, disposable test asset set results in those (and only those) assets being removed from the seeded library; assets outside the selection remain untouched — run against disposable seeded/test content only, never real user data, and only in a test target/scheme, never in the shipped app.

## 3. UI Tests

Automated `XCUITest` flow covering the full core loop end-to-end on simulator with a seeded photo library:

```
Launch
 → Dashboard renders (storage ring visible, "Scan Now" present)
 → Tap Scan Now → Permission prompt handled (simulator auto-grant via test configuration)
 → Scan progress UI appears and completes
 → Navigate to Similar Photos → group visible → select a non-keep item
 → Navigate to Screenshots → Select All
 → Navigate to Large Videos → open preview → dismiss → select one video
 → Navigate to Review → verify displayed counts match selections made above
 → Tap Confirm & Clean Up → confirm native system dialog
 → Cleanup Result screen shows non-zero freed storage and correct counts
 → Return to Dashboard → verify counts/state reflect the completed cleanup
```

Additional UI test branches:
- Cancel at Review → verify no navigation to Cleanup Result, selections preserved.
- Deny permission at prompt → verify Dashboard and unaffected categories remain usable, denied category shows correct empty/permission state, no crash.

## 4. Safety Tests (highest priority in the suite)

These are written as explicit, named tests because each one maps directly to a stated product principle (Document 01, "Trust Before Cleanup") and a regression here is the worst possible outcome for this product.

| Test | Assertion |
|---|---|
| `test_deletionRequiresExplicitConfirmation` | `PerformCleanupUseCase.execute` cannot be invoked from any code path except the Review screen's confirm action; verified structurally (no other call site exists) and behaviorally (a `CleanupSelection` is never constructed and executed anywhere except the reviewed/confirmed flow) |
| `test_cancelledConfirmationPerformsNoDeletion` | Cancelling the Review screen, and separately, declining the native iOS delete confirmation, results in zero calls reaching `PhotoLibraryService.delete`/`ContactService.delete`, and the pre-cancel `StorageSummary` is unchanged |
| `test_deselectedAssetsAreNeverDeleted` | Given a group of 5 with 2 selected, executing cleanup results in exactly those 2 being deleted and the other 3 verifiably still present via a post-cleanup fetch |
| `test_selectionCountMatchesDeletionCount` | `CleanupSummary.deleted*Count` values, summed, equal `CleanupSelection.totalItemCount` in the success path; any deviation must appear in `CleanupSummary.failures`, never silently dropped |
| `test_displayedFreedStorageMatchesSelectedResources` | The recoverable-bytes figure shown at Review time, for a given selection, equals the sum of `byteSize` for exactly those selected assets — independently recomputed in the test rather than trusting the same code path that produced the UI value |
| `test_deniedPermissionsDoNotCrash` | Launching the app, and separately, revoking permission mid-session and foregrounding again, never throws an uncaught exception; all affected screens render a permission-state view instead |
| `test_emptySelectionCannotBeConfirmed` | `CleanupSelection.isEmpty == true` → `PerformCleanupUseCase.execute` throws `ReclaimError.emptySelection` and no framework delete call is attempted; UI-level "Confirm" button is also disabled in this state, tested independently at both layers since either alone could regress |
| `test_keepPhotoNeverAutoSelected` | For every generated `PhotoGroup` fixture, `effectiveKeepID` is never a member of the default "select group" selection set |

## 5. Manual / Real-Device Test Matrix

Run once automated suites pass, on a physical iPhone (Document 10, Phase 15):

- Real photo library containing genuine duplicates, similar bursts, screenshots, large videos, and a contacts list with genuine duplicates.
- Permission states: fresh install (not determined) → grant full → later switch to Limited in Settings → later Deny → re-launch each time and verify correct behavior.
- Empty states: a secondary test device/account with an near-empty photo library and contacts list, to verify empty-state copy (not just the happy path).
- Large-library performance pass (Document 09) with scan duration, memory, and UI responsiveness recorded via Instruments.

## 6. What Is Out of Scope for Testing

- No load/performance testing beyond the single realistic large-library pass described in Document 09 — this is not a backend service.
- No penetration/security testing beyond the architectural guarantee that no network calls exist (verifiable via Instruments' Network instrument showing zero traffic during a full scan+cleanup session — this is itself treated as a test to run and record, not just an assumption).
