//
//  UnionFind.swift
//  Reclaim
//
//  Document 06 §2 step 7: pairwise "similar" edges within a bucket are
//  merged via union-find (disjoint-set) into connected components. This
//  correctly handles a burst of 5 photos where photo 1 vs. photo 5 might
//  exceed the pairwise threshold but a chain of adjacent pairwise matches
//  ties them into one group — near-linear, no O(n²) all-pairs pass needed
//  at the clustering stage either.
//

import Foundation

struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ x: Int) -> Int {
        if parent[x] != x {
            parent[x] = find(parent[x]) // path compression
        }
        return parent[x]
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }
        if rank[rootA] < rank[rootB] {
            parent[rootA] = rootB
        } else if rank[rootA] > rank[rootB] {
            parent[rootB] = rootA
        } else {
            parent[rootB] = rootA
            rank[rootA] += 1
        }
    }

    /// Groups of original indices sharing a root, in ascending root order.
    /// Singleton "groups" (an index that never unioned with anything) are
    /// excluded by the caller (PhotoClustering) since a group of one is not
    /// a duplicate/similar group at all (Document 06 §2 step 7: "a bucket
    /// with no pairs under threshold produces zero groups").
    func components(count: Int) -> [[Int]] {
        var mutableSelf = self
        var buckets: [Int: [Int]] = [:]
        for i in 0..<count {
            let root = mutableSelf.find(i)
            buckets[root, default: []].append(i)
        }
        return buckets.values.sorted { ($0.first ?? 0) < ($1.first ?? 0) }
    }
}

/// Pure clustering logic over an array of perceptual hashes — takes hashes
/// in, returns index groups + confidence out. No PhotoKit/CoreImage
/// dependency, so it's testable with synthetic UInt64 fixtures
/// (Document 08 §1 "Similarity thresholds & clustering").
enum PhotoClustering {
    struct Cluster {
        let indices: [Int]
        /// confidence = 1 - (averagePairwiseHammingDistance / 64), an
        /// honest, directly-computed number (Document 06 §2 step 8).
        let confidence: Double
    }

    /// Clusters `hashes` (all assumed to already be in the same metadata
    /// bucket — SimilarityDetector's job upstream) into groups where every
    /// member is transitively connected via pairwise Hamming distance
    /// within `HammingDistance.similarityThreshold`.
    static func cluster(hashes: [UInt64]) -> [Cluster] {
        guard hashes.count > 1 else { return [] }

        var uf = UnionFind(count: hashes.count)
        var pairwiseDistances: [String: Int] = [:] // "i-j" -> distance, for confidence calc

        for i in 0..<hashes.count {
            for j in (i + 1)..<hashes.count {
                let d = HammingDistance.distance(hashes[i], hashes[j])
                if d <= HammingDistance.similarityThreshold {
                    uf.union(i, j)
                    pairwiseDistances["\(i)-\(j)"] = d
                }
            }
        }

        let components = uf.components(count: hashes.count).filter { $0.count > 1 }

        return components.map { indices in
            let indexSet = Set(indices)
            let relevantDistances = pairwiseDistances.compactMap { key, value -> Int? in
                let parts = key.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 2 else { return nil }
                guard indexSet.contains(parts[0]) && indexSet.contains(parts[1]) else { return nil }
                return value
            }
            let avgDistance = relevantDistances.isEmpty
                ? 0.0
                : Double(relevantDistances.reduce(0, +)) / Double(relevantDistances.count)
            let confidence = 1.0 - (avgDistance / 64.0)
            return Cluster(indices: indices.sorted(), confidence: confidence)
        }
    }
}
