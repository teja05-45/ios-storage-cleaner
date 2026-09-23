//
//  DuplicateContactDetector.swift
//  Reclaim
//
//  Document 06 §6. THE SINGLE HIGHEST PRODUCT-RISK ALGORITHM IN THE APP
//  (Document 13 §2.8) — a false positive here risks a user losing a real,
//  unique contact. Two hard guards, both enforced structurally, not just
//  by convention:
//
//   1. Name similarity ALONE is never sufficient to classify a pair as a
//      duplicate candidate of either tier (this build's instructions §5).
//      `.exact` requires a real shared phone or email. `.probable` requires
//      high name similarity PLUS at least one secondary signal — never
//      name alone.
//   2. Oversized groups (>8 members) are demoted to `.probable` with a
//      penalized confidence and an explicit "review carefully" reason —
//      a large shared-phone bucket is more likely a shared office/family
//      line than eight true duplicate people (Document 13 §2.8).
//

import Foundation

protocol DuplicateContactDetectorProtocol: Sendable {
    func detectDuplicateGroups(in contacts: [ContactCandidate]) -> [ContactGroup]
}

struct DuplicateContactDetector: DuplicateContactDetectorProtocol {

    /// Name-similarity floor for a `.probable` classification. Deliberately
    /// high (favoring precision) since name similarity is only ever half
    /// the evidence required (guard #1 above).
    private let probableNameSimilarityThreshold = 0.90

    /// Groups larger than this are demoted to `.probable` regardless of how
    /// they were formed (guard #2 above).
    private let maxTrustedGroupSize = 8

    func detectDuplicateGroups(in contacts: [ContactCandidate]) -> [ContactGroup] {
        guard contacts.count > 1 else { return [] }

        var uf = UnionFind(count: contacts.count)
        // "i-j" (i<j) -> true if the pair was joined by an exact signal,
        // false if joined by a probable signal. Used after unions settle to
        // decide each resulting component's tier.
        var pairHadExactEdge: [String: Bool] = [:]

        // --- Pass 1: exact-signal bucketing (phone/email) — O(n), not O(n²) ---
        var phoneBuckets: [String: [Int]] = [:]
        var emailBuckets: [String: [Int]] = [:]
        for (index, contact) in contacts.enumerated() {
            for phone in contact.normalizedPhones {
                phoneBuckets[phone, default: []].append(index)
            }
            for email in contact.normalizedEmails {
                emailBuckets[email, default: []].append(index)
            }
        }

        for bucket in phoneBuckets.values where bucket.count > 1 {
            for i in 1..<bucket.count {
                uf.union(bucket[0], bucket[i])
                pairHadExactEdge["\(min(bucket[0], bucket[i]))-\(max(bucket[0], bucket[i]))"] = true
            }
        }
        for bucket in emailBuckets.values where bucket.count > 1 {
            for i in 1..<bucket.count {
                uf.union(bucket[0], bucket[i])
                pairHadExactEdge["\(min(bucket[0], bucket[i]))-\(max(bucket[0], bucket[i]))"] = true
            }
        }

        // --- Pass 2: probable-signal comparison, bounded to a first-letter
        // bucket of (familyName, or givenName if familyName is empty) so
        // this stays well short of a full O(n²) all-pairs pass over a large
        // address book (Document 09's "avoid O(n²)" principle, applied here
        // even though contact libraries are typically much smaller than
        // 10,000+ photo libraries). ---
        var letterBuckets: [Character: [Int]] = [:]
        for (index, contact) in contacts.enumerated() {
            let key = contact.familyName.isEmpty ? contact.givenName : contact.familyName
            let letter = key.lowercased().first ?? "#"
            letterBuckets[letter, default: []].append(index)
        }

        for bucket in letterBuckets.values where bucket.count > 1 {
            for i in 0..<bucket.count {
                for j in (i + 1)..<bucket.count {
                    let a = bucket[i], b = bucket[j]
                    let pairKey = "\(min(a, b))-\(max(a, b))"
                    if pairHadExactEdge[pairKey] == true { continue } // already an exact edge, no need to also evaluate as probable

                    let nameScore = NameSimilarity.score(contacts[a].displayName, contacts[b].displayName)
                    guard nameScore >= probableNameSimilarityThreshold else { continue }

                    // GUARD #1: name similarity alone never qualifies. A
                    // secondary signal — even a weak one — must also be
                    // present. "Weak" here means: the last-10 phone digits
                    // match but ContactNormalizer.phonesMatch itself
                    // declined to call it exact (both numbers carried an
                    // explicit, differing country code — the one case that
                    // normalizer intentionally excludes from .exact for
                    // precision, per Document 06 §6 step 4).
                    let hasWeakPhoneSignal = weakPhoneOverlap(contacts[a].normalizedPhones, contacts[b].normalizedPhones)
                    let hasWeakEmailSignal = weakEmailLocalPartOverlap(contacts[a].normalizedEmails, contacts[b].normalizedEmails)

                    guard hasWeakPhoneSignal || hasWeakEmailSignal else { continue }

                    uf.union(a, b)
                    pairHadExactEdge[pairKey] = false // explicit probable edge, not exact
                }
            }
        }

        // --- Assemble components into ContactGroups ---
        let components = uf.components(count: contacts.count).filter { $0.count > 1 }

        return components.map { indices in
            let members = indices.map { contacts[$0] }
            let isOversized = indices.count > maxTrustedGroupSize

            let hasAnyExactEdge = indices.indices.contains { i in
                indices.indices.contains { j in
                    guard i < j else { return false }
                    let key = "\(min(indices[i], indices[j]))-\(max(indices[i], indices[j]))"
                    return pairHadExactEdge[key] == true
                }
            }

            let tier: ContactDuplicateTier = (isOversized || !hasAnyExactEdge) ? .probable : .exact
            let baseConfidence: Double = tier == .exact ? 1.0 : 0.75
            let confidence = isOversized ? baseConfidence * 0.5 : baseConfidence

            let reason = matchReason(hasExactEdge: hasAnyExactEdge, isOversized: isOversized, members: members)

            let primary = members.max { $0.fieldCount == $1.fieldCount ? $0.id > $1.id : $0.fieldCount < $1.fieldCount }?.id ?? members[0].id

            return ContactGroup(
                tier: tier,
                members: members,
                matchReason: reason,
                recommendedPrimaryID: primary,
                confidence: confidence
            )
        }
    }

    // MARK: - Weak secondary signals (never used alone — see guard #1)

    private func weakPhoneOverlap(_ phonesA: [String], _ phonesB: [String]) -> Bool {
        for a in phonesA {
            for b in phonesB {
                guard let na = ContactNormalizer.normalizePhone(a), let nb = ContactNormalizer.normalizePhone(b) else { continue }
                guard na.last10.count == 10, nb.last10.count == 10 else { continue }
                if na.last10 == nb.last10 && na.fullForm != nb.fullForm {
                    return true // same national number, different/conflicting country code — weak, not exact
                }
            }
        }
        return false
    }

    private func weakEmailLocalPartOverlap(_ emailsA: [String], _ emailsB: [String]) -> Bool {
        for a in emailsA {
            for b in emailsB {
                guard a != b else { continue } // exact match handled in pass 1, not a "weak" signal
                let localA = a.split(separator: "@").first.map(String.init) ?? ""
                let localB = b.split(separator: "@").first.map(String.init) ?? ""
                if !localA.isEmpty && localA == localB {
                    return true // same username, different provider/domain
                }
            }
        }
        return false
    }

    private func matchReason(hasExactEdge: Bool, isOversized: Bool, members: [ContactCandidate]) -> String {
        if isOversized {
            return "Large group of \(members.count) — shared contact info may indicate a shared line, not duplicate people. Review carefully."
        }
        if hasExactEdge {
            return "Same phone number or email address"
        }
        return "Similar name with a related phone number or email"
    }
}
