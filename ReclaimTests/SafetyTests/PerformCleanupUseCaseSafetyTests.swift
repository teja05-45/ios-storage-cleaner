//
//  PerformCleanupUseCaseSafetyTests.swift
//  ReclaimTests
//
//  Document 08 §4. Every case here targets one of the guards documented in
//  PerformCleanupUseCase.swift's header comment directly.
//

import XCTest
@testable import Reclaim

@MainActor
final class PerformCleanupUseCaseSafetyTests: XCTestCase {

    private func makeUseCase(
        photoLibrary: FakePhotoLibraryService = FakePhotoLibraryService(),
        contactService: FakeContactService = FakeContactService(),
        storageService: FakeStorageService = FakeStorageService()
    ) -> PerformCleanupUseCase {
        PerformCleanupUseCase(
            photoLibrary: photoLibrary,
            contactService: contactService,
            cleanupService: CleanupService(),
            storageService: storageService
        )
    }

    // MARK: - Guard: no confirmation, no deletion

    func test_notConfirmed_throwsAndNeverCallsDelete() async {
        let photoLibrary = FakePhotoLibraryService()
        photoLibrary.validAssetIDs = ["a"]
        photoLibrary.deletableAssetIDs = ["a"]
        let useCase = makeUseCase(photoLibrary: photoLibrary)

        let selection = CleanupSelection(photoAssetIDs: ["a"])

        do {
            _ = try await useCase.execute(selection, confirmed: false)
            XCTFail("expected .notConfirmed to be thrown")
        } catch ReclaimError.notConfirmed {
            // expected
        } catch {
            XCTFail("expected ReclaimError.notConfirmed, got \(error)")
        }

        XCTAssertEqual(photoLibrary.deleteCallCount, 0, "deleteAssets must never be called when confirmed == false")
    }

    // MARK: - Guard: empty selection cannot be confirmed

    func test_emptySelection_throwsEvenWhenConfirmedTrue() async {
        let photoLibrary = FakePhotoLibraryService()
        let useCase = makeUseCase(photoLibrary: photoLibrary)

        do {
            _ = try await useCase.execute(CleanupSelection(), confirmed: true)
            XCTFail("expected .emptySelection to be thrown")
        } catch ReclaimError.emptySelection {
            // expected
        } catch {
            XCTFail("expected ReclaimError.emptySelection, got \(error)")
        }

        XCTAssertEqual(photoLibrary.deleteCallCount, 0)
    }

    // MARK: - Guard: stale asset safely skipped and reported (ADR-05)

    func test_staleAsset_skippedAndReported_notDeleted() async {
        let photoLibrary = FakePhotoLibraryService()
        // "a" is still valid; "b" has vanished since the scan.
        photoLibrary.validAssetIDs = ["a"]
        photoLibrary.deletableAssetIDs = ["a"]
        let useCase = makeUseCase(photoLibrary: photoLibrary)

        let selection = CleanupSelection(photoAssetIDs: ["a", "b"])
        let summary = try! await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(summary.deletedPhotoCount, 1, "only the still-valid asset should be deleted")
        XCTAssertEqual(photoLibrary.lastDeleteRequest, ["a"], "the stale asset must never even be included in the delete request")
        XCTAssertTrue(summary.failures.contains { $0.id == "b" && $0.reason == .staleAsset })
    }

    // MARK: - Guard: permission revoked, cleanup does not proceed blindly

    func test_permissionRevoked_doesNotAttemptDeletion() async {
        let photoLibrary = FakePhotoLibraryService()
        photoLibrary.authorization = .denied // revoked since the scan ran
        photoLibrary.validAssetIDs = ["a"]
        photoLibrary.deletableAssetIDs = ["a"]
        let useCase = makeUseCase(photoLibrary: photoLibrary)

        let selection = CleanupSelection(photoAssetIDs: ["a"])
        let summary = try! await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(photoLibrary.deleteCallCount, 0, "deletion must never be attempted once authorization is no longer usable")
        XCTAssertEqual(summary.deletedPhotoCount, 0)
        XCTAssertTrue(summary.failures.contains { $0.id == "a" && $0.reason == .permissionRevoked })
    }

    func test_contactsPermissionRevoked_doesNotAttemptContactDeletion() async {
        let contactService = FakeContactService()
        contactService.authorization = .denied
        contactService.validContactIDs = ["c1"]
        contactService.deletableContactIDs = ["c1"]
        let useCase = makeUseCase(contactService: contactService)

        let selection = CleanupSelection(contactIDs: ["c1"])
        let summary = try! await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(contactService.deleteCallCount, 0)
        XCTAssertEqual(summary.deletedContactCount, 0)
        XCTAssertTrue(summary.failures.contains { $0.id == "c1" && $0.reason == .permissionRevoked })
    }

    // MARK: - Guard: failed deletion accurately reported (partial failure)

    func test_partialFrameworkFailure_accuratelyReported() async {
        let photoLibrary = FakePhotoLibraryService()
        photoLibrary.validAssetIDs = ["a", "b"]
        photoLibrary.deletableAssetIDs = ["a"] // "b" is valid but the OS declines/fails to delete it
        let useCase = makeUseCase(photoLibrary: photoLibrary)

        let selection = CleanupSelection(photoAssetIDs: ["a", "b"])
        let summary = try! await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(summary.deletedPhotoCount, 1)
        XCTAssertTrue(summary.hadPartialFailure)
        XCTAssertTrue(summary.failures.contains { $0.id == "b" })
        // Never silently reports 2/2 success when only 1 was confirmed.
        XCTAssertNotEqual(summary.deletedPhotoCount, selection.photoAssetIDs.count)
    }

    func test_completeFrameworkFailure_reportsZeroDeletedAllFailed() async {
        let photoLibrary = FakePhotoLibraryService()
        photoLibrary.validAssetIDs = ["a"]
        photoLibrary.deleteError = ReclaimError.frameworkFailure("user declined native confirmation")
        let useCase = makeUseCase(photoLibrary: photoLibrary)

        let selection = CleanupSelection(photoAssetIDs: ["a"])
        let summary = try! await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(summary.deletedPhotoCount, 0)
        XCTAssertTrue(summary.failures.contains { $0.id == "a" })
    }

    // MARK: - Success path: accurate summary, bytesFreed independently computed

    func test_successfulCleanup_accurateCounts() async {
        let photoLibrary = FakePhotoLibraryService()
        photoLibrary.validAssetIDs = ["a", "b"]
        photoLibrary.deletableAssetIDs = ["a", "b"]
        let contactService = FakeContactService()
        contactService.validContactIDs = ["c1"]
        contactService.deletableContactIDs = ["c1"]
        let storage = FakeStorageService()
        // Simulate 2,000,000 bytes freed between the pre- and post-cleanup readings.
        storage.capacitySequence = [
            DeviceCapacity(totalBytes: 100_000_000, availableBytes: 10_000_000), // before
            DeviceCapacity(totalBytes: 100_000_000, availableBytes: 12_000_000)  // after
        ]
        let useCase = makeUseCase(photoLibrary: photoLibrary, contactService: contactService, storageService: storage)

        let selection = CleanupSelection(photoAssetIDs: ["a", "b"], contactIDs: ["c1"])
        let summary = try! await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(summary.deletedPhotoCount, 2)
        XCTAssertEqual(summary.deletedContactCount, 1)
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(summary.bytesFreed, 2_000_000, "bytesFreed must come from the independently-read before/after device capacity, not the pre-cleanup byte-sum estimate")
    }

    func test_allItemsStale_reportsAllFailuresNoSuccessFabricated() async {
        let photoLibrary = FakePhotoLibraryService()
        photoLibrary.validAssetIDs = [] // everything has vanished since the scan
        let useCase = makeUseCase(photoLibrary: photoLibrary)

        let selection = CleanupSelection(photoAssetIDs: ["a", "b"])
        let summary = try! await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(summary.deletedPhotoCount, 0)
        XCTAssertEqual(summary.failures.count, 2)
        XCTAssertEqual(photoLibrary.deleteCallCount, 0, "no delete call should ever be attempted when nothing survives revalidation")
    }

    // MARK: - OPEN-3: summary carries exactly what the OS confirmed deleted

    func test_summaryCarriesConfirmedDeletedIDs_notRequestedIDs() async {
        let photoLibrary = FakePhotoLibraryService()
        photoLibrary.validAssetIDs = ["a", "b", "c"]
        // "a" is valid and deletable, "b" is valid but the OS declines it,
        // "c" is stale. Only "a" is truly deleted.
        photoLibrary.deletableAssetIDs = ["a"]
        let useCase = makeUseCase(photoLibrary: photoLibrary)

        let selection = CleanupSelection(photoAssetIDs: ["a", "b", "c"])
        let summary = try! await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(summary.deletedPhotoAssetIDs, ["a"], "the summary must name exactly what the OS confirmed deleted")
        XCTAssertEqual(summary.deletedContactIDs, [])
        XCTAssertEqual(summary.deletedPhotoCount, summary.deletedPhotoAssetIDs.count, "the count and the confirmed ID set must agree")
    }

    func test_summaryConfirmedContactIDs_matchDeletedContactCount() async {
        let contactService = FakeContactService()
        contactService.validContactIDs = ["c1", "c2"]
        contactService.deletableContactIDs = ["c1"] // c2 valid but declined
        let useCase = makeUseCase(contactService: contactService)

        let selection = CleanupSelection(contactIDs: ["c1", "c2"])
        let summary = try! await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(summary.deletedContactIDs, ["c1"])
        XCTAssertEqual(summary.deletedContactCount, summary.deletedContactIDs.count)
    }

    func test_summaryDeletedIDsEmpty_whenNothingDeleted() async {
        let photoLibrary = FakePhotoLibraryService()
        photoLibrary.authorization = .denied // revoked: nothing will be deleted
        let useCase = makeUseCase(photoLibrary: photoLibrary)

        let selection = CleanupSelection(photoAssetIDs: ["a"])
        let summary = try! await useCase.execute(selection, confirmed: true)

        XCTAssertTrue(summary.deletedPhotoAssetIDs.isEmpty, "a cleanup that deleted nothing must not report any confirmed IDs")
    }
}
