import XCTest
@testable import CodeGo

final class CacheMaintenanceTests: XCTestCase {
    func testClearRemovesCachesAndOldTemporaryFilesButPreservesUserDataAndActiveFiles() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let caches = root.appendingPathComponent("Library/Caches")
        let temporary = root.appendingPathComponent("tmp")
        let documents = root.appendingPathComponent("Documents")
        for directory in [caches, temporary, documents] { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        let payload = Data(repeating: 1, count: 4096)
        try payload.write(to: caches.appendingPathComponent("response"))
        let old = temporary.appendingPathComponent("old-download")
        try payload.write(to: old)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -172800)], ofItemAtPath: old.path)
        let active = temporary.appendingPathComponent("active-download")
        try payload.write(to: active)
        let account = documents.appendingPathComponent("accounts.json")
        try payload.write(to: account)
        // A cache symlink must never cause traversal/deletion outside the cache root.
        try fm.createSymbolicLink(at: caches.appendingPathComponent("external"), withDestinationURL: documents)
        let manager = CacheMaintenance(cacheDirectory: caches, temporaryDirectory: temporary)
        let before = try await manager.size()
        XCTAssertGreaterThanOrEqual(before, 8192)
        let result = try await manager.clear()
        XCTAssertEqual(result.failedItems, 0)
        XCTAssertEqual(result.remainingBytes, 0)
        XCTAssertGreaterThan(result.freedBytes, 0)
        XCTAssertTrue(fm.fileExists(atPath: caches.path))
        XCTAssertFalse(fm.fileExists(atPath: old.path))
        XCTAssertEqual(try Data(contentsOf: active), payload)
        XCTAssertEqual(try Data(contentsOf: account), payload)
        let repeated = try await manager.clear()
        XCTAssertEqual(repeated.freedBytes, 0)
    }

    func testDiagnosticsIncludesHiddenRecentAndSharedFilesWithoutFollowingLinks() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("app")
        let group = root.appendingPathComponent("group")
        let documents = app.appendingPathComponent("Documents")
        let temp = app.appendingPathComponent("tmp")
        for directory in [documents, temp, group] { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        let payload = Data(repeating: 7, count: 8192)
        try payload.write(to: documents.appendingPathComponent(".hidden"))
        try payload.write(to: temp.appendingPathComponent("recent"))
        try payload.write(to: group.appendingPathComponent("snapshot"))
        try fm.createSymbolicLink(at: group.appendingPathComponent("link"), withDestinationURL: app)
        let report = await StorageDiagnosticsScanner.scan(roots: [
            .init(name: "App", url: app), .init(name: "共享", url: group),
            .init(name: "不可访问", url: nil)
        ])
        XCTAssertEqual(report.logicalBytes, 24576)
        XCTAssertEqual(report.fileCount, 3)
        XCTAssertEqual(report.roots.count, 3)
        XCTAssertEqual(report.roots.last?.unavailable, true)
        XCTAssertEqual(report.files.count, 3)
        XCTAssertTrue(report.directories.contains { $0.path == "App/Documents" && $0.logicalBytes == 8192 })
        XCTAssertTrue(report.files.contains { $0.path == "App/Documents/.hidden" })
        XCTAssertFalse(report.text.contains(root.path))
        XCTAssertEqual(try Data(contentsOf: temp.appendingPathComponent("recent")), payload)
        XCTAssertEqual(try Data(contentsOf: group.appendingPathComponent("snapshot")), payload)
    }

    func testDiagnosticsMissingRootIsReportedNotSilentZero() async {
        let report = await StorageDiagnosticsScanner.scan(roots: [.init(name: "missing", url: URL(fileURLWithPath: "/nonexistent-" + UUID().uuidString))])
        XCTAssertEqual(report.roots.first?.unavailable, true)
        XCTAssertGreaterThan(report.errorCount, 0)
    }

    func testIncomingDeletesOnlySelectedUnchangedRegularIPA() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let incoming = root.appendingPathComponent("Incoming")
        try fm.createDirectory(at: incoming, withIntermediateDirectories: true)
        for name in ["a.ipa", "b.IPA", "settings.json"] { try Data("original".utf8).write(to: incoming.appendingPathComponent(name)) }
        try fm.createDirectory(at: incoming.appendingPathComponent("folder.ipa"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: incoming.appendingPathComponent("link.ipa"), withDestinationURL: incoming.appendingPathComponent("settings.json"))
        let manager = IncomingIPACleaner(groupURL: root)
        let items = try await manager.list()
        XCTAssertEqual(Set(items.map(\.name)), ["a.ipa", "b.IPA"])
        let selected = try XCTUnwrap(items.first { $0.name == "a.ipa" })
        let result = try await manager.delete([selected])
        XCTAssertEqual(result.deletedCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: incoming.appendingPathComponent("a.ipa").path))
        XCTAssertTrue(fm.fileExists(atPath: incoming.appendingPathComponent("b.IPA").path))
        XCTAssertEqual(try String(contentsOf: incoming.appendingPathComponent("settings.json")), "original")
        let remaining = try await manager.list()
        XCTAssertEqual(remaining.count, 1)
        try Data("changed-size".utf8).write(to: incoming.appendingPathComponent("b.IPA"))
        let changed = try await manager.delete(remaining)
        XCTAssertEqual(changed.deletedCount, 0)
        XCTAssertEqual(changed.failures.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: incoming.appendingPathComponent("b.IPA").path))
    }

    func testIncomingRejectsSymlinkDirectoryAndReplacedFile() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let incoming = root.appendingPathComponent("Incoming")
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: incoming, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let file = incoming.appendingPathComponent("a.ipa")
        try Data("keep".utf8).write(to: file)
        let manager = IncomingIPACleaner(groupURL: root)
        let items = try await manager.list()
        try fm.removeItem(at: file)
        try fm.createSymbolicLink(at: file, withDestinationURL: outside)
        let result = try await manager.delete(items)
        XCTAssertEqual(result.deletedCount, 0)
        XCTAssertEqual(result.failures.count, 1)
        try fm.removeItem(at: incoming)
        try fm.createSymbolicLink(at: incoming, withDestinationURL: outside)
        do { _ = try await manager.list(); XCTFail("Symlink Incoming must be rejected") } catch {}
        XCTAssertTrue(fm.fileExists(atPath: outside.path))
    }

    func testMissingDirectoriesAreEmpty() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = CacheMaintenance(cacheDirectory: root.appendingPathComponent("caches"), temporaryDirectory: root.appendingPathComponent("tmp"))
        let size = try await manager.size()
        XCTAssertEqual(size, 0)
        let result = try await manager.clear()
        XCTAssertEqual(result.remainingBytes, 0)
    }
}
