//
//  ScanCache.swift
//  Reclaim
//
//  ADR-07 (Document 14), Document 04 ADR-04, Document 07 §4. Persists only
//  derived data (hashes, sizes, timestamps, schema version) as JSON under
//  Application Support. PhotoKit/Contacts remain the source of truth —
//  this cache is NEVER treated as proof that an asset still exists (that's
//  exactly what ADR-05's revalidation step guards against). Contacts are
//  never cached across launches (ADR-07).
//

import Foundation

protocol ScanCacheProtocol: Sendable {
    func load() -> ScanResult?
    func save(_ result: ScanResult)
    func clear()
}

final class ScanCacheLive: ScanCacheProtocol, @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.reclaim.scancache", qos: .utility)

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = appSupport.appendingPathComponent("Reclaim", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("scan-cache.json")
    }

    func load() -> ScanResult? {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            guard let result = try? JSONDecoder().decode(ScanResult.self, from: data) else { return nil }
            // Schema-version guard: a cache written by an older hashing/
            // threshold implementation is never mixed with current
            // semantics — force a full rescan instead (ADR-07).
            guard result.cacheSchemaVersion == ScanResult.currentSchemaVersion else { return nil }
            return result
        }
    }

    func save(_ result: ScanResult) {
        queue.async {
            guard let data = try? JSONEncoder().encode(result) else { return }
            try? data.write(to: self.fileURL, options: .atomic)
        }
    }

    func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }
}
