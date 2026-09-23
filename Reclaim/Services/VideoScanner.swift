//
//  VideoScanner.swift
//  Reclaim
//
//  Document 06 §5: lists videos largest-to-smallest using metadata already
//  captured during PhotoLibraryService.fetchVideoAssets (duration/
//  resolution from PHAsset directly — no AVAsset instantiated here). Byte
//  size is resolved per-asset via the same ADR-01 path photos use.
//  Thumbnail/preview loading is lazy, triggered only when a specific video
//  row's preview is actually opened (Features/LargeVideos), never during
//  this scan pass.
//

import Foundation

protocol VideoScannerProtocol: Sendable {
    func scanVideos(photoLibrary: PhotoLibraryServiceProtocol, onBatch: @escaping @Sendable (Int, Int) -> Void) async throws -> [VideoAsset]
}

struct VideoScanner: VideoScannerProtocol {
    func scanVideos(photoLibrary: PhotoLibraryServiceProtocol, onBatch: @escaping @Sendable (Int, Int) -> Void) async throws -> [VideoAsset] {
        let videos = try await photoLibrary.fetchVideoAssets(onBatch: onBatch)

        var withSizes: [VideoAsset] = []
        withSizes.reserveCapacity(videos.count)
        for video in videos {
            let size = (try? await photoLibrary.resourceByteSize(forAssetID: video.id)) ?? 0
            withSizes.append(VideoAsset(
                id: video.id,
                creationDate: video.creationDate,
                duration: video.duration,
                pixelSize: video.pixelSize,
                byteSize: size
            ))
        }

        return withSizes.sorted { $0.byteSize > $1.byteSize }
    }
}
