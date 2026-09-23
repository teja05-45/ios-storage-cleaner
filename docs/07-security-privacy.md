# 07 — Security & Privacy

## 1. Core Commitment

All scanning, hashing, scoring, matching, and comparison logic executes **entirely on-device**. Reclaim makes **zero network requests** of any kind — no analytics SDK, no crash reporter that transmits payloads off-device, no remote config, no ad SDK, no cloud AI inference. This is a hard architectural constraint (Document 03 §3), not a policy that could be silently violated by a future dependency, because the app has no networking library or URLSession usage anywhere in its dependency graph outside of the one explicit exception below.

**Explicit, user-controlled exception:** tapping "Open Settings" from a permission-denied state opens the iOS Settings app via `UIApplication.openSettingsURLString` — this is a local OS deep link, not a network request, and is the only system-level hop the app ever initiates.

## 2. What Never Leaves the Device

- Photo/video pixel data, thumbnails, and full-resolution assets
- Perceptual hashes (these are derived from private image content and are treated as private, even though they are not literally the image)
- Contact names, phone numbers, emails, or any `CNContact` field
- Scan results, cache files, or logs

## 3. No Analytics on Private Content

- No third-party analytics SDK is included (Document 03 §3: zero third-party dependencies).
- If any first-party, privacy-safe operational logging exists (e.g., "scan completed in Xs" for the developer's own debugging during development), it must never include asset identifiers, contact fields, filenames, or any value derived from private content — `Infrastructure/Logging.swift` enforces this by only accepting primitive counts/durations/enum states as log payloads, never model instances.
- No usage analytics (screen views, tap tracking, funnels) are implemented in this scope at all — not "anonymized," simply absent, since the assignment's scope does not require them and adding them would work against the privacy-first positioning for no product benefit.

## 4. No Unnecessary Persistence

- `ScanCache` persists only: asset local identifiers, computed hash values, byte sizes, group membership, and timestamps — never image bytes, never contact field values (Document 05 §7, §12).
- Thumbnails live only in an in-memory/disk-backed `NSCache`, explicitly documented as disposable and safe to lose (e.g., under memory pressure, or if the user clears app data) — the app never treats the thumbnail cache as a source of truth; it always re-derives from PhotoKit if evicted.
- No contact data is cached at all beyond the current screen's live fetch plus the minimal `ContactCandidate` comparison keys used transiently during a scan pass; these are not written to `ScanCache` in a form that would let someone reconstruct a person's phone number or email from the cache file (only normalized, non-reversible-in-practice comparison keys are considered for caching, and the implementation defaults to *not* caching contact scan results across launches at all in v1, re-scanning contacts fresh each session, since contact libraries are typically small enough that this is cheap — documented in Document 09).

## 5. Minimum Permissions & Rationale

| Permission | Why requested | When requested |
|---|---|---|
| Photo Library (`NSPhotoLibraryUsageDescription`) | Required to enumerate, thumbnail, and delete photo/video/screenshot assets | On first entry into any Photos-dependent screen (Clean Up hub), never at cold launch before the user has seen why it's needed |
| Contacts (`NSContactsUsageDescription`) | Required to enumerate and delete/merge duplicate contact records | On first entry into the Duplicate Contacts screen specifically — not bundled with the Photos prompt, so a user who only cares about photo cleanup is never asked for contacts access |

Usage description strings state the purpose plainly and specifically (e.g., "Reclaim scans your photos on-device to find duplicates and similar images. Nothing is uploaded."), avoiding generic boilerplate — this string is itself a privacy commitment surfaced at the moment of the OS permission dialog, not just buried in a privacy policy.

**No permission is requested "just in case."** The app requests exactly Photos and Contacts, and nothing else (no location, no microphone, no camera, no push notifications).

## 6. Denied / Limited / Restricted Behavior

See Document 01 §3.7 and Document 02 §4 for the full state table and UI treatment. Security-relevant guarantees:

- **Denied Photos or Contacts:** the corresponding category screens show an explicit permission-needed state and link to Settings; the app performs no PhotoKit/Contacts API calls in this state (guarded at the Service layer, not just the UI layer, so a ViewModel bug can't accidentally trigger a call that would just fail loudly — the Service checks authorization status before any fetch and returns a typed `.permissionDenied` result rather than attempting the call).
- **Limited Photo Library:** the app operates correctly on exactly the assets the user has granted, no more; a persistent, dismissible-per-session banner explains the limited scope and offers `PHPhotoLibrary.presentLimitedLibraryPicker` to expand it — the app never nags to "upgrade" to full access in a way that resembles a dark pattern (single, calm mention, not a blocking modal).
- **Restricted (e.g., Screen Time/parental controls):** same UI treatment as denied, with copy that accurately reflects that this cannot be changed via the in-app Settings link.

## 7. Deletion Confirmation & Auditability

- Every deletion path (photos, screenshots, videos, contacts) is gated by the single `CleanupSelection` → Review screen → explicit confirm tap → `PerformCleanupUseCase` flow (Document 01 §3.6, Document 05 §9). There is no secondary code path that can construct and execute a deletion.
- Photo/video deletion additionally triggers the **native iOS system confirmation dialog** as part of `PHPhotoLibrary.performChanges` — this is an OS-level safety net entirely outside the app's control, and the app's own Review confirmation is deliberately treated as a prerequisite to reaching that OS dialog, not a replacement for it.
- Contact deletion via `CNSaveRequest` executes synchronously against the on-device contacts database with no OS-level secondary confirmation, which is exactly why the in-app Review + per-group merge/delete preview (Document 01 §3.5) carries the full weight of the safety guarantee for that category — documented explicitly as the reason contacts get an additional per-group preview screen that photos/videos don't strictly need.
- `CleanupSummary` (Document 05 §10) is populated from what the OS actually confirms was deleted, never from the request — this is the audit trail the user sees on the Cleanup Result screen, and it is honest about partial failures rather than reporting 100% success unconditionally.

## 8. Error Handling & Failure Modes

- All Photos/Contacts framework calls are wrapped in typed `async throws` service methods (Document 03 §7); failures surface specific, actionable UI states rather than crashing.
- A mid-scan permission revocation (e.g., user changes permission in Settings while app is backgrounded) is detected on foreground re-entry via authorization-status re-check before any further framework call, not assumed to remain valid for the app's lifetime.

## 9. What This App Explicitly Cannot Do (and does not claim to)

Documented here so the product never markets capability iOS does not grant a third-party app:

- **Cannot see or clean "system junk," cache files, or other apps' storage.** iOS sandboxes each app; a third-party app has no API to enumerate or delete another app's data or OS cache. Reclaim's Dashboard never shows a number for this.
- **Cannot permanently, unrecoverably delete photos bypassing iOS's own safety net.** Deleted photos go to the user's "Recently Deleted" album (standard PhotoKit behavior, ~30-day OS-level grace period) — this is disclosed to the user as a positive, not hidden, since it reinforces the trust story ("even after you confirm here, iOS gives you one more safety net").
- **Cannot guarantee phone-number normalization is internationally perfect** (Document 06 §6) — disclosed as a known limitation, not silently assumed correct.
- **Cannot detect semantically-similar-but-visually-different photos** (e.g., different photos of the same event/person on different days) — only near-duplicate/burst-style visual similarity via perceptual hashing (Document 06 §2).
- **Cannot run any part of its pipeline in the cloud**, by design — there is no server component to this product at all.
