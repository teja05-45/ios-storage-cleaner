//
//  PerceptualHashTests.swift
//  ReclaimTests
//
//  Document 08 §1: determinism, identical→0 distance, known cases.
//

import XCTest
@testable import Reclaim

final class PerceptualHashTests: XCTestCase {

    func test_dHash_returnsNilForWrongGridDimensions() {
        let tooFewRows: [[UInt8]] = Array(repeating: Array(repeating: 128, count: 9), count: 7)
        XCTAssertNil(PerceptualHash.dHash(fromGrayscaleGrid: tooFewRows))

        let tooFewCols: [[UInt8]] = Array(repeating: Array(repeating: 128, count: 8), count: 8)
        XCTAssertNil(PerceptualHash.dHash(fromGrayscaleGrid: tooFewCols))
    }

    func test_dHash_isDeterministic() {
        let grid = makeGradientGrid()
        let hash1 = PerceptualHash.dHash(fromGrayscaleGrid: grid)
        let hash2 = PerceptualHash.dHash(fromGrayscaleGrid: grid)
        XCTAssertEqual(hash1, hash2)
    }

    func test_dHash_identicalImages_zeroDistance() {
        let gridA = makeGradientGrid()
        let gridB = makeGradientGrid()
        let hashA = PerceptualHash.dHash(fromGrayscaleGrid: gridA)!
        let hashB = PerceptualHash.dHash(fromGrayscaleGrid: gridB)!
        XCTAssertEqual(HammingDistance.distance(hashA, hashB), 0)
    }

    func test_dHash_flatImage_allBitsZero() {
        // Every pixel identical -> left is never < right -> hash is all zeros.
        let flat: [[UInt8]] = Array(repeating: Array(repeating: 100, count: 9), count: 8)
        let hash = PerceptualHash.dHash(fromGrayscaleGrid: flat)
        XCTAssertEqual(hash, 0)
    }

    func test_dHash_knownBitPattern() {
        // Row of strictly increasing values -> every left<right -> all 8 bits set for that row.
        var grid: [[UInt8]] = []
        for _ in 0..<8 {
            grid.append([0, 10, 20, 30, 40, 50, 60, 70, 80])
        }
        let hash = PerceptualHash.dHash(fromGrayscaleGrid: grid)!
        XCTAssertEqual(hash, 0xFFFFFFFFFFFFFFFF) // all 64 bits set
    }

    func test_dHash_distinctImages_producesNonzeroDistance() {
        let gridA = makeGradientGrid()
        var gridB = gridA
        gridB[0][0] = 255
        gridB[0][1] = 0
        let hashA = PerceptualHash.dHash(fromGrayscaleGrid: gridA)!
        let hashB = PerceptualHash.dHash(fromGrayscaleGrid: gridB)!
        XCTAssertGreaterThan(HammingDistance.distance(hashA, hashB), 0)
    }

    // MARK: - Helpers

    private func makeGradientGrid() -> [[UInt8]] {
        (0..<8).map { row in
            (0..<9).map { col in UInt8((row * 9 + col) % 256) }
        }
    }
}
