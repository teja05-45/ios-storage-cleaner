//
//  ContactsView.swift
//  Reclaim
//
//  Document 02 §4.7 — duplicate-contact groups split into Exact and
//  Probable tiers. Rows disclose the match reason (Document 01 §3.5's
//  disclosure requirement). Selection only; automated merge does not exist
//  by decision (ADR-02) — the detail screen shows exactly what a deletion
//   would cost, and deletion runs exclusively through Review.
//

import SwiftUI

@MainActor
struct ContactsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    private var store: ReviewStore? { appEnvironment?.reviewStore }

    var body: some View {
        Group {
            if let store {
                content(for: store)
            } else {
                Text("Scan first to see duplicate contacts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Duplicate Contacts")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(for store: ReviewStore) -> some View {
        if store.contactGroups.isEmpty {
            ContentUnavailableView(
                "No Duplicate Contacts Found",
                systemImage: "person.2",
                description: Text("Contacts that look like the same person will appear here after a scan.")
            )
        } else {
            let exact = store.contactGroups.filter { $0.tier == .exact }
            let probable = store.contactGroups.filter { $0.tier == .probable }
            List {
                if !exact.isEmpty {
                    section(for: exact, title: "Exact Duplicates", tierExplanation: "Share the same phone number or email address.")
                }
                if !probable.isEmpty {
                    section(for: probable, title: "Probable Duplicates", tierExplanation: "Similar name plus a matching phone or email — never name similarity alone.")
                }
            }
        }
    }

    private func section(for groups: [ContactGroup], title: String, tierExplanation: String) -> some View {
        Section {
            ForEach(groups) { group in
                NavigationLink(value: group.id) {
                    ContactGroupRow(group: group)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(tierExplanation)
        }
    }
}

@MainActor
private struct ContactGroupRow: View {
    let group: ContactGroup

    var body: some View {
        HStack(spacing: 12) {
            AvatarStack(names: group.members.map(\.displayName))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.members.map(\.displayName).joined(separator: ", "))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                // Document 01 §3.5: always disclose why these were matched.
                Text(group.matchReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(group.selection.count) selected")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                Text(confidenceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.members.count) contacts grouped as \(group.tier == .exact ? "exact" : "probable") duplicates, \(group.selection.count) selected for deletion")
        .accessibilityValue(group.matchReason)
    }

    private var confidenceLabel: String {
        group.tier == .exact ? "Certain match" : "Likely match"
    }
}

/// Small overlapping-initials stack standing in for the avatar stack in
/// Document 02 §4.7. Uses initials only — contact photos are deliberately
/// never fetched (minimal key fetch, Document 07 §5).
@MainActor
struct AvatarStack: View {
    let names: [String]

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(names.prefix(3).enumerated().reversed()), id: \.offset) { _, name in
                ZStack {
                    Circle().fill(Color(.systemGray4))
                    Text(initials(for: name))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
        .accessibilityHidden(true) // names are read from the row text
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        let result = first + last
        return result.isEmpty ? "?" : result
    }
}
