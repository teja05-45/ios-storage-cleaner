//
//  ReviewStore.swift
//  Reclaim
//
//  Document 04 §1, this build's instructions §7. The single source of
//  truth for selection across every category. Every category screen reads
//  and writes selection THROUGH this store's methods — none of them hold a
//  parallel, private `Set<String>` of their own. This is what makes
//  "Review count == sum of real category selections" true by construction
//  rather than by convention: there is only one place selection state
//  lives, so there is nothing for it to drift from.
//
//  @Observable (iOS 17+) so every SwiftUI view reading any property here
//  re-renders automatically on mutation — no separate Combine plumbing
//  needed (Document 03 §2).
//

import Foundation
import Observation

@Observable
@MainActor
final class ReviewStore {

    // MARK: - Photo groups (exact duplicates + similar photos share this shape)

    private(set) var exactDuplicateGroups: [PhotoGroup] = []
    private(set) var similarPhotoGroups: [PhotoGroup] = []

    // MARK: - Screenshots

    private(set) var screenshotAssets: [PhotoAsset] = []
    private(set) var selectedScreenshotIDs: Set<String> = []

    // MARK: - Large videos

    private(set) var videoAssets: [VideoAsset] = []
    private(set) var selectedVideoIDs: Set<String> = []

    // MARK: - Contacts

    private(set) var contactGroups: [ContactGroup] = []

    // MARK: - Scan metadata

    private(set) var lastScanDate: Date?
    private(set) var scannedWithLimitedPhotoAccess: Bool = false

    // MARK: - Loading scan results

    func loadPhotoResults(exactDuplicates: [PhotoGroup], similar: [PhotoGroup], scannedWithLimitedAccess: Bool) {
        exactDuplicateGroups = exactDuplicates
        similarPhotoGroups = similar
        scannedWithLimitedPhotoAccess = scannedWithLimitedAccess
        lastScanDate = Date()
    }

    func loadScreenshots(_ assets: [PhotoAsset]) {
        screenshotAssets = assets
        selectedScreenshotIDs = []
    }

    func loadVideos(_ assets: [VideoAsset]) {
        videoAssets = assets
        selectedVideoIDs = []
    }

    func loadContactGroups(_ groups: [ContactGroup]) {
        contactGroups = groups
    }

    // MARK: - Mutating selection (the ONLY place any of this state changes)

    func toggleExactDuplicateSelection(groupID: UUID, assetID: String) {
        guard let index = exactDuplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
        exactDuplicateGroups[index].toggleSelection(for: assetID)
    }

    func toggleSimilarPhotoSelection(groupID: UUID, assetID: String) {
        guard let index = similarPhotoGroups.firstIndex(where: { $0.id == groupID }) else { return }
        similarPhotoGroups[index].toggleSelection(for: assetID)
    }

    func setUserChosenKeep(groupID: UUID, assetID: String, inExactDuplicates: Bool) {
        if inExactDuplicates {
            guard let index = exactDuplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
            exactDuplicateGroups[index].setUserChosenKeep(assetID)
        } else {
            guard let index = similarPhotoGroups.firstIndex(where: { $0.id == groupID }) else { return }
            similarPhotoGroups[index].setUserChosenKeep(assetID)
        }
    }

    func toggleScreenshotSelection(assetID: String) {
        if selectedScreenshotIDs.contains(assetID) {
            selectedScreenshotIDs.remove(assetID)
        } else {
            selectedScreenshotIDs.insert(assetID)
        }
    }

    func selectAllScreenshots() {
        selectedScreenshotIDs = Set(screenshotAssets.map(\.id))
    }

    func deselectAllScreenshots() {
        selectedScreenshotIDs = []
    }

    func toggleVideoSelection(assetID: String) {
        if selectedVideoIDs.contains(assetID) {
            selectedVideoIDs.remove(assetID)
        } else {
            selectedVideoIDs.insert(assetID)
        }
    }

    func toggleContactSelection(groupID: UUID, contactID: String) {
        guard let index = contactGroups.firstIndex(where: { $0.id == groupID }) else { return }
        contactGroups[index].toggleSelection(for: contactID)
    }

    /// "Select All Recommended" (Document 02 §4.3): the *only* bulk action
    /// in the app that pre-selects anything — selects every non-keep member
    /// of every photo group. Explicit, opt-in, and fully reviewable before
    /// any deletion is possible. PhotoGroup.selectAllExceptKeep() structurally
    /// excludes every effective keep.
    func selectAllRecommendedInPhotoGroups() {
        for index in exactDuplicateGroups.indices {
            exactDuplicateGroups[index].selectAllExceptKeep()
        }
        for index in similarPhotoGroups.indices {
            similarPhotoGroups[index].selectAllExceptKeep()
        }
    }

    /// Clears selection across every photo group (never touches screenshots,
    /// videos, or contacts — bulk actions are per category on purpose).
    func deselectAllInPhotoGroups() {
        for index in exactDuplicateGroups.indices {
            exactDuplicateGroups[index].deselectAll()
        }
        for index in similarPhotoGroups.indices {
            similarPhotoGroups[index].deselectAll()
        }
    }

    /// Removes a single photo from selection, wherever it lives. Used by the
    /// Review screen's per-item remove (Document 02 §4.8). The owning group
    /// is looked up so the mutation still goes through PhotoGroup's guarded
    /// path — never a raw set edit.
    func deselectPhoto(assetID: String) {
        if let index = exactDuplicateGroups.firstIndex(where: { $0.members.contains(where: { $0.id == assetID }) }) {
            exactDuplicateGroups[index].toggleSelection(for: assetID)
        } else if let index = similarPhotoGroups.firstIndex(where: { $0.members.contains(where: { $0.id == assetID }) }) {
            similarPhotoGroups[index].toggleSelection(for: assetID)
        }
    }

    /// Removes a single contact from selection regardless of owning group
    /// (Review screen's per-item remove).
    /// Applies an arbitrary mutation to one live photo group. This is the
    /// only sanctioned way for views to perform compound edits (e.g. the
    /// detail screen's keep-and-deselect combination): the arrays are
    /// private(set), so inout access from a view is impossible by design.
    func mutatePhotoGroup(groupID: UUID, inExactDuplicates: Bool, _ transform: (inout PhotoGroup) -> Void) {
        if inExactDuplicates {
            guard let index = exactDuplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
            transform(&exactDuplicateGroups[index])
        } else {
            guard let index = similarPhotoGroups.firstIndex(where: { $0.id == groupID }) else { return }
            transform(&similarPhotoGroups[index])
        }
    }

    func deselectContact(contactID: String) {
        guard let index = contactGroups.firstIndex(where: { $0.members.contains(where: { $0.id == contactID }) }) else { return }
        contactGroups[index].toggleSelection(for: contactID)
    }

    /// Every currently-selected photo across both group kinds, in stable
    /// group order — the Review screen's photo section data source.
    var selectedPhotoMembers: [PhotoAsset] {
        var members: [PhotoAsset] = []
        for group in exactDuplicateGroups {
            members.append(contentsOf: group.members.filter { group.selection.contains($0.id) })
        }
        for group in similarPhotoGroups {
            members.append(contentsOf: group.members.filter { group.selection.contains($0.id) })
        }
        return members
    }

    var selectedScreenshots: [PhotoAsset] {
        screenshotAssets.filter { selectedScreenshotIDs.contains($0.id) }
    }

    var selectedVideos: [VideoAsset] {
        videoAssets.filter { selectedVideoIDs.contains($0.id) }
    }

    /// Selected contacts paired with their group (the group supplies the
    /// match-reason disclosure on the Review screen).
    var selectedContactMembers: [(group: ContactGroup, member: ContactCandidate)] {
        var result: [(ContactGroup, ContactCandidate)] = []
        for group in contactGroups {
            for member in group.members where group.selection.contains(member.id) {
                result.append((group, member))
            }
        }
        return result
    }

    // MARK: - Aggregation (Review screen reads these — never its own copy)

    var currentSelection: CleanupSelection {
        var photoIDs: Set<String> = []
        // `selection` is `private(set)` on PhotoGroup/ContactGroup — readable
        // from anywhere in the module, settable only through the group's own
        // mutating methods. ReviewStore reads it directly here; this is the
        // single place selection is aggregated across categories.
        for group in exactDuplicateGroups { photoIDs.formUnion(group.selection) }
        for group in similarPhotoGroups { photoIDs.formUnion(group.selection) }

        var contactIDs: Set<String> = []
        for group in contactGroups { contactIDs.formUnion(group.selection) }

        return CleanupSelection(
            photoAssetIDs: photoIDs,
            screenshotAssetIDs: selectedScreenshotIDs,
            videoAssetIDs: selectedVideoIDs,
            contactIDs: contactIDs
        )
    }

    var categorizedSelection: CategorizedSelection {
        let selection = currentSelection
        return CategorizedSelection(
            photoIDs: selection.photoAssetIDs,
            screenshotIDs: selection.screenshotAssetIDs,
            videoIDs: selection.videoAssetIDs,
            contactIDs: selection.contactIDs
        )
    }

    var estimatedRecoverableBytes: Int64 {
        var total: Int64 = 0
        for group in exactDuplicateGroups { total += group.recoverableBytes }
        for group in similarPhotoGroups { total += group.recoverableBytes }
        for asset in screenshotAssets where selectedScreenshotIDs.contains(asset.id) { total += asset.byteSize }
        for asset in videoAssets where selectedVideoIDs.contains(asset.id) { total += asset.byteSize }
        return total
    }

    var recoverableBytesByCategory: [CleanupCategory: Int64] {
        var result: [CleanupCategory: Int64] = [:]
        result[.similarPhotos] = similarPhotoGroups.reduce(0) { $0 + $1.recoverableBytes }
            + exactDuplicateGroups.reduce(0) { $0 + $1.recoverableBytes }
        result[.screenshots] = screenshotAssets.filter { selectedScreenshotIDs.contains($0.id) }.reduce(0) { $0 + $1.byteSize }
        result[.largeVideos] = videoAssets.filter { selectedVideoIDs.contains($0.id) }.reduce(0) { $0 + $1.byteSize }
        result[.duplicateContacts] = 0 // contacts have no meaningful byte size
        return result
    }

    /// Removes selection for IDs that PerformCleanupUseCase's revalidation
    /// step found to be stale, and removes successfully-deleted IDs after
    /// cleanup completes — keeping ReviewStore consistent with reality
    /// rather than continuing to show items that no longer exist.
    func removeFromSelection(photoKitIDs: Set<String>, contactIDs: Set<String>) {
        pruneDeletedAssets(photoKitIDs: photoKitIDs)
        pruneDeletedContacts(contactIDs: contactIDs)
    }

    private func pruneDeletedAssets(photoKitIDs: Set<String>) {
        guard !photoKitIDs.isEmpty else { return }
        exactDuplicateGroups = exactDuplicateGroups.compactMap { Self.prunedGroup($0, deletedIDs: photoKitIDs) }
        similarPhotoGroups = similarPhotoGroups.compactMap { Self.prunedGroup($0, deletedIDs: photoKitIDs) }
        screenshotAssets.removeAll { photoKitIDs.contains($0.id) }
        selectedScreenshotIDs.subtract(photoKitIDs)
        videoAssets.removeAll { photoKitIDs.contains($0.id) }
        selectedVideoIDs.subtract(photoKitIDs)
    }

    /// Rebuilds a group after some of its members were confirmed deleted.
    /// Surviving state is carried over deliberately:
    ///  - `selection` keeps every surviving member's selected-for-deletion
    ///    mark. Since OPEN-3, the OS may confirm only part of a group's
    ///    selection (declined native dialog, partial framework failure);
    ///    survivors must stay selected so the user can retry them from
    ///    exactly where they were, instead of silently losing their picks.
    ///  - `userChosenKeepID` survives when the chosen keep did — a partial
    ///    deletion elsewhere in the group must not reset the user's
    ///    explicit override to the algorithm's recommendation.
    ///  - The keep falls back to the first remaining member only when the
    ///    previous keep is actually gone.
    /// Groups that fall below two members are dissolved (nil): a "group"
    /// of one is no longer a duplicate.
    private static func prunedGroup(_ group: PhotoGroup, deletedIDs: Set<String>) -> PhotoGroup? {
        let remaining = group.members.filter { !deletedIDs.contains($0.id) }
        guard remaining.count > 1 else { return nil }
        let remainingIDs = Set(remaining.map(\.id))
        let survivingUserKeep = group.userChosenKeepID.flatMap { remainingIDs.contains($0) ? $0 : nil }
        let survivingRecommendedKeep = remainingIDs.contains(group.recommendedKeepID) ? group.recommendedKeepID : remaining[0].id
        return PhotoGroup(
            id: group.id,
            kind: group.kind,
            members: remaining,
            recommendedKeepID: survivingRecommendedKeep,
            userChosenKeepID: survivingUserKeep,
            selection: group.selection.intersection(remainingIDs),
            confidence: group.confidence
        )
    }

    private func pruneDeletedContacts(contactIDs: Set<String>) {
        guard !contactIDs.isEmpty else { return }
        contactGroups = contactGroups.compactMap { group in
            let remaining = group.members.filter { !contactIDs.contains($0.id) }
            guard remaining.count > 1 else { return nil } // a "group" of one is no longer a duplicate group
            let remainingIDs = Set(remaining.map(\.id))
            return ContactGroup(
                id: group.id,
                tier: group.tier,
                members: remaining,
                matchReason: group.matchReason,
                recommendedPrimaryID: remainingIDs.contains(group.recommendedPrimaryID) ? group.recommendedPrimaryID : remaining[0].id,
                selection: group.selection.intersection(remainingIDs),
                confidence: group.confidence
            )
        }
    }

}
