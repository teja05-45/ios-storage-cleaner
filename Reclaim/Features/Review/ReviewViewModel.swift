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
            environment.reviewStore.removeFromSelection(
                photoKitIDs: selection.allPhotoKitAssetIDs,
                contactIDs: selection.contactIDs
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
