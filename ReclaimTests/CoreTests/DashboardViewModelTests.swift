//
//  DashboardViewModelTests.swift
//  ReclaimTests
//
//  Covers the Dashboard ViewModel's scan status lifecycle against a fully
//  fake AppEnvironment: the cancelled-status fix (the pipeline RETURNS
//  .cancelled rather than throwing — the ViewModel must reflect it or the
//  progress UI sticks forever), and the single-scan-start guard.
//

import XCTest
import CoreGraphics
@testable import Reclaim

@MainActor
final class DashboardViewModelTests: XCTestCase {

    private final class FakeDuplicateContactDetector: DuplicateContactDetectorProtocol, @unchecked Sendable {
        var result: [ContactGroup] = []
        func detectDuplicateGroups(in contacts: [ContactCandidate]) -> [ContactGroup] { result }
    }

    private var photoLibrary: FakePhotoLibraryService!
    private var contactService: FakeContactService!
    private var screenshotDetector: FakeScreenshotDetector!
    private var environment: AppEnvironment!
    private var viewModel: DashboardViewModel!

    override func setUp() {
        super.setUp()
        photoLibrary = FakePhotoLibraryService()
        contactService = FakeContactService()
        screenshotDetector = FakeScreenshotDetector()
        environment = AppEnvironment(
            photoLibrary: photoLibrary,
            contactService: contactService,
            storageService: FakeStorageService(),
            scanCache: FakeScanCache(),
            screenshotDetector: screenshotDetector
        )
        viewModel = DashboardViewModel(environment: environment)
    }

    override func tearDown() {
        viewModel = nil
        environment = nil
        contactService = nil
        photoLibrary = nil
        screenshotDetector = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    /// Mirrors the pipeline-test fixture: screenshot-flagged assets so the
    /// real ScreenshotDetector route (and the gated sizing below it) engages.
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

    // MARK: - Cancelled status is reflected (regression)

    func test_cancelledPipelineStatus_isReflectedNotStuckOnScanning() async {
        photoLibrary.authorization = .authorized
        photoLibrary.gateByteSizesUntilCancelled = true
        // Script real screenshot-flagged assets so the pipeline actually
        // reaches the gated screenshot-sizing call: with no assets the scan
        // completes in milliseconds and the cancel below is a no-op on an
        // already-completed scan (first-run test-design error, fixed).
        photoLibrary.scriptedPhotoAssets = [photo(id: "p1", screenshot: true), photo(id: "p2", screenshot: true)]
        photoLibrary.byteSizes = ["p1": 111, "p2": 222]
        screenshotDetector.detected = [photo(id: "p1", screenshot: true), photo(id: "p2", screenshot: true)]

        viewModel.startScan()
        // Let the scan reach the gated screenshot-sizing call, then cancel.
        try? await Task.sleep(nanoseconds: 100_000_000)
        viewModel.cancelScan()

        // The pipeline returns .cancelled (it does NOT throw); the
        // ViewModel must end in .cancelled — never stuck on .scanning.
        for _ in 0..<200 {
            if viewModel.scanStatus == .cancelled { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.scanStatus, .cancelled,
                       "scan UI must return to a rescan-able state after cancellation — Document 09 §8")
        XCTAssertFalse(viewModel.scanStatus.isScanning)
    }

    // MARK: - Completed status

    func test_successfulScan_endsInCompletedStatus() async {
        photoLibrary.authorization = .authorized
        photoLibrary.scriptedPhotoAssets = []
        viewModel.startScan()

        for _ in 0..<200 {
            if viewModel.scanStatus == .completed { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.scanStatus, .completed)
    }

    // MARK: - Single-start guard

    func test_startScanWhileScanning_isIgnored() async {
        photoLibrary.authorization = .authorized
        photoLibrary.gateByteSizesUntilCancelled = true
        photoLibrary.scriptedPhotoAssets = [photo(id: "p1", screenshot: true), photo(id: "p2", screenshot: true)]
        photoLibrary.byteSizes = ["p1": 111, "p2": 222]
        screenshotDetector.detected = [photo(id: "p1", screenshot: true), photo(id: "p2", screenshot: true)]

        viewModel.startScan()
        try? await Task.sleep(nanoseconds: 50_000_000)
        viewModel.startScan() // must be a no-op while scanning
        viewModel.cancelScan()

        for _ in 0..<200 {
            if viewModel.scanStatus == .cancelled { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.scanStatus, .cancelled)
    }
}
