//
//  ScreenshotsView.swift
//  Reclaim
//
//  Document 02 §4.5 / Document 01 §3.3: a fast flat grid of everything the
//  OS itself flags via PHAsset.mediaSubtypes — no duplicate/similarity
//  logic here by design (false-positive risk isn't worth it for a flat
//  set). Selection only; deletion happens exclusively through Review.
//

import SwiftUI

struct ScreenshotsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    private var store: ReviewStore? { appEnvironment?.reviewStore }

    var body: some View {
        Group {
            if let store {
                content(for: store)
            } else {
                Text("Scan first to see screenshots.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Screenshots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                bulkActions
            }
        }
    }

    @ViewBuilder
    private func content(for store: ReviewStore) -> some View {
        let screenshots = Self.orderMostRecentFirst(store.screenshotAssets)
        if screenshots.isEmpty {
            ContentUnavailableView(
                "No Screenshots Found",
                systemImage: "camera.viewfinder",
                description: Text("Screenshots on your device will appear here after a scan.")
            )
        } else {
            let selectedCount = store.selectedScreenshotIDs.count
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Live counter — updates as selection changes
                    // (Document 02 §4.5 "running recoverable-size counter").
                    Text("\(selectedCount) selected — \(ByteFormatting.string(fromByteCount: selectedBytes(for: store)))")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .padding(.horizontal)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(screenshots) { asset in
                            ScreenshotCell(
                                asset: asset,
                                isSelected: store.selectedScreenshotIDs.contains(asset.id)
                            ) {
                                store.toggleScreenshotSelection(assetID: asset.id)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
    }

    private var bulkActions: some View {
        HStack {
            Button("Select All") { store?.selectAllScreenshots() }
                .disabled(store?.screenshotAssets.isEmpty ?? true)
            Spacer()
            Button("Deselect All") { store?.deselectAllScreenshots() }
                .disabled((store?.selectedScreenshotIDs.isEmpty ?? true))
        }
        .font(.subheadline)
    }

    private func selectedBytes(for store: ReviewStore) -> Int64 {
        store.screenshotAssets
            .filter { store.selectedScreenshotIDs.contains($0.id) }
            .reduce(0) { $0 + $1.byteSize }
    }

    /// Document 01 §3.3: chronological, most recent first. Assets without a
    /// capture date sort to the end rather than being dropped. Static so
    /// the ordering contract is unit-testable without UI (screenshot
    /// ordering was an audit-identified test-coverage gap).
    static func orderMostRecentFirst(_ assets: [PhotoAsset]) -> [PhotoAsset] {
        assets.sorted {
            switch ($0.creationDate, $1.creationDate) {
            case let (a?, b?):
                return a == b ? $0.id < $1.id : a > b
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return $0.id < $1.id
            }
        }
    }
}

private struct ScreenshotCell: View {
    let asset: PhotoAsset
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 4) {
                AssetThumbnailView(assetID: asset.id, targetSize: CGSize(width: 104, height: 104))
                    .frame(width: 104, height: 104)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.white, .red)
                                .padding(4)
                        }
                    }
                Text(MediaFormatting.captureDate(from: asset.creationDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this screenshot")
    }

    private var accessibilityText: String {
        var parts = ["Screenshot"]
        parts.append(isSelected ? "selected for deletion" : "not selected")
        parts.append(ByteFormatting.string(fromByteCount: asset.byteSize))
        if asset.creationDate != nil {
            parts.append("taken \(MediaFormatting.captureDate(from: asset.creationDate))")
        }
        return parts.joined(separator: ", ")
    }
}
