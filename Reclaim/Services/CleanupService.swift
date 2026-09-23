//
//  CleanupService.swift
//  Reclaim
//
//  Document 04: "given a validated set, execute deletion and report
//  results" — the boundary described in ADR-05 (Document 14). This service
//  does NOT revalidate; that happens upstream in PerformCleanupUseCase.
//  This keeps CleanupService testable in isolation with simple fakes that
//  only need to simulate delete outcomes, not fetch/existence behavior.
//

import Foundation

protocol CleanupServiceProtocol: Sendable {
    /// Executes deletion for an already-revalidated selection. Returns a
    /// summary built entirely from what the underlying services actually
    /// confirmed — never from the requested counts (Document 05 §10).
    func execute(
        _ selection: CleanupSelection,
        categorized: CategorizedSelection,
        photoLibrary: PhotoLibraryServiceProtocol,
        contactService: ContactServiceProtocol
    ) async -> (deletedPhotoKitIDs: Set<String>, deletedContactIDs: Set<String>, failures: [CleanupFailure])
}

/// The selection split by category, so CleanupService (and the caller) know
/// which PhotoKit IDs were photos vs. screenshots vs. videos for accurate
/// per-category counts in CleanupSummary, even though PhotoKit deletes them
/// via one unified call.
struct CategorizedSelection: Sendable {
    let photoIDs: Set<String>
    let screenshotIDs: Set<String>
    let videoIDs: Set<String>
    let contactIDs: Set<String>
}

struct CleanupService: CleanupServiceProtocol {

    func execute(
        _ selection: CleanupSelection,
        categorized: CategorizedSelection,
        photoLibrary: PhotoLibraryServiceProtocol,
        contactService: ContactServiceProtocol
    ) async -> (deletedPhotoKitIDs: Set<String>, deletedContactIDs: Set<String>, failures: [CleanupFailure]) {

        var failures: [CleanupFailure] = []
        var deletedPhotoKitIDs: Set<String> = []
        var deletedContactIDs: Set<String> = []

        // ADR-08: PHPhotoLibrary.performChanges is one atomic call for every
        // PhotoKit-backed category (photos + screenshots + videos share one
        // underlying asset type as far as PhotoKit is concerned) — this
        // also means the user sees exactly one native "Delete X Photos"
        // confirmation, not three.
        let allPhotoKitIDs = categorized.photoIDs.union(categorized.screenshotIDs).union(categorized.videoIDs)
        if !allPhotoKitIDs.isEmpty {
            do {
                deletedPhotoKitIDs = try await photoLibrary.deleteAssets(ids: allPhotoKitIDs)
                let notConfirmed = allPhotoKitIDs.subtracting(deletedPhotoKitIDs)
                failures.append(contentsOf: categorize(notConfirmed, categorized: categorized, reason: .frameworkError("Not confirmed by system")))
            } catch {
                let message: String
                if case ReclaimError.frameworkFailure(let m) = error { message = m } else { message = "\(error)" }
                failures.append(contentsOf: categorize(allPhotoKitIDs, categorized: categorized, reason: .frameworkError(message)))
            }
        }

        if !categorized.contactIDs.isEmpty {
            do {
                deletedContactIDs = try await contactService.deleteContacts(ids: categorized.contactIDs)
                let notConfirmed = categorized.contactIDs.subtracting(deletedContactIDs)
                for id in notConfirmed {
                    failures.append(.contact(id: id, reason: .frameworkError("Not confirmed by system")))
                }
            } catch {
                let message: String
                if case ReclaimError.frameworkFailure(let m) = error { message = m } else { message = "\(error)" }
                for id in categorized.contactIDs {
                    failures.append(.contact(id: id, reason: .frameworkError(message)))
                }
            }
        }

        return (deletedPhotoKitIDs, deletedContactIDs, failures)
    }

    private func categorize(_ ids: Set<String>, categorized: CategorizedSelection, reason: CleanupFailureReason) -> [CleanupFailure] {
        ids.map { id in
            if categorized.photoIDs.contains(id) { return .photo(id: id, reason: reason) }
            if categorized.screenshotIDs.contains(id) { return .screenshot(id: id, reason: reason) }
            return .video(id: id, reason: reason)
        }
    }
}
