//
//  PhotoLibraryService.swift
//  Reclaim
//
//  Document 03 §4: "Services own all PhotoKit/Contacts/AVFoundation calls."
//  Document 04 §2: "Services are the ONLY layer that imports Photos,
//  Contacts, or AVFoundation." This file, and this file alone in the photo
//  pipeline, imports Photos.
//
//  Protocol-first so UseCases/ViewModels can be tested against a fake with
//  no PhotoKit entitlement or simulator library needed (Document 03 §4, §7).
//

import Foundation
import Photos
import CoreGraphics

protocol PhotoLibraryServiceProtocol: Sendable {
    /// Current authorization, mapped to the app's shared PermissionState.
    /// Never assumed valid across app lifecycle — callers re-check on
    /// foreground re-entry (Document 07 §8).
    func currentAuthorization() -> PermissionState

    /// Requests authorization if `.notDetermined`; returns the resulting
    /// state either way. Never called at cold launch before context is
    /// given — the caller (a ViewModel) decides when this is appropriate
    /// (Document 01 §3.7).
    func requestAuthorization() async -> PermissionState

    /// Presents the native limited-library picker so the user can expand
    /// their selection. Bridges into UIKit at the call site
    /// (UIViewControllerRepresentable) since this has no native SwiftUI API.
    @MainActor
    func presentLimitedLibraryPicker() async

    /// Enumerates all photo (non-video) assets the app is currently
    /// authorized to see. Metadata-only — no thumbnails, no hashing
    /// (Document 09 §3 phase 1). Reports progress via `onBatch` so callers
    /// can update UI incrementally without waiting for the whole library.
    func fetchPhotoAssets(onBatch: @Sendable (Int, Int) -> Void) async throws -> [PhotoAsset]

    /// Enumerates all video assets. Metadata-only — pixelWidth/Height/
    /// duration read directly from PHAsset, no AVAsset instantiated here
    /// (Document 06 §5, ADR-06 concurrency notes).
    func fetchVideoAssets(onBatch: @Sendable (Int, Int) -> Void) async throws -> [VideoAsset]

    /// Authoritative byte size for an asset's primary resource. See ADR-01
    /// (Document 14): fast KVC path with a streamed-read fallback.
    func resourceByteSize(forAssetID id: String) async throws -> Int64

    /// SHA-256 over the asset's primary resource data, computed
    /// incrementally via streamed reads — never loads the full resource
    /// into memory at once (Document 06 §1, Document 09 §2).
    func contentHash(forAssetID id: String) async throws -> String

    /// Small, fast-delivery thumbnail for hashing/scoring/display. Never
    /// full-resolution (Document 09 §2).
    func requestThumbnail(forAssetID id: String, targetSize: CGSize) async -> ThumbnailPixels?

    /// Whether every ID in `ids` still resolves to a real, current PHAsset.
    /// Used by PerformCleanupUseCase's revalidation step (ADR-05) — returns
    /// only the subset that is still valid.
    func stillValidAssetIDs(_ ids: Set<String>) async -> Set<String>

    /// Requests deletion via PHPhotoLibrary.performChanges, which triggers
    /// the native OS "Delete X Photos" confirmation (Document 07 §7,
    /// ADR-08). Returns the IDs the OS actually confirmed deleted — never
    /// assumed to equal the requested set.
    func deleteAssets(ids: Set<String>) async throws -> Set<String>
}

/// A grayscale pixel grid extracted from a thumbnail, plus the raw
/// luminance data needed for sharpness/exposure scoring. Crossing from the
/// Services layer (which owns CoreImage/vImage) into Core (which stays
/// framework-free) happens through this plain-data type.
struct ThumbnailPixels: Sendable {
    /// 9x8 grayscale grid (0...255) for dHash — see PerceptualHash.dHash.
    let dHashGrid: [[UInt8]]
    /// Laplacian-variance sharpness measure, precomputed in the Services
    /// layer (vImage convolution) and handed to Core/Utilities/BestPhotoScoring
    /// as a plain Double.
    let sharpnessRaw: Double
    /// 1.0 minus the proportion of near-clipped pixels.
    let exposureRaw: Double
}
