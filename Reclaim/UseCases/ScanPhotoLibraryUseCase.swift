//
//  ScanPhotoLibraryUseCase.swift
//  Reclaim
//
//  Orchestrates the photo/video/screenshot scan phases described in
//  Document 09 §3-4. Publishes progress via `onProgress` so the Dashboard
//  can render phase/completed/total (this build's instructions §10),
//  supports cooperative cancellation via `Task.isCancelled` checks at phase
//  boundaries (Document 09 §8), and returns partial results rather than
//  discarding them if cancelled mid-scan.
//

import Foundation

struct PhotoLibraryScanResult: Sendable {
    let exactDuplicateGroups: [PhotoGroup]
    let similarPhotoGroups: [PhotoGroup]
    let screenshots: [PhotoAsset]
    let videos: [VideoAsset]
    let scannedWithLimitedAccess: Bool
    let status: ScanStatus
}

struct ScanPhotoLibraryUseCase {
    let photoLibrary: PhotoLibraryServiceProtocol
    let duplicateDetector: DuplicateDetectorProtocol
    let similarityDetector: SimilarityDetectorProtocol
    let screenshotDetector: ScreenshotDetectorProtocol
    let videoScanner: VideoScannerProtocol

    func execute(onProgress: @escaping @Sendable (ScanStatus) -> Void) async throws -> PhotoLibraryScanResult {
        let authorization = photoLibrary.currentAuthorization()
        guard authorization.isUsable else {
            throw ReclaimError.permissionNotGranted(.photos)
        }
        let scannedWithLimitedAccess = authorization == .limited

        onProgress(.scanning(phase: "Finding photos", completed: 0, total: 0))
        let allPhotos = try await photoLibrary.fetchPhotoAssets { completed, total in
            onProgress(.scanning(phase: "Finding photos", completed: completed, total: total))
        }
        if Task.isCancelled {
            return PhotoLibraryScanResult(
                exactDuplicateGroups: [], similarPhotoGroups: [], screenshots: [], videos: [],
                scannedWithLimitedAccess: scannedWithLimitedAccess, status: .cancelled
            )
        }

        // Screenshots first — cheapest category, gives the user something
        // to review immediately (progressive results, Document 09 §4).
        onProgress(.scanning(phase: "Detecting screenshots", completed: 0, total: allPhotos.count))
        let screenshots = screenshotDetector.detectScreenshots(in: allPhotos)
        if Task.isCancelled {
            return PhotoLibraryScanResult(
                exactDuplicateGroups: [], similarPhotoGroups: [], screenshots: screenshots, videos: [],
                scannedWithLimitedAccess: scannedWithLimitedAccess, status: .cancelled
            )
        }

        onProgress(.scanning(phase: "Finding exact duplicates", completed: 0, total: allPhotos.count))
        let exactDuplicates = try await duplicateDetector.detectExactDuplicates(in: allPhotos, photoLibrary: photoLibrary)
        if Task.isCancelled {
            return PhotoLibraryScanResult(
                exactDuplicateGroups: exactDuplicates, similarPhotoGroups: [], screenshots: screenshots, videos: [],
                scannedWithLimitedAccess: scannedWithLimitedAccess, status: .cancelled
            )
        }

        // Exclude exact-duplicate members from similarity analysis — an
        // asset already grouped as an exact duplicate shouldn't also appear
        // in a similar-photos group, which would let the user select it
        // for deletion twice under two different reasons (Document 05 §2
        // implicit invariant: an asset belongs to at most one PhotoGroup).
        let exactDuplicateMemberIDs = Set(exactDuplicates.flatMap { $0.members.map(\.id) })
        let remainingForSimilarity = allPhotos.filter { !exactDuplicateMemberIDs.contains($0.id) }

        onProgress(.scanning(phase: "Finding similar photos", completed: 0, total: remainingForSimilarity.count))
        let similarGroups = try await similarityDetector.detectSimilarGroups(in: remainingForSimilarity, photoLibrary: photoLibrary)
        if Task.isCancelled {
            return PhotoLibraryScanResult(
                exactDuplicateGroups: exactDuplicates, similarPhotoGroups: similarGroups, screenshots: screenshots, videos: [],
                scannedWithLimitedAccess: scannedWithLimitedAccess, status: .cancelled
            )
        }

        onProgress(.scanning(phase: "Finding large videos", completed: 0, total: 0))
        let videos = try await videoScanner.scanVideos(photoLibrary: photoLibrary) { completed, total in
            onProgress(.scanning(phase: "Finding large videos", completed: completed, total: total))
        }

        onProgress(.completed)

        return PhotoLibraryScanResult(
            exactDuplicateGroups: exactDuplicates,
            similarPhotoGroups: similarGroups,
            screenshots: screenshots,
            videos: videos,
            scannedWithLimitedAccess: scannedWithLimitedAccess,
            status: .completed
        )
    }
}
