//
//  HammingDistance.swift
//  Reclaim
//
//  Document 06 §2 step 5: XOR + popcount — cheap UInt64 bitwise op. This is
//  the only "compare everything" step in the similarity pipeline, and it's
//  restricted to an already-small metadata bucket by SimilarityDetector, so
//  it stays fast even in the worst case (Document 09 §2).
//

import Foundation

enum HammingDistance {
    /// Number of differing bits between two 64-bit hashes, 0...64.
    static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Threshold chosen conservatively (favoring precision over recall) per
    /// Document 06 §2 step 6: distances of 0-4 reliably indicate
    /// near-identical images in published dHash literature; 5 is set
    /// slightly below the common upper bound to keep the false-positive
    /// rate low. Centralized here (not duplicated at call sites) so it is a
    /// single, documented, tunable constant — never a magic number buried
    /// in comparison code (this build's instructions §5 "Keep thresholds
    /// centralized/configurable").
    static let similarityThreshold = 5

    static func isSimilar(_ a: UInt64, _ b: UInt64) -> Bool {
        distance(a, b) <= similarityThreshold
    }
}
