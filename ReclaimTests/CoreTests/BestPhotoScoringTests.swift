//
//  BestPhotoScoringTests.swift
//  ReclaimTests
//
//  Document 08 §1: "known fixture ranks correctly". Also verifies `reason`
//  never references an unimplemented signal (Document 06 §3 hard prohibition).
//

import XCTest
@testable import Reclaim

final class BestPhotoScoringTests: XCTestCase {

    func test_score_emptyInput_returnsEmpty() {
        XCTAssertTrue(BestPhotoScoring.score([]).isEmpty)
    }

    func test_recommendedKeep_picksHighestResolutionAndSharpness() {
        let signals = [
            BestPhotoScoring.RawSignals(assetID: "low", resolutionPixels: 100, sharpnessRaw: 10, exposureRaw: 0.5, byteSize: 1000),
            BestPhotoScoring.RawSignals(assetID: "high", resolutionPixels: 1000, sharpnessRaw: 100, exposureRaw: 0.9, byteSize: 5000)
        ]
        let keep = BestPhotoScoring.recommendedKeepID(signals)
        XCTAssertEqual(keep, "high")
    }

    func test_score_isDeterministic_tiesBrokenByID() {
        // Identical signals -> identical total scores -> tie broken by
        // asset ID for a stable, repeatable recommendation.
        let signals = [
            BestPhotoScoring.RawSignals(assetID: "b", resolutionPixels: 500, sharpnessRaw: 50, exposureRaw: 0.7, byteSize: 2000),
            BestPhotoScoring.RawSignals(assetID: "a", resolutionPixels: 500, sharpnessRaw: 50, exposureRaw: 0.7, byteSize: 2000)
        ]
        XCTAssertEqual(BestPhotoScoring.recommendedKeepID(signals), "a")
    }

    func test_reason_neverMentionsUnimplementedSignals() {
        let signals = [
            BestPhotoScoring.RawSignals(assetID: "a", resolutionPixels: 1000, sharpnessRaw: 90, exposureRaw: 0.9, byteSize: 3000),
            BestPhotoScoring.RawSignals(assetID: "b", resolutionPixels: 200, sharpnessRaw: 20, exposureRaw: 0.3, byteSize: 1000)
        ]
        let candidates = BestPhotoScoring.score(signals)
        let forbiddenTerms = ["face", "smile", "eyes", "subject", "background", "best photo"]
        for candidate in candidates {
            for term in forbiddenTerms {
                XCTAssertFalse(
                    candidate.reason.lowercased().contains(term),
                    "reason string '\(candidate.reason)' references an unimplemented signal: \(term)"
                )
            }
        }
    }

    func test_allScoresAreWithinZeroToOne() {
        let signals = [
            BestPhotoScoring.RawSignals(assetID: "a", resolutionPixels: 1000, sharpnessRaw: 90, exposureRaw: 0.9, byteSize: 3000),
            BestPhotoScoring.RawSignals(assetID: "b", resolutionPixels: 200, sharpnessRaw: 20, exposureRaw: 0.3, byteSize: 1000),
            BestPhotoScoring.RawSignals(assetID: "c", resolutionPixels: 500, sharpnessRaw: 50, exposureRaw: 0.5, byteSize: 2000)
        ]
        for candidate in BestPhotoScoring.score(signals) {
            XCTAssertGreaterThanOrEqual(candidate.totalScore, 0.0)
            XCTAssertLessThanOrEqual(candidate.totalScore, 1.0)
        }
    }
}
