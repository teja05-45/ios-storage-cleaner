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
    /// Monotonic token incremented on every startScan. Progress hops arrive
    /// as unstructured Tasks, so a hop from a superseded scan can be
    /// dispatched after the current scan's terminal status; the epoch check
    /// in the progress closure drops those stragglers.
    private var scanEpoch = 0
    /// Retained so the foreground re-entry observation lives as long as the
    /// ViewModel does. Without this reference the token is deallocated
    /// immediately and the observer silently never fires (a leak-free but
    /// equally silent observer is worse: permissions would appear to "stick"
    /// across a Settings round-trip).
    // deinit is nonisolated under Swift concurrency rules and cannot touch
    // MainActor-isolated state; the token is only read here to deregister.
    nonisolated(unsafe) private var foregroundObserver: NSObjectProtocol?

    var hasScannedOnce: Bool {
        environment.reviewStore.lastScanDate != nil
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        refreshPermissions()
        refreshStorage()

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: .reclaimDidBecomeActive, object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                // Document 07 §8: re-check on every foreground re-entry —
                // a permission revoked in Settings while backgrounded must
                // be reflected immediately, not on next cold launch.
                self?.refreshPermissions()
                self?.refreshStorage()
            }
        }
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
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
        // Synchronous entry: the UI enters the scanning state immediately,
        // and the single-start guard can never be raced by Task scheduling.
        scanStatus = .scanning(phase: "Preparing", completed: 0, total: 0)
        scanEpoch += 1
        let epoch = scanEpoch
        scanTask = Task {
            Log.scanStarted(category: .similarPhotos)
            let started = Date()
            var photoScanCancelled = false
            do {
                if photosPermission.isUsable {
                    let result = try await environment.scanPhotoLibraryUseCase().execute { status in
                        Task { @MainActor [weak self] in
                            guard let self, epoch == self.scanEpoch else { return }
                            // Callback statuses only advance an IN-FLIGHT
                            // scan. Terminal transitions (.completed,
                            // .cancelled, .failed) are owned by this scan
                            // body below, so a queued hop can never overwrite
                            // them after the fact.
                            guard self.scanStatus.isScanning else { return }
                            self.scanStatus = status
                        }
                    }
                    environment.reviewStore.loadPhotoResults(
                        exactDuplicates: result.exactDuplicateGroups,
                        similar: result.similarPhotoGroups,
                        scannedWithLimitedAccess: result.scannedWithLimitedAccess
                    )
                    environment.reviewStore.loadScreenshots(result.screenshots)
                    environment.reviewStore.loadVideos(result.videos)
                    photoScanCancelled = {
                        if case .cancelled = result.status { return true }
                        return false
                    }()
                }
                // Do not START new scan work after the user cancelled the
                // photo scan — partial results stand, and the terminal
                // status below is .cancelled.
                if contactsPermission.isUsable, !photoScanCancelled {
                    let contactGroups = try await environment.scanContactsUseCase().execute()
                    environment.reviewStore.loadContactGroups(contactGroups)
                }
                // One authoritative terminal transition after all scan work:
                // .cancelled when the photo pipeline reported cancellation
                // (it RETURNS rather than throws, so partial results
                // survive), .completed otherwise — deterministic on every
                // path, including contacts-only scans.
                scanStatus = photoScanCancelled ? .cancelled : .completed
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
