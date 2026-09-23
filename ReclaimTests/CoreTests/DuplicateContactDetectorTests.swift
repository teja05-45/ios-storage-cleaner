//
//  DuplicateContactDetectorTests.swift
//  ReclaimTests
//
//  Document 06 §6, Document 13 §2.8: "the false-positive guard... is
//  explicitly called the most important unit test." This suite verifies it
//  directly, plus the >8-member oversized-bucket demotion rule.
//

import XCTest
@testable import Reclaim

final class DuplicateContactDetectorTests: XCTestCase {

    private let detector = DuplicateContactDetector()

    private func contact(_ id: String, given: String, family: String, phones: [String] = [], emails: [String] = []) -> ContactCandidate {
        ContactCandidate(
            id: id,
            givenName: given,
            familyName: family,
            normalizedPhones: phones,
            normalizedEmails: emails,
            fieldCount: phones.count + emails.count + 2,
            imageDataAvailable: false
        )
    }

    // MARK: - THE most important test: name similarity alone is never sufficient

    func test_identicalNames_noSharedPhoneOrEmail_neverGrouped() {
        // Two different real people who happen to share an extremely
        // common name, with zero overlapping phone/email evidence. This
        // MUST NOT be surfaced as a duplicate candidate of either tier —
        // that would risk deleting a real, unique contact based on name
        // alone (this build's instructions §5, Document 13 §2.8).
        let contacts = [
            contact("1", given: "John", family: "Smith", phones: ["4155550001"], emails: ["john.smith.nyc@example.com"]),
            contact("2", given: "John", family: "Smith", phones: ["2125559999"], emails: ["jsmith.chicago@example.com"])
        ]
        let groups = detector.detectDuplicateGroups(in: contacts)
        XCTAssertTrue(groups.isEmpty, "identical names with zero shared phone/email must never be flagged as duplicates")
    }

    func test_similarButNotIdenticalNames_noOtherSignal_neverGrouped() {
        let contacts = [
            contact("1", given: "Jon", family: "Smith", phones: ["4155550001"]),
            contact("2", given: "John", family: "Smith", phones: ["2125559999"])
        ]
        let groups = detector.detectDuplicateGroups(in: contacts)
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: - Exact tier

    func test_exactPhoneMatch_classifiedAsExact() {
        let contacts = [
            contact("1", given: "John", family: "Smith", phones: ["4155550001"]),
            contact("2", given: "Jonathan", family: "Smyth", phones: ["4155550001"]) // same phone, different name spelling
        ]
        let groups = detector.detectDuplicateGroups(in: contacts)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].tier, .exact)
    }

    func test_exactEmailMatch_classifiedAsExact() {
        let contacts = [
            contact("1", given: "John", family: "Smith", emails: ["john@example.com"]),
            contact("2", given: "J", family: "S", emails: ["john@example.com"])
        ]
        let groups = detector.detectDuplicateGroups(in: contacts)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].tier, .exact)
    }

    func test_unrelatedContacts_noSharedSignal_notGrouped() {
        let contacts = [
            contact("1", given: "Alice", family: "Anderson", phones: ["4155550001"]),
            contact("2", given: "Bob", family: "Baker", phones: ["2125559999"])
        ]
        XCTAssertTrue(detector.detectDuplicateGroups(in: contacts).isEmpty)
    }

    // MARK: - Probable tier (name similarity + a genuine secondary signal)

    func test_similarName_withWeakPhoneSignal_classifiedAsProbable() {
        // Same national number, different explicit country code — the one
        // case ContactNormalizer.phonesMatch intentionally excludes from
        // .exact, but which still counts as a weak secondary signal here.
        let contacts = [
            contact("1", given: "John", family: "Smith", phones: ["+1 415 555 0001"]),
            contact("2", given: "John", family: "Smith", phones: ["+44 415 555 0001"])
        ]
        let groups = detector.detectDuplicateGroups(in: contacts)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].tier, .probable)
    }

    func test_reorderedName_withSharedPhone_stillGrouped() {
        let contacts = [
            contact("1", given: "John", family: "Smith", phones: ["4155550001"]),
            contact("2", given: "Smith,", family: "John", phones: ["4155550001"])
        ]
        let groups = detector.detectDuplicateGroups(in: contacts)
        XCTAssertEqual(groups.count, 1)
    }

    // MARK: - Oversized bucket demotion

    func test_oversizedGroup_demotedToProbableWithReducedConfidence() {
        // 9 contacts sharing one phone number (e.g. a shared office line) —
        // exceeds maxTrustedGroupSize (8), so even though every pair is an
        // "exact" phone match, the whole group is demoted to .probable with
        // a penalized confidence and a "review carefully" reason
        // (Document 13 §2.8).
        var contacts: [ContactCandidate] = []
        for i in 0..<9 {
            contacts.append(contact("\(i)", given: "Employee\(i)", family: "Office", phones: ["4155550001"]))
        }
        let groups = detector.detectDuplicateGroups(in: contacts)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].tier, .probable, "an oversized group must be demoted to .probable even if every pairwise edge was exact")
        XCTAssertLessThan(groups[0].confidence, 1.0)
        XCTAssertTrue(groups[0].matchReason.lowercased().contains("review") || groups[0].matchReason.lowercased().contains("large"))
    }

    func test_recommendedPrimary_isRicherRecord() {
        let contacts = [
            contact("sparse", given: "John", family: "Smith", phones: ["4155550001"]),
            contact("rich", given: "John", family: "Smith", phones: ["4155550001", "4155550002"], emails: ["john@example.com"])
        ]
        let groups = detector.detectDuplicateGroups(in: contacts)
        XCTAssertEqual(groups.first?.recommendedPrimaryID, "rich")
    }

    func test_singleContact_neverGrouped() {
        let contacts = [contact("1", given: "John", family: "Smith", phones: ["4155550001"])]
        XCTAssertTrue(detector.detectDuplicateGroups(in: contacts).isEmpty)
    }
}
