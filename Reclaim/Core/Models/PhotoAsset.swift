//
//  PhotoAsset.swift
//  Reclaim
//
//  Document 05 §1, §3. No image bytes or thumbnails are ever stored here —
//  only the PHAsset.localIdentifier reference. Thumbnails are fetched on
//  demand through ThumbnailCache.
//

import Foundation
import CoreGraphics

struct PhotoAsset: Identifiable, Hashable, Sendable {
    /// PHAsset.localIdentifier — stable, never the asset bytes.
    let id: String
    let creationDate: Date?
    let pixelSize: CGSize
    /// Sum of PHAssetResource byte size(s) for this asset. See ADR-01
    /// (Document 14) for how this is computed.
    let byteSize: Int64
    /// From PHAsset.mediaSubtypes.contains(.photoScreenshot) — the only
    /// reliable signal for this category (Document 06 §4).
    let isScreenshot: Bool
    let mediaType: MediaKind

    /// Populated after SimilarityDetector's hashing pass; nil until computed.
    /// This split (fast enumeration now, slow analysis later) is what makes
    /// progressive results possible (Document 09 §4).
    var perceptualHash: UInt64?

    /// Populated during best-photo scoring; nil until computed.
    var sharpnessScore: Double?

    /// Returns a copy with `byteSize` set. Used by the scan pipeline after
    /// the cheap metadata pass resolves sizes lazily (ADR-01) — screenshots
    /// and duplicate candidates get their real byte size without re-carrying
    /// every other field by hand.
    func withByteSize(_ newSize: Int64) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: creationDate,
            pixelSize: pixelSize,
            byteSize: newSize,
            isScreenshot: isScreenshot,
            mediaType: mediaType,
            perceptualHash: perceptualHash,
            sharpnessScore: sharpnessScore
        )
    }

    init(
        id: String,
        creationDate: Date?,
        pixelSize: CGSize,
        byteSize: Int64,
        isScreenshot: Bool,
        mediaType: MediaKind = .photo,
        perceptualHash: UInt64? = nil,
        sharpnessScore: Double? = nil
    ) {
        self.id = id
        self.creationDate = creationDate
        self.pixelSize = pixelSize
        self.byteSize = byteSize
        self.isScreenshot = isScreenshot
        self.mediaType = mediaType
        self.perceptualHash = perceptualHash
        self.sharpnessScore = sharpnessScore
    }

    // Hashable/Equatable driven by id alone — two PhotoAsset snapshots of the
    // same underlying asset are "the same" for grouping/selection purposes
    // even if their analysis-derived fields differ.
    static func == (lhs: PhotoAsset, rhs: PhotoAsset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Lightweight scoring wrapper used only during best-photo selection
/// (Document 06 §3). Not persisted, not shown directly in UI beyond `reason`.
struct PhotoCandidate: Sendable {
    let asset: PhotoAsset
    let resolutionScore: Double
    let sharpnessScore: Double
    let exposureScore: Double
    let totalScore: Double
    /// Human-readable, derived directly from the scores above — e.g.
    /// "Highest resolution, sharpest of 4". Never references an
    /// unimplemented signal (face detection etc. — hard prohibition,
    /// Document 06 §3).
    let reason: String
}
