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
        exactDuplicateGroups = exactDuplicateGroups.compactMap { group in
            let remaining = group.members.filter { !photoKitIDs.contains($0.id) }
            guard remaining.count > 1 else { return nil } // a "group" of one is no longer a duplicate group
            return PhotoGroup(
                id: group.id,
                kind: group.kind,
                members: remaining,
                recommendedKeepID: remaining.contains(where: { $0.id == group.effectiveKeepID }) ? group.effectiveKeepID : remaining[0].id,
                confidence: group.confidence
            )
        }
        similarPhotoGroups = similarPhotoGroups.compactMap { group in
            let remaining = group.members.filter { !photoKitIDs.contains($0.id) }
            guard remaining.count > 1 else { return nil }
            return PhotoGroup(
                id: group.id,
                kind: group.kind,
                members: remaining,
                recommendedKeepID: remaining.contains(where: { $0.id == group.effectiveKeepID }) ? group.effectiveKeepID : remaining[0].id,
                confidence: group.confidence
            )
        }
        screenshotAssets.removeAll { photoKitIDs.contains($0.id) }
        selectedScreenshotIDs.subtract(photoKitIDs)
        videoAssets.removeAll { photoKitIDs.contains($0.id) }
        selectedVideoIDs.subtract(photoKitIDs)
    }

    private func pruneDeletedContacts(contactIDs: Set<String>) {
        guard !contactIDs.isEmpty else { return }
        contactGroups = contactGroups.compactMap { group in
            let remaining = group.members.filter { !contactIDs.contains($0.id) }
            guard remaining.count > 1 else { return nil }
            return ContactGroup(
                id: group.id,
                tier: group.tier,
                members: remaining,
                matchReason: group.matchReason,
                recommendedPrimaryID: remaining.contains(where: { $0.id == group.recommendedPrimaryID }) ? group.recommendedPrimaryID : remaining[0].id,
                confidence: group.confidence
            )
        }
    }

}
