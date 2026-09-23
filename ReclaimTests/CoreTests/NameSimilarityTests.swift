//
//  NameSimilarityTests.swift
//  ReclaimTests
//
//  Document 08 §1: "reordered 'Last, First' vs 'First Last' cases" is
//  called out explicitly as a required test.
//

import XCTest
@testable import Reclaim

final class NameSimilarityTests: XCTestCase {

    func test_identicalNames_scoreIsOne() {
        XCTAssertEqual(NameSimilarity.score("John Smith", "John Smith"), 1.0, accuracy: 0.0001)
    }

    func test_caseInsensitive() {
        XCTAssertEqual(NameSimilarity.score("John Smith", "JOHN SMITH"), 1.0, accuracy: 0.0001)
    }

    func test_reorderedName_scoresHighViaTokenForm() {
        // "Smith, John" normalizes (comma -> space) to "smith john", whose
        // canonical token form ("john smith") matches "John Smith"'s
        // canonical form exactly -> should score 1.0 via the token path
        // even though the direct string comparison would not.
        let score = NameSimilarity.score("Smith, John", "John Smith")
        XCTAssertEqual(score, 1.0, accuracy: 0.0001)
    }

    func test_completelyDifferentNames_scoresLow() {
        let score = NameSimilarity.score("John Smith", "Zbigniew Kowalski")
        XCTAssertLessThan(score, 0.5)
    }

    func test_minorTypo_scoresHighButNotPerfect() {
        let score = NameSimilarity.score("Jon Smith", "John Smith")
        XCTAssertGreaterThan(score, 0.7)
        XCTAssertLessThan(score, 1.0)
    }

    func test_bothEmpty_scoresOne() {
        XCTAssertEqual(NameSimilarity.score("", ""), 1.0)
    }

    func test_oneEmpty_scoresZero() {
        XCTAssertEqual(NameSimilarity.score("John Smith", ""), 0.0)
    }

    func test_levenshteinDistance_knownValues() {
        XCTAssertEqual(NameSimilarity.levenshteinDistance("kitten", "sitting"), 3)
        XCTAssertEqual(NameSimilarity.levenshteinDistance("", ""), 0)
        XCTAssertEqual(NameSimilarity.levenshteinDistance("abc", ""), 3)
    }
}
