//
//  PhotoGroupsView.swift
//  Reclaim
//
//  Document 02 §4.3 — Similar Photos group list. Selection only: nothing
//  is ever deleted from this screen (Document 02 §4.3 "Destructive
//  behavior: none here"). Reads and writes selection exclusively through
//  ReviewStore, so the Review screen's counts can never drift from what
//  the user sees here (Document 04 ADR-03).
//

import SwiftUI

struct PhotoGroupsView: View {
    /// false renders the exact-duplicates list, true the similar-photos
    /// list — same row shape, different store collections.
    let showingSimilar: Bool
    @Environment(\.appEnvironment) private var appEnvironment

    private var store: ReviewStore? { appEnvironment?.reviewStore }

    var body: some View {
        Group {
            if let store {
                content(for: store)
            } else {
                Text("Scan first to see photo groups.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(showingSimilar ? "Similar Photos" : "Exact Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                photoBulkActions
            }
        }
    }

    @ViewBuilder
    private func content(for store: ReviewStore) -> some View {
        let groups = showingSimilar ? store.similarPhotoGroups : store.exactDuplicateGroups
        if groups.isEmpty {
            emptyState
        } else {
            List {
                Section {
                    ForEach(groups) { group in
                        NavigationLink(value: group.id) {
                            PhotoGroupRow(group: group)
                        }
                    }
                } header: {
                    Text("\(groups.count) group\(groups.count == 1 ? "" : "s")")
                } footer: {
                    // Document 06 §3: similarity is an algorithmic
                    // recommendation, never an "AI knows best" claim.
                    Text(showingSimilar
                         ? "Similarity is an algorithmic suggestion based on visual comparison. Always check the group before selecting."
                         : "These photos are byte-identical copies of each other.")
                }
            }
            .navigationDestination(for: UUID.self) { groupID in
                if let group = groups.first(where: { $0.id == groupID }) {
                    PhotoGroupDetailView(group: group, inExactDuplicates: !showingSimilar)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            showingSimilar ? "No Similar Photos Found" : "No Exact Duplicates Found",
            systemImage: "photo.on.rectangle.angled",
            description: Text(showingSimilar
                              ? "Visually similar bursts and retakes will appear here after a scan."
                              : "Byte-identical copies will appear here after a scan.")
        )
    }

    private var photoBulkActions: some View {
        HStack {
            Button("Select All Recommended") {
                store?.selectAllRecommendedInPhotoGroups()
            }
            .disabled((store?.exactDuplicateGroups.isEmpty ?? true) && (store?.similarPhotoGroups.isEmpty ?? true))
            Spacer()
            Button("Deselect All") {
                store?.deselectAllInPhotoGroups()
            }
            .disabled(store?.currentSelection.photoAssetIDs.isEmpty ?? true)
        }
        .font(.subheadline)
    }
}

/// One list row: stacked top-3 thumbnails, member count, keep note,
/// live recoverable bytes for the group's current selection.
struct PhotoGroupRow: View {
    let group: PhotoGroup

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ForEach(Array(group.members.prefix(3).enumerated().reversed()), id: \.element.id) { index, asset in
                    AssetThumbnailView(assetID: asset.id, targetSize: CGSize(width: 44, height: 44))
                        .frame(width: 44, height: 44)
                        .offset(x: CGFloat(index) * 6, y: CGFloat(index) * -4)
                }
            }
            .frame(width: 60, height: 56)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(kindLabel)
                    .font(.subheadline.weight(.medium))
                Text(keepNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(group.selection.count) selected")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                Text(ByteFormatting.string(fromByteCount: group.recoverableBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.members.count) \(kindLabel) in this group, \(group.selection.count) selected for deletion")
        .accessibilityValue(ByteFormatting.string(fromByteCount: group.recoverableBytes))
    }

    private var kindLabel: String {
        group.kind == .exactDuplicate ? "Exact duplicates" : "Similar photos"
    }

    private var keepNote: String {
        // Document 06 §3: "recommended", never "best" — and the user's own
        // override takes precedence in the wording.
        let basis = group.kind == .exactDuplicate
            ? "first taken"
            : "sharpest, highest resolution"
        let prefix = group.userChosenKeepID != nil ? "Your choice" : "Suggested keep"
        return "\(prefix): \(basis)"
    }
}
