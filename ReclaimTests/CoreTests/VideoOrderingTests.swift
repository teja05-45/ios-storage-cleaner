//
//  VideoOrderingTests.swift
//  ReclaimTests
//
//  Covers LargeVideosView's pure ordering contract (Document 02 §4.6:
//  largest-first by default, optional newest-first, deterministic ties).
//  Pure Foundation — no UI, no PhotoKit (Document 03 §7).
//

import XCTest
import CoreGraphics
@testable import Reclaim

@MainActor
final class VideoOrderingTests: XCTestCase {

    private func video(
        id: String,
        byteSize: Int64,
        creationDate: Date? = nil
    ) -> VideoAsset {
        VideoAsset(
            id: id,
            creationDate: creationDate,
            duration: 10,
            pixelSize: CGSize(width: 1920, height: 1080),
            byteSize: byteSize
        )
    }

    // MARK: - Largest first

    func test_largestFirst_sortsByByteSizeDescending() {
        let a = video(id: "a", byteSize: 100)
        let b = video(id: "b", byteSize: 300)
        let c = video(id: "c", byteSize: 200)

        let ordered = LargeVideosView.order([a, b, c], by: .largestFirst)

        XCTAssertEqual(ordered.map(\.id), ["b", "c", "a"])
    }

    func test_largestFirst_equalSizes_breakTiesByIDForDeterminism() {
        let x = video(id: "x", byteSize: 100)
        let y = video(id: "y", byteSize: 100)

        let ordered = LargeVideosView.order([y, x], by: .largestFirst)

        XCTAssertEqual(ordered.map(\.id), ["x", "y"])
    }

    // MARK: - Newest first

    func test_newestFirst_sortsByCreationDateDescending() {
        let old = video(id: "old", byteSize: 100, creationDate: Date(timeIntervalSince1970: 1_000))
        let new = video(id: "new", byteSize: 100, creationDate: Date(timeIntervalSince1970: 2_000))

        let ordered = LargeVideosView.order([old, new], by: .newestFirst)

        XCTAssertEqual(ordered.map(\.id), ["new", "old"])
    }

    func test_newestFirst_undatedAssetsSortLastWithoutBeingDropped() {
        let dated = video(id: "dated", byteSize: 100, creationDate: Date(timeIntervalSince1970: 1_000))
        let undated = video(id: "undated", byteSize: 100, creationDate: nil)

        let ordered = LargeVideosView.order([undated, dated], by: .newestFirst)

        XCTAssertEqual(ordered.map(\.id), ["dated", "undated"])
    }

    // MARK: - Default sort choice

    func test_defaultSortOrder_isLargestFirst() {
        // The picker's first case is the list's default — keeps the
        // UX-spec default (largest first) enforced by construction.
        XCTAssertEqual(LargeVideosView.SortOrder.allCases.first, .largestFirst)
    }
}
