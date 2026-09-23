//
//  AppEnvironment.swift
//  Reclaim
//
//  Document 04 §1 "AppEnvironment (composition root)". Every service and
//  use case is constructed here, once, and threaded down via the SwiftUI
//  environment or explicit initializer injection — no singletons accessed
//  ad hoc from inside a ViewModel (Document 13 §2.1 flagged this as the
//  risk to guard against). A test target builds its own `AppEnvironment`
//  with fake services (see ReclaimTests) rather than touching this type at
//  all, which is what makes the whole app testable without PhotoKit/
//  Contacts entitlements in the test target (Document 03 §7).
//

import Foundation

@MainActor
final class AppEnvironment {
    let photoLibrary: PhotoLibraryServiceProtocol
    let contactService: ContactServiceProtocol
    let storageService: StorageServiceProtocol

    /// Constructed but unused this build: the scan pipeline computes results
    /// per launch and never reads the on-disk cache (ADR-07 limits the cache
    /// to derived data only; wiring it into the read path is future work).
    /// Kept here so the composition root stays the single place a future
    /// scan-caching implementation is threaded through.
    let scanCache: ScanCacheProtocol

    let duplicateDetector: DuplicateDetectorProtocol
    let similarityDetector: SimilarityDetectorProtocol
    let screenshotDetector: ScreenshotDetectorProtocol
    let videoScanner: VideoScannerProtocol
    let duplicateContactDetector: DuplicateContactDetectorProtocol
    let cleanupService: CleanupServiceProtocol

    let reviewStore: ReviewStore

    init(
        photoLibrary: PhotoLibraryServiceProtocol,
        contactService: ContactServiceProtocol,
        storageService: StorageServiceProtocol,
        scanCache: ScanCacheProtocol,
        duplicateDetector: DuplicateDetectorProtocol = DuplicateDetector(),
        similarityDetector: SimilarityDetectorProtocol = SimilarityDetector(),
        screenshotDetector: ScreenshotDetectorProtocol = ScreenshotDetector(),
        videoScanner: VideoScannerProtocol = VideoScanner(),
        duplicateContactDetector: DuplicateContactDetectorProtocol = DuplicateContactDetector(),
        cleanupService: CleanupServiceProtocol = CleanupService()
    ) {
        self.photoLibrary = photoLibrary
        self.contactService = contactService
        self.storageService = storageService
        self.scanCache = scanCache
        self.duplicateDetector = duplicateDetector
        self.similarityDetector = similarityDetector
        self.screenshotDetector = screenshotDetector
        self.videoScanner = videoScanner
        self.duplicateContactDetector = duplicateContactDetector
        self.cleanupService = cleanupService
        self.reviewStore = ReviewStore()
    }

    /// Live, production environment. Constructed once by ReclaimApp.
    static func live() -> AppEnvironment {
        AppEnvironment(
            photoLibrary: PhotoLibraryServiceLive(),
            contactService: ContactServiceLive(),
            storageService: StorageServiceLive(),
            scanCache: ScanCacheLive()
        )
    }

    // MARK: - Use case factories (constructed on demand — cheap value types)

    func scanPhotoLibraryUseCase() -> ScanPhotoLibraryUseCase {
        ScanPhotoLibraryUseCase(
            photoLibrary: photoLibrary,
            duplicateDetector: duplicateDetector,
            similarityDetector: similarityDetector,
            screenshotDetector: screenshotDetector,
            videoScanner: videoScanner
        )
    }

    func scanContactsUseCase() -> ScanContactsUseCase {
        ScanContactsUseCase(contactService: contactService, duplicateContactDetector: duplicateContactDetector)
    }

    func computeStorageSummaryUseCase() -> ComputeStorageSummaryUseCase {
        ComputeStorageSummaryUseCase(storageService: storageService)
    }

    func performCleanupUseCase() -> PerformCleanupUseCase {
        PerformCleanupUseCase(
            photoLibrary: photoLibrary,
            contactService: contactService,
            cleanupService: cleanupService,
            storageService: storageService
        )
    }
}
