//
//  DuplicateDetector.swift
//  Reclaim
//
//  Document 06 §1: dimensions+size bucketing (cheap prefilter) then
//  streamed SHA-256 verification within each bucket — never SHA-256 across
//  the whole library, and never a thumbnail hash mistaken for proof of
//  exact duplication (this build's instructions §5 "Do not use a thumbnail
//  hash as proof of exact duplication").
//

import Foundation

protocol DuplicateDetectorProtocol: Sendable {
    func detectExactDuplicates(in assets: [PhotoAsset], photoLibrary: PhotoLibraryServiceProtocol) async throws -> [PhotoGroup]
}

struct DuplicateDetector: DuplicateDetectorProtocol {

    func detectExactDuplicates(in assets: [PhotoAsset], photoLibrary: PhotoLibraryServiceProtocol) async throws -> [PhotoGroup] {
        // Step 1: cheap prefilter — bucket by (pixel width, pixel height).
        // Byte size isn't known yet at this point in the pipeline (fetched
        // lazily), so dimensions alone form the first bucket; size is
        // folded in as the buckets are resolved below.
        var dimensionBuckets: [String: [PhotoAsset]] = [:]
        for asset in assets {
            let key = "\(Int(asset.pixelSize.width))x\(Int(asset.pixelSize.height))"
            dimensionBuckets[key, default: []].append(asset)
        }

        var groups: [PhotoGroup] = []

        for (_, bucketAssets) in dimensionBuckets where bucketAssets.count > 1 {
            // Step 2: refine by byte size within the dimension bucket —
            // cheap, no content read yet.
            var sizeBuckets: [Int64: [PhotoAsset]] = [:]
            for asset in bucketAssets {
                let size = try await photoLibrary.resourceByteSize(forAssetID: asset.id)
                sizeBuckets[size, default: []].append(asset)
            }

            for (_, sizeGroup) in sizeBuckets where sizeGroup.count > 1 {
                // Step 3: only now, within a small same-dimension/same-size
                // candidate set, verify true content equality via streamed
                // SHA-256 — the expensive step is bounded to genuine
                // candidates, never the whole library (Document 09 §2).
                var hashBuckets: [String: [PhotoAsset]] = [:]
                for asset in sizeGroup {
                    let hash = try await photoLibrary.contentHash(forAssetID: asset.id)
                    hashBuckets[hash, default: []].append(asset)
                }

                for (_, exactMatches) in hashBuckets where exactMatches.count > 1 {
                    // Recommended keep: earliest creationDate (most likely
                    // "the original"), ties broken by asset ID for
                    // determinism.
                    let sorted = exactMatches.sorted {
                        switch ($0.creationDate, $1.creationDate) {
                        case let (a?, b?): return a == b ? $0.id < $1.id : a < b
                        case (nil, _?): return false
                        case (_?, nil): return true
                        case (nil, nil): return $0.id < $1.id
                        }
                    }
                    let keepID = sorted[0].id
                    groups.append(PhotoGroup(
                        kind: .exactDuplicate,
                        members: exactMatches,
                        recommendedKeepID: keepID,
                        confidence: 1.0 // byte-identical content hash — no ambiguity
                    ))
                }
            }
        }

        return groups
    }
}
