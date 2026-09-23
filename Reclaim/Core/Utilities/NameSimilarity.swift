//
//  NameSimilarity.swift
//  Reclaim
//
//  Document 06 §6 "Name similarity". Pure Foundation.
//

import Foundation

enum NameSimilarity {

    /// Classic Levenshtein (edit distance) via a rolling-two-row DP —
    /// O(min(m,n)) space, O(m*n) time. Case/whitespace already normalized
    /// by the caller (`score(_:_:)` below).
    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var previousRow = Array(0...bChars.count)
        var currentRow = Array(repeating: 0, count: bChars.count + 1)

        for i in 1...aChars.count {
            currentRow[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                currentRow[j] = Swift.min(
                    previousRow[j] + 1,       // deletion
                    currentRow[j - 1] + 1,    // insertion
                    previousRow[j - 1] + cost // substitution
                )
            }
            previousRow = currentRow
        }
        return previousRow[bChars.count]
    }

    /// Normalizes case/whitespace, then tries both:
    /// 1. Direct Levenshtein similarity on the full name strings.
    /// 2. Token-set overlap (handles reordering, e.g. "John Smith" vs
    ///    "Smith, John") — takes the tokens of each name, sorts them, joins,
    ///    and runs Levenshtein on that canonical form.
    /// Returns the higher of the two, since either form matching is
    /// evidence of the same underlying name (Document 06 §6, Document 08 §1
    /// "reordered 'Last, First' vs 'First Last' cases").
    static func score(_ nameA: String, _ nameB: String) -> Double {
        let normA = normalize(nameA)
        let normB = normalize(nameB)

        if normA.isEmpty && normB.isEmpty { return 1.0 }
        if normA.isEmpty || normB.isEmpty { return 0.0 }

        let directScore = similarityScore(normA, normB)

        let canonicalA = canonicalTokenForm(normA)
        let canonicalB = canonicalTokenForm(normB)
        let tokenScore = similarityScore(canonicalA, canonicalB)

        return Swift.max(directScore, tokenScore)
    }

    // MARK: - Private

    private static func normalize(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func canonicalTokenForm(_ normalizedName: String) -> String {
        normalizedName
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: " ")
    }

    private static func similarityScore(_ a: String, _ b: String) -> Double {
        let distance = levenshteinDistance(a, b)
        let maxLen = Swift.max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLen))
    }
}
