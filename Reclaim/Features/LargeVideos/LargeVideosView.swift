//
//  LargeVideosView.swift
//  Reclaim
//
//  Document 02 §4.6 / Document 01 §3.4: ranked list of every video by
//  size, with duration/resolution/date metadata and full in-app playback
//  preview before selection — a thumbnail is not sufficient evidence to
//  delete a video, so preview is a first-class affordance here, not a
//  bonus. Selection only; deletion happens exclusively through Review.
//

import SwiftUI
import AVKit

struct LargeVideosView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    enum SortOrder: String, CaseIterable, Identifiable {
        case largestFirst
        case newestFirst
        var id: String { rawValue }
    }

    @State private var sortOrder: SortOrder = .largestFirst
    @State private var previewVideo: VideoAsset?

    private var store: ReviewStore? { appEnvironment?.reviewStore }

    var body: some View {
        Group {
            if let store {
                content(for: store)
            } else {
                Text("Scan first to see videos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Large Videos")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $previewVideo) { video in
            VideoPreviewView(video: video)
        }
    }

    @ViewBuilder
    private func content(for store: ReviewStore) -> some View {
        let videos = Self.order(store.videoAssets, by: sortOrder)
        if videos.isEmpty {
            ContentUnavailableView(
                "No Videos Found",
                systemImage: "video",
                description: Text("Videos on your device will appear here after a scan, largest first.")
            )
        } else {
            List {
                Section {
                    ForEach(videos) { video in
                        VideoRow(
                            video: video,
                            isSelected: store.selectedVideoIDs.contains(video.id),
                            onPreview: { previewVideo = video },
                            onToggleSelection: { store.toggleVideoSelection(assetID: video.id) }
                        )
                    }
                } header: {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Text(order == .largestFirst ? "Largest first" : "Newest first").tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .textCase(nil)
                } footer: {
                    Text("\(store.selectedVideoIDs.count) selected — \(ByteFormatting.string(fromByteCount: selectedBytes(for: store)))")
                        .textCase(nil)
                }
            }
        }
    }

    private func selectedBytes(for store: ReviewStore) -> Int64 {
        store.videoAssets
            .filter { store.selectedVideoIDs.contains($0.id) }
            .reduce(0) { $0 + $1.byteSize }
    }

    /// Sorting contract for the video list. Kept static and pure so it is
    /// unit-testable without UI. Ties break by ID for determinism; undated
    /// assets sort to the end under newest-first rather than being dropped.
    static func order(_ videos: [VideoAsset], by order: SortOrder) -> [VideoAsset] {
        switch order {
        case .largestFirst:
            return videos.sorted {
                $0.byteSize == $1.byteSize ? $0.id < $1.id : $0.byteSize > $1.byteSize
            }
        case .newestFirst:
            return videos.sorted {
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
}

private struct VideoRow: View {
    let video: VideoAsset
    let isSelected: Bool
    let onPreview: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPreview) {
                ZStack {
                    AssetThumbnailView(assetID: video.id, targetSize: CGSize(width: 72, height: 72))
                        .frame(width: 72, height: 72)
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play preview")

            VStack(alignment: .leading, spacing: 2) {
                Text(MediaFormatting.duration(from: video.duration))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                Text("\(MediaFormatting.resolution(video.pixelSize)) · \(ByteFormatting.string(fromByteCount: video.byteSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(MediaFormatting.captureDate(from: video.creationDate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                onToggleSelection()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.red : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isSelected ? "Deselect video" : "Select video")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        "Video, \(MediaFormatting.duration(from: video.duration)), \(MediaFormatting.resolution(video.pixelSize)), \(ByteFormatting.string(fromByteCount: video.byteSize)), \(isSelected ? "selected for deletion" : "not selected")"
    }
}

/// Full-screen playback (AVPlayerViewController via UIViewControllerRepresentable,
/// per Document 03 §2 / ADR in Document 14). Previews never modify anything —
/// Document 01 §3.4's hard requirement is playback *before* selection.
private struct VideoPreviewView: View {
    let video: VideoAsset
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                ProgressView()
                    .tint(.white)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding()
            .accessibilityLabel("Close preview")
        }
        .task {
            guard let photoLibrary = appEnvironment?.photoLibrary else { return }
            // Document 09 §2: only materialize an AVAsset when the user
            // actually opens a preview — never during the scan/list pass.
            let item = await photoLibrary.playerItem(forVideoAssetID: video.id)
            let resolved = item.map { AVPlayer(playerItem: $0) }
            player = resolved
            player?.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
