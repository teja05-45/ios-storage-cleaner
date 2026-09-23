//
//  ScanContactsUseCase.swift
//  Reclaim
//

import Foundation

struct ScanContactsUseCase {
    let contactService: ContactServiceProtocol
    let duplicateContactDetector: DuplicateContactDetectorProtocol

    func execute() async throws -> [ContactGroup] {
        guard contactService.currentAuthorization().isUsable else {
            throw ReclaimError.permissionNotGranted(.contacts)
        }
        let contacts = try await contactService.fetchAllContacts()
        return duplicateContactDetector.detectDuplicateGroups(in: contacts)
    }
}

/// Document 01 §3.1: real device capacity + the current selection's
/// recoverable estimate, never a fabricated pre-scan number.
struct ComputeStorageSummaryUseCase {
    let storageService: StorageServiceProtocol

    func execute(
        recoverableBytes: Int64,
        recoverableByCategory: [CleanupCategory: Int64],
        lastScanDate: Date?
    ) -> StorageSummary? {
        guard let capacity = storageService.currentCapacity() else { return nil }
        return StorageSummary(
            totalCapacityBytes: capacity.totalBytes,
            usedBytes: capacity.usedBytes,
            availableBytes: capacity.availableBytes,
            recoverableBytes: recoverableBytes,
            recoverableByCategory: recoverableByCategory,
            lastScanDate: lastScanDate
        )
    }
}
