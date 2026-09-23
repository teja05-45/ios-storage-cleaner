//
//  PhotoLibraryServiceLive.swift
//  Reclaim
//
//  Real PhotoKit-backed implementation. See PhotoLibraryService.swift for
//  the protocol/rationale. API usage verified against current Apple
//  documentation before writing (Document 14 §0):
//   - PHPhotoLibrary.authorizationStatus(for:)/requestAuthorization(for:)
//   - PHPhotoLibrary.presentLimitedLibraryPicker(from:)
//   - PHAssetResourceManager.requestData(for:options:...) for streamed reads
//   - PHAssetResource.value(forKey: "fileSize") as a documented-risk fast
//     path (ADR-01), never as the only path.
//

import Foundation
import Photos
import PhotosUI
import CoreGraphics
import CryptoKit
import UIKit
import AVKit

final class PhotoLibraryServiceLive: NSObject, PhotoLibraryServiceProtocol, @unchecked Sendable {

    private let imageManager = PHCachingImageManager()
    private let resourceManager = PHAssetResourceManager.default()

    // MARK: - Authorization

    func currentAuthorization() -> PermissionState {
        map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> PermissionState {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return map(status)
    }

    @MainActor
    func presentLimitedLibraryPicker() async {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.rootViewController else { return }
        await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }

    private func map(_ status: PHAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    // MARK: - Enumeration (Document 09 §3 phase 1: metadata-only, batched)

    func fetchPhotoAssets(onBatch: @Sendable (Int, Int) -> Void) async throws -> [PhotoAsset] {
        guard currentAuthorization().isUsable else {
            throw ReclaimError.permissionNotGranted(.photos)
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                let options = PHFetchOptions()
                options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
                let result = PHAsset.fetchAssets(with: options)

                var assets: [PhotoAsset] = []
                assets.reserveCapacity(result.count)

                let batchSize = 200
                var batchIndex = 0

                autoreleasepool {
                    result.enumerateObjects { asset, index, _ in
                        let photoAsset = PhotoAsset(
                            id: asset.localIdentifier,
                            creationDate: asset.creationDate,
                            pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                            byteSize: 0, // populated lazily by resourceByteSize(forAssetID:) — kept out of the fast enumeration pass per Document 09 §3
                            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                            mediaType: .photo
                        )
                        assets.append(photoAsset)

                        if index > 0 && index % batchSize == 0 {
                            batchIndex += 1
                            onBatch(index, result.count)
                        }
                    }
                }
                onBatch(result.count, result.count)
                continuation.resume(returning: assets)
            }
        }
    }

    func fetchVideoAssets(onBatch: @Sendable (Int, Int) -> Void) async throws -> [VideoAsset] {
        guard currentAuthorization().isUsable else {
            throw ReclaimError.permissionNotGranted(.photos)
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options = PHFetchOptions()
                options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
                let result = PHAsset.fetchAssets(with: options)

                var videos: [VideoAsset] = []
                videos.reserveCapacity(result.count)

                autoreleasepool {
                    result.enumerateObjects { asset, index, _ in
                        // Duration/resolution read directly from PHAsset —
                        // no AVAsset instantiated here (Document 06 §5).
                        let video = VideoAsset(
                            id: asset.localIdentifier,
                            creationDate: asset.creationDate,
                            duration: asset.duration,
                            pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                            byteSize: 0 // populated lazily, see fetchPhotoAssets note above
                        )
                        videos.append(video)

                        if index > 0 && index % 200 == 0 {
                            onBatch(index, result.count)
                        }
                    }
                }
                onBatch(result.count, result.count)
                continuation.resume(returning: videos)
            }
        }
    }

    // MARK: - Resource size (ADR-01: KVC fast path, streamed fallback)

    func resourceByteSize(forAssetID id: String) async throws -> Int64 {
        guard let asset = fetchAsset(id: id) else {
            throw ReclaimError.staleSelection(id: id)
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = primaryResource(from: resources) else {
            throw ReclaimError.frameworkFailure("No resources for asset")
        }

        // Fast path: undocumented but widely-used, App-Review-approved KVC
        // key (Document 14 ADR-01). Guarded so any unexpected type/nil
        // falls through to the streamed, fully-documented path below.
        if let value = primary.value(forKey: "fileSize") {
            if let number = value as? NSNumber {
                return number.int64Value
            }
            if let int64 = value as? Int64 {
                return int64
            }
        }

        // Fallback: stream the resource and count bytes. Slower, but uses
        // only fully-documented API (Document 09 §2 streaming requirement).
        return try await streamedByteCount(for: primary)
    }

    private func streamedByteCount(for resource: PHAssetResource) async throws -> Int64 {
        try await withCheckedThrowingContinuation { continuation in
            var total: Int64 = 0
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false
            resourceManager.requestData(for: resource, options: options) { chunk in
                total += Int64(chunk.count)
            } completionHandler: { error in
                if let error {
                    continuation.resume(throwing: ReclaimError.frameworkFailure(error.localizedDescription))
                } else {
                    continuation.resume(returning: total)
                }
            }
        }
    }

    // MARK: - Content hash (Document 06 §1: streamed SHA-256, never fully buffered)

    func contentHash(forAssetID id: String) async throws -> String {
        guard let asset = fetchAsset(id: id) else {
            throw ReclaimError.staleSelection(id: id)
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = primaryResource(from: resources) else {
            throw ReclaimError.frameworkFailure("No resources for asset")
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasher = SHA256()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false
            resourceManager.requestData(for: primary, options: options) { chunk in
                hasher.update(data: chunk)
            } completionHandler: { error in
                if let error {
                    continuation.resume(throwing: ReclaimError.frameworkFailure(error.localizedDescription))
                } else {
                    let digest = hasher.finalize()
                    continuation.resume(returning: digest.compactMap { String(format: "%02x", $0) }.joined())
                }
            }
        }
    }

    // MARK: - Thumbnails (Document 09 §2: small, fast-delivery only)

    func requestThumbnail(forAssetID id: String, targetSize: CGSize) async -> ThumbnailPixels? {
        guard let asset = fetchAsset(id: id) else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false

        let image: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                // PHImageManager may invoke this handler more than once
                // (degraded then final image). Resume exactly once — the
                // first (fastest) delivery is sufficient for hashing.
                if !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }

        guard let cgImage = image?.cgImage else { return nil }
        return ImagePixelExtractor.extract(from: cgImage)
    }

    @MainActor
    func requestDisplayImage(forAssetID id: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = fetchAsset(id: id) else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false

        return await withCheckedContinuation { continuation in
            var resumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Opportunistic delivery can call back multiple times
                // (degraded, then final). Resume on the final callback:
                // skipping the degraded frame avoids flicker, and a second
                // resume would crash the continuation. Apple guarantees a
                // final non-degraded callback even on failure (with a nil
                // image), so the continuation cannot be left hanging.
                let isDegraded = ((info as? [AnyHashable: Any])?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded && !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - Revalidation (ADR-05)

    func stillValidAssetIDs(_ ids: Set<String>) async -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var valid: Set<String> = []
        result.enumerateObjects { asset, _, _ in
            valid.insert(asset.localIdentifier)
        }
        return valid
    }

    // MARK: - Video preview playback

    func playerItem(forVideoAssetID id: String) async -> AVPlayerItem? {
        guard let asset = fetchAsset(id: id) else { return nil }
        return await withCheckedContinuation { continuation in
            PHCachingImageManager.default().requestPlayerItem(forVideo: asset, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    // MARK: - Deletion (ADR-08: the only PhotoKit delete call site)

    func deleteAssets(ids: Set<String>) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var assetsToDelete: [PHAsset] = []
        var confirmedIDs: Set<String> = []
        result.enumerateObjects { asset, _, _ in
            assetsToDelete.append(asset)
            confirmedIDs.insert(asset.localIdentifier)
        }
        guard !assetsToDelete.isEmpty else { return [] }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSFastEnumeration)
            }
            // performChanges throws on failure/decline; if it returns
            // without throwing, the OS confirmed the deletion for every
            // asset we requested that still resolved.
            return confirmedIDs
        } catch {
            // The user declined the native confirmation, or a framework
            // error occurred. Report zero deleted — PerformCleanupUseCase
            // records this as a failure for every requested ID, never
            // silently assumes partial success (Document 05 §10).
            throw ReclaimError.frameworkFailure(error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    private func fetchAsset(id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Prefers the resource matching the asset's primary type
    /// (photo/fullSizePhoto/video), falling back to the first resource —
    /// an asset can have multiple resources (e.g. Live Photo still + video,
    /// edited original + current), and "primary" here means "the one that
    /// represents what the user sees," per Document 06 §1.
    private func primaryResource(from resources: [PHAssetResource]) -> PHAssetResource? {
        let preferredTypes: [PHAssetResourceType] = [.photo, .fullSizePhoto, .video, .fullSizeVideo]
        for type in preferredTypes {
            if let match = resources.first(where: { $0.type == type }) {
                return match
            }
        }
        return resources.first
    }
}
