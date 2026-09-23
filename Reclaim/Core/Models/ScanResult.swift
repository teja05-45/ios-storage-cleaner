//
//  ScanResult.swift
//  Reclaim
//
//  Document 05 §7. Stores Summary projections (IDs, byte sizes, hashes,
//  group membership) rather than live in-memory model types, and never
//  stores thumbnails or contact field values — keeps the on-disk ScanCache
//  small and free of content that would matter if the cache file were
//  inspected (Document 07 §4).
//

import Foundation

struct PhotoGroupSummary: Codable, Sendable {
    let id: UUID
    let kind: PhotoGroupKind
    let memberIDs: [String]
    let recommendedKeepID: String
    let confidence: Double
}

struct PhotoAssetSummary: Codable, Sendable {
    let id: String
    let byteSize: Int64
    let creationDate: Date?
}

struct VideoAssetSummary: Codable, Sendable {
    let id: String
    let byteSize: Int64
    let creationDate: Date?
}

struct ContactGroupSummary: Codable, Sendable {
    let id: UUID
    let tier: ContactDuplicateTier
    let memberIDs: [String]
    let recommendedPrimaryID: String
    let confidence: Double
}

struct ScanResult: Codable, Sendable {
    let scannedAt: Date
    let photoGroups: [PhotoGroupSummary]
    let screenshots: [PhotoAssetSummary]
    let videos: [VideoAssetSummary]
    let contactGroups: [ContactGroupSummary]
    /// Bumped whenever hashing/threshold logic changes, forcing a full
    /// rescan rather than silently mixing old and new hash semantics
    /// (Document 04 ADR-04, ADR-07 in Document 14).
    let cacheSchemaVersion: Int

    /// True if the photo portion of this scan was produced under `.limited`
    /// PhotoKit authorization. Threaded through so the UI can honestly state
    /// "only your selected photos were scanned" rather than implying full
    /// coverage (ADR-04, Document 01 §3.7).
    let scannedWithLimitedPhotoAccess: Bool

    static let currentSchemaVersion = 1
}
