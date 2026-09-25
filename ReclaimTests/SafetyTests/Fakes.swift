//
//  Fakes.swift
//  ReclaimTests
//
//  Document 03 §7: protocol-first services exist specifically so this file
//  can exist — the entire safety-critical cleanup pipeline is testable
//  without a PhotoKit/Contacts entitlement, a simulator, or a device.
//

import Foundation
import CoreGraphics
import UIKit
import AVKit
@testable import Reclaim

final class FakePhotoLibraryService: PhotoLibraryServiceProtocol, @unchecked Sendable {
    var authorization: PermissionState = .authorized
    /// IDs that `stillValidAssetIDs` will report as valid. Anything
    /// requested but not in this set simulates a stale/vanished asset.
    var validAssetIDs: Set<String> = []
    /// IDs that `deleteAssets` will report as successfully deleted.
    var deletableAssetIDs: Set<String> = []
    var deleteError: Error?
    var deleteCallCount = 0
    var lastDeleteRequest: Set<String> = []
    /// Per-asset fixtures so scan-pipeline tests (duplicate bucketing,
    /// size resolution) can script what the framework would return.
    var byteSizes: [String: Int64] = [:]
    var contentHashes: [String: String] = [:]
    /// Scripted thumbnails so similarity tests can drive the real
    /// detector's hash+cluster pipeline deterministically, without UIKit
    /// image decoding (the real pipeline starts from a small grayscale
    /// grid — the fake supplies that grid directly).
    var scriptedThumbnails: [String: ThumbnailPixels] = [:]
    /// Number of times contentHash was invoked — lets tests assert the
    /// expensive hashing step stayed bounded to genuine candidates.
    private(set) var hashCallCount = 0
    /// Scripted enumeration results for the scan pipeline.
    var scriptedPhotoAssets: [PhotoAsset] = []
    var scriptedVideoAssets: [VideoAsset] = []
    /// When true, `resourceByteSize` parks (cooperatively) until the
    /// surrounding task is cancelled — lets tests cancel the scan mid
    /// screenshot-sizing and verify partial-result preservation.
    var gateByteSizesUntilCancelled = false

    func currentAuthorization() -> PermissionState { authorization }
    func requestAuthorization() async -> PermissionState { authorization }
    func presentLimitedLibraryPicker() async {}

    func fetchPhotoAssets(onBatch: @escaping @Sendable (Int, Int) -> Void) async throws -> [PhotoAsset] { scriptedPhotoAssets }
    func fetchVideoAssets(onBatch: @escaping @Sendable (Int, Int) -> Void) async throws -> [VideoAsset] { scriptedVideoAssets }

    func resourceByteSize(forAssetID id: String) async throws -> Int64 {
        while gateByteSizesUntilCancelled && !Task.isCancelled {
            await Task.yield()
        }
        return byteSizes[id] ?? 0
    }
    func contentHash(forAssetID id: String) async throws -> String {
        hashCallCount += 1
        return contentHashes[id] ?? ""
    }
    func requestThumbnail(forAssetID id: String, targetSize: CGSize) async -> ThumbnailPixels? {
        scriptedThumbnails[id]
    }

    func requestDisplayImage(forAssetID id: String, targetSize: CGSize) async -> UIImage? { nil }
    func playerItem(forVideoAssetID id: String) async -> AVPlayerItem? { nil }

    func stillValidAssetIDs(_ ids: Set<String>) async -> Set<String> {
        ids.intersection(validAssetIDs)
    }

    func deleteAssets(ids: Set<String>) async throws -> Set<String> {
        deleteCallCount += 1
        lastDeleteRequest = ids
        if let deleteError { throw deleteError }
        return ids.intersection(deletableAssetIDs)
    }
}

final class FakeContactService: ContactServiceProtocol, @unchecked Sendable {
    var authorization: PermissionState = .authorized
    var validContactIDs: Set<String> = []
    var deletableContactIDs: Set<String> = []
    var deleteError: Error?
    var deleteCallCount = 0

    func currentAuthorization() -> PermissionState { authorization }
    func requestAuthorization() async -> PermissionState { authorization }
    func fetchAllContacts() async throws -> [ContactCandidate] { [] }
    func fetchDisplayFields(forContactID id: String) async throws -> ContactDisplayFields {
        ContactDisplayFields(givenName: "", familyName: "", phoneNumbers: [], emailAddresses: [])
    }

    func stillValidContactIDs(_ ids: Set<String>) async -> Set<String> {
        ids.intersection(validContactIDs)
    }

    func deleteContacts(ids: Set<String>) async throws -> Set<String> {
        deleteCallCount += 1
        if let deleteError { throw deleteError }
        return ids.intersection(deletableContactIDs)
    }
}

final class FakeStorageService: StorageServiceProtocol, @unchecked Sendable {
    /// A queue of capacities returned on successive calls, simulating
    /// "before" then "after" cleanup readings. Falls back to `fixedCapacity`
    /// once exhausted.
    var capacitySequence: [DeviceCapacity] = []
    var fixedCapacity: DeviceCapacity? = DeviceCapacity(totalBytes: 100_000_000, availableBytes: 10_000_000)
    private var callIndex = 0

    func currentCapacity() -> DeviceCapacity? {
        defer { callIndex += 1 }
        if callIndex < capacitySequence.count { return capacitySequence[callIndex] }
        return fixedCapacity
    }
}

/// A real (not fake) CleanupService is used in most PerformCleanupUseCase
/// tests, since CleanupService itself has no PhotoKit/Contacts dependency
/// beyond the protocols already faked above — this exercises the real
/// integration between PerformCleanupUseCase and CleanupService, not just
/// PerformCleanupUseCase's own logic in isolation.

// MARK: - Scan-pipeline detector fakes

final class FakeDuplicateDetector: DuplicateDetectorProtocol, @unchecked Sendable {
    var result: [PhotoGroup] = []
    private(set) var callCount = 0
    /// Optional shared event recorder so tests can pin phase ordering.
    var onRun: (@Sendable (String) -> Void)?
    func detectExactDuplicates(in assets: [PhotoAsset], photoLibrary: PhotoLibraryServiceProtocol) async throws -> [PhotoGroup] {
        callCount += 1
        onRun?("duplicates")
        return result
    }
}

final class FakeSimilarityDetector: SimilarityDetectorProtocol, @unchecked Sendable {
    var result: [PhotoGroup] = []
    /// Assets the use case handed in — lets tests assert screenshots and
    /// exact-duplicate members are excluded from similarity analysis.
    private(set) var receivedAssets: [PhotoAsset] = []
    var onRun: (@Sendable (String) -> Void)?
    func detectSimilarGroups(in assets: [PhotoAsset], photoLibrary: PhotoLibraryServiceProtocol) async throws -> [PhotoGroup] {
        onRun?("similarity")
        receivedAssets = assets
        return result
    }
}

final class FakeScreenshotDetector: ScreenshotDetectorProtocol, @unchecked Sendable {
    /// Detected screenshots — tests usually script this to the screenshot
    /// subset of the scripted photo assets, mirroring the real detector's
    /// mediaSubtypes filter.
    var detected: [PhotoAsset] = []
    func detectScreenshots(in assets: [PhotoAsset]) -> [PhotoAsset] {
        detected
    }
}

final class FakeVideoScanner: VideoScannerProtocol, @unchecked Sendable {
    var result: [VideoAsset] = []
    private(set) var callCount = 0
    func scanVideos(photoLibrary: PhotoLibraryServiceProtocol, onBatch: @escaping @Sendable (Int, Int) -> Void) async throws -> [VideoAsset] {
        callCount += 1
        return result
    }
}

/// In-memory scan cache so AppEnvironment can be built in ViewModel tests
/// without touching the real on-disk cache.
final class FakeScanCache: ScanCacheProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _stored: ScanResult?
    var stored: ScanResult? {
        lock.lock(); defer { lock.unlock() }
        return _stored
    }
    func load() -> ScanResult? { stored }
    func save(_ result: ScanResult) {
        lock.lock(); defer { lock.unlock() }
        _stored = result
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        _stored = nil
    }
}
