//
//  CleanupResultView.swift
//  Reclaim
//
//  Document 02 §4.9, Document 05 §10. Shows exactly what was deleted, and
//  is explicit about partial failures — never implies 100% success when
//  `summary.failures` is non-empty.
//

import SwiftUI

struct CleanupResultView: View {
    let summary: CleanupSummary
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: summary.hadPartialFailure ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(summary.hadPartialFailure ? .orange : .green)
                    .padding(.top, 24)

                VStack(spacing: 6) {
                    Text(summary.hadPartialFailure ? "Cleanup Mostly Complete" : "Cleanup Complete")
                        .font(.title2.weight(.bold))
                    Text("\(summary.totalDeletedCount) item\(summary.totalDeletedCount == 1 ? "" : "s") removed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    // bytesFreed is an independently recomputed device
                    // free-space delta, never the pre-cleanup estimate
                    // (Document 01 §3.6, ADR in Document 14).
                    Text(ByteFormatting.string(fromByteCount: max(0, summary.bytesFreed)))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("freed on your device")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                .padding(.horizontal)

                if summary.hadPartialFailure {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(summary.failures.count) item\(summary.failures.count == 1 ? "" : "s") couldn't be removed", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                        Text(failureExplanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.1)))
                    .padding(.horizontal)
                }

                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
            }
            .padding(.bottom, 24)
        }
    }

    private var failureExplanation: String {
        let reasons = Set(summary.failures.map(\.reason))
        var parts: [String] = []
        if reasons.contains(.staleAsset) {
            parts.append("Some items had already changed or been removed.")
        }
        if reasons.contains(.permissionRevoked) {
            parts.append("Access was changed during cleanup.")
        }
        if reasons.contains(where: { if case .frameworkError = $0 { return true }; return false }) {
            parts.append("Some items failed to delete due to a system error.")
        }
        return parts.isEmpty ? "Some items could not be removed." : parts.joined(separator: " ")
    }
}
