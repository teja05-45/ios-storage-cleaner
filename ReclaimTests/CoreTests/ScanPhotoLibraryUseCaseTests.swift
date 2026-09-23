//
//  ScanPhotoLibraryUseCaseTests.swift
//  ReclaimTests
//
//  Covers the scan pipeline's orchestration contract (Document 09 §3–4):
//  phase ordering, the ISSUE-05 screenshot-size resolution (bytes must be
//  real, not 0, so recoverable estimates are honest), exclusion of
//  screenshots and exact-duplicate members from similarity analysis
//  (an asset must not be deletable under two reasons), and cancellation
//  preserving partial results with a .cancelled status.
//

import XCTest
import CoreGraphics
@testable import Reclaim

final class ScanPhotoLibraryUseCaseTests: XCTestCase {

    private func photo(id: String, screenshot: Bool = false) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: Date(timeIntervalSince1970: 1_000),
            pixelSize: CGSize(width: 100, height: 100),
            byteSize: 0,
            isScreenshot: screenshot,
            mediaType: .photo
        )
    }

    private func makeUseCase(
        photoLibrary: FakePhotoLibraryService,
        duplicates: FakeDuplicateDetector = FakeDuplicateDetector(),
        similarity: FakeSimilarityDetector = FakeSimilarityDetector(),
        screenshots: FakeScreenshotDetector = FakeScreenshotDetector(),
        videos: FakeVideoScanner = FakeVideoScanner()
    ) -> ScanPhotoLibraryUseCase {
        ScanPhotoLibraryUseCase(
            photoLibrary: photoLibrary,
            duplicateDetector: duplicates,
            similarityDetector: similarity,
            screenshotDetector: screenshots,
            videoScanner: videos
        )
    }

    /// Minimal thread-safe event collector for phase-ordering assertions
    /// (the pipeline runs detectors from async contexts).
    private final class EventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [String] = []
        var events: [String] {
            lock.lock(); defer { lock.unlock() }
            return _events
        }
        func record(_ event: String) {
            lock.lock(); defer { lock.unlock() }
            _events.append(event)
        }
    }

    // MARK: - Happy path

    func test_completedScan_returnsAllCategoriesWithCompletedStatus() async throws {
        let service = FakePhotoLibraryService()
        service.authorization = .authorized
        service.scriptedPhotoAssets = [photo(id: "p1"), photo(id: "p2")]
        let screenshots = FakeScreenshotDetector()
        screenshots.detected = [photo(id: "p1", screenshot: true)]
        let videos = FakeVideoScanner()
        videos.result = [VideoAsset(id: "v1", creationDate: nil, duration: 1, pixelSize: .zero, byteSize: 10)]
        let useCase = makeUseCase(photoLibrary: service, screenshots: screenshots, videos: videos)

        let result = try await useCase.execute { _ in }

        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.screenshots.map(\.id), ["p1"])
        XCTAssertEqual(result.videos.map(\.id), ["v1"])
        XCTAssertTrue(result.scannedWithLimitedAccess == false)
    }

    func test_limitedAuthorization_isReportedHonestly() async throws {
        let service = FakePhotoLibraryService()
        service.authorization = .limited
        service.scriptedPhotoAssets = [photo(id: "p1")]
        let useCase = makeUseCase(photoLibrary: service)

        let result = try await useCase.execute { _ in }

        XCTAssertTrue(result.scannedWithLimitedAccess, ".limited must reach the UI as its own state, never collapsed into full access (ADR-04)")
    }

    // MARK: - ISSUE-05: screenshot byte sizes resolved at detection

    func test_screenshotSizes_areResolvedFromRealResources_notZero() async throws {
        let service = FakePhotoLibraryService()
        service.authorization = .authorized
        service.scriptedPhotoAssets = [photo(id: "p1", screenshot: true)]
        service.byteSizes = ["p1": 123_456]
        let screenshots = FakeScreenshotDetector()
        screenshots.detected = [photo(id: "p1", screenshot: true)]
        let useCase = makeUseCase(photoLibrary: service, screenshots: screenshots)

        let result = try await useCase.execute { _ in }

        XCTAssertEqual(result.screenshots.first?.byteSize, 123_456, "a 0-byte placeholder would silently under-report recoverable-bytes estimates (audit ISSUE-05)")
    }

    func test_screenshotSizeFailure_fallsBackToZeroWithoutFailingTheScan() async throws {
        // The pipeline uses (try? ...) for sizes: an unreadable resource
        // degrades that screenshot's estimate to 0 rather than aborting the
        // whole scan. Pins the intended degradation, so a future refactor
        // doesn't accidentally turn it into a thrown error.
        let service = FakePhotoLibraryService()
        service.authorization = .authorized
        service.scriptedPhotoAssets = [photo(id: "p1", screenshot: true)]
        service.byteSizes = ["other": 1] // no size scripted for p1 → returns 0
        let screenshots = FakeScreenshotDetector()
        screenshots.detected = [photo(id: "p1", screenshot: true)]
        let useCase = makeUseCase(photoLibrary: service, screenshots: screenshots)

        let result = try await useCase.execute { _ in }

        XCTAssertEqual(result.screenshots.first?.byteSize, 0)
        XCTAssertEqual(result.status, .completed)
    }

    // MARK: - Exclusion contract (one asset, one deletion reason)

    func test_similarityAnalysis_excludesExactDuplicateMembers() async throws {
        let service = FakePhotoLibraryService()
        service.authorization = .authorized
        service.scriptedPhotoAssets = [photo(id: "p1"), photo(id: "p2"), photo(id: "p3")]
        let duplicates = FakeDuplicateDetector()
        duplicates.result = [PhotoGroup(
            kind: .exactDuplicate,
            members: [photo(id: "p1"), photo(id: "p2")],
            recommendedKeepID: "p1",
            confidence: 1.0
        )]
        let similarity = FakeSimilarityDetector()
        let useCase = makeUseCase(photoLibrary: service, duplicates: duplicates, similarity: similarity)

        _ = try await useCase.execute { _ in }

        XCTAssertEqual(similarity.receivedAssets.map(\.id), ["p3"], "an asset already grouped as an exact duplicate must not also enter similarity analysis — that would let it be selected for deletion twice under two reasons")
    }

    func test_exactDuplicatesRunBeforeSimilarity_detectionOrderContract() async throws {
        // Ordering contract from Document 09 §3: duplicates first, because
        // similarity's input depends on duplicates' output (the exclusion).
        // Pinned via a shared, lock-safe event recorder on the fakes.
        let service = FakePhotoLibraryService()
        service.authorization = .authorized
        service.scriptedPhotoAssets = [photo(id: "p1"), photo(id: "p2")]
        let recorder = EventRecorder()
        let duplicates = FakeDuplicateDetector()
        duplicates.onRun = { recorder.record($0) }
        let similarity = FakeSimilarityDetector()
        similarity.onRun = { recorder.record($0) }
        let useCase = makeUseCase(photoLibrary: service, duplicates: duplicates, similarity: similarity)

        _ = try await useCase.execute { _ in }

        XCTAssertEqual(recorder.events, ["duplicates", "similarity"],
                       "similarity must run after duplicates — its input is duplicates' output")
    }

    // MARK: - Cancellation (Document 09 §8: partial results preserved)

    func test_cancellationDuringScreenshotSizing_preservesPartialResultsAndReportsCancelled() async throws {
        let service = FakePhotoLibraryService()
        service.authorization = .authorized
        service.scriptedPhotoAssets = [photo(id: "p1", screenshot: true), photo(id: "p2", screenshot: true)]
        service.byteSizes = ["p1": 111, "p2": 222]
        service.gateByteSizesUntilCancelled = true // park during p1's sizing
        let screenshots = FakeScreenshotDetector()
        screenshots.detected = [photo(id: "p1", screenshot: true), photo(id: "p2", screenshot: true)]
        let useCase = makeUseCase(photoLibrary: service, screenshots: screenshots)

        let task = Task {
            try await useCase.execute { _ in }
        }
        // Let the pipeline reach the gated size call, then cancel.
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let result = try await task.value

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(result.screenshots.map(\.id), ["p1"], "the screenshot sized before cancellation must be preserved, not discarded")
        XCTAssertEqual(result.videos, [], "phases after the cancellation point must not run")
    }

    func test_cancellationBeforeAnyPhase_returnsEmptyCancelledResult() async throws {
        let service = FakePhotoLibraryService()
        service.authorization = .authorized
        let useCase = makeUseCase(photoLibrary: service)

        let task = Task {
            try await useCase.execute { _ in }
        }
        task.cancel()
        let result = try await task.value

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertTrue(result.screenshots.isEmpty)
        XCTAssertTrue(result.videos.isEmpty)
    }

    // MARK: - SimilarityDetector real implementation (nil-thumbnail tolerance)

    func test_similarityDetector_realImplementation_skipsAssetsWhoseThumbnailFails() async throws {
        // The real detector 'continue's on nil thumbnails instead of throwing
        // — pins that an unreadable asset is excluded from similarity, not
        // allowed to abort the analysis for everyone else.
        let service = FakePhotoLibraryService()
        service.scriptedPhotoAssets = [photo(id: "p1"), photo(id: "p2")]
        // No thumbnails scripted → requestThumbnail returns nil for both.
        let detector = SimilarityDetector()

        let groups = try await detector.detectSimilarGroups(in: [photo(id: "p1"), photo(id: "p2")], photoLibrary: service)

        XCTAssertTrue(groups.isEmpty, "without readable thumbnails no similarity decision can be made — and none was fabricated")
    }
}
