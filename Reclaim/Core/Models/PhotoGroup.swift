//
//  PhotoGroup.swift
//  Reclaim
//
//  Document 05 §2. A cluster of related PhotoAssets (exact duplicates or
//  visually similar). Carries the single most safety-relevant invariant in
//  the photo pipeline: the recommended/chosen "keep" photo is never present
//  in `selection`.
//

import Foundation

struct PhotoGroup: Identifiable, Sendable {
    let id: UUID
    let kind: PhotoGroupKind
    let members: [PhotoAsset]

    /// PhotoAsset.id the algorithm suggests keeping (Document 06 §3).
    var recommendedKeepID: String

    /// Non-nil once the user overrides the recommendation by tapping
    /// "Keep this instead" (Document 02 §4.4).
    var userChosenKeepID: String?

    /// Asset IDs currently marked for deletion within this group.
    /// INVARIANT: `effectiveKeepID` is never a member of this set. Enforced
    /// by every mutating method below — there is no public API on this type
    /// that can put the app into the illegal state of both keeping and
    /// deleting the same asset (Document 05 §2, Document 08 §1 "Selection logic").
    private(set) var selection: Set<String>

    /// 0...1, see Document 06 §2 step 8 for derivation.
    let confidence: Double

    init(
        id: UUID = UUID(),
        kind: PhotoGroupKind,
        members: [PhotoAsset],
        recommendedKeepID: String,
        userChosenKeepID: String? = nil,
        selection: Set<String> = [],
        confidence: Double
    ) {
        self.id = id
        self.kind = kind
        self.members = members
        self.recommendedKeepID = recommendedKeepID
        self.userChosenKeepID = userChosenKeepID
        // Strip the effective keep out of any seeded selection so the
        // invariant holds even for a caller-constructed initial state
        // (e.g. a test fixture).
        var seeded = selection
        let keep = userChosenKeepID ?? recommendedKeepID
        seeded.remove(keep)
        self.selection = seeded
        self.confidence = confidence
    }

    var effectiveKeepID: String { userChosenKeepID ?? recommendedKeepID }

    var recoverableBytes: Int64 {
        members
            .filter { selection.contains($0.id) }
            .reduce(0) { $0 + $1.byteSize }
    }

    /// Toggle an individual asset's selection state. Silently refuses to
    /// select the effective keep — this is the single choke point that
    /// upholds the group invariant; no other code path mutates `selection`.
    mutating func toggleSelection(for assetID: String) {
        guard assetID != effectiveKeepID else { return }
        guard members.contains(where: { $0.id == assetID }) else { return }
        if selection.contains(assetID) {
            selection.remove(assetID)
        } else {
            selection.insert(assetID)
        }
    }

    /// "Select group" bulk action — selects every member except the
    /// effective keep. This is the *only* place selection can be bulk-set,
    /// and it always, structurally, excludes the keep photo (Document 02 §4.3:
    /// "the app never pre-selects the photo it just recommended keeping").
    mutating func selectAllExceptKeep() {
        selection = Set(members.map(\.id)).subtracting([effectiveKeepID])
    }

    mutating func deselectAll() {
        selection = []
    }

    /// Overriding the keep choice automatically clears the new keep from
    /// selection if it happened to be selected — the invariant holds through
    /// this transition too, never producing a moment where both are true.
    mutating func setUserChosenKeep(_ assetID: String) {
        guard members.contains(where: { $0.id == assetID }) else { return }
        userChosenKeepID = assetID
        selection.remove(assetID)
    }
}
