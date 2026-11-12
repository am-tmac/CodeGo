import Foundation
import Darwin

/// Explicit user-selected deletion, separate from routine cache cleaning.
actor IncomingIPACleaner {
    struct Item: Identifiable, Sendable {
        var id: String { name }
        let name: String
        let size: Int64
        fileprivate let inode: UInt64
        fileprivate let device: Int32
        fileprivate let modifiedSeconds: Int
        fileprivate let modifiedNanos: Int
    }
    struct Result: Sendable {
        let deletedCount: Int
        let deletedBytes: Int64
        let failures: [String]
    }
    private let groupURL: URL?
    init(groupURL: URL?) { self.groupURL = groupURL }
    private func failure(_ text: String) -> NSError {
        NSError(domain: "IncomingIPACleaner", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private func directory() throws -> Int32 {
        guard let groupURL else { throw failure("当前 App Group 不可访问") }
        let root = open(groupURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw failure("无法访问共享容器") }
        defer { close(root) }
        let fd = openat(root, "Incoming", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure("Incoming 不存在、不是普通目录或没有访问权限") }
        return fd
    }
    private func metadata(_ name: String, fd: Int32) throws -> Item {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0"),
              (name as NSString).pathExtension.lowercased() == "ipa" else { throw failure("不是 Incoming 内的 IPA 文件") }
        var info = stat()
        guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
              (info.st_mode & S_IFMT) == S_IFREG else { throw failure("文件不存在、已替换或不是普通 IPA") }
        return Item(name: name, size: Int64(info.st_size), inode: UInt64(info.st_ino), device: info.st_dev,
                    modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanos: info.st_mtimespec.tv_nsec)
    }
    func list() throws -> [Item] {
        let fd = try directory()
        defer { close(fd) }
        // Enumerate the opened directory rather than re-resolving its path.
        guard let stream = fdopendir(dup(fd)) else { throw failure("无法读取 Incoming") }
        defer { closedir(stream) }
        var items: [Item] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if let item = try? metadata(name, fd: fd) { items.append(item) }
        }
        return items.sorted { $0.size == $1.size ? $0.name < $1.name : $0.size > $1.size }
    }
    func delete(_ selected: [Item]) throws -> Result {
        let fd = try directory()
        defer { close(fd) }
        var count = 0
        var bytes: Int64 = 0
        var failures: [String] = []
        var seen = Set<String>()
        for item in selected where seen.insert(item.name).inserted {
            do {
                let current = try metadata(item.name, fd: fd)
                guard current.inode == item.inode, current.device == item.device, current.size == item.size,
                      current.modifiedSeconds == item.modifiedSeconds, current.modifiedNanos == item.modifiedNanos
                else { throw failure("文件已变化，请重新扫描并确认") }
                // unlinkat never follows a last-component symlink or recursively deletes directories.
                guard unlinkat(fd, item.name, 0) == 0 else { throw failure("删除失败，可能没有权限") }
                var remaining = stat()
                guard fstatat(fd, item.name, &remaining, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT
                else { throw failure("路径仍存在或已重新生成，请重新扫描") }
                count += 1; bytes += item.size
            } catch { failures.append(item.name + "：" + error.localizedDescription) }
        }
        return Result(deletedCount: count, deletedBytes: bytes, failures: failures)
    }
}
