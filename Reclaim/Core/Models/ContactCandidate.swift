//
//  ContactCandidate.swift
//  Reclaim
//
//  Document 05 §5-6. normalizedPhones/normalizedEmails store comparison
//  keys, not necessarily the literal displayed value — the group detail
//  screen re-fetches the live CNContact for display so the user always sees
//  real, current data, never a stale cached copy (Document 05 §5 note).
//

import Foundation

struct ContactCandidate: Identifiable, Hashable, Sendable {
    /// CNContact.identifier
    let id: String
    let givenName: String
    let familyName: String
    let normalizedPhones: [String]
    let normalizedEmails: [String]
    /// Total populated fields, used to suggest which record is "richer"
    /// as the default primary/keep record.
    let fieldCount: Int
    let imageDataAvailable: Bool

    var displayName: String {
        let full = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "(No Name)" : full
    }
}

struct ContactGroup: Identifiable, Sendable {
    let id: UUID
    let tier: ContactDuplicateTier
    let members: [ContactCandidate]
    /// e.g. "Same phone number, similar name" — shown per Document 01 §3.5's
    /// disclosure requirement.
    let matchReason: String

    /// The record suggested to keep — defaults to the member with the
    /// highest fieldCount ("richer" record), ties broken by array order.
    var recommendedPrimaryID: String

    /// Member IDs marked for deletion. Never includes recommendedPrimaryID
    /// by default, mirroring PhotoGroup's invariant.
    private(set) var selection: Set<String>

    /// 0...1 for .probable; 1.0 for .exact (Document 06 §6).
    let confidence: Double

    init(
        id: UUID = UUID(),
        tier: ContactDuplicateTier,
        members: [ContactCandidate],
        matchReason: String,
        recommendedPrimaryID: String,
        selection: Set<String> = [],
        confidence: Double
    ) {
        self.id = id
        self.tier = tier
        self.members = members
        self.matchReason = matchReason
        self.recommendedPrimaryID = recommendedPrimaryID
        var seeded = selection
        seeded.remove(recommendedPrimaryID)
        self.selection = seeded
        self.confidence = confidence
    }

    mutating func toggleSelection(for contactID: String) {
        guard contactID != recommendedPrimaryID else { return }
        guard members.contains(where: { $0.id == contactID }) else { return }
        if selection.contains(contactID) {
            selection.remove(contactID)
        } else {
            selection.insert(contactID)
        }
    }

    /// Field-diff preview data: which fields differ between the primary and
    /// a given non-primary member, so Document 01 §3.5's "what would be
    /// lost" disclosure can be rendered. Pure comparison, no framework
    /// dependency — the live CNContact values are supplied by the ViewModel.
    struct FieldDiff: Sendable {
        let label: String
        let primaryValue: String?
        let otherValue: String?
        var wouldBeLost: Bool { otherValue != nil && otherValue != primaryValue }
    }
}
