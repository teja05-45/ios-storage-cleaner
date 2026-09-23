//
//  ReclaimError.swift
//  Reclaim
//
//  Typed error surface for the whole app. Service methods that touch
//  PhotoKit/Contacts/AVFoundation are `async throws` and surface one of
//  these cases rather than passing an `NSError` straight through to a
//  ViewModel (Document 03 §7).
//

import Foundation

enum ReclaimError: Error, Equatable, Sendable {
    /// A destructive operation was attempted with an empty selection.
    /// `PerformCleanupUseCase` throws this structurally — see Document 05 §9
    /// and safety test `test_emptySelectionCannotBeConfirmed`.
    case emptySelection

    /// `PerformCleanupUseCase.execute` was called with `confirmed: false`.
    /// Distinct from `.emptySelection` so tests and logs can tell "there
    /// was nothing to delete" apart from "there was something to delete but
    /// the user never confirmed it" — both are refused, but they're
    /// different situations.
    case notConfirmed

    /// The relevant PhotoKit/Contacts permission is not currently usable
    /// (`.notDetermined`, `.denied`, or `.restricted`). The service layer
    /// checks authorization *before* attempting any framework call and
    /// returns this rather than letting the call fail loudly (Document 07 §6).
    case permissionNotGranted(PermissionDomain)

    /// A framework call (PhotoKit fetch, Contacts fetch, resource read)
    /// failed. The underlying description is preserved for logging (never
    /// for display verbatim to the user without translation — Document 02 §2.7
    /// requires specific, actionable copy, not a raw framework error string).
    case frameworkFailure(String)

    /// A scan was cancelled by the user. Distinct from `.failed` — this is
    /// not an error state, partial results are preserved (Document 09 §8).
    case scanCancelled

    /// An asset or contact that was selected during Review no longer
    /// resolves at cleanup time (ADR-05). Carries the id for failure
    /// reporting, never for display.
    case staleSelection(id: String)

    var isUserFacingRecoverable: Bool {
        switch self {
        case .emptySelection, .notConfirmed, .permissionNotGranted, .scanCancelled, .staleSelection:
            return true
        case .frameworkFailure:
            return false
        }
    }
}
