//
//  SimilarityDetector.swift
//  Reclaim
//
//  Document 06 §2 full pipeline. Bounded concurrency per ADR-06
//  (Document 14): a fixed TaskGroup cap, never one task per asset.
//

import Foundation
import CoreGraphics

protocol SimilarityDetectorProtocol: Sendable {
    func detectSimilarGroups(in assets: [PhotoAsset], photoLibrary: PhotoLibraryServiceProtocol) async throws -> [PhotoGroup]
}

struct SimilarityDetector: SimilarityDetectorProtocol {

    /// ADR-06: bounded concurrency, scaled to the device but capped low
    /// enough to bound memory/thermal impact even on high-core devices.
    /// Tunable — named explicitly so it's the one place to revisit once
    /// profiled on a physical device (Document 09 §9, Document 13 §5).
    var maxConcurrentBuckets: Int {
        min(ProcessInfo.processInfo.activeProcessorCount, 4)
    }

    /// Photos with creation dates within this window are bucketed together
    /// before any pixel analysis — the cheap metadata prefilter
    /// (Document 06 §2 step 3). A rolling window (not calendar-day
    /// boundaries) so a burst shot at 11:59pm and 12:01am still buckets
    /// together (Document 06 §2's explicit midnight-crossing requirement).
    private let bucketWindow: TimeInterval = 120 // 2 minutes

    func detectSimilarGroups(in assets: [PhotoAsset], photoLibrary: PhotoLibraryServiceProtocol) async throws -> [PhotoGroup] {
        // Step 2: exclude screenshots from similarity analysis — they're a
        // separate, simpler category with their own detector
        // (Document 06 §2 step 2, §4).
        let candidates = assets.filter { !$0.isScreenshot && $0.creationDate != nil }
        guard candidates.count > 1 else { return [] }

        // Step 3: rolling time-window bucketing.
        let sorted = candidates.sorted { $0.creationDate! < $1.creationDate! }
        var buckets: [[PhotoAsset]] = []
        var currentBucket: [PhotoAsset] = [sorted[0]]

        for asset in sorted.dropFirst() {
            if let last = currentBucket.last?.creationDate,
               asset.creationDate!.timeIntervalSince(last) <= bucketWindow {
                currentBucket.append(asset)
            } else {
                if currentBucket.count > 1 { buckets.append(currentBucket) }
                currentBucket = [asset]
            }
        }
        if currentBucket.count > 1 { buckets.append(currentBucket) }

        guard !buckets.isEmpty else { return [] }

        // Steps 4-6: thumbnails + dHash, bounded concurrency across buckets.
        var groups: [PhotoGroup] = []

        try await withThrowingTaskGroup(of: [PhotoGroup].self) { taskGroup in
            var iterator = buckets.makeIterator()
            var active = 0

            func submitNext() {
                guard let bucket = iterator.next() else { return }
                active += 1
                taskGroup.addTask {
                    try await self.processBucket(bucket, photoLibrary: photoLibrary)
                }
            }

            for _ in 0..<maxConcurrentBuckets { submitNext() }

            while let result = try await taskGroup.next() {
                active -= 1
                groups.append(contentsOf: result)
                submitNext()
            }
        }

        return groups
    }

    /// Steps 4-9 for a single metadata bucket: hash every member, cluster
    /// by Hamming distance, score each cluster's members, recommend a keep.
    private func processBucket(_ bucket: [PhotoAsset], photoLibrary: PhotoLibraryServiceProtocol) async throws -> [PhotoGroup] {
        var hashedAssets: [(asset: PhotoAsset, hash: UInt64, pixels: ThumbnailPixels)] = []

        for asset in bucket {
            guard let pixels = await photoLibrary.requestThumbnail(forAssetID: asset.id, targetSize: CGSize(width: 64, height: 64)) else {
                continue // unreadable thumbnail — asset silently excluded from similarity analysis, not from the library
            }
            guard let hash = PerceptualHash.dHash(fromGrayscaleGrid: pixels.dHashGrid) else { continue }
            hashedAssets.append((asset, hash, pixels))
        }

        guard hashedAssets.count > 1 else { return [] }

        let clusters = PhotoClustering.cluster(hashes: hashedAssets.map(\.hash))

        var groups: [PhotoGroup] = []
        for cluster in clusters {
            let members = cluster.indices.map { hashedAssets[$0] }

            var signals: [BestPhotoScoring.RawSignals] = []
            for member in members {
                let byteSize = (try? await photoLibrary.resourceByteSize(forAssetID: member.asset.id)) ?? 0
                signals.append(BestPhotoScoring.RawSignals(
                    assetID: member.asset.id,
                    resolutionPixels: Double(member.asset.pixelSize.width * member.asset.pixelSize.height),
                    sharpnessRaw: member.pixels.sharpnessRaw,
                    exposureRaw: member.pixels.exposureRaw,
                    byteSize: byteSize
                ))
            }

            guard let keepID = BestPhotoScoring.recommendedKeepID(signals) else { continue }

            // Members carry their real byte size (BUG-01): sizes were just
            // resolved for scoring — folding them back here keeps group
            // recoverable-bytes estimates and Review rows honest instead
            // of reporting the enumeration placeholder 0.
            let sizesByID = Dictionary(uniqueKeysWithValues: signals.map { ($0.assetID, $0.byteSize) })
            let sizedMembers = members.map { $0.asset.withByteSize(sizesByID[$0.asset.id] ?? $0.asset.byteSize) }

            groups.append(PhotoGroup(
                kind: .similar,
                members: sizedMembers,
                recommendedKeepID: keepID,
                confidence: cluster.confidence
            ))
        }
        return groups
    }
}
