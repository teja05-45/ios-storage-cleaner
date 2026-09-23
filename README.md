# Reclaim — iOS Storage Cleaner

A native iOS app that finds duplicate/similar photos, screenshots, large videos, and duplicate contacts on-device, so you can review and delete what you don't need. Nothing is uploaded — every scan runs entirely on your iPhone.

> **Build status: code-complete for the core loop, not yet compiled.** This codebase was written to the full specification in `/docs` in an environment without Xcode, a Simulator, or a physical iPhone. See [Known Limitations](#known-limitations) before treating this as a finished, shippable build.

## Product

Reclaim scans four categories on request (never automatically, never in the background):

- **Similar & Duplicate Photos** — byte-identical duplicates (verified by content hash, not just size) and visually similar bursts, with a heuristic "recommended keep" you can override.
- **Screenshots** — everything the OS itself flags as a screenshot.
- **Large Videos** — sorted by actual file size.
- **Duplicate Contacts** — grouped into Exact (shared phone/email) and Probable (similar name plus a secondary signal) tiers, with a field-diff preview before you delete anything.

Every category feeds into one **Review** screen. Nothing is ever deleted without an explicit, itemized confirmation there — see [Safety Architecture](#safety-architecture).

## Architecture

```
Core/        — models, errors, pure algorithms. Foundation only, no Photos/Contacts/AVFoundation.
Services/    — the ONLY layer that imports Photos/Contacts/AVFoundation. Protocol-first, so
               everything above this layer is testable with fakes.
UseCases/    — orchestration: scan pipelines, and the safety-critical PerformCleanupUseCase.
Features/    — SwiftUI views + @Observable ViewModels, one folder per screen area.
Infrastructure/ — ScanCache (on-disk, derived data only), ThumbnailCache, PII-safe Logging.
```

Dependencies flow one way: `Features → UseCases → Services → Core`. Nothing in `Core` imports a framework beyond `Foundation`/`CoreGraphics`, which is what makes the algorithm layer testable without a device (see [Testing](#testing)).

Full rationale for every non-obvious call is in `docs/14-implementation-decisions.md` (an ADR log) — including why contact deduplication ships as review-and-delete rather than automated merge, why photo resource size uses an undocumented-but-widely-used PhotoKit key with a documented fallback, and why the storage math uses the specific `URLResourceKey`s it does.

## Safety Architecture

```
SCAN → RESULTS → SELECTION → REVIEW → EXPLICIT CONFIRMATION → REVALIDATE → CLEANUP → RESULT
```

This is enforced structurally, not just visually:

- **`CleanupSelection`** is the only type that can trigger deletion. It's constructed in exactly one place — `ReviewStore.currentSelection` — read from the single source of truth for selection across every category.
- **`PerformCleanupUseCase.execute`** is the only method in the codebase that can initiate a delete. It throws on an unconfirmed or empty selection, re-checks that Photos/Contacts authorization is still usable, and **revalidates every selected ID against the live library immediately before deleting** — an asset or contact that vanished between scan and confirmation is dropped from the executable set and reported as a failure, never silently executed against or silently dropped.
- **Deletion has exactly two call sites in the entire app**: `PhotoLibraryServiceLive.deleteAssets` (which triggers the native OS "Delete X Photos" confirmation as a second safety net) and `ContactServiceLive.deleteContacts` (which has no OS-level equivalent — the in-app Review screen carries the full safety weight for that category).
- **`PhotoGroup`/`ContactGroup` make it structurally impossible to select the recommended-keep/primary record** — every mutating method routes through a guard that excludes it, including the initializer.
- **Duplicate-contact detection has a hard false-positive guard**: name similarity alone can never classify a pair as a duplicate candidate, of either tier. See `DuplicateContactDetectorTests.test_identicalNames_noSharedPhoneOrEmail_neverGrouped` — two different people who happen to share a common name and have zero overlapping phone/email evidence are never flagged, even if their names are byte-identical.
- **Cleanup results are never fabricated.** `CleanupSummary.deletedPhotoCount` etc. come from what the OS actually confirmed deleted, not from the requested count. `bytesFreed` is computed from an independently re-read device-storage snapshot taken after cleanup, not copied from the pre-cleanup estimate.

## Scanning Algorithms

- **Exact duplicates**: cheap bucketing by (dimensions, byte size) narrows the field, then a streamed SHA-256 over each candidate's actual resource bytes confirms true content equality — a thumbnail hash is never treated as proof of exact duplication.
- **Similar photos**: assets are bucketed by a rolling creation-time window (handles bursts spanning midnight), then a 64-bit dHash perceptual hash is computed per thumbnail, clustered via union-find over pairwise Hamming distance (transitive chains merge correctly even when the two endpoints individually exceed the threshold), and each cluster's members are scored on resolution/sharpness (Laplacian variance)/exposure/file size to produce a "recommended keep" — always described as a heuristic recommendation, never as "the best photo" or anything implying ML/face detection that isn't actually implemented.
- **Duplicate contacts**: phone/email normalization (documented limitation: last-10-digit suffix matching, not full E.164 parsing) plus name similarity (Levenshtein, with a token-reordered comparison so "Smith, John" matches "John Smith"), classified into Exact/Probable tiers with the false-positive guard described above and an oversized-group (>8 members) demotion to protect against a shared office/family line being mistaken for eight duplicate people.

Every algorithm's pure math lives in `Core/Utilities` with no PhotoKit/Contacts/image-framework dependency, so it's unit-tested with synthetic fixtures.

## Privacy

- Zero network calls anywhere in the app. No analytics, no crash reporting SDK, no third-party dependencies at all.
- Logging (`Infrastructure/Logging.swift`) only accepts primitives (counts, durations, category names) — there is no logging call that accepts a model instance, a name, a phone number, or an asset identifier.
- The on-disk scan cache stores only derived data (hashes, byte sizes, timestamps) — never thumbnails, never contact field values. Contacts are never cached across app launches at all.
- Requesting Photos access never implies write/add access is needed — the app only ever deletes, and `NSPhotoLibraryAddUsageDescription` is deliberately omitted (flagged in `Info.plist` for confirmation on first real build, per `docs/14-implementation-decisions.md`).

## Testing

Full suite (`ReclaimTests/`) targets three things:

1. **Algorithm correctness** (`CoreTests/`) — dHash determinism and known bit patterns, Hamming distance and the transitive-chain clustering property, contact phone/email normalization edge cases, name-similarity reordering, best-photo scoring, and — most importantly — the duplicate-contact false-positive guard and oversized-group demotion.
2. **Selection invariants** (`GroupSelectionInvariantTests`) — the recommended-keep/primary can never end up in `selection`, under any sequence of mutations, including a caller trying to seed an illegal initial state.
3. **Cleanup safety** (`SafetyTests/`) — using fake `PhotoLibraryServiceProtocol`/`ContactServiceProtocol`/`StorageServiceProtocol` implementations, verifying: no confirmation → no deletion, empty selection → throws, stale asset → skipped and reported (never attempted), permission revoked → no delete call attempted, partial framework failure → accurately reported (never rounded up to full success), and a clean success path with `bytesFreed` coming from an independently-simulated before/after storage reading.

**These tests are written but not yet run** — see Known Limitations.

## Performance

Designed for 10,000+ photos / 1,000+ videos per Document 09's targets: metadata-only enumeration before any pixel analysis, screenshots/exact-duplicates/videos computed from cheap signals that don't require perceptual hashing, similarity analysis bounded to same-time-window buckets (never an all-pairs O(n²) comparison), a fixed `TaskGroup` concurrency cap (`min(core count, 4)`, named as a tunable constant), streamed (never fully-buffered) reads for content hashing and resource sizing, and cooperative cancellation checked at every phase boundary.

**No Instruments-measured numbers are included anywhere in this repository.** The design above is real; the measurements proving it holds at scale on a real device are not, because this environment has no device to measure on. Anyone continuing this build should treat a real-device Instruments pass as a required, not optional, next step before calling performance work done.

## Known Limitations

Disclosed deliberately, per the project's own "never fabricate" principle — not discovered gaps:

- **Not yet compiled.** No Swift/Xcode toolchain was available in the environment this was written in. The code follows current, verified Apple API signatures (`docs/14-implementation-decisions.md` §0), but the first real step for anyone picking this up should be opening it in Xcode and fixing whatever the compiler finds — a hand-authored `.xcodeproj` in particular should be treated as unverified until Xcode confirms it.
- **No automated contact merge.** Ships a full field-diff preview and safe delete; does not construct-and-save a merged contact. See ADR-02 in `docs/14-implementation-decisions.md`.
- **Phone normalization is a last-10-digit-suffix heuristic**, not full ITU E.164 parsing (Document 06 §6, `ContactNormalizer`).
- **Screenshots/Large Videos/Duplicate Contacts SwiftUI screens are not yet built.** `DashboardView` and `ReviewView` (the safety-critical core loop) are complete; the individual category browsing/selection screens for these three categories follow the exact same `ReviewStore`-backed pattern as photos and are the next slice of work, not a design gap.
- **No real-device validation matrix has been run** (Limited Photos access, Contacts denial, cancellation mid-scan, an actual 10,000+ photo library, VoiceOver, Dynamic Type at accessibility sizes). All of this requires a physical iPhone.
- **No demo recording exists yet** for the same reason.

## Setup

1. Open `Reclaim.xcodeproj` in Xcode 15+ (targets iOS 17+).
2. Build and run on a simulator or device signed with your own development team.
3. Grant Photos/Contacts access when prompted from the Dashboard.
4. Run `⌘U` to execute the `ReclaimTests` target.

## AI-Assisted Development

This codebase was written by Claude (Anthropic) from a detailed specification package (`/docs`), following an explicit gap-analysis → API-verification → decision-log → implementation workflow, with every non-obvious architectural choice recorded as an ADR in `docs/14-implementation-decisions.md` rather than left implicit in code comments alone.
