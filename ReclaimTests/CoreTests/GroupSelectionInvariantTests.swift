//
//  GroupSelectionInvariantTests.swift
//  ReclaimTests
//
//  Document 05 §2, Document 08 §1 "Selection logic". The single most
//  important structural invariant in the photo/contact pipeline: the
//  effective keep/primary is NEVER present in `selection`, under any
//  sequence of mutations.
//

import XCTest
@testable import Reclaim

final class PhotoGroupInvariantTests: XCTestCase {

    private func makeAssets(_ ids: [String]) -> [PhotoAsset] {
        ids.map { PhotoAsset(id: $0, creationDate: nil, pixelSize: .zero, byteSize: 1000, isScreenshot: false) }
    }

    func test_toggleSelection_cannotSelectTheKeep() {
        var group = PhotoGroup(kind: .exactDuplicate, members: makeAssets(["a", "b", "c"]), recommendedKeepID: "a", confidence: 1.0)
        group.toggleSelection(for: "a")
        XCTAssertFalse(group.selection.contains("a"), "the recommended keep must never become selected")
    }

    func test_selectAllExceptKeep_excludesKeep() {
        var group = PhotoGroup(kind: .exactDuplicate, members: makeAssets(["a", "b", "c"]), recommendedKeepID: "a", confidence: 1.0)
        group.selectAllExceptKeep()
        XCTAssertEqual(group.selection, Set(["b", "c"]))
        XCTAssertFalse(group.selection.contains("a"))
    }

    func test_changingKeep_removesNewKeepFromSelection() {
        var group = PhotoGroup(kind: .exactDuplicate, members: makeAssets(["a", "b", "c"]), recommendedKeepID: "a", confidence: 1.0)
        group.selectAllExceptKeep() // selection = {b, c}
        group.setUserChosenKeep("b") // b becomes the new keep
        XCTAssertFalse(group.selection.contains("b"), "the new keep must be removed from selection the moment it's chosen")
        XCTAssertEqual(group.effectiveKeepID, "b")
    }

    func test_initializer_stripsKeepFromSeededSelection() {
        // Even a caller-constructed initial state cannot violate the invariant.
        let group = PhotoGroup(
            kind: .exactDuplicate,
            members: makeAssets(["a", "b", "c"]),
            recommendedKeepID: "a",
            selection: Set(["a", "b"]), // illegally includes the keep
            confidence: 1.0
        )
        XCTAssertFalse(group.selection.contains("a"))
        XCTAssertTrue(group.selection.contains("b"))
    }

    func test_toggleSelection_ignoresUnknownAssetID() {
        var group = PhotoGroup(kind: .exactDuplicate, members: makeAssets(["a", "b"]), recommendedKeepID: "a", confidence: 1.0)
        group.toggleSelection(for: "not-a-real-id")
        XCTAssertTrue(group.selection.isEmpty)
    }

    func test_recoverableBytes_onlyCountsSelected() {
        var group = PhotoGroup(kind: .exactDuplicate, members: makeAssets(["a", "b", "c"]), recommendedKeepID: "a", confidence: 1.0)
        group.toggleSelection(for: "b")
        XCTAssertEqual(group.recoverableBytes, 1000) // only "b" selected, 1000 bytes each
    }

    func test_deselectAll_clearsSelection() {
        var group = PhotoGroup(kind: .exactDuplicate, members: makeAssets(["a", "b", "c"]), recommendedKeepID: "a", confidence: 1.0)
        group.selectAllExceptKeep()
        group.deselectAll()
        XCTAssertTrue(group.selection.isEmpty)
    }
}

final class ContactGroupInvariantTests: XCTestCase {

    private func makeContact(_ id: String, fieldCount: Int = 2) -> ContactCandidate {
        ContactCandidate(id: id, givenName: "Test", familyName: id, normalizedPhones: [], normalizedEmails: [], fieldCount: fieldCount, imageDataAvailable: false)
    }

    func test_toggleSelection_cannotSelectThePrimary() {
        var group = ContactGroup(tier: .exact, members: [makeContact("a"), makeContact("b")], matchReason: "test", recommendedPrimaryID: "a", confidence: 1.0)
        group.toggleSelection(for: "a")
        XCTAssertFalse(group.selection.contains("a"))
    }

    func test_toggleSelection_nonPrimaryToggles() {
        var group = ContactGroup(tier: .exact, members: [makeContact("a"), makeContact("b")], matchReason: "test", recommendedPrimaryID: "a", confidence: 1.0)
        group.toggleSelection(for: "b")
        XCTAssertTrue(group.selection.contains("b"))
        group.toggleSelection(for: "b")
        XCTAssertFalse(group.selection.contains("b"))
    }
}
