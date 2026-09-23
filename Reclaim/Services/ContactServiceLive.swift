//
//  ContactServiceLive.swift
//  Reclaim
//
//  Real Contacts-backed implementation. ADR-02 (Document 14): no merge
//  method exists here by design — only fetch and delete. ADR-08: this is
//  one of exactly two deletion call sites in the whole app.
//

import Foundation
import Contacts

final class ContactServiceLive: ContactServiceProtocol, @unchecked Sendable {

    private let store = CNContactStore()

    /// Minimal key set (Document 07 §5) — exactly what the app displays or
    /// compares, nothing more.
    private static let fetchKeys: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor
    ]

    func currentAuthorization() -> PermissionState {
        map(CNContactStore.authorizationStatus(for: .contacts))
    }

    func requestAuthorization() async -> PermissionState {
        await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted ? .authorized : .denied)
            }
        }
    }

    private func map(_ status: CNAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .limited: return .limited // Contacts also gained .limited in iOS 18; treated identically to .authorized here since Contacts has no partial-library concept analogous to Photos.
        @unknown default: return .denied
        }
    }

    func fetchAllContacts() async throws -> [ContactCandidate] {
        guard currentAuthorization().isUsable else {
            throw ReclaimError.permissionNotGranted(.contacts)
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [store] in
                var results: [ContactCandidate] = []
                let request = CNContactFetchRequest(keysToFetch: Self.fetchKeys)
                do {
                    try store.enumerateContacts(with: request) { contact, _ in
                        let phones = contact.phoneNumbers.map { $0.value.stringValue }
                        let emails = contact.emailAddresses.map { String($0.value) }
                        let normalizedPhones = phones.compactMap { ContactNormalizer.normalizePhone($0)?.fullForm }
                        let normalizedEmails = emails.map { ContactNormalizer.normalizeEmail($0) }

                        var fieldCount = 0
                        if !contact.givenName.isEmpty { fieldCount += 1 }
                        if !contact.familyName.isEmpty { fieldCount += 1 }
                        fieldCount += phones.count
                        fieldCount += emails.count
                        if contact.imageDataAvailable { fieldCount += 1 }

                        results.append(ContactCandidate(
                            id: contact.identifier,
                            givenName: contact.givenName,
                            familyName: contact.familyName,
                            normalizedPhones: normalizedPhones,
                            normalizedEmails: normalizedEmails,
                            fieldCount: fieldCount,
                            imageDataAvailable: contact.imageDataAvailable
                        ))
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: ReclaimError.frameworkFailure(error.localizedDescription))
                }
            }
        }
    }

    func fetchDisplayFields(forContactID id: String) async throws -> ContactDisplayFields {
        do {
            let contact = try store.unifiedContact(withIdentifier: id, keysToFetch: Self.fetchKeys)
            return ContactDisplayFields(
                givenName: contact.givenName,
                familyName: contact.familyName,
                phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue },
                emailAddresses: contact.emailAddresses.map { String($0.value) }
            )
        } catch {
            throw ReclaimError.staleSelection(id: id)
        }
    }

    func stillValidContactIDs(_ ids: Set<String>) async -> Set<String> {
        guard !ids.isEmpty else { return [] }
        var valid: Set<String> = []
        for id in ids {
            if (try? store.unifiedContact(withIdentifier: id, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) != nil {
                valid.insert(id)
            }
        }
        return valid
    }

    func deleteContacts(ids: Set<String>) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let saveRequest = CNSaveRequest()
        var confirmedIDs: Set<String> = []

        for id in ids {
            guard let mutable = try? store.unifiedContact(
                withIdentifier: id,
                keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
            ).mutableCopy() as? CNMutableContact else {
                continue // stale — omitted from confirmedIDs, reported by the use case's revalidation pass, not here
            }
            saveRequest.delete(mutable)
            confirmedIDs.insert(id)
        }

        guard !confirmedIDs.isEmpty else { return [] }

        do {
            try store.execute(saveRequest)
            return confirmedIDs
        } catch {
            throw ReclaimError.frameworkFailure(error.localizedDescription)
        }
    }
}
