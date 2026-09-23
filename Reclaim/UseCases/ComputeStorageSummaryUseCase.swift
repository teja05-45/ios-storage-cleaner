//
//  ComputeStorageSummaryUseCase.swift
//  Reclaim
//
//  Document 01 §3.1: real device capacity + the current selection's
//  recoverable estimate, never a fabricated pre-scan number. Extracted to
//  its own file (audit OPEN-1) — it has nothing to do with contact
//  scanning and was only co-located by accident.
//

import Foundation

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
