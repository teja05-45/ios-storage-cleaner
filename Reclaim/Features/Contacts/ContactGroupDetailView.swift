//
//  ContactGroupDetailView.swift
//  Reclaim
//
//  Document 01 §3.5 / Document 02 §4.7 — the field-diff preview that makes
//  review-and-delete safe without automated merge (ADR-02): for every
//  non-primary member the screen shows which fields would survive and
//  which would be lost, fetched live from the Contacts store (never a
//  stale cached copy — Document 05 §5 note). Selection only; deletion
//  happens exclusively through Review.
//

import SwiftUI

@MainActor
struct ContactGroupDetailView: View {
    let group: ContactGroup

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var displayFields: [String: ContactDisplayFields] = [:]
    @State private var loadFailed = false

    // This view reads MainActor-isolated ReviewStore state from SwiftUI
    // closures that Swift 6 mode's minimal checking treats as nonisolated;
    // the view is MainActor-bound by contract, so the compiler's crossing
    // diagnostic is satisfied with assumeIsolated.
    private var liveGroup: ContactGroup? {
        MainActor.assumeIsolated {
            appEnvironment?.reviewStore.contactGroups.first(where: { $0.id == group.id })
        }
    }

    private var primary: ContactCandidate? {
        guard let live = liveGroup else { return nil }
        return live.members.first(where: { $0.id == live.recommendedPrimaryID })
    }

    var body: some View {
        Group {
            if let live = liveGroup {
                content(for: live)
            } else {
                ContentUnavailableView("Group No Longer Available", systemImage: "person.2.slash")
            }
        }
        .navigationTitle("Duplicate Group")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(for live: ContactGroup) -> some View {
        List {
            Section {
                ForEach(live.members) { member in
                    memberRow(member: member, group: live)
                }
            } header: {
                Text(live.tier == .exact ? "Exact duplicates" : "Probable duplicates")
            } footer: {
                Text(live.matchReason)
            }

            if loadFailed {
                Section {
                    // Honest failure state — live field values could not be
                    // fetched, so the diff below may be incomplete.
                    Label("Couldn't load current contact details. The field comparison may be incomplete.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            ForEach(live.members.filter { $0.id != live.recommendedPrimaryID }) { member in
                fieldDiffSection(primary: primary, member: member)
            }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button("Select Duplicates") {
                        selectAllDuplicates(in: live)
                    }
                    Spacer()
                    Button("Deselect Group") {
                        deselectAll(in: live)
                    }
                }
                .font(.subheadline)
            }
        }
        .task {
            await loadDisplayFields(for: live)
        }
    }

    private func memberRow(member: ContactCandidate, group: ContactGroup) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(member.displayName)
                        .font(.subheadline.weight(.medium))
                    if member.id == group.recommendedPrimaryID {
                        Text("Keep")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                            .foregroundStyle(.green)
                    }
                }
                Text(summaryLine(for: member))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if member.id != group.recommendedPrimaryID {
                Button {
                    appEnvironment?.reviewStore.toggleContactSelection(groupID: group.id, contactID: member.id)
                } label: {
                    Image(systemName: group.selection.contains(member.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(group.selection.contains(member.id) ? Color.red : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(group.selection.contains(member.id) ? "Deselect contact" : "Select contact for deletion")
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The per-field "what would be lost" disclosure (Document 01 §3.5).
    /// Rendered only once live display fields are available; falls back to
    /// normalized comparison keys when a fetch fails.
    private func fieldDiffSection(primary: ContactCandidate?, member: ContactCandidate) -> some View {
        Section {
            if let primary, let primaryFields = displayFields[primary.id], let memberFields = displayFields[member.id] {
                let diffs = Self.fieldDiffs(primary: primaryFields, other: memberFields)
                ForEach(Array(diffs.enumerated()), id: \.offset) { _, diff in
                    HStack(alignment: .top) {
                        Text(diff.label)
                            .font(.caption)
                            .frame(width: 70, alignment: .leading)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(diff.primaryValue ?? "—")
                                .font(.caption)
                            if diff.wouldBeLost {
                                Text(diff.otherValue ?? "")
                                    .font(.caption)
                                    .strikethrough()
                                    .foregroundStyle(.red)
                                Text("will be lost")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.red)
                            } else if let other = diff.otherValue {
                                Text(other)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text(fieldCountSummary(primary: primary, member: member))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("If you delete \"\(member.displayName)\"")
        }
    }

    private func summaryLine(for member: ContactCandidate) -> String {
        var parts: [String] = []
        if !member.normalizedPhones.isEmpty { parts.append("\(member.normalizedPhones.count) phone\(member.normalizedPhones.count == 1 ? "" : "s")") }
        if !member.normalizedEmails.isEmpty { parts.append("\(member.normalizedEmails.count) email\(member.normalizedEmails.count == 1 ? "" : "s")") }
        return parts.isEmpty ? "No phone or email on this record" : parts.joined(separator: ", ")
    }

    private func fieldCountSummary(primary: ContactCandidate?, member: ContactCandidate) -> String {
        guard let primary else { return "" }
        let primaryFields = primary.fieldCount
        let memberFields = member.fieldCount
        if memberFields > primaryFields {
            return "This record has \(memberFields - primaryFields) more field\(memberFields - primaryFields == 1 ? "" : "s") than the one marked Keep. Check the contacts app before deleting."
        }
        return "The record marked Keep holds at least as much information as this one."
    }

    private func selectAllDuplicates(in group: ContactGroup) {
        for member in group.members where member.id != group.recommendedPrimaryID {
            if !group.selection.contains(member.id) {
                appEnvironment?.reviewStore.toggleContactSelection(groupID: group.id, contactID: member.id)
            }
        }
    }

    private func deselectAll(in group: ContactGroup) {
        for member in group.members where group.selection.contains(member.id) {
            appEnvironment?.reviewStore.toggleContactSelection(groupID: group.id, contactID: member.id)
        }
    }

    private func loadDisplayFields(for group: ContactGroup) async {
        guard let contactService = appEnvironment?.contactService else { return }
        do {
            for member in group.members {
                displayFields[member.id] = try await contactService.fetchDisplayFields(forContactID: member.id)
            }
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Pure field-diff computation, static so it is unit-testable without
    /// the Contacts framework.
    static func fieldDiffs(primary: ContactDisplayFields, other: ContactDisplayFields) -> [ContactGroup.FieldDiff] {
        var diffs: [ContactGroup.FieldDiff] = []
        let primaryName = [primary.givenName, primary.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let otherName = [other.givenName, other.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        // A name difference between the two records is displayed so the user
        // can eyeball the match, but it is NOT flagged as unique data that
        // would be lost: both records carry a name, and after deleting one
        // the surviving record's name remains. Only data present on the
        // other side but absent from the primary is a real loss.
        diffs.append(ContactGroup.FieldDiff(
            label: "Name",
            primaryValue: primaryName.isEmpty ? nil : primaryName,
            otherValue: otherName.isEmpty ? nil : otherName,
            isLoss: false
        ))

        let primaryPhones = Set(primary.phoneNumbers)
        let otherPhones = Set(other.phoneNumbers)
        for phone in primaryPhones.union(otherPhones).sorted() {
            diffs.append(ContactGroup.FieldDiff(
                label: "Phone",
                primaryValue: primaryPhones.contains(phone) ? phone : nil,
                otherValue: otherPhones.contains(phone) ? phone : nil
            ))
        }

        let primaryEmails = Set(primary.emailAddresses)
        let otherEmails = Set(other.emailAddresses)
        for email in primaryEmails.union(otherEmails).sorted() {
            diffs.append(ContactGroup.FieldDiff(
                label: "Email",
                primaryValue: primaryEmails.contains(email) ? email : nil,
                otherValue: otherEmails.contains(email) ? email : nil
            ))
        }
        return diffs
    }
}
