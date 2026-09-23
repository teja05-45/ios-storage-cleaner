//
//  ScreenshotOrderingTests.swift
//  ReclaimTests
//
//  Document 01 §3.3: screenshots are reviewed chronologically, most recent
//  first. The ordering lives as a static pure function so this contract is
//  directly testable — one of the audit's documented coverage gaps.
//

import XCTest
import CoreGraphics
@testable import Reclaim

final class ScreenshotOrderingTests: XCTestCase {

    private func screenshot(id: String, creationDate: Date?) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: creationDate,
            pixelSize: CGSize(width: 100, height: 200),
            byteSize: 1_000,
            isScreenshot: true,
            mediaType: .photo
        )
    }

    func test_orderMostRecentFirst_putsNewestScreenshotFirst() {
        let old = screenshot(id: "old", creationDate: Date(timeIntervalSince1970: 1_000))
        let new = screenshot(id: "new", creationDate: Date(timeIntervalSince1970: 2_000))

        let ordered = ScreenshotsView.orderMostRecentFirst([old, new])

        XCTAssertEqual(ordered.map(\.id), ["new", "old"])
    }

    func test_orderMostRecentFirst_undatedScreenshotsSortLastWithoutBeingDropped() {
        let dated = screenshot(id: "dated", creationDate: Date(timeIntervalSince1970: 1_000))
        let undated = screenshot(id: "undated", creationDate: nil)

        let ordered = ScreenshotsView.orderMostRecentFirst([undated, dated])

        XCTAssertEqual(ordered.map(\.id), ["dated", "undated"])
    }

    func test_orderMostRecentFirst_identicalDates_breakTiesByIDForDeterminism() {
        let date = Date(timeIntervalSince1970: 1_000)
        let a = screenshot(id: "a", creationDate: date)
        let b = screenshot(id: "b", creationDate: date)

        let ordered = ScreenshotsView.orderMostRecentFirst([b, a])

        XCTAssertEqual(ordered.map(\.id), ["a", "b"])
    }

    func test_orderMostRecentFirst_preservesAllAssets() {
        let assets = (0..<50).map { screenshot(id: "s\($0)", creationDate: Date(timeIntervalSince1970: TimeInterval($0))) }

        let ordered = ScreenshotsView.orderMostRecentFirst(assets)

        XCTAssertEqual(ordered.count, 50)
        XCTAssertEqual(Set(ordered.map(\.id)), Set(assets.map(\.id)))
    }
}
