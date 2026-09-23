//
//  StorageService.swift
//  Reclaim
//
//  Document 04 §1. Wraps FileManager.deviceCapacity() (Core/Extensions) —
//  this is the only place "used/total/available" gets turned into a
//  StorageSummary. Never invents a number iOS doesn't expose
//  (Document 01 §3.1, Document 07 §9).
//

import Foundation

protocol StorageServiceProtocol: Sendable {
    /// Real, OS-reported total/used/available capacity. `recoverableBytes`/
    /// `recoverableByCategory` are supplied by the caller from the current
    /// ScanResult's selection — this service never computes those itself,
    /// since it has no knowledge of scan state (single-responsibility split
    /// matches Document 04's dependency-direction rule: StorageService
    /// doesn't depend on ScanResult).
    func currentCapacity() -> DeviceCapacity?
}

struct StorageServiceLive: StorageServiceProtocol {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func currentCapacity() -> DeviceCapacity? {
        fileManager.deviceCapacity()
    }
}
