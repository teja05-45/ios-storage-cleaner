//
//  ReviewViewModel.swift
//  Reclaim
//
//  Document 02 §4.9, this build's instructions §7. Reads exclusively from
//  ReviewStore — holds no parallel selection state of its own. The single
//  `confirmCleanup()` method is the ONLY call site in the ViewModel layer
//  that invokes PerformCleanupUseCase.
//

import Foundation
import Observation

@Observable
@MainActor
final class ReviewViewModel {
    private let environment: AppEnvironment

    private(set) var isCleaningUp = false
    private(set) var cleanupSummary: CleanupSummary?
    private(set) var cleanupError: ReclaimError?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var reviewStore: ReviewStore { environment.reviewStore }

    var selection: CleanupSelection { environment.reviewStore.currentSelection }
    var estimatedRecoverableBytes: Int64 { environment.reviewStore.estimatedRecoverableBytes }
    var canConfirm: Bool { !selection.isEmpty && !isCleaningUp }

    // MARK: - Per-item removal (Document 02 §4.8)

    // Removing an item directly from Review mutates the single source of
    // truth, so the totals, the confirm button's enabled state, and the
    // eventual CleanupSelection can never disagree with what is on screen.

    func removePhoto(id: String) {
        environment.reviewStore.deselectPhoto(assetID: id)
    }

    func removeScreenshot(id: String) {
        environment.reviewStore.toggleScreenshotSelection(assetID: id)
    }

    func removeVideo(id: String) {
        environment.reviewStore.toggleVideoSelection(assetID: id)
    }

    func removeContact(id: String) {
        environment.reviewStore.deselectContact(contactID: id)
    }

    /// The ONLY call site for PerformCleanupUseCase in the ViewModel layer.
    /// Called exclusively from the Review screen's explicit "Delete
    /// Forever"-style confirm button — never from a swipe action, never
    /// from a category screen, never automatically.
    func confirmCleanup() async {
        guard canConfirm else { return }
        isCleaningUp = true
        cleanupError = nil
        Log.cleanupStarted(itemCount: selection.totalItemCount)

        do {
            let summary = try await environment.performCleanupUseCase().execute(selection, confirmed: true)
            cleanupSummary = summary
            // OPEN-3: prune exactly what the OS confirmed deleted — never the
            // requested set. Items the OS did not confirm stay visible (and
            // stay in the store) alongside their reported failure, instead of
            // vanishing from the UI while still existing in the library.
            environment.reviewStore.removeFromSelection(
                photoKitIDs: summary.deletedPhotoAssetIDs,
                contactIDs: summary.deletedContactIDs
            )
            Log.cleanupCompleted(deletedCount: summary.totalDeletedCount, failureCount: summary.failures.count)
        } catch let error as ReclaimError {
            cleanupError = error
        } catch {
            cleanupError = .frameworkFailure("\(error)")
        }
        isCleaningUp = false
    }
}
