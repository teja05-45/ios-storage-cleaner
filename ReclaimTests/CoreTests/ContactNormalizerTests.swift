//
//  ContactNormalizerTests.swift
//  ReclaimTests
//
//  Document 08 §1: phone last-10 suffix matching, country-code precision
//  case, email case/whitespace normalization, +tag stripping (off by default).
//

import XCTest
@testable import Reclaim

final class ContactNormalizerTests: XCTestCase {

    // MARK: - Phone

    func test_normalizePhone_stripsFormatting() {
        let result = ContactNormalizer.normalizePhone("(415) 555-0123")
        XCTAssertEqual(result?.last10, "4155550123")
    }

    func test_normalizePhone_preservesLeadingPlus() {
        let result = ContactNormalizer.normalizePhone("+1 415 555 0123")
        XCTAssertTrue(result?.fullForm.hasPrefix("+") ?? false)
        XCTAssertTrue(result?.hasCountryCode ?? false)
    }

    func test_normalizePhone_emptyString_returnsNil() {
        XCTAssertNil(ContactNormalizer.normalizePhone(""))
        XCTAssertNil(ContactNormalizer.normalizePhone("   "))
    }

    func test_phonesMatch_sameNumberDifferentFormatting() {
        XCTAssertTrue(ContactNormalizer.phonesMatch("(415) 555-0123", "415-555-0123"))
    }

    func test_phonesMatch_last10SuffixMatch_noCountryCodeEither() {
        XCTAssertTrue(ContactNormalizer.phonesMatch("415-555-0123", "4155550123"))
    }

    func test_phonesMatch_differentNumbers_doesNotMatch() {
        XCTAssertFalse(ContactNormalizer.phonesMatch("415-555-0123", "415-555-9999"))
    }

    /// Document 06 §6 step 4: two numbers sharing a last-10 suffix but BOTH
    /// carrying explicit, presumably-different country codes should not be
    /// silently equated — precision-over-recall.
    func test_phonesMatch_bothHaveCountryCodes_doesNotAutoMatchOnSuffixAlone() {
        // Same last 10 digits, but both have an explicit country code and
        // the full forms differ -> should NOT match under the exact rule.
        XCTAssertFalse(ContactNormalizer.phonesMatch("+1 415 555 0123", "+44 415 555 0123"))
    }

    func test_phonesMatch_oneHasCountryCodeOneDoesnt_suffixMatches() {
        XCTAssertTrue(ContactNormalizer.phonesMatch("+1 415 555 0123", "415-555-0123"))
    }

    // MARK: - Email

    func test_normalizeEmail_lowercasesAndTrims() {
        XCTAssertEqual(ContactNormalizer.normalizeEmail("  Jane.Doe@Example.com  "), "jane.doe@example.com")
    }

    func test_emailsMatch_caseInsensitive() {
        XCTAssertTrue(ContactNormalizer.emailsMatch("Jane@Example.com", "jane@example.com"))
    }

    func test_emailsMatch_plusTag_offByDefault() {
        // stripGmailPlusTag defaults to false -> these should NOT match.
        XCTAssertFalse(ContactNormalizer.emailsMatch("jane+work@example.com", "jane@example.com"))
    }

    func test_emailsMatch_plusTag_whenExplicitlyEnabled() {
        XCTAssertTrue(ContactNormalizer.emailsMatch("jane+work@example.com", "jane@example.com", stripGmailPlusTag: true))
    }
}
