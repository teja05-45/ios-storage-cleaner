//
//  ImagePixelExtractor.swift
//  Reclaim
//
//  Document 06 §2 step 3, §3. Converts a small CGImage thumbnail into:
//   1. A 9x8 grayscale grid for PerceptualHash.dHash (Core/Utilities).
//   2. A Laplacian-variance sharpness measure (classical focus-measure
//      operator, computed via a manual 3x3 convolution over a slightly
//      larger grayscale downsample — small enough to stay cheap per
//      Document 09 §2, since this always runs on a thumbnail, never a
//      full-resolution image).
//   3. An exposure measure: proportion of near-clipped (very dark/very
//      bright) pixels, inverted so higher = better exposed.
//
//  This is intentionally in Services, not Core — it's the one place
//  CoreGraphics/Accelerate-flavored pixel extraction happens, keeping
//  Core/Utilities/PerceptualHash.swift and BestPhotoScoring.swift pure and
//  testable with synthetic fixtures (Document 04 §1 module map).
//

import Foundation
import CoreGraphics
import Accelerate

enum ImagePixelExtractor {

    /// dHash grid target: 9 columns x 8 rows (Document 06 §2 step 3).
    private static let dHashWidth = 9
    private static let dHashHeight = 8

    /// A separate, slightly larger downsample used for sharpness/exposure,
    /// since dHash's 9x8 grid is too coarse for a meaningful focus measure.
    private static let analysisSide = 32

    static func extract(from cgImage: CGImage) -> ThumbnailPixels? {
        guard let dHashGrid = grayscaleGrid(from: cgImage, width: dHashWidth, height: dHashHeight) else {
            return nil
        }
        guard let analysisGrid = grayscaleGrid(from: cgImage, width: analysisSide, height: analysisSide) else {
            return ThumbnailPixels(dHashGrid: dHashGrid, sharpnessRaw: 0, exposureRaw: 0)
        }

        let sharpness = laplacianVariance(analysisGrid, width: analysisSide, height: analysisSide)
        let exposure = exposureScore(analysisGrid)

        return ThumbnailPixels(dHashGrid: dHashGrid, sharpnessRaw: sharpness, exposureRaw: exposure)
    }

    // MARK: - Grayscale downsample

    /// Resizes `cgImage` to `width` x `height` and returns row-major
    /// grayscale brightness values (0...255) using CoreGraphics' own
    /// grayscale color space for the draw — this is the resize+grayscale
    /// step Document 06 §2 step 3 specifies via CoreImage/vImage; using a
    /// CGContext draw into a grayscale bitmap achieves the same result with
    /// fewer moving parts and no extra CoreImage context setup cost per call.
    private static func grayscaleGrid(from cgImage: CGImage, width: Int, height: Int) -> [[UInt8]]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)

        var grid: [[UInt8]] = []
        grid.reserveCapacity(height)
        for row in 0..<height {
            var rowValues: [UInt8] = []
            rowValues.reserveCapacity(width)
            for col in 0..<width {
                rowValues.append(buffer[row * width + col])
            }
            grid.append(rowValues)
        }
        return grid
    }

    // MARK: - Sharpness (Laplacian variance)

    /// Classical focus-measure operator: convolve with the discrete
    /// Laplacian kernel [[0,1,0],[1,-4,1],[0,1,0]], then take the variance
    /// of the response. Higher variance = more high-frequency detail = sharper.
    private static func laplacianVariance(_ grid: [[UInt8]], width: Int, height: Int) -> Double {
        guard width >= 3, height >= 3 else { return 0 }

        var responses: [Double] = []
        responses.reserveCapacity((width - 2) * (height - 2))

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Double(grid[y][x])
                let up = Double(grid[y - 1][x])
                let down = Double(grid[y + 1][x])
                let left = Double(grid[y][x - 1])
                let right = Double(grid[y][x + 1])
                let response = up + down + left + right - (4 * center)
                responses.append(response)
            }
        }

        guard !responses.isEmpty else { return 0 }
        let mean = responses.reduce(0, +) / Double(responses.count)
        let variance = responses.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(responses.count)
        return variance
    }

    // MARK: - Exposure

    /// Proportion of near-clipped pixels (< 10 or > 245 out of 255),
    /// inverted so a higher score means better exposed.
    private static func exposureScore(_ grid: [[UInt8]]) -> Double {
        let allPixels = grid.flatMap { $0 }
        guard !allPixels.isEmpty else { return 0 }

        let clippedCount = allPixels.filter { $0 < 10 || $0 > 245 }.count
        let clippedProportion = Double(clippedCount) / Double(allPixels.count)
        return 1.0 - clippedProportion
    }
}
