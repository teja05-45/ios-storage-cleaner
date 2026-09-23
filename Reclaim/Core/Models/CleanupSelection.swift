//
//  CleanupSelection.swift
//  Reclaim
//
//  Document 05 §9-10. CleanupSelection is intentionally the *only* type
//  that can trigger deletion — no other code path in the app constructs
//  one implicitly. See Document 07 §7 and safety test
//  `test_deletionRequiresExplicitConfirmation`.
//

import Foundation

struct CleanupSelection: Sendable, Equatable {
    let photoAssetIDs: Set<String>
    let screenshotAssetIDs: Set<String>
    let videoAssetIDs: Set<String>
    let contactIDs: Set<String>

    init(
        photoAssetIDs: Set<String> = [],
        screenshotAssetIDs: Set<String> = [],
        videoAssetIDs: Set<String> = [],
        contactIDs: Set<String> = []
    ) {
        self.photoAssetIDs = photoAssetIDs
        self.screenshotAssetIDs = screenshotAssetIDs
        self.videoAssetIDs = videoAssetIDs
        self.contactIDs = contactIDs
    }

    var totalItemCount: Int {
        photoAssetIDs.count + screenshotAssetIDs.count + videoAssetIDs.count + contactIDs.count
    }

    var isEmpty: Bool { totalItemCount == 0 }

    /// All PhotoKit-backed IDs (photos + screenshots + videos), used
    /// wherever a step needs to treat every PHAsset-based category
    /// uniformly (e.g. a single `PHPhotoLibrary.performChanges` call).
    var allPhotoKitAssetIDs: Set<String> {
        photoAssetIDs.union(screenshotAssetIDs).union(videoAssetIDs)
    }
}

enum CleanupFailure: Sendable, Equatable, Identifiable {
    case photo(id: String, reason: CleanupFailureReason)
    case screenshot(id: String, reason: CleanupFailureReason)
    case video(id: String, reason: CleanupFailureReason)
    case contact(id: String, reason: CleanupFailureReason)

    var id: String {
        switch self {
        case .photo(let id, _), .screenshot(let id, _), .video(let id, _), .contact(let id, _):
            return id
        }
    }

    var reason: CleanupFailureReason {
        switch self {
        case .photo(_, let r), .screenshot(_, let r), .video(_, let r), .contact(_, let r):
            return r
        }
    }
}

/// The honest, post-hoc report shown on the Cleanup Result screen.
/// `deleted*Count` fields are populated from what the OS actually reports
/// back — never copied from `requested` counts. This is the model-level
/// enforcement of "never fake a deletion result" (Document 05 §10).
struct CleanupSummary: Sendable, Equatable {
    let requested: CleanupSelection
    let deletedPhotoCount: Int
    let deletedVideoCount: Int
    let deletedScreenshotCount: Int
    let deletedContactCount: Int
    /// Recomputed from pre/post StorageSummary — never estimated
    /// (Document 01 §3.6, ADR in Document 06 §9 of this build's instructions).
    let bytesFreed: Int64
    let failures: [CleanupFailure]
    /// The IDs the OS actually confirmed deleted (OPEN-3): photos/screenshots/
    /// videos in one set, contacts in the other. Callers that prune live
    /// state after cleanup (ReviewStore) must use these — never `requested` —
    /// so the UI drops exactly what is gone, no more, no less.
    var deletedPhotoAssetIDs: Set<String> = []
    var deletedContactIDs: Set<String> = []

    init(
        requested: CleanupSelection,
        deletedPhotoCount: Int,
        deletedVideoCount: Int,
        deletedScreenshotCount: Int,
        deletedContactCount: Int,
        bytesFreed: Int64,
        failures: [CleanupFailure],
        deletedPhotoAssetIDs: Set<String> = [],
        deletedContactIDs: Set<String> = []
    ) {
        self.requested = requested
        self.deletedPhotoCount = deletedPhotoCount
        self.deletedVideoCount = deletedVideoCount
        self.deletedScreenshotCount = deletedScreenshotCount
        self.deletedContactCount = deletedContactCount
        self.bytesFreed = bytesFreed
        self.failures = failures
        self.deletedPhotoAssetIDs = deletedPhotoAssetIDs
        self.deletedContactIDs = deletedContactIDs
    }

    var totalDeletedCount: Int {
        deletedPhotoCount + deletedVideoCount + deletedScreenshotCount + deletedContactCount
    }

    var hadPartialFailure: Bool { !failures.isEmpty }
}
