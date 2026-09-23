//
//  ScanContactsUseCase.swift
//  Reclaim
//

import Foundation

struct ScanContactsUseCase {
    let contactService: ContactServiceProtocol
    let duplicateContactDetector: DuplicateContactDetectorProtocol

    func execute() async throws -> [ContactGroup] {
        guard contactService.currentAuthorization().isUsable else {
            throw ReclaimError.permissionNotGranted(.contacts)
        }
        let contacts = try await contactService.fetchAllContacts()
        return duplicateContactDetector.detectDuplicateGroups(in: contacts)
    }
}
