//
//  DetectionPipelineTests.swift
//  ReclaimTests
//
//  Two contracts these suites previously left unpinned:
//
//  1. BUG-01 regression: detector-built groups must carry the REAL byte
//     sizes resolved during bucketing/scoring — not the enumeration-time
//     placeholder 0. A 0-byte member silently under-reports every
//     recoverable-bytes estimate the user sees (Dashboard card, group
//     rows, Review totals).
//
//  2. Deterministic performance envelopes (CI regression tripwires):
//     synthetic, fixed inputs; generous wall-clock ceilings that fire only
//     on algorithmic blowups (e.g. an accidental all-pairs regression).
//     These are NOT device benchmarks and predict nothing about real-
//     library performance on an iPhone (docs/26, §Limitations).
//

import XCTest
import CoreGraphics
@testable import Reclaim

final class DetectionPipelineTests: XCTestCase {

    // MARK: - Fixtures

    private func photo(id: String, secondsAfterBase: Double = 0, screenshot: Bool = false) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: Date(timeIntervalSince1970: 1_000_000 + secondsAfterBase),
            pixelSize: CGSize(width: 100, height: 100),
            byteSize: 0, // enumeration-time placeholder — the pipeline must replace it
            isScreenshot: screenshot,
            mediaType: .photo
        )
    }

    /// An all-gradient 9x8 grayscale grid: every horizontal comparison is
    /// "darker than right neighbor", so dHash yields all 64 bits set — a
    /// deterministic fixture for the encoding pass.
    private static let gradientGrid: [[UInt8]] = (0..<8).map { _ in
        (0..<9).map { UInt8($0 * 20) }
    }

    // MARK: - BUG-01 regression: exact duplicates carry real sizes

    func test_exactDuplicateGroup_membersCarryRealByteSizes_notZero() async throws {
        let detector = DuplicateDetector()
        let service = FakePhotoLibraryService()
        service.byteSizes = ["a": 123_456, "b": 123_456] // same size ⇒ same bucket
        service.contentHashes = ["a": "deadbeef", "b": "deadbeef"]

        let groups = try await detector.detectExactDuplicates(
            in: [photo(id: "a"), photo(id: "b")],
            photoLibrary: service
        )

        XCTAssertEqual(groups.count, 1)
        let sizes = Dictionary(uniqueKeysWithValues: groups[0].members.map { ($0.id, $0.byteSize) })
        XCTAssertEqual(sizes["a"], 123_456, "group members must carry the size resolved during bucketing (BUG-01)")
        XCTAssertEqual(sizes["b"], 123_456, "group members must carry the size resolved during bucketing (BUG-01)")
        // recoverableBytes counts SELECTED members only — a freshly detected
        // group legitimately reports 0. The user-facing behavior under test:
        // once a member is selected, its REAL size counts, never 0.
        var group = groups[0]
        let memberID = group.members[1].id // non-keep member (keep is the id-sorted first)
        group.toggleSelection(for: memberID)
        XCTAssertEqual(group.recoverableBytes, 123_456,
                       "selecting one member must report the real resolved bytes, not 0 (BUG-01)")
    }

    // MARK: - BUG-01 regression: similar groups carry real sizes

    func test_similarGroup_membersCarryRealByteSizes_notZero() async throws {
        let service = FakePhotoLibraryService()
        service.byteSizes = ["s1": 1_500, "s2": 2_500]
        service.scriptedThumbnails = [
            "s1": ThumbnailPixels(dHashGrid: Self.gradientGrid, sharpnessRaw: 10, exposureRaw: 0.9),
            "s2": ThumbnailPixels(dHashGrid: Self.gradientGrid, sharpnessRaw: 12, exposureRaw: 0.8)
        ]
        let detector = SimilarityDetector()

        let groups = try await detector.detectSimilarGroups(
            in: [photo(id: "s1", secondsAfterBase: 0), photo(id: "s2", secondsAfterBase: 30)],
            photoLibrary: service
        )

        XCTAssertEqual(groups.count, 1, "identical deterministic hashes must form one cluster")
        let sizes = Dictionary(uniqueKeysWithValues: groups[0].members.map { ($0.id, $0.byteSize) })
        XCTAssertEqual(sizes["s1"], 1_500, "group members must carry the size resolved during scoring (BUG-01)")
        XCTAssertEqual(sizes["s2"], 2_500, "group members must carry the size resolved during scoring (BUG-01)")
    }

    // MARK: - Deterministic performance envelopes (CI tripwires, not benchmarks)

    /// dHash encoding over 2,000 fixed synthetic grids. Asserts encoding
    /// correctness (a pure gradient is all 64 bits set) and stays within a
    /// generous wall-clock ceiling that only fires on algorithmic blowups.
    func test_hashEncodingPerformance_2000Grids_staysInEnvelope() throws {
        let grids = Array(repeating: Self.gradientGrid, count: 2_000)

        let start = Date()
        let encoded = grids.compactMap { PerceptualHash.dHash(fromGrayscaleGrid: $0) }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(encoded.count, 2_000)
        XCTAssertTrue(encoded.allSatisfy { $0 == UInt64.max },
                      "the pure-gradient fixture must encode to all 64 bits set")
        XCTAssertLessThan(elapsed, 10.0,
                          "dHash encoding of 2,000 grids exceeded the regression envelope (\(elapsed)s)")
    }

    /// Clustering 2,000 hashes organized as 100 provably-separated families
    /// of 20. Code construction: each family f (0..<100) spreads its 7
    /// information bits as 8-bit runs (positions 0..55), so distinct
    /// families differ by ≥ 8 Hamming bits; the 2-bit member tag (positions
    /// 56-57) keeps intra-family distance ≤ 2. With the similarity
    /// threshold at ≤ 5, no cross-family pair can ever merge, so the
    /// cluster count must be EXACTLY 100 — and the run must stay inside the
    /// wall-clock envelope (the real cost is milliseconds).
    func test_clusterPerformance_2000Hashes_100Families_staysInEnvelope() {
        var hashes: [UInt64] = []
        hashes.reserveCapacity(2_000)
        for family in 0..<100 {
            var base: UInt64 = 0
            for k in 0..<7 where (family >> k) & 1 == 1 {
                base |= ((1 << 8) - 1) << (k * 8)
            }
            for member in 0..<20 {
                hashes.append(base | (UInt64(member % 4) << 56))
            }
        }

        // Verify the fixture's separation property itself before relying on it.
        let firstFamilyBase = hashes[0] & ~(UInt64(3) << 56)
        let secondFamilyBase = hashes[20] & ~(UInt64(3) << 56)
        XCTAssertGreaterThanOrEqual(HammingDistance.distance(firstFamilyBase, secondFamilyBase), 8,
                                    "fixture families must be provably non-mergeable at threshold 5")

        let start = Date()
        let clusters = PhotoClustering.cluster(hashes: hashes)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(clusters.count, 100,
                       "100 separated families must produce exactly 100 clusters — a different count means the grouping math changed")
        XCTAssertLessThan(elapsed, 10.0,
                          "clustering 2,000 hashes exceeded the regression envelope (\(elapsed)s)")
    }

    /// Contact normalization (phone/email) + name similarity scoring over
    /// 2,000 deterministic synthetic contacts. Pure Foundation, no Contacts
    /// framework. Ceiling is generous — the tripwire fires only on a
    /// quadratic-or-worse regression.
    func test_contactNormalizationPerformance_2000Contacts_staysInEnvelope() {
        let start = Date()
        for i in 0..<2_000 {
            let suffix = String(format: "%04d", i % 10_000)
            let phone = "+1 (555) 0\(i % 10)0-\(suffix)"
            let normalized = ContactNormalizer.normalizePhone(phone)
            XCTAssertNotNil(normalized)
            XCTAssertEqual(normalized?.last10.count, 10)

            let email = "user\(i)@example.com"
            XCTAssertFalse(ContactNormalizer.normalizeEmail(email).isEmpty)

            // Deliberately the expensive path: full Levenshtein over
            // reordered tokens (token-set canonical form).
            let score = NameSimilarity.score("Alex Morgan \(i)", "Morgan, Alex \(i)")
            XCTAssertTrue(score >= 0.0 && score <= 1.0)
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 10.0,
                          "normalization+similarity over 2,000 contacts exceeded the regression envelope (\(elapsed)s)")
    }
}
