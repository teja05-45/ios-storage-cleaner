//
//  ScreenshotDetector.swift
//  Reclaim
//
//  Document 06 §4: the simplest category by design — filters on the
//  `isScreenshot` flag already captured during enumeration (from
//  PHAsset.mediaSubtypes.contains(.photoScreenshot)), no further analysis.
//

import Foundation

protocol ScreenshotDetectorProtocol: Sendable {
    func detectScreenshots(in assets: [PhotoAsset]) -> [PhotoAsset]
}

struct ScreenshotDetector: ScreenshotDetectorProtocol {
    func detectScreenshots(in assets: [PhotoAsset]) -> [PhotoAsset] {
        assets.filter(\.isScreenshot)
    }
}
