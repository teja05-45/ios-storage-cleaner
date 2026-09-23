//
//  PerceptualHash.swift
//  Reclaim
//
//  Document 06 §2 step 3-4, Document 04 §1 ("hashing math, pure, testable,
//  no PhotoKit"). This file contains ONLY the bit-encoding math over an
//  already-extracted grayscale brightness grid. Extracting that grid from a
//  real PHAsset thumbnail (resize/grayscale via CoreImage/vImage) is the
//  Services layer's job (SimilarityDetector) — kept out of Core so this
//  logic is testable with synthetic fixtures in milliseconds, no simulator
//  photo library needed (Document 03 §4).
//

import Foundation

enum PerceptualHash {
    /// dHash ("difference hash") — chosen over average-hash for better
    /// resilience to minor exposure/brightness shifts (common between burst
    /// shots), and over a DCT-based pHash for lower CPU cost at comparable
    /// accuracy for this use case (Document 06 §2 step 4).
    ///
    /// - Parameter grid: an 9-columns × 8-rows grayscale brightness grid
    ///   (values 0...255), row-major, `grid.count == 8`, each row
    ///   `grid[r].count == 9`. The extra column is what makes 8 horizontal
    ///   adjacent-pixel comparisons possible per row (9 columns → 8 gaps),
    ///   producing exactly 64 bits (8 rows × 8 bits).
    /// - Returns: a 64-bit fingerprint where bit `(row * 8 + col)` is 1 if
    ///   `grid[row][col] < grid[row][col + 1]` ("this pixel is darker than
    ///   its right neighbor"), 0 otherwise.
    static func dHash(fromGrayscaleGrid grid: [[UInt8]]) -> UInt64? {
        guard grid.count == 8 else { return nil }
        guard grid.allSatisfy({ $0.count == 9 }) else { return nil }

        var hash: UInt64 = 0
        var bitIndex = 0
        for row in grid {
            for col in 0..<8 {
                let left = row[col]
                let right = row[col + 1]
                if left < right {
                    hash |= (1 << UInt64(bitIndex))
                }
                bitIndex += 1
            }
        }
        return hash
    }
}
