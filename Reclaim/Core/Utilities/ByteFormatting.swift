//
//  ByteFormatting.swift
//  Reclaim
//
//  Thin wrapper around ByteCountFormatter so every screen formats storage
//  numbers identically (Document 02 §2.3: numbers that matter use
//  monospacedDigit; this utility only owns the string, not the font).
//

import Foundation

enum ByteFormatting {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    /// Human-readable string for a byte count, e.g. "1.2 GB", "340 KB", "0 bytes".
    static func string(fromByteCount bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
