//
//  PerformCleanupUseCase.swift
//  Reclaim
//
//  THE SINGLE MOST SAFETY-CRITICAL FUNCTION IN THE ENTIRE APP
//  (Document 13 §2.9). This is the only type in the codebase permitted to
//  initiate destructive operations, and its `execute` method is the only
//  method on it that does so. Enforces, structurally:
//
//   1. Empty selection cannot be confirmed (throws immediately).
//   2. Current authorization is re-checked, not assumed from scan time.
//   3. Every selected ID is revalidated against the live framework state
//      immediately before deletion (ADR-05) — stale IDs are dropped from
//      the executable set and reported as failures, never silently
//      executed against or silently omitted from the result.
//   4. Deletion only proceeds for the revalidated subset.
//   5. The result (`CleanupSummary`) is built entirely from what actually
//      happened — never from what was requested (Document 05 §10).
//   6. `bytesFreed` is computed from an independently recomputed post-
//      cleanup StorageSummary, never copied from the pre-cleanup estimate
//      (this build's instructions §9).
//
//  See ReclaimTests/SafetyTests/PerformCleanupUseCaseSafetyTests.swift for
//  the test suite that targets every one of these guarantees directly.
//

import Foundation

struct PerformCleanupUseCase {
    let photoLibrary: PhotoLibraryServiceProtocol
    let contactService: ContactServiceProtocol
    let cleanupService: CleanupServiceProtocol
    let storageService: StorageServiceProtocol

    /// - Parameter confirmed: must be `true` — this is not a formality.
    ///   The caller (ReviewViewModel) only ever calls this method from the
    ///   single confirm-button handler, after the user has seen the full
    ///   Review screen. There is no other call site anywhere in the app.
    func execute(_ selection: CleanupSelection, confirmed: Bool) async throws -> CleanupSummary {
        // GUARD 1: no confirmation, no deletion. Structural, not advisory —
        // this line is what safety test `test_deletionRequiresExplicitConfirmation`
        // exercises directly.
        guard confirmed else {
            throw ReclaimError.notConfirmed
        }

        // GUARD 2: empty selection cannot be confirmed, regardless of the
        // `confirmed` flag's value.
        guard !selection.isEmpty else {
            throw ReclaimError.emptySelection
        }

        let preCleanupCapacity = storageService.currentCapacity()

        // GUARD 3: re-check current authorization. A permission revoked in
        // Settings while the app was backgrounded between Review and
        // Confirm must not result in a blind deletion attempt.
        let photoKitIDs = selection.allPhotoKitAssetIDs
        var revalidatedPhotoKitIDs: Set<String> = []
        var staleFailures: [CleanupFailure] = []

        if !photoKitIDs.isEmpty {
            if photoLibrary.currentAuthorization().isUsable {
                // GUARD 4: revalidate every selected PhotoKit asset against
                // the live library — an asset deleted, edited away, or
                // otherwise vanished between scan and confirmation is
                // dropped from the executable set here (ADR-05), not
                // discovered as a surprise failure from the delete call.
                let stillValid = await photoLibrary.stillValidAssetIDs(photoKitIDs)
                revalidatedPhotoKitIDs = stillValid
                let stale = photoKitIDs.subtracting(stillValid)
                staleFailures.append(contentsOf: categorizeStalePhotoKit(stale, selection: selection))
            } else {
                // Permission revoked entirely — every PhotoKit item in this
                // selection fails with `.permissionRevoked`, none are
                // attempted.
                staleFailures.append(contentsOf: categorizeStalePhotoKit(photoKitIDs, reason: .permissionRevoked, selection: selection))
            }
        }

        var revalidatedContactIDs: Set<String> = []
        if !selection.contactIDs.isEmpty {
            if contactService.currentAuthorization().isUsable {
                let stillValid = await contactService.stillValidContactIDs(selection.contactIDs)
                revalidatedContactIDs = stillValid
                let stale = selection.contactIDs.subtracting(stillValid)
                for id in stale { staleFailures.append(.contact(id: id, reason: .staleAsset)) }
            } else {
                for id in selection.contactIDs { staleFailures.append(.contact(id: id, reason: .permissionRevoked)) }
            }
        }

        let categorized = CategorizedSelection(
            photoIDs: selection.photoAssetIDs.intersection(revalidatedPhotoKitIDs),
            screenshotIDs: selection.screenshotAssetIDs.intersection(revalidatedPhotoKitIDs),
            videoIDs: selection.videoAssetIDs.intersection(revalidatedPhotoKitIDs),
            contactIDs: revalidatedContactIDs
        )

        // GUARD 5: if revalidation dropped everything, there is nothing
        // left to execute — this is reported as an all-failures result,
        // never silently treated as success.
        let revalidatedSelection = CleanupSelection(
            photoAssetIDs: categorized.photoIDs,
            screenshotAssetIDs: categorized.screenshotIDs,
            videoAssetIDs: categorized.videoIDs,
            contactIDs: categorized.contactIDs
        )

        var executionFailures: [CleanupFailure] = []
        var deletedPhotoKitIDs: Set<String> = []
        var deletedContactIDs: Set<String> = []

        if !revalidatedSelection.isEmpty {
            let result = await cleanupService.execute(
                revalidatedSelection,
                categorized: categorized,
                photoLibrary: photoLibrary,
                contactService: contactService
            )
            deletedPhotoKitIDs = result.deletedPhotoKitIDs
            deletedContactIDs = result.deletedContactIDs
            executionFailures = result.failures
        }

        // Post-cleanup storage recomputed independently — never copied from
        // the pre-cleanup estimate (this build's instructions §9,
        // Document 01 §3.6).
        let postCleanupCapacity = storageService.currentCapacity()
        let bytesFreed = computeBytesFreed(before: preCleanupCapacity, after: postCleanupCapacity)

        let deletedPhotoCount = categorized.photoIDs.intersection(deletedPhotoKitIDs).count
        let deletedScreenshotCount = categorized.screenshotIDs.intersection(deletedPhotoKitIDs).count
        let deletedVideoCount = categorized.videoIDs.intersection(deletedPhotoKitIDs).count

        return CleanupSummary(
            requested: selection,
            deletedPhotoCount: deletedPhotoCount,
            deletedVideoCount: deletedVideoCount,
            deletedScreenshotCount: deletedScreenshotCount,
            deletedContactCount: deletedContactIDs.count,
            bytesFreed: bytesFreed,
            failures: staleFailures + executionFailures,
            // OPEN-3: the summary now carries exactly what the OS confirmed,
            // so callers can prune live state without touching anything that
            // merely *requested* deletion and failed or went stale.
            deletedPhotoAssetIDs: deletedPhotoKitIDs,
            deletedContactIDs: deletedContactIDs
        )
    }

    // MARK: - Private

    private func categorizeStalePhotoKit(_ ids: Set<String>, reason: CleanupFailureReason = .staleAsset, selection: CleanupSelection) -> [CleanupFailure] {
        ids.map { id in
            if selection.photoAssetIDs.contains(id) { return .photo(id: id, reason: reason) }
            if selection.screenshotAssetIDs.contains(id) { return .screenshot(id: id, reason: reason) }
            return .video(id: id, reason: reason)
        }
    }

    /// Honest, disclosed limitation (this build's instructions §9): if
    /// either capacity reading is unavailable, `bytesFreed` cannot be
    /// reliably established and is reported as 0 with the caller (the
    /// Cleanup Result screen) expected to fall back to showing the
    /// pre-cleanup *estimate* labeled explicitly as an estimate, never as a
    /// fabricated "freed" number.
    private func computeBytesFreed(before: DeviceCapacity?, after: DeviceCapacity?) -> Int64 {
        guard let before, let after else { return 0 }
        return max(0, after.availableBytes - before.availableBytes)
    }
}
