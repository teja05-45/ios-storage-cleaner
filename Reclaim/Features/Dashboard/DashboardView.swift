//
//  DashboardView.swift
//  Reclaim
//
//  Document 02 §4.1. Never shows a fabricated number before a real scan.
//  Permission-gated: each category card reflects actual permission state,
//  never implies access the user hasn't granted.
//

import SwiftUI

@MainActor
struct DashboardView: View {
    @State var viewModel: DashboardViewModel
    @State private var showingReview = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    storageCard
                    if viewModel.photosPermission == .limited {
                        limitedAccessBanner
                    }
                    if !viewModel.photosPermission.isUsable || !viewModel.contactsPermission.isUsable {
                        permissionPrompts
                    }
                    scanSection
                    if viewModel.hasScannedOnce {
                        categorySummary
                    }
                }
                .padding()
            }
            .navigationTitle("Reclaim")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showingReview) {
                ReviewView(viewModel: ReviewViewModel(environment: viewModel.appEnvironment))
            }
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Storage", systemImage: "internaldrive")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let summary = viewModel.storageSummary {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ByteFormatting.string(fromByteCount: summary.usedBytes))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("used of \(ByteFormatting.string(fromByteCount: summary.totalCapacityBytes))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if viewModel.hasScannedOnce {
                    Divider()
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.green)
                        Text("\(ByteFormatting.string(fromByteCount: summary.recoverableBytes)) could be recovered")
                            .font(.subheadline.weight(.medium))
                    }
                }
            } else {
                Text("Storage information unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Storage information is currently unavailable")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var limitedAccessBanner: some View {
        Button {
            Task { await viewModel.presentLimitedLibraryPicker() }
        } label: {
            HStack {
                Image(systemName: "photo.stack")
                VStack(alignment: .leading, spacing: 2) {
                    // Document 01 §3.7: never implies a full-library scan
                    // when access is limited.
                    Text("Only your selected photos are scanned")
                        .font(.subheadline.weight(.medium))
                    Text("Tap to choose more photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    private var permissionPrompts: some View {
        VStack(spacing: 12) {
            if !viewModel.photosPermission.isUsable {
                PermissionPromptRow(
                    icon: "photo.on.rectangle.angled",
                    title: "Photos Access",
                    state: viewModel.photosPermission
                ) {
                    Task { await viewModel.requestPhotosAccess() }
                }
            }
            if !viewModel.contactsPermission.isUsable {
                PermissionPromptRow(
                    icon: "person.crop.circle",
                    title: "Contacts Access",
                    state: viewModel.contactsPermission
                ) {
                    Task { await viewModel.requestContactsAccess() }
                }
            }
        }
    }

    private var scanSection: some View {
        VStack(spacing: 12) {
            switch viewModel.scanStatus {
            case .notStarted, .completed, .cancelled, .failed:
                Button {
                    viewModel.startScan()
                } label: {
                    Label(viewModel.hasScannedOnce ? "Scan Again" : "Scan for Space to Clean Up", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.photosPermission.isUsable && !viewModel.contactsPermission.isUsable)
                .accessibilityLabel(viewModel.hasScannedOnce ? "Scan again" : "Scan for items to clean up")
                .accessibilityHint("Scans your photo library and contacts on this device only. Nothing is deleted by scanning.")

            case .scanning(let phase, let completed, let total):
                VStack(spacing: 8) {
                    if total > 0 {
                        ProgressView(value: Double(completed), total: Double(total))
                    } else {
                        ProgressView()
                    }
                    Text(phase)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Cancel", role: .cancel) {
                        viewModel.cancelScan()
                    }
                    .font(.subheadline)
                }
            }

            if let error = viewModel.lastError {
                Text(errorMessage(for: error))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Closes the audit's central ISSUE-09 gap: category cards are now
    /// real navigation into the selection screens, so a user can actually
    /// accumulate a selection and reach Review (the core loop is
    /// user-reachable end to end). Each card states its own live counts —
    /// what was found and what is currently selected — straight from
    /// ReviewStore, never from a private copy.
    private var categorySummary: some View {
        VStack(spacing: 12) {
            let store = viewModel.reviewStore

            NavigationLink {
                PhotoGroupsView(showingSimilar: false)
            } label: {
                CategoryRow(
                    icon: "photo.on.rectangle",
                    title: "Exact Duplicates",
                    subtitle: "\(store.exactDuplicateGroups.count) group\(store.exactDuplicateGroups.count == 1 ? "" : "s"), \(selectedPhotoCount(in: store)) selected"
                )
            }
            .buttonStyle(.plain)
            .disabled(store.exactDuplicateGroups.isEmpty)

            NavigationLink {
                PhotoGroupsView(showingSimilar: true)
            } label: {
                CategoryRow(
                    icon: "photo.stack",
                    title: "Similar Photos",
                    subtitle: "\(store.similarPhotoGroups.count) group\(store.similarPhotoGroups.count == 1 ? "" : "s"), \(selectedPhotoCount(in: store)) selected"
                )
            }
            .buttonStyle(.plain)
            .disabled(store.similarPhotoGroups.isEmpty)

            NavigationLink {
                ScreenshotsView()
            } label: {
                CategoryRow(
                    icon: "camera.viewfinder",
                    title: "Screenshots",
                    subtitle: "\(store.screenshotAssets.count) found, \(store.selectedScreenshotIDs.count) selected"
                )
            }
            .buttonStyle(.plain)
            .disabled(store.screenshotAssets.isEmpty)

            NavigationLink {
                LargeVideosView()
            } label: {
                CategoryRow(
                    icon: "video",
                    title: "Large Videos",
                    subtitle: "\(store.videoAssets.count) found, \(store.selectedVideoIDs.count) selected"
                )
            }
            .buttonStyle(.plain)
            .disabled(store.videoAssets.isEmpty)

            NavigationLink {
                ContactsView()
            } label: {
                CategoryRow(
                    icon: "person.2",
                    title: "Duplicate Contacts",
                    subtitle: "\(store.contactGroups.count) group\(store.contactGroups.count == 1 ? "" : "s"), \(selectedContactCount(in: store)) selected"
                )
            }
            .buttonStyle(.plain)
            .disabled(store.contactGroups.isEmpty)

            if !store.currentSelection.isEmpty {
                Button {
                    showingReview = true
                } label: {
                    Label("Review \(store.currentSelection.totalItemCount) Selected Items", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Opens the final review before anything is deleted")
            }
        }
    }

    private func selectedPhotoCount(in store: ReviewStore) -> Int {
        store.exactDuplicateGroups.reduce(0) { $0 + $1.selection.count }
            + store.similarPhotoGroups.reduce(0) { $0 + $1.selection.count }
    }

    private func selectedContactCount(in store: ReviewStore) -> Int {
        store.contactGroups.reduce(0) { $0 + $1.selection.count }
    }

    private func errorMessage(for error: ReclaimError) -> String {
        switch error {
        case .permissionNotGranted:
            return "Grant access to Photos or Contacts to scan for items to clean up."
        case .frameworkFailure:
            return "Something went wrong during the scan. Please try again."
        default:
            return "The scan couldn't be completed. Please try again."
        }
    }
}

@MainActor
private struct PermissionPromptRow: View {
    let icon: String
    let title: String
    let state: PermissionState
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(state == .notDetermined ? "Allow" : "Open Settings") {
                if state == .notDetermined {
                    action()
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var statusText: String {
        switch state {
        case .notDetermined: return "Not yet requested"
        case .denied: return "Access denied — open Settings to allow"
        case .restricted: return "Restricted by device settings"
        case .authorized, .limited: return "Access granted"
        }
    }
}

@MainActor
private struct CategoryRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}
