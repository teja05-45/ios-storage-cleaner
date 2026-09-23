//
//  FileManager+Storage.swift
//  Reclaim
//
//  Document 04 §1 module map. Wraps the exact URLResourceKeys chosen in
//  ADR-03 (Document 14): `.volumeAvailableCapacityForImportantUsageKey` for
//  available space (Apple's documented guidance for storage decisions made
//  in response to a user request — this app's exact scenario), and
//  `.volumeTotalCapacityKey` for total capacity. "Used" is derived by
//  subtraction; iOS exposes no direct "used bytes" key.
//
//  This lives in Core/Extensions (Foundation-only) per Document 04's module
//  map, even though it's consumed by Services/StorageService.swift.
//

import Foundation

struct DeviceCapacity: Sendable {
    let totalBytes: Int64
    let availableBytes: Int64
    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
}

extension FileManager {
    /// Reads volume capacity for the app's own container. Returns nil if
    /// the resource values are unavailable (documented as a real,
    /// non-fabricated possibility — the Dashboard shows an error state in
    /// that case rather than a fabricated number, per Document 02 §2.7).
    func deviceCapacity() -> DeviceCapacity? {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? homeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else {
            return nil
        }

        guard let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }

        return DeviceCapacity(totalBytes: Int64(total), availableBytes: available)
    }
}
