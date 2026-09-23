//
//  ReviewView.swift
//  Reclaim
//
//  Document 02 §4.9. Shows exactly what will be deleted, grouped by
//  category, with an explicit confirmation step before anything happens.
//  This view never triggers deletion itself — it only calls
//  `viewModel.confirmCleanup()` from one button, after a confirmation
//  dialog the user must explicitly accept.
//

import SwiftUI

struct ReviewView: View {
    @State var viewModel: ReviewViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingConfirmDialog = false

    var body: some View {
        NavigationStack {
            Group {
                if let summary = viewModel.cleanupSummary {
                    CleanupResultView(summary: summary) { dismiss() }
                } else {
                    reviewContent
                }
            }
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var reviewContent: some View {
        List {
            Section {
                HStack {
                    Text("Total to remove")
                    Spacer()
                    Text(ByteFormatting.string(fromByteCount: viewModel.estimatedRecoverableBytes))
                        .font(.headline)
                        .monospacedDigit()
                }
            } header: {
                Text("\(viewModel.selection.totalItemCount) items selected")
            } footer: {
                // Document 01 §3.1: never claims this equals a guaranteed
                // device free-space delta.
                Text("Estimated size of selected items. Actual space freed on your device may differ slightly.")
            }

            // Document 02 §4.8: every selected item must be individually
            // inspectable here, and removable — totals update live through
            // ReviewStore, so what is confirmed is exactly what is shown.
            let store = viewModel.reviewStore
            if !store.selectedPhotoMembers.isEmpty {
                selectedItemsSection(
                    title: "Photos",
                    items: store.selectedPhotoMembers.map { member in
                        SelectedItem(id: member.id, title: "Photo", subtitle: MediaFormatting.captureDate(from: member.creationDate), byteSize: member.byteSize, assetID: member.id)
                    },
                    onRemove: { viewModel.removePhoto(id: $0) }
                )
            }
            if !store.selectedScreenshots.isEmpty {
                selectedItemsSection(
                    title: "Screenshots",
                    items: store.selectedScreenshots.map { asset in
                        SelectedItem(id: asset.id, title: "Screenshot", subtitle: MediaFormatting.captureDate(from: asset.creationDate), byteSize: asset.byteSize, assetID: asset.id)
                    },
                    onRemove: { viewModel.removeScreenshot(id: $0) }
                )
            }
            if !store.selectedVideos.isEmpty {
                selectedItemsSection(
                    title: "Videos",
                    items: store.selectedVideos.map { video in
                        SelectedItem(id: video.id, title: "Video", subtitle: MediaFormatting.duration(from: video.duration), byteSize: video.byteSize, assetID: video.id)
                    },
                    onRemove: { viewModel.removeVideo(id: $0) }
                )
            }
            if !store.selectedContactMembers.isEmpty {
                selectedItemsSection(
                    title: "Contacts",
                    items: store.selectedContactMembers.map { pair in
                        // Contacts contribute no bytes but carry the match
                        // reason — the user should be reminded why each one
                        // was flagged before confirming deletion.
                        SelectedItem(id: pair.member.id, title: pair.member.displayName, subtitle: pair.group.matchReason, byteSize: nil, assetID: nil)
                    },
                    onRemove: { viewModel.removeContact(id: $0) }
                )
            }

            if let error = viewModel.cleanupError {
                Section {
                    Text(errorMessage(for: error))
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) {
                    showingConfirmDialog = true
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isCleaningUp {
                            ProgressView()
                        } else {
                            Text("Delete \(viewModel.selection.totalItemCount) Items")
                        }
                        Spacer()
                    }
                }
                .disabled(!viewModel.canConfirm)
                // OPEN-4 accessibility: the destructive control carries an
                // explicit label and hint — a VoiceOver user must hear what
                // this deletes before reaching the confirm dialog.
                .accessibilityLabel("Delete \(viewModel.selection.totalItemCount) items permanently")
                .accessibilityHint("Opens a confirmation dialog. Deleted photos and videos remain in Recently Deleted for 30 days; contacts are removed immediately.")
            }
        }
        // Explicit confirmation dialog — the last gate before
        // PerformCleanupUseCase.execute is ever called (Document 07 §7).
        .confirmationDialog(
            "Delete \(viewModel.selection.totalItemCount) items?",
            isPresented: $showingConfirmDialog,
            titleVisibility: .visible
        ) {
            Button("Delete Forever", role: .destructive) {
                Task { await viewModel.confirmCleanup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone from within Reclaim. Deleted photos and videos go to your device's Recently Deleted album for 30 days; deleted contacts are removed immediately.")
        }
    }

    private func selectedItemsSection(
        title: String,
        items: [SelectedItem],
        onRemove: @escaping (String) -> Void
    ) -> some View {
        Section(title) {
            ForEach(items) { item in
                SelectedItemRow(item: item, onRemove: { onRemove(item.id) })
            }
        }
    }

    private func errorMessage(for error: ReclaimError) -> String {
        switch error {
        case .emptySelection: return "Nothing is selected."
        case .notConfirmed: return "Deletion was not confirmed."
        case .permissionNotGranted: return "Access was revoked. Please re-grant access in Settings."
        case .frameworkFailure: return "Some items could not be deleted. See details above."
        case .scanCancelled: return "Cancelled."
        case .staleSelection: return "Some selected items are no longer available and were skipped."
        }
    }
}

/// One inspectable row in a Review section: title, detail line, byte size
/// when the category has one (contacts don't), thumbnail when it is a
/// PhotoKit asset, and an explicit per-item remove action.
struct SelectedItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let byteSize: Int64?
    /// Non-nil for photos/screenshots/videos — drives thumbnail loading.
    let assetID: String?
}

struct SelectedItemRow: View {
    let item: SelectedItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let assetID = item.assetID {
                AssetThumbnailView(assetID: assetID, targetSize: CGSize(width: 44, height: 44))
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium))
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let byteSize = item.byteSize {
                Text(ByteFormatting.string(fromByteCount: byteSize))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(item.title) from selection")
        }
        .accessibilityElement(children: .contain)
    }
}
