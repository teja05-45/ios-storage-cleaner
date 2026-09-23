//
//  DashboardViewModel.swift
//  Reclaim
//
//  Document 01 §3.1, §3.7. Owns: current permission states (re-checked on
//  foreground, never assumed), storage summary (real device numbers,
//  honest pre-scan state), and scan orchestration. Never pre-selects
//  anything or shows a fabricated number before a real scan has run.
//

import Foundation
import Observation

@Observable
@MainActor
final class DashboardViewModel {
    private let environment: AppEnvironment

    private(set) var photosPermission: PermissionState = .notDetermined
    private(set) var contactsPermission: PermissionState = .notDetermined

    private(set) var storageSummary: StorageSummary?
    private(set) var scanStatus: ScanStatus = .notStarted
    private(set) var lastError: ReclaimError?

    private var scanTask: Task<Void, Never>?

    var hasScannedOnce: Bool {
        environment.reviewStore.lastScanDate != nil
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        refreshPermissions()
        refreshStorage()

        NotificationCenter.default.addObserver(
            forName: .reclaimDidBecomeActive, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Document 07 §8: re-check on every foreground re-entry —
                // a permission revoked in Settings while backgrounded must
                // be reflected immediately, not on next cold launch.
                self?.refreshPermissions()
                self?.refreshStorage()
            }
        }
    }

    func refreshPermissions() {
        photosPermission = environment.photoLibrary.currentAuthorization()
        contactsPermission = environment.contactService.currentAuthorization()
        Log.permissionStateChanged(domain: .photos, isUsable: photosPermission.isUsable)
        Log.permissionStateChanged(domain: .contacts, isUsable: contactsPermission.isUsable)
    }

    func refreshStorage() {
        storageSummary = environment.computeStorageSummaryUseCase().execute(
            recoverableBytes: environment.reviewStore.estimatedRecoverableBytes,
            recoverableByCategory: environment.reviewStore.recoverableBytesByCategory,
            lastScanDate: environment.reviewStore.lastScanDate
        )
    }

    func requestPhotosAccess() async {
        photosPermission = await environment.photoLibrary.requestAuthorization()
    }

    func requestContactsAccess() async {
        contactsPermission = await environment.contactService.requestAuthorization()
    }

    func presentLimitedLibraryPicker() async {
        await environment.photoLibrary.presentLimitedLibraryPicker()
        refreshPermissions()
    }

    func startScan() {
        guard !scanStatus.isScanning else { return }
        lastError = nil
        scanTask = Task {
            Log.scanStarted(category: .similarPhotos)
            let started = Date()
            do {
                if photosPermission.isUsable {
                    let result = try await environment.scanPhotoLibraryUseCase().execute { [weak self] status in
                        Task { @MainActor in self?.scanStatus = status }
                    }
                    environment.reviewStore.loadPhotoResults(
                        exactDuplicates: result.exactDuplicateGroups,
                        similar: result.similarPhotoGroups,
                        scannedWithLimitedAccess: result.scannedWithLimitedAccess
                    )
                    environment.reviewStore.loadScreenshots(result.screenshots)
                    environment.reviewStore.loadVideos(result.videos)
                }
                if contactsPermission.isUsable {
                    let contactGroups = try await environment.scanContactsUseCase().execute()
                    environment.reviewStore.loadContactGroups(contactGroups)
                }
                refreshStorage()
                let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
                Log.scanCompleted(category: .similarPhotos, itemCount: environment.reviewStore.similarPhotoGroups.count, durationMs: elapsedMs)
            } catch is CancellationError {
                scanStatus = .cancelled
            } catch let error as ReclaimError {
                lastError = error
                scanStatus = .failed("Scan failed")
                Log.scanFailed(category: .similarPhotos)
            } catch {
                lastError = .frameworkFailure("\(error)")
                scanStatus = .failed("Scan failed")
                Log.scanFailed(category: .similarPhotos)
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    var reviewStore: ReviewStore { environment.reviewStore }
    var appEnvironment: AppEnvironment { environment }
}
