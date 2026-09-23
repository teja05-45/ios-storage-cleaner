//
//  VideoAsset.swift
//  Reclaim
//
//  Document 05 §4. Kept separate from PhotoAsset rather than a shared
//  MediaAsset superset with optional fields — video-specific requirements
//  (duration, preview playback) and photo-specific requirements
//  (perceptual hash, sharpness) never overlap in the UI, so a shared type
//  would carry dead optional fields on both sides. Documented tradeoff:
//  slight duplication of id/creationDate/byteSize, in exchange for each
//  model only ever describing real, relevant data.
//

import Foundation
import CoreGraphics

struct VideoAsset: Identifiable, Hashable, Sendable {
    /// PHAsset.localIdentifier
    let id: String
    let creationDate: Date?
    let duration: TimeInterval
    let pixelSize: CGSize
    let byteSize: Int64

    static func == (lhs: VideoAsset, rhs: VideoAsset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
