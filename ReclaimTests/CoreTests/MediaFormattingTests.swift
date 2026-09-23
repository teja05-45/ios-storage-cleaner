//
//  MediaFormattingTests.swift
//  ReclaimTests
//
//  Covers the shared metadata formatting used by the Screenshots and
//  Large Videos screens (Document 02 §4.5–4.6). Pure Foundation — runs
//  without PhotoKit, a simulator, or a device (Document 03 §7).
//

import XCTest
@testable import Reclaim

final class MediaFormattingTests: XCTestCase {

    // MARK: - Duration

    func test_duration_zeroSeconds_showsZero() {
        XCTAssertEqual(MediaFormatting.duration(from: 0), "0:00")
    }

    func test_duration_underAMinute() {
        XCTAssertEqual(MediaFormatting.duration(from: 47), "0:47")
    }

    func test_duration_roundsSubSecondToNearestSecond() {
        XCTAssertEqual(MediaFormatting.duration(from: 59.6), "1:00")
    }

    func test_duration_overAnHour_includesHours() {
        XCTAssertEqual(MediaFormatting.duration(from: 3723), "1:02:03")
    }

    func test_duration_negativeClampsToZero() {
        XCTAssertEqual(MediaFormatting.duration(from: -5), "0:00")
    }

    // MARK: - Resolution

    func test_resolution_formatsWidthAndHeight() {
        XCTAssertEqual(MediaFormatting.resolution(CGSize(width: 1920, height: 1080)), "1920 × 1080")
    }

    // MARK: - Capture date

    func test_captureDate_nilShowsPlaceholder() {
        XCTAssertEqual(MediaFormatting.captureDate(from: nil), "—")
    }

    func test_captureDate_presentIsNonEmptyAndNotPlaceholder() {
        // Locale-dependent rendering is deliberate (Document 02: locale-
        // appropriate dates); the contract under test is nil-handling and
        // that a real date never renders as the nil placeholder.
        let result = MediaFormatting.captureDate(from: Date(timeIntervalSince1970: 0))
        XCTAssertNotEqual(result, "—")
        XCTAssertFalse(result.isEmpty)
    }
}
