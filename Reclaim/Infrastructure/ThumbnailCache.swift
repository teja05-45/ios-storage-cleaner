//
//  ThumbnailCache.swift
//  Reclaim
//
//  Document 09 §2/§7. A disposable in-memory cache for display thumbnails
//  only — never for the ThumbnailPixels used in hashing/scoring (those are
//  computed once per scan and stored, via ScanResult's derived hash, not
//  re-derived from a cached image). NSCache automatically evicts under
//  memory pressure; nothing here assumes a cached entry survives.
//

import Foundation
import UIKit

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 500
        return c
    }()

    private init() {}

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
