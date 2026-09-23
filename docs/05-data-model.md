# 05 — Data Model

All types below live in `Core/Models` and import only `Foundation` (+ `CoreGraphics` for `CGSize` where noted) — never `Photos`/`Contacts`/`AVFoundation` — so they remain trivially testable and serializable.

## 1. PhotoAsset

Represents a single photo library asset relevant to scanning.

```swift
struct PhotoAsset: Identifiable, Hashable {
    let id: String                    // PHAsset.localIdentifier — stable, never the asset bytes
    let creationDate: Date?
    let pixelSize: CGSize             // width/height, from PHAsset
    let byteSize: Int64               // sum of PHAssetResource fileSize(s)
    let isScreenshot: Bool            // from PHAsset.mediaSubtypes
    let mediaType: MediaKind          // .photo (video handled by VideoAsset)
    var perceptualHash: UInt64?       // populated after SimilarityDetector pass; nil until computed
    var sharpnessScore: Double?       // populated during best-photo scoring, nil until computed
}
```

Notes:
- No image bytes or thumbnail are ever stored on this model — only the `localIdentifier` reference back into PhotoKit. Thumbnails are fetched on demand through `ThumbnailCache`.
- `perceptualHash`/`sharpnessScore` are optional and computed lazily/in a background pass so the initial enumeration (fast) is decoupled from the expensive analysis pass (slow) — this split matters for progressive UI (Document 09).

## 2. PhotoGroup

A cluster of related `PhotoAsset`s (exact duplicates or visually similar).

```swift
struct PhotoGroup: Identifiable {
    let id: UUID
    let kind: PhotoGroupKind          // .exactDuplicate or .similar
    let members: [PhotoAsset]
    var recommendedKeepID: String     // PhotoAsset.id the algorithm suggests keeping
    var userChosenKeepID: String?     // non-nil once user overrides recommendation
    var selection: Set<String>        // asset IDs currently marked for deletion within this group
    let confidence: Double            // 0...1, see Document 06 for derivation

    var effectiveKeepID: String { userChosenKeepID ?? recommendedKeepID }
    var recoverableBytes: Int64 {
        members.filter { selection.contains($0.id) }
               .reduce(0) { $0 + $1.byteSize }
    }
}
```

Invariant enforced at the ViewModel layer: `effectiveKeepID` is never present in `selection` — the app will not let the user select-for-deletion the photo currently marked as "keep" without first either changing the keep choice or being shown an explicit warning; the default "select group" action always excludes the keep photo automatically.

## 3. PhotoCandidate

Lightweight scoring wrapper used only during best-photo selection (Document 06); not persisted, not shown directly in UI beyond its `reason`.

```swift
struct PhotoCandidate {
    let asset: PhotoAsset
    let resolutionScore: Double
    let sharpnessScore: Double
    let exposureScore: Double
    let totalScore: Double
    let reason: String   // human-readable, e.g. "Highest resolution, sharpest of 4"
}
```

## 4. VideoAsset

```swift
struct VideoAsset: Identifiable, Hashable {
    let id: String                    // PHAsset.localIdentifier
    let creationDate: Date?
    let duration: TimeInterval
    let pixelSize: CGSize             // resolution
    let byteSize: Int64
}
```

Kept separate from `PhotoAsset` (rather than a shared `MediaAsset` superset with optional video fields) because video-specific requirements (duration, preview playback) and photo-specific requirements (perceptual hash, sharpness) never overlap in the UI — a shared type would carry dead optional fields on both sides. Tradeoff documented in Document 04's ADR pattern: slight duplication of `id`/`creationDate`/`byteSize` fields, in exchange for each model only ever describing real, relevant data.

## 5. ContactCandidate

A single contact record surfaced for duplicate review.

```swift
struct ContactCandidate: Identifiable, Hashable {
    let id: String                    // CNContact.identifier
    let givenName: String
    let familyName: String
    let normalizedPhones: [String]    // see Document 06 normalization rules
    let normalizedEmails: [String]
    let fieldCount: Int                // total populated fields, used to suggest which record is "richer"
    let imageDataAvailable: Bool
}
```

Note: `normalizedPhones`/`normalizedEmails` store normalized *comparison keys*, not necessarily the literal displayed value — the group detail screen re-fetches the live `CNContact` for display so the user always sees real, current data, never a stale cached copy.

## 6. ContactGroup

```swift
struct ContactGroup: Identifiable {
    let id: UUID
    let tier: ContactDuplicateTier     // .exact or .probable
    let members: [ContactCandidate]
    let matchReason: String            // e.g. "Same phone number, similar name"
    var recommendedPrimaryID: String   // the record suggested to keep/merge into
    var selection: Set<String>         // member IDs marked for deletion (never includes recommendedPrimaryID by default)
    let confidence: Double             // 0...1 for .probable; 1.0 for .exact
}
```

## 7. ScanResult

Aggregate output of a full or incremental scan, cached via `ScanCache`.

```swift
struct ScanResult: Codable {
    let scannedAt: Date
    let photoGroups: [PhotoGroupSummary]     // Codable-safe projection, not live PhotoGroup
    let screenshots: [PhotoAssetSummary]
    let videos: [VideoAssetSummary]
    let contactGroups: [ContactGroupSummary]
    let cacheSchemaVersion: Int               // bump forces full rescan on algorithm changes
}
```

`ScanResult` stores `Summary` projections (IDs, byte sizes, hashes, group membership — the minimum needed to reconstruct UI state and detect "what changed since last scan") rather than the live in-memory model types, and never stores thumbnails or contact field values, keeping the on-disk cache small and free of any content that would matter if the cache file were inspected.

## 8. StorageSummary

```swift
struct StorageSummary {
    let totalCapacityBytes: Int64
    let usedBytes: Int64
    let availableBytes: Int64
    let recoverableBytes: Int64             // derived from current ScanResult selections
    let recoverableByCategory: [CleanupCategory: Int64]
    let lastScanDate: Date?
}
```

`totalCapacityBytes`/`usedBytes`/`availableBytes` come directly from `URLResourceKey` volume capacity keys — never modeled.

## 9. CleanupSelection

The explicit, user-approved payload that Review hands to `PerformCleanupUseCase`. This is intentionally the *only* type that can trigger deletion — no other code path in the app constructs one implicitly.

```swift
struct CleanupSelection {
    let photoAssetIDs: Set<String>      // from similar/duplicate groups
    let screenshotAssetIDs: Set<String>
    let videoAssetIDs: Set<String>
    let contactIDs: Set<String>

    var totalItemCount: Int { photoAssetIDs.count + screenshotAssetIDs.count + videoAssetIDs.count + contactIDs.count }
    var isEmpty: Bool { totalItemCount == 0 }
}
```

`PerformCleanupUseCase` refuses to execute (throws `ReclaimError.emptySelection`) if `isEmpty` — a structural guard against the "scan → auto-delete" failure mode, independent of any UI-level disabled-button check.

## 10. CleanupSummary

The honest, post-hoc report shown on the Cleanup Result screen.

```swift
struct CleanupSummary {
    let requested: CleanupSelection
    let deletedPhotoCount: Int          // actually confirmed deleted by PhotoKit, not requested count
    let deletedVideoCount: Int
    let deletedScreenshotCount: Int
    let deletedContactCount: Int
    let bytesFreed: Int64               // recomputed from pre/post StorageSummary, not estimated
    let failures: [CleanupFailure]      // any item that could not be deleted, with reason
}
```

`deleted*Count` fields are populated from what the OS actually reports back (e.g., `PHPhotoLibrary.performChanges` completion, `CNSaveRequest` execution result), never copied from the `requested` counts — this is the model-level enforcement of "never fake a deletion result."

## 11. Enums

```swift
enum MediaKind { case photo, video }
enum PhotoGroupKind { case exactDuplicate, similar }
enum ContactDuplicateTier { case exact, probable }
enum CleanupCategory { case similarPhotos, screenshots, largeVideos, duplicateContacts }
enum ScanStatus { case notStarted, scanning(phase: String, progress: Double), completed, cancelled, failed(String) }
```

## 12. What is deliberately *not* modeled

- No model stores raw image/video bytes or full-resolution pixel buffers — thumbnails are transient (`UIImage` in `ThumbnailCache`, evictable, never `Codable`).
- No model stores a contact's full field set beyond what's needed for matching/display in the current screen — the source of truth for display remains a live `CNContact` fetch.
- No "junk file" or "cache size" model exists anywhere in the app, because iOS does not expose that data to a third-party app (Document 07).
