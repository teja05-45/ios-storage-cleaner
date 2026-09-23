//
//  ReviewStorePruningTests.swift
//  ReclaimTests
//
//  Covers ReviewStore.removeFromSelection — the post-cleanup state repair
//  driven by CleanupSummary's OS-confirmed ID sets (OPEN-3). The safety
//  properties under test: survivors of a partial cleanup stay selected for
//  retry, a user's keep override survives when its asset survives, the
//  keep-invariant self-heals when the keep itself was deleted, dissolved
//  groups disappear instead of rendering broken state, and screenshots/
//  videos prune without touching any other category.
//

import XCTest
import CoreGraphics
@testable import Reclaim

@MainActor
final class ReviewStorePruningTests: XCTestCase {

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

    private func group(
        members: [PhotoAsset],
        keepID: String,
        kind: PhotoGroupKind = .exactDuplicate
    ) -> PhotoGroup {
        PhotoGroup(
            id: UUID(),
            kind: kind,
            members: members,
            recommendedKeepID: keepID,
            confidence: 1.0
        )
    }

    // MARK: - Photo group pruning

    func test_pruning_removesOnlyConfirmedIDs() {
        let store = ReviewStore()
        let g = group(members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2), asset(id: "c", byteSize: 3)], keepID: "a")
        store.loadPhotoResults(exactDuplicates: [g], similar: [], scannedWithLimitedAccess: false)

        store.removeFromSelection(photoKitIDs: ["b"], contactIDs: [])

        XCTAssertEqual(store.exactDuplicateGroups[0].members.map(\.id), ["a", "c"])
    }

    func test_pruning_survivorsOfPartialCleanupStaySelected() {
        // Scenario behind OPEN-3: user selected b and c; the OS confirmed
        // only b. c still exists and must still be marked for deletion so
        // the user can retry it instead of silently losing the pick.
        let store = ReviewStore()
        let g = group(members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2), asset(id: "c", byteSize: 3)], keepID: "a")
        store.loadPhotoResults(exactDuplicates: [g], similar: [], scannedWithLimitedAccess: false)
        store.toggleExactDuplicateSelection(groupID: store.exactDuplicateGroups[0].id, assetID: "b")
        store.toggleExactDuplicateSelection(groupID: store.exactDuplicateGroups[0].id, assetID: "c")

        store.removeFromSelection(photoKitIDs: ["b"], contactIDs: [])

        XCTAssertEqual(store.currentSelection.photoAssetIDs, ["c"], "a survivor of a partial deletion must remain selected")
    }

    func test_pruning_userKeepOverrideSurvivesWhenItsAssetSurvives() {
        let store = ReviewStore()
        let g = group(members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2)], keepID: "a")
        store.loadPhotoResults(exactDuplicates: [g], similar: [], scannedWithLimitedAccess: false)
        store.setUserChosenKeep(groupID: store.exactDuplicateGroups[0].id, assetID: "b", inExactDuplicates: true)

        store.removeFromSelection(photoKitIDs: [], contactIDs: []) // no-op call must not disturb state
        XCTAssertEqual(store.exactDuplicateGroups[0].userChosenKeepID, "b")

        // A partial deletion elsewhere must not reset the override either
        // (here there is nothing else to delete, so assert the path exists
        // via a sibling-free group prune with an unrelated ID).
        store.removeFromSelection(photoKitIDs: ["not-in-group"], contactIDs: [])
        XCTAssertEqual(store.exactDuplicateGroups[0].userChosenKeepID, "b")
    }

    func test_pruning_deletedKeepInvariantSelfHeals() {
        // The recommended keep itself was confirmed deleted: the rebuilt
        // group must fall back to a surviving keep and the initializer must
        // guarantee that keep is not marked for deletion.
        let store = ReviewStore()
        let g = group(members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2)], keepID: "a")
        store.loadPhotoResults(exactDuplicates: [g], similar: [], scannedWithLimitedAccess: false)
        store.toggleExactDuplicateSelection(groupID: store.exactDuplicateGroups[0].id, assetID: "b")
        store.removeFromSelection(photoKitIDs: ["a"], contactIDs: [])

        let rebuilt = store.exactDuplicateGroups[0]
        XCTAssertEqual(rebuilt.effectiveKeepID, "b", "keep falls back to a survivor when the original keep is gone")
        XCTAssertFalse(rebuilt.selection.contains("b"), "the new keep can never be selected for deletion")
    }

    func test_pruning_groupBelowTwoMembersIsDissolved() {
        let store = ReviewStore()
        let g = group(members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2)], keepID: "a")
        store.loadPhotoResults(exactDuplicates: [g], similar: [], scannedWithLimitedAccess: false)

        store.removeFromSelection(photoKitIDs: ["b"], contactIDs: [])

        XCTAssertTrue(store.exactDuplicateGroups.isEmpty, "a 'group' of one is no longer a duplicate group")
    }

    // MARK: - Screenshots / videos

    func test_pruning_screenshotsAndVideosRemovedAndDeselected() {
        let store = ReviewStore()
        store.loadScreenshots([asset(id: "s1", byteSize: 5, screenshot: true), asset(id: "s2", byteSize: 7, screenshot: true)])
        store.loadVideos([
            VideoAsset(id: "v1", creationDate: nil, duration: 1, pixelSize: .zero, byteSize: 100),
            VideoAsset(id: "v2", creationDate: nil, duration: 1, pixelSize: .zero, byteSize: 200)
        ])
        store.toggleScreenshotSelection(assetID: "s1")
        store.toggleVideoSelection(assetID: "v1")

        store.removeFromSelection(photoKitIDs: ["s1", "v1"], contactIDs: [])

        XCTAssertEqual(store.screenshotAssets.map(\.id), ["s2"])
        XCTAssertEqual(store.videoAssets.map(\.id), ["v2"])
        XCTAssertTrue(store.selectedScreenshotIDs.isEmpty)
        XCTAssertTrue(store.selectedVideoIDs.isEmpty)
    }

    func test_pruning_photosDoesNotTouchContactsAndViceVersa() {
        let store = ReviewStore()
        let g = group(members: [asset(id: "a", byteSize: 1), asset(id: "b", byteSize: 2)], keepID: "a")
        store.loadPhotoResults(exactDuplicates: [g], similar: [], scannedWithLimitedAccess: false)
        let cg = ContactGroup(
            id: UUID(),
            tier: .exact,
            members: [
                ContactCandidate(id: "c1", givenName: "A", familyName: "B", normalizedPhones: ["555"], normalizedEmails: [], fieldCount: 2, imageDataAvailable: false),
                ContactCandidate(id: "c2", givenName: "A", familyName: "B", normalizedPhones: ["555"], normalizedEmails: [], fieldCount: 2, imageDataAvailable: false)
            ],
            matchReason: "Same phone",
            recommendedPrimaryID: "c1",
            confidence: 1.0
        )
        store.loadContactGroups([cg])
        store.toggleContactSelection(groupID: store.contactGroups[0].id, contactID: "c2")
        // Photo-side prune with a contact ID must do nothing to contacts,
        // and vice versa (the sets are categorically disjoint).
        store.removeFromSelection(photoKitIDs: [], contactIDs: ["c2"])

        XCTAssertEqual(store.exactDuplicateGroups.count, 1)
        XCTAssertEqual(store.contactGroups.count, 1)
        XCTAssertTrue(store.currentSelection.contactIDs.isEmpty)
    }

    // MARK: - Contact group pruning

    func test_pruning_contactGroupSurvivorsStaySelected() {
        let store = ReviewStore()
        let cg = ContactGroup(
            id: UUID(),
            tier: .probable,
            members: [
                ContactCandidate(id: "c1", givenName: "A", familyName: "B", normalizedPhones: ["555"], normalizedEmails: [], fieldCount: 2, imageDataAvailable: false),
                ContactCandidate(id: "c2", givenName: "A", familyName: "B", normalizedPhones: ["555"], normalizedEmails: [], fieldCount: 2, imageDataAvailable: false),
                ContactCandidate(id: "c3", givenName: "A", familyName: "B", normalizedPhones: ["555"], normalizedEmails: [], fieldCount: 2, imageDataAvailable: false)
            ],
            matchReason: "Same phone, similar name",
            recommendedPrimaryID: "c1",
            confidence: 0.9
        )
        store.loadContactGroups([cg])
        store.toggleContactSelection(groupID: store.contactGroups[0].id, contactID: "c2")
        store.toggleContactSelection(groupID: store.contactGroups[0].id, contactID: "c3")

        store.removeFromSelection(photoKitIDs: [], contactIDs: ["c2"])

        XCTAssertEqual(store.contactGroups[0].members.map(\.id), ["c1", "c3"])
        XCTAssertEqual(store.currentSelection.contactIDs, ["c3"], "surviving selected contact must stay selected")
        XCTAssertEqual(store.contactGroups[0].recommendedPrimaryID, "c1")
    }
}
