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

            if viewModel.selection.photoAssetIDs.count + viewModel.selection.screenshotAssetIDs.count > 0 {
                categorySection(
                    title: "Photos & Screenshots",
                    count: viewModel.selection.photoAssetIDs.count + viewModel.selection.screenshotAssetIDs.count
                )
            }
            if !viewModel.selection.videoAssetIDs.isEmpty {
                categorySection(title: "Videos", count: viewModel.selection.videoAssetIDs.count)
            }
            if !viewModel.selection.contactIDs.isEmpty {
                categorySection(title: "Contacts", count: viewModel.selection.contactIDs.count)
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

    private func categorySection(title: String, count: Int) -> some View {
        Section(title) {
            HStack {
                Text("\(count) item\(count == 1 ? "" : "s")")
                Spacer()
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
