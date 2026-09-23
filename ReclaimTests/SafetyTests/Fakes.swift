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

    func currentAuthorization() -> PermissionState { authorization }
    func requestAuthorization() async -> PermissionState { authorization }
    func presentLimitedLibraryPicker() async {}

    func fetchPhotoAssets(onBatch: @Sendable (Int, Int) -> Void) async throws -> [PhotoAsset] { [] }
    func fetchVideoAssets(onBatch: @Sendable (Int, Int) -> Void) async throws -> [VideoAsset] { [] }
    func resourceByteSize(forAssetID id: String) async throws -> Int64 { 0 }
    func contentHash(forAssetID id: String) async throws -> String { "" }
    func requestThumbnail(forAssetID id: String, targetSize: CGSize) async -> ThumbnailPixels? { nil }

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
