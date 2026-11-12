import Foundation

/// Only disposable app caches and temporary items older than 24 hours.
/// Never touches Application Support, Documents, shared snapshots, cookies or Keychain.
actor CacheMaintenance {
    static let shared = CacheMaintenance()
    struct Result: Sendable {
        let freedBytes: Int64
        let remainingBytes: Int64
        let failedItems: Int
    }
    private let cacheDirectory: URL
    private let temporaryDirectory: URL
    private let fm = FileManager.default

    init(cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
         temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.cacheDirectory = cacheDirectory
        self.temporaryDirectory = temporaryDirectory
    }

    private func children(_ directory: URL) throws -> [URL] {
        guard fm.fileExists(atPath: directory.path) else { return [] }
        return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey])
    }

    private func bytes(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey, .fileAllocatedSizeKey])
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory == true {
            return try children(url).reduce(0) { try $0 + bytes($1) }
        }
        return Int64(max(values.fileSize ?? 0, values.fileAllocatedSize ?? 0))
    }

    private func candidates() throws -> [URL] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        // A directory is eligible only if all descendants are old. Never remove an active
        // download just because its parent directory was created more than a day ago.
        func isOld(_ url: URL) throws -> Bool {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey])
            guard let modified = values.contentModificationDate, modified < cutoff else { return false }
            if values.isSymbolicLink == true { return true }
            if values.isDirectory == true { return try children(url).allSatisfy { try isOld($0) } }
            return true
        }
        return try children(cacheDirectory) + children(temporaryDirectory).filter { try isOld($0) }
    }

    func size() throws -> Int64 {
        try candidates().reduce(0) { try $0 + bytes($1) }
    }

    func clear() throws -> Result {
        let items = try candidates()
        let before = try items.reduce(Int64(0)) { try $0 + bytes($1) }
        URLCache.shared.removeAllCachedResponses()
        var failed = 0
        for item in items {
            do { try fm.removeItem(at: item) }
            catch { failed += 1 }
        }
        let remaining = try size()
        return Result(freedBytes: max(0, before - remaining), remainingBytes: remaining, failedItems: failed)
    }
}
