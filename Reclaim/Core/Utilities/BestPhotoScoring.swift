//
//  BestPhotoScoring.swift
//  Reclaim
//
//  Document 06 §3. This file owns ONLY the normalization/weighting/reason
//  math. Computing the raw sharpness (Laplacian variance via vImage) and
//  exposure (histogram clipping) signals from actual pixel data is the
//  Services layer's job (SimilarityDetector) — kept out of Core so this
//  logic is testable with synthetic fixture numbers, no image processing
//  needed (Document 03 §4, Document 08 §1).
//
//  EXPLICITLY NOT IMPLEMENTED (Document 06 §3): face detection, eyes-open/
//  closed detection, smile detection, subject-vs-background focus
//  discrimination. `reason` never references any of these — only signals
//  actually computed below.
//

import Foundation

enum BestPhotoScoring {

    /// One asset's raw, per-signal inputs before normalization.
    struct RawSignals {
        let assetID: String
        /// pixelWidth * pixelHeight
        let resolutionPixels: Double
        /// Laplacian-variance focus measure over a downsampled grayscale
        /// thumbnail — higher means sharper.
        let sharpnessRaw: Double
        /// Proportion of near-clipped (very dark/very bright) pixels,
        /// inverted so higher means "better exposed" — 1.0 minus the
        /// clipped-pixel proportion, computed upstream in Services.
        let exposureRaw: Double
        let byteSize: Int64
    }

    /// Weighted, normalized (0-1 per signal within the group) formula per
    /// Document 06 §3. Sharpness weighted highest because blur is the most
    /// common, most visually obvious reason a user would reject a
    /// "recommended keep." These are named, documented constants — never
    /// magic numbers buried in the formula (this build's instructions §18).
    enum Weight {
        static let resolution = 0.35
        static let sharpness = 0.45
        static let exposure = 0.15
        static let fileSize = 0.05
    }

    /// Scores every asset in a group and returns `PhotoCandidate`s carrying
    /// a human-readable `reason` for the top-scoring candidate. Returns an
    /// empty array if `signals` is empty; a single-element group still
    /// scores (trivially, as the only/best candidate) since callers may use
    /// this for a group of one during testing, though in practice
    /// SimilarityDetector only forms groups of 2+.
    static func score(_ signals: [RawSignals]) -> [PhotoCandidate] {
        guard !signals.isEmpty else { return [] }

        let maxResolution = signals.map(\.resolutionPixels).max() ?? 1
        let maxSharpness = signals.map(\.sharpnessRaw).max() ?? 1
        let maxExposure = signals.map(\.exposureRaw).max() ?? 1
        let maxByteSize = signals.map { Double($0.byteSize) }.max() ?? 1

        func normalized(_ value: Double, max: Double) -> Double {
            max > 0 ? value / max : 0
        }

        var candidates: [(signals: RawSignals, scores: (res: Double, sharp: Double, exp: Double, size: Double), total: Double)] = []

        for s in signals {
            let resScore = normalized(s.resolutionPixels, max: maxResolution)
            let sharpScore = normalized(s.sharpnessRaw, max: maxSharpness)
            let expScore = normalized(s.exposureRaw, max: maxExposure)
            let sizeScore = normalized(Double(s.byteSize), max: maxByteSize)

            let total = Weight.resolution * resScore
                + Weight.sharpness * sharpScore
                + Weight.exposure * expScore
                + Weight.fileSize * sizeScore

            candidates.append((s, (resScore, sharpScore, expScore, sizeScore), total))
        }

        let maxTotal = candidates.map(\.total).max() ?? 0

        return candidates.map { entry in
            let reason = reasonString(
                for: entry,
                isTopCandidate: entry.total == maxTotal,
                groupSize: signals.count
            )
            return PhotoCandidate(
                asset: PhotoAsset(
                    id: entry.signals.assetID,
                    creationDate: nil,
                    pixelSize: .zero,
                    byteSize: entry.signals.byteSize,
                    isScreenshot: false
                ),
                resolutionScore: entry.scores.res,
                sharpnessScore: entry.scores.sharp,
                exposureScore: entry.scores.exp,
                totalScore: entry.total,
                reason: reason
            )
        }
    }

    /// Convenience: the recommended-keep asset ID for a group, i.e. the
    /// candidate with the highest total score. Ties broken by asset ID for
    /// determinism (same input always produces same recommendation).
    static func recommendedKeepID(_ signals: [RawSignals]) -> String? {
        let scored = score(signals)
        return scored
            .sorted { $0.totalScore == $1.totalScore ? $0.asset.id < $1.asset.id : $0.totalScore > $1.totalScore }
            .first?.asset.id
    }

    // MARK: - Private

    private static func reasonString(
        for entry: (signals: RawSignals, scores: (res: Double, sharp: Double, exp: Double, size: Double), total: Double),
        isTopCandidate: Bool,
        groupSize: Int
    ) -> String {
        guard isTopCandidate else {
            return "Lower overall quality than the recommended photo in this group of \(groupSize)."
        }

        var reasons: [String] = []
        if entry.scores.res >= 0.99 { reasons.append("highest resolution") }
        if entry.scores.sharp >= 0.99 { reasons.append("sharpest") }
        if entry.scores.exp >= 0.99 && reasons.isEmpty { reasons.append("best exposed") }

        if reasons.isEmpty {
            return "Best overall balance of resolution and sharpness of \(groupSize)."
        }

        let joined = reasons.count == 1
            ? reasons[0].capitalizingFirstLetter()
            : reasons.map { $0 }.joined(separator: ", ").capitalizingFirstLetter()

        return "\(joined) of \(groupSize)."
    }
}

private extension String {
    func capitalizingFirstLetter() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
