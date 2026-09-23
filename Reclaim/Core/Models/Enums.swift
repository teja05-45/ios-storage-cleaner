//
//  Enums.swift
//  Reclaim
//
//  Core/Models — imports Foundation only. Never Photos/Contacts/AVFoundation.
//  See Document 05 §11.
//

import Foundation

/// Kind of media a `PhotoAsset`/`VideoAsset` represents.
enum MediaKind: String, Codable, Sendable {
    case photo
    case video
}

/// Why a `PhotoGroup` was formed.
enum PhotoGroupKind: String, Codable, Sendable {
    case exactDuplicate
    case similar
}

/// Confidence tier for a `ContactGroup`. See Document 06 §6.
enum ContactDuplicateTier: String, Codable, Sendable {
    case exact
    case probable
}

/// The four cleanup categories the Dashboard/Review screens aggregate across.
enum CleanupCategory: String, Codable, Sendable, CaseIterable {
    case similarPhotos
    case screenshots
    case largeVideos
    case duplicateContacts
}

/// Status of a scan, reported phase-by-phase (Document 09 §3).
enum ScanStatus: Equatable, Sendable {
    case notStarted
    case scanning(phase: String, completed: Int, total: Int)
    case completed
    case cancelled
    case failed(String)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

/// PhotoKit/Contacts authorization, normalized into one shared shape used by
/// every permission-gated screen. `.limited` is a **first-class, distinct**
/// case — never collapsed into a boolean "has access" — per ADR-04
/// (Document 14) and Document 01 §3.7 / Document 07 §6.
enum PermissionState: Equatable, Sendable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted

    /// Whether the app should attempt to use the associated framework at all.
    /// `.limited` counts as usable — the app operates fully on the granted subset.
    var isUsable: Bool {
        switch self {
        case .authorized, .limited: return true
        case .notDetermined, .denied, .restricted: return false
        }
    }
}

/// Which framework a `PermissionState` describes, so a single permission
/// banner/view can be reused for both Photos and Contacts (Document 02).
enum PermissionDomain: String, Sendable {
    case photos
    case contacts
}

/// Reason a specific item could not be deleted, surfaced honestly in
/// `CleanupSummary.failures` rather than silently dropped (Document 05 §10,
/// Document 07 §7, ADR-05).
enum CleanupFailureReason: Equatable, Sendable {
    /// The asset/contact no longer resolves — it was deleted, edited away, or
    /// otherwise vanished between scan and confirmation.
    case staleAsset
    /// Authorization changed between scan and confirmation (e.g. revoked in
    /// Settings while the app was backgrounded).
    case permissionRevoked
    /// The OS-level delete call itself reported failure for this item
    /// (e.g. the user declined the native "Delete Photos" dialog, or a
    /// framework error occurred).
    case frameworkError(String)
}
