//
//  CleanupSelectionTests.swift
//  ReclaimTests
//

import XCTest
@testable import Reclaim

final class CleanupSelectionTests: XCTestCase {

    func test_emptySelection_isEmptyTrue() {
        XCTAssertTrue(CleanupSelection().isEmpty)
        XCTAssertEqual(CleanupSelection().totalItemCount, 0)
    }

    func test_totalItemCount_sumsAllCategories() {
        let selection = CleanupSelection(
            photoAssetIDs: ["p1", "p2"],
            screenshotAssetIDs: ["s1"],
            videoAssetIDs: ["v1", "v2", "v3"],
            contactIDs: ["c1"]
        )
        XCTAssertEqual(selection.totalItemCount, 7)
        XCTAssertFalse(selection.isEmpty)
    }

    func test_allPhotoKitAssetIDs_unionsPhotoScreenshotVideo_excludesContacts() {
        let selection = CleanupSelection(
            photoAssetIDs: ["p1"],
            screenshotAssetIDs: ["s1"],
            videoAssetIDs: ["v1"],
            contactIDs: ["c1"]
        )
        XCTAssertEqual(selection.allPhotoKitAssetIDs, Set(["p1", "s1", "v1"]))
        XCTAssertFalse(selection.allPhotoKitAssetIDs.contains("c1"))
    }

    func test_cleanupSummary_hadPartialFailure() {
        let summary = CleanupSummary(
            requested: CleanupSelection(photoAssetIDs: ["a"]),
            deletedPhotoCount: 0, deletedVideoCount: 0, deletedScreenshotCount: 0, deletedContactCount: 0,
            bytesFreed: 0,
            failures: [.photo(id: "a", reason: .staleAsset)]
        )
        XCTAssertTrue(summary.hadPartialFailure)
        XCTAssertEqual(summary.totalDeletedCount, 0)
    }

    func test_cleanupSummary_noFailures_hadPartialFailureFalse() {
        let summary = CleanupSummary(
            requested: CleanupSelection(photoAssetIDs: ["a"]),
            deletedPhotoCount: 1, deletedVideoCount: 0, deletedScreenshotCount: 0, deletedContactCount: 0,
            bytesFreed: 1000,
            failures: []
        )
        XCTAssertFalse(summary.hadPartialFailure)
        XCTAssertEqual(summary.totalDeletedCount, 1)
    }
}
