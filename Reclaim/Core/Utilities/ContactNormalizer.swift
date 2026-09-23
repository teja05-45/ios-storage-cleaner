//
//  ContactNormalizer.swift
//  Reclaim
//
//  Document 06 §6. Pure Foundation, no Contacts import — takes raw strings
//  in, returns comparison keys out.
//
//  KNOWN, DISCLOSED LIMITATION (Document 06 §6, Document 04 ADR-02, README):
//  phone normalization here is a pragmatic last-10-digit-suffix heuristic,
//  not full ITU E.164 parsing. A production system would use a library like
//  libphonenumber for correct region/country-code disambiguation. This is a
//  documented, deliberate tradeoff, not a silent assumption of correctness.
//

import Foundation

enum ContactNormalizer {

    // MARK: - Phone

    struct NormalizedPhone: Equatable {
        /// Fully stripped form, digits only, with a leading "+" preserved
        /// if the original had a country code.
        let fullForm: String
        /// Last 10 digits of `fullForm` — the "national significant number"
        /// approximation used for suffix matching (Document 06 §6).
        let last10: String
        /// Whether `fullForm` carried an explicit leading "+" country code.
        let hasCountryCode: Bool
    }

    /// Strips all non-digit characters except a leading "+", per
    /// Document 06 §6 steps 1-2.
    static func normalizePhone(_ raw: String) -> NormalizedPhone? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hasLeadingPlus = trimmed.hasPrefix("+")
        let digitsOnly = trimmed.filter(\.isNumber)
        guard !digitsOnly.isEmpty else { return nil }

        let fullForm = hasLeadingPlus ? "+" + digitsOnly : digitsOnly
        let last10 = String(digitsOnly.suffix(10))
        guard last10.count == 10 else {
            // Too short to be a real phone number for matching purposes —
            // still return a value (full-form-only matching still applies)
            // but last10 comparisons should not fire on short strings.
            return NormalizedPhone(fullForm: fullForm, last10: digitsOnly, hasCountryCode: hasLeadingPlus)
        }
        return NormalizedPhone(fullForm: fullForm, last10: last10, hasCountryCode: hasLeadingPlus)
    }

    /// Two phone numbers match if either their full normalized forms match,
    /// or their last-10-digit suffixes match AND at least one of the two
    /// numbers lacked a country code — so two genuinely different
    /// international numbers that happen to share a local suffix are not
    /// accidentally equated (Document 06 §6 step 4, a deliberate
    /// precision-over-recall choice).
    static func phonesMatch(_ a: String, _ b: String) -> Bool {
        guard let na = normalizePhone(a), let nb = normalizePhone(b) else { return false }

        if na.fullForm == nb.fullForm { return true }

        guard na.last10.count == 10, nb.last10.count == 10 else { return false }
        guard na.last10 == nb.last10 else { return false }
        return !na.hasCountryCode || !nb.hasCountryCode
    }

    // MARK: - Email

    /// Lowercases and trims. `stripGmailPlusTag` defaults to false — the
    /// "+tag" stripping refinement is documented as off-by-default to avoid
    /// false-positive merges for users who intentionally use tagged
    /// addresses for different purposes (Document 06 §6 step 3).
    static func normalizeEmail(_ raw: String, stripGmailPlusTag: Bool = false) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard stripGmailPlusTag, let atIndex = trimmed.firstIndex(of: "@") else { return trimmed }

        let localPart = trimmed[trimmed.startIndex..<atIndex]
        guard let plusIndex = localPart.firstIndex(of: "+") else { return trimmed }

        let domainPart = trimmed[atIndex...]
        trimmed = String(localPart[localPart.startIndex..<plusIndex]) + String(domainPart)
        return trimmed
    }

    static func emailsMatch(_ a: String, _ b: String, stripGmailPlusTag: Bool = false) -> Bool {
        normalizeEmail(a, stripGmailPlusTag: stripGmailPlusTag)
            == normalizeEmail(b, stripGmailPlusTag: stripGmailPlusTag)
    }
}
