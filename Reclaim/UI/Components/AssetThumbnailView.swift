//
//  AssetThumbnailView.swift
//  Reclaim
//
//  Document 02 §2/§4.3–4.7: every category screen shows PhotoKit
//  thumbnails fetched on demand — never the full-resolution resource
//  (Document 09 §2). The image is requested at the cell's point size ×
//  display scale and memoized in the process-wide ThumbnailCache keyed by
//  asset + pixel size, so scrolling a 10,000-item grid neither refetches
//  visible rows nor retains anything beyond NSCache's eviction bound.
//  No-ops on actual fetches in previews/tests (nil environment), keeping
//  this component safely instantiable anywhere.
//

import SwiftUI
import UIKit

struct AssetThumbnailView: View {
    let assetID: String
    /// Point size of the requesting cell; the image is fetched at pixel
    /// scale so it stays crisp on 2×/3× devices without ever touching the
    /// full-resolution resource.
    let targetSize: CGSize

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemFill))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: assetID) {
            // Cache hit: show it immediately, no fetch, no placeholder flash.
            let pixelSize = CGSize(
                width: targetSize.width * UIScreen.main.scale,
                height: targetSize.height * UIScreen.main.scale
            )
            let cacheKey = "\(assetID)#\(Int(pixelSize.width))x\(Int(pixelSize.height))"
            if let cached = ThumbnailCache.shared.image(forKey: cacheKey) {
                image = cached
                return
            }
            guard let photoLibrary = appEnvironment?.photoLibrary else { return }
            let fetched = await photoLibrary.requestDisplayImage(forAssetID: assetID, targetSize: pixelSize)
            // Only adopt if this view is still showing the same asset —
            // grid cells are recycled aggressively while scrolling.
            guard assetID == self.assetID else { return }
            if let fetched {
                image = fetched
                ThumbnailCache.shared.setImage(fetched, forKey: cacheKey)
            }
        }
    }
}
