//
//  HammingDistanceAndClusteringTests.swift
//  ReclaimTests
//
//  Document 08 §1: Hamming distance correctness, threshold behavior, and
//  the transitive-chain clustering property (A~B~C groups even if A vs C
//  individually exceeds the threshold).
//

import XCTest
@testable import Reclaim

final class HammingDistanceTests: XCTestCase {

    func test_distance_identicalValues_isZero() {
        XCTAssertEqual(HammingDistance.distance(0xFF00FF00, 0xFF00FF00), 0)
    }

    func test_distance_knownValue() {
        // 0b0000 vs 0b1111 -> 4 differing bits
        XCTAssertEqual(HammingDistance.distance(0b0000, 0b1111), 4)
    }

    func test_distance_isSymmetric() {
        let a: UInt64 = 0x1234
        let b: UInt64 = 0x5678
        XCTAssertEqual(HammingDistance.distance(a, b), HammingDistance.distance(b, a))
    }

    func test_isSimilar_respectsThreshold() {
        // Craft two values differing in exactly 5 bits (at threshold, should pass).
        let a: UInt64 = 0
        let b: UInt64 = 0b11111 // 5 bits set
        XCTAssertEqual(HammingDistance.distance(a, b), 5)
        XCTAssertTrue(HammingDistance.isSimilar(a, b))

        let c: UInt64 = 0b111111 // 6 bits set — over threshold
        XCTAssertFalse(HammingDistance.isSimilar(a, c))
    }
}

final class PhotoClusteringTests: XCTestCase {

    func test_cluster_emptyOrSingle_returnsNoGroups() {
        XCTAssertEqual(PhotoClustering.cluster(hashes: []).count, 0)
        XCTAssertEqual(PhotoClustering.cluster(hashes: [0x1]).count, 0)
    }

    func test_cluster_allDissimilar_returnsNoGroups() {
        // Values chosen to be far apart (>5 bit distance from each other).
        let hashes: [UInt64] = [0x0000000000000000, 0x00000000000000FF, 0xFFFFFFFF00000000]
        let clusters = PhotoClustering.cluster(hashes: hashes)
        XCTAssertEqual(clusters.count, 0)
    }

    func test_cluster_twoSimilarValues_oneGroup() {
        let a: UInt64 = 0
        let b: UInt64 = 0b111 // distance 3, under threshold
        let clusters = PhotoClustering.cluster(hashes: [a, b])
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(Set(clusters[0].indices), Set([0, 1]))
    }

    func test_cluster_transitiveChain_mergesIntoOneGroup() {
        // A vs C exceeds the threshold directly, but A~B (distance <=5) and
        // B~C (distance <=5) should still transitively merge all three into
        // one cluster via union-find (Document 06 §2 step 7).
        let a: UInt64 = 0b000000 // 0
        let b: UInt64 = 0b000011 // distance from a: 2
        let c: UInt64 = 0b001111 // distance from b: 2, distance from a: 4 (still under 5 here, so use a value where a-c direct actually breaks threshold)

        // Construct explicit distances using distinct bit positions so a-c
        // truly exceeds the threshold while a-b and b-c do not.
        let x: UInt64 = 0
        let y: UInt64 = 0b0000000000011111 // 5 bits set, distance(x,y) = 5, still similar
        let z: UInt64 = 0b1111100000011111 // shares y's 5 bits, adds 5 more -> distance(x,z) = 10 (not similar), distance(y,z) = 5 (similar)

        XCTAssertFalse(HammingDistance.isSimilar(x, z)) // direct pair would NOT cluster alone
        XCTAssertTrue(HammingDistance.isSimilar(x, y))
        XCTAssertTrue(HammingDistance.isSimilar(y, z))

        let clusters = PhotoClustering.cluster(hashes: [x, y, z])
        XCTAssertEqual(clusters.count, 1, "x, y, z should transitively merge into a single cluster via the x-y and y-z edges")
        XCTAssertEqual(Set(clusters[0].indices), Set([0, 1, 2]))

        _ = (a, b, c) // silence unused-variable warnings from the illustrative values above
    }

    func test_cluster_confidenceIsWithinValidRange() {
        let a: UInt64 = 0
        let b: UInt64 = 0b111
        let clusters = PhotoClustering.cluster(hashes: [a, b])
        XCTAssertGreaterThanOrEqual(clusters[0].confidence, 0.0)
        XCTAssertLessThanOrEqual(clusters[0].confidence, 1.0)
    }
}
