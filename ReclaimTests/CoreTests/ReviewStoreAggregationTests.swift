//
//  ReviewStoreAggregationTests.swift
//  ReclaimTests
//
//  Closes the audit's documented coverage gap: no test asserted the
//  recoverable-bytes aggregation math in ReviewStore, nor that per-category
//  selection always equals `currentSelection`'s aggregation. These
//  invariants are what make "Review count == real selection count" true
//  (Document 04 ADR-03) — they deserve direct tests, not just transitively
//  via the safety suite.
//

import XCTest
import CoreGraphics
@testable import Reclaim

@MainActor
final class ReviewStoreAggregationTests: XCTestCase {

    private func asset(id: String, byteSize: Int64, screenshot: Bool = false) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: nil,
            pixelSize: CGSize(width: 100, height: 100),
            byteSize: byteSize,
            isScreenshot: screenshot,
            mediaType: .photo
        )
    }

    private func group(id: UUID, kind: PhotoGroupKind, members: [PhotoAsset], keepID: String) -> PhotoGroup {
        PhotoGroup(
            id: id,
            kind: kind,
            members: members,
            recommendedKeepID: keepID,
            confidence: 1.0
        )
    }

    // MARK: - estimatedRecoverableBytes

    func test_recoverableBytes_sumsSelectedAcrossAllCategories() {
        let store = ReviewStore()
        let g1 = group(id: UUID(), kind: .exactDuplicate, members: [asset(id: "a", byteSize: 10), asset(id: "b", byteSize: 20)], keepID: "a")
        let g2 = group(id: UUID(), kind: .similar, members: [asset(id: "c", byteSize: 40), asset(id: "d", byteSize: 80)], keepID: "c")
        store.loadPhotoResults(exactDuplicates: [g1], similar: [g2], scannedWithLimitedAccess: false)

        store.toggleExactDuplicateSelection(groupID: store.exactDuplicateGroups[0].id, assetID: "b")
        store.toggleSimilarPhotoSelection(groupID: store.similarPhotoGroups[0].id, assetID: "d")
        XCTAssertEqual(store.estimatedRecoverableBytes, 100, "20 + 80 bytes from the two selected non-keep assets")
    }

    func test_recoverableBytes_selectedScreenshotsAndVideosCounted() {
        let store = ReviewStore()
        store.loadScreenshots([asset(id: "s1", byteSize: 5, screenshot: true), asset(id: "s2", byteSize: 7, screenshot: true)])
        store.loadVideos([
            VideoAsset(id: "v1", creationDate: nil, duration: 1, pixelSize: .zero, byteSize: 500),
            VideoAsset(id: "v2", creationDate: nil, duration: 1, pixelSize: .zero, byteSize: 300)
        ])

        store.toggleScreenshotSelection(assetID: "s2")
        store.toggleVideoSelection(assetID: "v1")

        XCTAssertEqual(store.estimatedRecoverableBytes, 507)
    }

    // MARK: - currentSelection aggregation

    func test_currentSelection_matchesPerCategoryStateExactly() {
        let store = ReviewStore()
        let g = group(id: UUID(), kind: .exactDuplicate, members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2), asset(id: "c", byteSize: 3)], keepID: "a")
        store.loadPhotoResults(exactDuplicates: [g], similar: [], scannedWithLimitedAccess: false)

        store.toggleExactDuplicateSelection(groupID: store.exactDuplicateGroups[0].id, assetID: "b")
        store.toggleExactDuplicateSelection(groupID: store.exactDuplicateGroups[0].id, assetID: "c")

        let selection = store.currentSelection

        XCTAssertEqual(selection.photoAssetIDs, ["b", "c"])
        XCTAssertTrue(selection.screenshotAssetIDs.isEmpty)
        XCTAssertTrue(selection.videoAssetIDs.isEmpty)
        XCTAssertTrue(selection.contactIDs.isEmpty)
        XCTAssertEqual(selection.totalItemCount, 2)
    }

    func test_currentSelection_aggregatesAcrossExactAndSimilarWithoutOverlap() {
        let store = ReviewStore()
        let exact = group(id: UUID(), kind: .exactDuplicate, members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2)], keepID: "a")
        let similar = group(id: UUID(), kind: .similar, members: [asset(id: "c", byteSize: 3), asset(id: "d", byteSize: 4)], keepID: "c")
        store.loadPhotoResults(exactDuplicates: [exact], similar: [similar], scannedWithLimitedAccess: false)

        store.toggleExactDuplicateSelection(groupID: store.exactDuplicateGroups[0].id, assetID: "b")
        store.toggleSimilarPhotoSelection(groupID: store.similarPhotoGroups[0].id, assetID: "d")
        XCTAssertEqual(store.currentSelection.photoAssetIDs, ["b", "d"])
    }

    // MARK: - Per-item removal (used by the Review screen)

    func test_deselectPhoto_removesOnlyThatAsset() {
        let store = ReviewStore()
        let g = group(id: UUID(), kind: .exactDuplicate, members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2)], keepID: "a")
        store.loadPhotoResults(exactDuplicates: [g], similar: [], scannedWithLimitedAccess: false)
        store.toggleExactDuplicateSelection(groupID: store.exactDuplicateGroups[0].id, assetID: "b")
        store.deselectPhoto(assetID: "b")

        XCTAssertTrue(store.currentSelection.photoAssetIDs.isEmpty)
    }

    // MARK: - Bulk photo actions

    func test_selectAllRecommended_selectsEveryNonKeepAcrossBothGroupKinds() {
        let store = ReviewStore()
        let exact = group(id: UUID(), kind: .exactDuplicate, members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2)], keepID: "a")
        let similar = group(id: UUID(), kind: .similar, members: [asset(id: "c", byteSize: 3), asset(id: "d", byteSize: 4)], keepID: "c")
        store.loadPhotoResults(exactDuplicates: [exact], similar: [similar], scannedWithLimitedAccess: false)

        store.selectAllRecommendedInPhotoGroups()

        XCTAssertEqual(store.currentSelection.photoAssetIDs, ["b", "d"], "Both keeps ('a' and 'c') must remain unselected")
    }

    func test_deselectAllInPhotoGroups_clearsPhotoSelectionOnly() {
        let store = ReviewStore()
        let g = group(id: UUID(), kind: .exactDuplicate, members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2)], keepID: "a")
        store.loadPhotoResults(exactDuplicates: [g], similar: [], scannedWithLimitedAccess: false)
        store.loadScreenshots([asset(id: "s1", byteSize: 5, screenshot: true)])
        store.toggleExactDuplicateSelection(groupID: store.exactDuplicateGroups[0].id, assetID: "b")
        store.toggleScreenshotSelection(assetID: "s1")

        store.deselectAllInPhotoGroups()

        XCTAssertTrue(store.currentSelection.photoAssetIDs.isEmpty)
        XCTAssertEqual(store.currentSelection.screenshotAssetIDs, ["s1"], "Screenshot selection is a separate category and must not be touched")
    }
}
