//
//  Logging.swift
//  Reclaim
//
//  Document 07 §12 / this build's instructions §12: never log contact
//  names, phone numbers, emails, asset identifiers, filenames, or image
//  metadata. This wrapper's API only accepts primitives/enums for the
//  parts of a message that vary — there is no overload that accepts a
//  model instance, a String built by interpolating a model's fields, or a
//  PHAsset/CNContact — so a call site would have to work hard, visibly, to
//  violate the rule rather than doing it by accident via string interpolation.
//

import Foundation
import os

enum Log {
    private static let subsystem = "com.reclaim.app"

    private static let scan = Logger(subsystem: subsystem, category: "scan")
    private static let cleanup = Logger(subsystem: subsystem, category: "cleanup")
    private static let permissions = Logger(subsystem: subsystem, category: "permissions")
    private static let general = Logger(subsystem: subsystem, category: "general")

    /// `count`/`durationMs` etc. are the only "data" these calls accept —
    /// aggregate numbers, never identifiers or content.
    static func scanStarted(category: CleanupCategory) {
        scan.info("scan started: \(category.rawValue, privacy: .public)")
    }

    static func scanCompleted(category: CleanupCategory, itemCount: Int, durationMs: Int) {
        scan.info("scan completed: \(category.rawValue, privacy: .public) items=\(itemCount, privacy: .public) durationMs=\(durationMs, privacy: .public)")
    }

    static func scanFailed(category: CleanupCategory) {
        scan.error("scan failed: \(category.rawValue, privacy: .public)")
    }

    static func cleanupStarted(itemCount: Int) {
        cleanup.info("cleanup started: itemCount=\(itemCount, privacy: .public)")
    }

    static func cleanupCompleted(deletedCount: Int, failureCount: Int) {
        cleanup.info("cleanup completed: deleted=\(deletedCount, privacy: .public) failures=\(failureCount, privacy: .public)")
    }

    static func permissionStateChanged(domain: PermissionDomain, isUsable: Bool) {
        permissions.info("permission changed: domain=\(domain.rawValue, privacy: .public) usable=\(isUsable, privacy: .public)")
    }

    static func error(_ message: StaticString) {
        general.error("\(message)")
    }
}
