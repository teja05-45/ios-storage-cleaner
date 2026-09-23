//
//  PhotoGroupDetailView.swift
//  Reclaim
//
//  Document 02 §4.4 — inspect one group closely and decide what to keep.
//  Every mutation goes through ReviewStore → PhotoGroup, whose mutating
//  methods make selecting the effective keep structurally impossible, so
//  the UI does not need to defend that invariant (and cannot violate it).
//  Selection only — nothing is deleted from this screen.
//

import SwiftUI

@MainActor
struct PhotoGroupDetailView: View {
    /// Passed by value from the list; every mutation re-reads the live
    /// group from ReviewStore, so the screen never renders stale state.
    let group: PhotoGroup
    let inExactDuplicates: Bool

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var previewAsset: PhotoAsset?

    private var liveGroup: PhotoGroup? {
        let store = appEnvironment?.reviewStore
        let groups = inExactDuplicates ? store?.exactDuplicateGroups : store?.similarPhotoGroups
        return groups?.first(where: { $0.id == group.id })
    }

    var body: some View {
        Group {
            if let live = liveGroup {
                content(for: live)
            } else {
                // The group vanished (post-cleanup pruning) — render an
                // honest empty state rather than a stale grid.
                ContentUnavailableView("Group No Longer Available", systemImage: "photo.stack")
            }
        }
        .navigationTitle("Group of \(group.members.count)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $previewAsset) { asset in
            PhotoDetailPreviewView(asset: asset)
        }
    }

    @ViewBuilder
    private func content(for live: PhotoGroup) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Document 06 §3: explainable, non-absolute recommendation.
                recommendedBanner(for: live)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                    ForEach(live.members) { asset in
                        PhotoGroupCell(
                            asset: asset,
                            isKeep: asset.id == live.effectiveKeepID,
                            isSelected: live.selection.contains(asset.id),
                            groupKind: live.kind
                        ) {
                            previewAsset = asset
                        } onToggleSelection: {
                            toggle(assetID: asset.id, inExactDuplicates: inExactDuplicates)
                        } onSetKeep: {
                            setKeep(assetID: asset.id)
                        }
                    }
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button("Select Group (Except Keep)") {
                        mutate { $0.selectAllExceptKeep() }
                    }
                    Spacer()
                    Button("Deselect Group") {
                        mutate { $0.deselectAll() }
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private func recommendedBanner(for live: PhotoGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let keep = live.members.first(where: { $0.id == live.effectiveKeepID })
            Label(
                live.userChosenKeepID != nil ? "Your chosen keep" : "Suggested to keep",
                systemImage: live.userChosenKeepID != nil ? "hand.tap" : "sparkles"
            )
            .font(.subheadline.weight(.medium))
            // Signals: resolution + capture order only — no face-detection
            // or "AI" claims (hard prohibition, Document 06 §3).
            Text(keep.map {
                live.kind == .exactDuplicate
                    ? "The earliest copy, taken \(MediaFormatting.captureDate(from: $0.creationDate))."
                    : "Highest resolution of the group (\(MediaFormatting.resolution($0.pixelSize)))."
            } ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func toggle(assetID: String, inExactDuplicates: Bool) {
        let store = appEnvironment?.reviewStore
        if inExactDuplicates {
            store?.toggleExactDuplicateSelection(groupID: group.id, assetID: assetID)
        } else {
            store?.toggleSimilarPhotoSelection(groupID: group.id, assetID: assetID)
        }
    }

    private func setKeep(assetID: String) {
        appEnvironment?.reviewStore.setUserChosenKeep(groupID: group.id, assetID: assetID, inExactDuplicates: inExactDuplicates)
    }

    /// Group-level actions re-read the live group and apply its own mutating
    /// method through the store's array — keeps every mutation funneled
    /// through ReviewStore's collections (no parallel copy of group state).
    private func mutate(_ transform: (inout PhotoGroup) -> Void) {
        guard let store = appEnvironment?.reviewStore else { return }
        store.mutatePhotoGroup(groupID: group.id, inExactDuplicates: inExactDuplicates, transform)
    }
}

/// One grid cell: thumbnail, keep badge, selection checkmark, tap to
/// preview, explicit "Keep this instead" for non-keep members.
@MainActor
private struct PhotoGroupCell: View {
    let asset: PhotoAsset
    let isKeep: Bool
    let isSelected: Bool
    let groupKind: PhotoGroupKind
    let onPreview: () -> Void
    let onToggleSelection: () -> Void
    let onSetKeep: () -> Void

    @State private var showingKeepAction = false

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onPreview) {
                AssetThumbnailView(assetID: asset.id, targetSize: CGSize(width: 104, height: 104))
                    .frame(width: 104, height: 104)
                    .overlay(alignment: .topLeading) {
                        if isKeep {
                            Image(systemName: "sparkles")
                                .font(.caption2.weight(.bold))
                                .padding(4)
                                .background(Circle().fill(.yellow))
                                .accessibilityLabel("Suggested keep")
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.white, .red)
                                .padding(4)
                        }
                    }
            }
            .buttonStyle(.plain)

            if isKeep {
                Text("Keep")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Button("Select") { onToggleSelection() }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                Button("Keep Instead") { showingKeepAction = true }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .confirmationDialog(
                        "Keep this photo instead?",
                        isPresented: $showingKeepAction,
                        titleVisibility: .visible
                    ) {
                        Button("Keep This Instead") { onSetKeep() }
                    }
            }

            Text(ByteFormatting.string(fromByteCount: asset.byteSize))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        // Document 02 §4.4: state must be announced, never conveyed by the
        // checkmark alone.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isKeep ? "The suggested photo to keep" : "Tap Select to mark this photo for deletion")
    }

    private var accessibilityText: String {
        var parts: [String] = []
        parts.append(isKeep ? "Suggested keep" : (isSelected ? "Selected for deletion" : "Not selected"))
        parts.append(ByteFormatting.string(fromByteCount: asset.byteSize))
        parts.append(MediaFormatting.resolution(asset.pixelSize))
        if let date = asset.creationDate {
            parts.append("taken \(MediaFormatting.captureDate(from: date))")
        }
        return parts.joined(separator: ", ")
    }
}

/// Full-screen tap-to-preview. Document 02 §4.4 asks for full-screen
/// preview with the full-resolution image — delivered through the live
/// service at device-pixel size on demand, never preloaded.
@MainActor
private struct PhotoDetailPreviewView: View {
    let asset: PhotoAsset
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: asset.id) {
            guard let photoLibrary = appEnvironment?.photoLibrary else { return }
            let scale = UIScreen.main.scale
            let size = CGSize(width: UIScreen.main.bounds.width * scale, height: UIScreen.main.bounds.height * scale)
            image = await photoLibrary.requestDisplayImage(forAssetID: asset.id, targetSize: size)
        }
        .overlay(alignment: .topTrailing) {
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
    }
}
