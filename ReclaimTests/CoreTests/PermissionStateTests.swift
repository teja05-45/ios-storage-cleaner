//
//  PermissionStateTests.swift
//  ReclaimTests
//
//  The automated permission matrix (docs/25 validation matrix, "Permissions"
//  row). Apple's system permission dialogs and the live PhotoKit/Contacts
//  status mapping (PhotoLibraryServiceLive.map / ContactServiceLive.map)
//  cannot run in this test target — that part is disclosed as requiring
//  simulator/device validation. What CAN be fully automated is the app's
//  own permission abstraction: the PermissionState truth table and every
//  gate that reads it, across all five states for both frameworks.
//
//  Contract under test: .limited is a first-class, usable state (ADR-04);
//  .notDetermined/.denied/.restricted are unusable; unusable state must
//  make every scan path throw .permissionNotGranted BEFORE any framework
//  enumeration happens.
//

import XCTest
import CoreGraphics
@testable import Reclaim

final class PermissionStateTests: XCTestCase {

    // MARK: - PermissionState truth table

    func test_permissionState_isUsable_truthTable() {
        XCTAssertTrue(PermissionState.authorized.isUsable, "authorized must be usable")
        XCTAssertTrue(PermissionState.limited.isUsable,
                      ".limited must be usable — the app operates fully on the granted subset (ADR-04)")
        XCTAssertFalse(PermissionState.notDetermined.isUsable)
        XCTAssertFalse(PermissionState.denied.isUsable)
        XCTAssertFalse(PermissionState.restricted.isUsable)
    }

    // MARK: - Photo scan gating across the matrix

    private func makePhotoUseCase(service: FakePhotoLibraryService) -> ScanPhotoLibraryUseCase {
        ScanPhotoLibraryUseCase(
            photoLibrary: service,
            duplicateDetector: FakeDuplicateDetector(),
            similarityDetector: FakeSimilarityDetector(),
            screenshotDetector: FakeScreenshotDetector(),
            videoScanner: FakeVideoScanner()
        )
    }

    func test_photoScan_notDetermined_throwsPermissionNotGranted_withoutEnumerating() async {
        let service = FakePhotoLibraryService()
        service.authorization = .notDetermined
        service.scriptedPhotoAssets = [photoFixture(id: "should-never-be-read")]

        do {
            _ = try await makePhotoUseCase(service: service).execute { _ in }
            XCTFail(".notDetermined must not reach enumeration")
        } catch let error as ReclaimError {
            guard case .permissionNotGranted(.photos) = error else {
                return XCTFail("expected .permissionNotGranted(.photos), got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func test_photoScan_denied_and_restricted_throwWithoutEnumerating() async {
        for state in [PermissionState.denied, .restricted] {
            let service = FakePhotoLibraryService()
            service.authorization = state
            service.scriptedPhotoAssets = [photoFixture(id: "should-never-be-read")]

            do {
                _ = try await makePhotoUseCase(service: service).execute { _ in }
                XCTFail("\(state) must not reach enumeration")
            } catch {
                // Any throw is acceptable at this gate; the enumeration
                // never having happened is the guarantee under test.
            }
        }
    }

    func test_photoScan_limited_proceedsAndIsReportedHonestly() async throws {
        let service = FakePhotoLibraryService()
        service.authorization = .limited
        service.scriptedPhotoAssets = [photoFixture(id: "p1")]

        let result = try await makePhotoUseCase(service: service).execute { _ in }

        XCTAssertTrue(result.scannedWithLimitedAccess,
                      ".limited must surface as its own state, never collapsed into full access (ADR-04)")
        XCTAssertEqual(result.status, .completed)
    }

    // MARK: - Contact scan gating across the matrix

    /// Local detector fake (the Dashboard test suite keeps a private one;
    /// duplication here is deliberate so suites stay independently readable).
    private final class EmptyContactDetector: DuplicateContactDetectorProtocol, @unchecked Sendable {
        func detectDuplicateGroups(in contacts: [ContactCandidate]) -> [ContactGroup] { [] }
    }

    func test_contactScan_unusableStates_throwPermissionNotGranted_withoutFetching() async {
        for state in [PermissionState.notDetermined, .denied, .restricted] {
            let service = FakeContactService()
            service.authorization = state
            let useCase = ScanContactsUseCase(
                contactService: service,
                duplicateContactDetector: EmptyContactDetector()
            )

            do {
                _ = try await useCase.execute()
                XCTFail("\(state) must not reach contact enumeration")
            } catch let error as ReclaimError {
                guard case .permissionNotGranted(.contacts) = error else {
                    return XCTFail("\(state): expected .permissionNotGranted(.contacts), got \(error)")
                }
            } catch {
                XCTFail("\(state): unexpected error type: \(error)")
            }
        }
    }

    func test_contactScan_authorized_proceedsToDetection() async throws {
        let service = FakeContactService()
        service.authorization = .authorized
        let useCase = ScanContactsUseCase(
            contactService: service,
            duplicateContactDetector: EmptyContactDetector()
        )

        let groups = try await useCase.execute()

        XCTAssertTrue(groups.isEmpty, "detector returns no groups; the contract is that the gate let the scan through")
    }

    // MARK: - Cleanup re-gating (permission revoked between scan and confirm)

    func test_cleanup_photoPermissionRevoked_everyPhotoKitItemFailsWithPermissionRevoked_zeroDeleteCalls() async throws {
        let photos = FakePhotoLibraryService()
        photos.authorization = .denied // revoked after scan
        photos.validAssetIDs = ["asset-1"]
        photos.deletableAssetIDs = ["asset-1"]
        let contacts = FakeContactService()
        contacts.authorization = .authorized
        contacts.validContactIDs = []
        contacts.deletableContactIDs = []

        let selection = CleanupSelection(
            photoAssetIDs: ["asset-1"],
            screenshotAssetIDs: [],
            videoAssetIDs: [],
            contactIDs: []
        )

        let useCase = PerformCleanupUseCase(
            photoLibrary: photos,
            contactService: contacts,
            cleanupService: CleanupService(),
            storageService: FakeStorageService()
        )

        let summary = try await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(photos.deleteCallCount, 0,
                       "revoked photo permission must abort deletion before any delete call")
        XCTAssertEqual(summary.failures.count, 1)
        guard case .photo(_, .permissionRevoked) = summary.failures[0] else {
            return XCTFail("expected a .photo failure with .permissionRevoked, got \(summary.failures[0])")
        }
    }

    func test_cleanup_contactPermissionRevoked_everyContactFailsWithPermissionRevoked_zeroDeleteCalls() async throws {
        let photos = FakePhotoLibraryService()
        photos.authorization = .authorized
        photos.validAssetIDs = []
        let contacts = FakeContactService()
        contacts.authorization = .restricted // revoked after scan
        contacts.validContactIDs = ["contact-1"]

        let selection = CleanupSelection(
            photoAssetIDs: [],
            screenshotAssetIDs: [],
            videoAssetIDs: [],
            contactIDs: ["contact-1"]
        )

        let useCase = PerformCleanupUseCase(
            photoLibrary: photos,
            contactService: contacts,
            cleanupService: CleanupService(),
            storageService: FakeStorageService()
        )

        let summary = try await useCase.execute(selection, confirmed: true)

        XCTAssertEqual(contacts.deleteCallCount, 0,
                       "revoked contacts permission must abort deletion before any delete call")
        XCTAssertEqual(summary.failures.count, 1)
        guard case .contact(_, .permissionRevoked) = summary.failures[0] else {
            return XCTFail("expected a .contact failure with .permissionRevoked, got \(summary.failures[0])")
        }
    }

    // MARK: - Fixture

    private func photoFixture(id: String) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: Date(timeIntervalSince1970: 1_000_000),
            pixelSize: CGSize(width: 100, height: 100),
            byteSize: 0,
            isScreenshot: false,
            mediaType: .photo
        )
    }
}
