//
//  ContactService.swift
//  Reclaim
//
//  Document 03 §4 / Document 04 §2: the only file in the contacts pipeline
//  that imports Contacts. Protocol-first for the same testability reason as
//  PhotoLibraryService.
//

import Foundation

protocol ContactServiceProtocol: Sendable {
    func currentAuthorization() -> PermissionState

    /// Requests Contacts authorization. Requested only from the Contacts
    /// screen itself — never bundled with the Photos permission prompt
    /// (Document 07 §5: each permission is requested at the point of first
    /// real need, never batched at launch).
    func requestAuthorization() async -> PermissionState

    /// Fetches every contact using the minimal key set the app actually
    /// needs (given name, family name, phone numbers, emails, image
    /// availability) — never over-fetches (Document 07 §5).
    func fetchAllContacts() async throws -> [ContactCandidate]

    /// Live field values for a specific contact, used to render the
    /// merge-preview field diff (Document 05 §5 note: display always reads
    /// current data, never a stale cached copy).
    func fetchDisplayFields(forContactID id: String) async throws -> ContactDisplayFields

    /// Whether every ID in `ids` still resolves to a real, current
    /// CNContact. Used by PerformCleanupUseCase's revalidation step (ADR-05).
    func stillValidContactIDs(_ ids: Set<String>) async -> Set<String>

    /// Deletes the given contacts via CNSaveRequest. No OS-level secondary
    /// confirmation exists for this API (ADR-08) — the in-app Review screen
    /// carries the full safety weight for this category. Returns the IDs
    /// actually confirmed deleted.
    func deleteContacts(ids: Set<String>) async throws -> Set<String>
}

/// Live display data for the merge-preview field diff. Kept separate from
/// ContactCandidate (which only holds normalized comparison keys) so the
/// preview always shows real, human-readable values.
struct ContactDisplayFields: Sendable {
    let givenName: String
    let familyName: String
    let phoneNumbers: [String]
    let emailAddresses: [String]
}
