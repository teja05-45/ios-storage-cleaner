//
//  ContactFieldDiffTests.swift
//  ReclaimTests
//
//  Covers ContactGroupDetailView's pure field-diff computation — the data
//  behind Document 01 §3.5's "what would be lost" disclosure. Pure
//  Foundation, no Contacts framework.
//

import XCTest
@testable import Reclaim

@MainActor
final class ContactFieldDiffTests: XCTestCase {

    private func fields(
        given: String = "",
        family: String = "",
        phones: [String] = [],
        emails: [String] = []
    ) -> ContactDisplayFields {
        ContactDisplayFields(givenName: given, familyName: family, phoneNumbers: phones, emailAddresses: emails)
    }

    func test_uniqueFieldOnNonPrimary_isMarkedAsWouldBeLost() {
        let primary = fields(given: "John", family: "Smith", phones: ["+1 555 0100"])
        let other = fields(given: "John", family: "Smith", phones: ["+1 555 0100", "+1 555 0199"])

        let diffs = ContactGroupDetailView.fieldDiffs(primary: primary, other: other)
        let unique = diffs.first { $0.otherValue == "+1 555 0199" }

        XCTAssertNotNil(unique)
        XCTAssertTrue(unique?.wouldBeLost ?? false, "A phone only on the deleted record must be disclosed as lost")
    }

    func test_sharedFields_areNotMarkedAsLost() {
        let shared = "+1 555 0100"
        let primary = fields(phones: [shared])
        let other = fields(phones: [shared])

        let diffs = ContactGroupDetailView.fieldDiffs(primary: primary, other: other)
        let phoneDiff = diffs.first { $0.label == "Phone" }

        XCTAssertNotNil(phoneDiff)
        XCTAssertFalse(phoneDiff?.wouldBeLost ?? true)
    }

    func test_fieldOnlyOnPrimary_showsAsMissingOnOtherWithoutLossFlag() {
        let primary = fields(given: "John", emails: ["john@example.com"])
        let other = fields(given: "John")

        let diffs = ContactGroupDetailView.fieldDiffs(primary: primary, other: other)
        let emailDiff = diffs.first { $0.label == "Email" }

        XCTAssertEqual(emailDiff?.primaryValue, "john@example.com")
        XCTAssertNil(emailDiff?.otherValue)
        XCTAssertFalse(emailDiff?.wouldBeLost ?? true, "The primary keeps this field; nothing is lost by deleting the other record")
    }

    func test_differentNames_areComparedAndNeverLostFlagged() {
        let primary = fields(given: "John", family: "Smith")
        let other = fields(given: "Jon", family: "Smith")

        let diffs = ContactGroupDetailView.fieldDiffs(primary: primary, other: other)
        let nameDiff = diffs.first { $0.label == "Name" }

        XCTAssertEqual(nameDiff?.primaryValue, "John Smith")
        XCTAssertEqual(nameDiff?.otherValue, "Jon Smith")
        XCTAssertFalse(nameDiff?.wouldBeLost ?? true, "Name spelling differences are shown, but the deleted record's name is not unique data")
    }

    func test_differingValuesOnBothSides_countAsLoss() {
        // Two different phones (neither shared): the deleted record's phone
        // exists only there — that is exactly the loss case the preview
        // exists to surface.
        let primary = fields(phones: ["+1 555 0100"])
        let other = fields(phones: ["+1 555 0200"])

        let diffs = ContactGroupDetailView.fieldDiffs(primary: primary, other: other)
        XCTAssertTrue(diffs.contains { $0.wouldBeLost })
    }
}
