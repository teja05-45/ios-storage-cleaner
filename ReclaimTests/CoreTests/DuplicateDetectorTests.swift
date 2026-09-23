//
//  DuplicateDetectorTests.swift
//  ReclaimTests
//
//  Closes the audit's second documented coverage gap: DuplicateDetector's
//  bucketing was untested. With the fake photo-library service now
//  scriptable (byte sizes + content hashes per asset ID), the full
//  bucket → refine → verify pipeline runs without PhotoKit (Document 03 §7).
//

import XCTest
import CoreGraphics
@testable import Reclaim

final class DuplicateDetectorTests: XCTestCase {

    private func asset(id: String, width: Int, height: Int) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: nil,
            pixelSize: CGSize(width: width, height: height),
            byteSize: 0,
            isScreenshot: false,
            mediaType: .photo
        )
    }

    private func makeService(
        byteSizes: [String: Int64],
        hashes: [String: String]
    ) -> FakePhotoLibraryService {
        let service = FakePhotoLibraryService()
        service.byteSizes = byteSizes
        service.contentHashes = hashes
        return service
    }

    func test_identicalHashSameDimensions_groupAsExactDuplicate() async throws {
        let detector = DuplicateDetector()
        let service = makeService(
            byteSizes: ["a": 100, "b": 100],
            hashes: ["a": "deadbeef", "b": "deadbeef"]
        )
        let groups = try await detector.detectExactDuplicates(
            in: [asset(id: "a", width: 100, height: 100), asset(id: "b", width: 100, height: 100)],
            photoLibrary: service
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].kind, .exactDuplicate)
        XCTAssertEqual(Set(groups[0].members.map(\.id)), ["a", "b"])
        XCTAssertEqual(groups[0].confidence, 1.0)
    }

    func test_differentHashes_sameDimensionsAndSize_neverGrouped() async throws {
        let detector = DuplicateDetector()
        let service = makeService(
            byteSizes: ["a": 100, "b": 100],
            hashes: ["a": "aaaa", "b": "bbbb"]
        )
        let groups = try await detector.detectExactDuplicates(
            in: [asset(id: "a", width: 100, height: 100), asset(id: "b", width: 100, height: 100)],
            photoLibrary: service
        )

        XCTAssertTrue(groups.isEmpty, "Different content hashes are not duplicates, whatever the metadata says")
    }

    func test_sameHashButDifferentDimensions_neverGrouped() async throws {
        let detector = DuplicateDetector()
        let service = makeService(
            byteSizes: ["a": 100, "b": 100],
            hashes: ["a": "deadbeef", "b": "deadbeef"]
        )
        let groups = try await detector.detectExactDuplicates(
            in: [asset(id: "a", width: 100, height: 100), asset(id: "b", width: 200, height: 200)],
            photoLibrary: service
        )

        XCTAssertTrue(groups.isEmpty, "The dimension prefilter must gate the hash comparison — different dimensions are never exact duplicates")
    }

    func test_sameDimensionsSameHashButDifferentByteSize_neverGrouped() async throws {
        let detector = DuplicateDetector()
        let service = makeService(
            byteSizes: ["a": 100, "b": 200],
            hashes: ["a": "deadbeef", "b": "deadbeef"]
        )
        let groups = try await detector.detectExactDuplicates(
            in: [asset(id: "a", width: 100, height: 100), asset(id: "b", width: 100, height: 100)],
            photoLibrary: service
        )

        XCTAssertTrue(groups.isEmpty, "The size refinement must gate hash verification")
    }

    func test_uniqueAssets_produceNoGroups() async throws {
        let detector = DuplicateDetector()
        let service = makeService(
            byteSizes: ["a": 100, "b": 300],
            hashes: ["a": "h1", "b": "h2"]
        )
        let groups = try await detector.detectExactDuplicates(
            in: [asset(id: "a", width: 100, height: 100), asset(id: "b", width: 640, height: 480)],
            photoLibrary: service
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func test_contentHash_neverQueriedWithoutCandidatePartners() async throws {
        // Hashing is the expensive step and must be bounded to genuine
        // candidates: an asset that shares no dimension bucket with any
        // other asset can never be an exact duplicate, so its content must
        // never be read (Document 09 §2).
        let detector = DuplicateDetector()
        let service = makeService(
            byteSizes: ["a": 100, "b": 200],
            hashes: ["a": "h1", "b": "h2"]
        )
        _ = try await detector.detectExactDuplicates(
            in: [asset(id: "a", width: 100, height: 100), asset(id: "b", width: 640, height: 480)],
            photoLibrary: service
        )

        XCTAssertEqual(service.hashCallCount, 0, "No two assets share a bucket — no content may be hashed")
    }
}
