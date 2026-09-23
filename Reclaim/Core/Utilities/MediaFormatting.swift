//
//  MediaFormatting.swift
//  Reclaim
//
//  Shared, deterministic formatting for video/photo metadata shown on
//  category screens (Document 02 §4.6: duration badge, resolution, date).
//  Pure Foundation — unit-tested without a device (Document 03 §4).
//

import Foundation
import CoreGraphics

enum MediaFormatting {
    /// "0:47", "12:05", "1:02:03" — hours shown only when present.
    /// Sub-second durations round to the nearest second.
    static func duration(from timeInterval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(timeInterval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// "1920 × 1080" — the × separator matches the UX spec's metadata row.
    static func resolution(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height))"
    }

    /// Locale-appropriate date ("Jun 2, 2024"), or "—" when the asset has
    /// no capture date (a real case for synced/imported assets).
    static func captureDate(from date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
