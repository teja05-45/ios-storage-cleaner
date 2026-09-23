//
//  StorageSummary.swift
//  Reclaim
//
//  Document 05 §8. totalCapacityBytes/usedBytes/availableBytes come directly
//  (or, for usedBytes, by simple subtraction) from URLResourceKey volume
//  capacity keys — never modeled (Document 01 §3.1, ADR-03 in Document 14).
//

import Foundation

struct StorageSummary: Sendable {
    let totalCapacityBytes: Int64
    let usedBytes: Int64
    let availableBytes: Int64
    /// Derived from the current ScanResult's selection — never a guess
    /// prior to scanning (Document 01 §3.1).
    let recoverableBytes: Int64
    let recoverableByCategory: [CleanupCategory: Int64]
    let lastScanDate: Date?
}
