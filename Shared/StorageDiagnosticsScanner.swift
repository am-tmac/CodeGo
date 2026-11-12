import Foundation

/// Read-only metadata scan. Never opens file contents, follows symlinks, or changes files.
enum StorageDiagnosticsScanner {
    struct Root: Sendable { let name: String; let url: URL? }
    struct Item: Sendable, Identifiable {
        var id: String { path }
        let path: String
        let logicalBytes: Int64
        let allocatedBytes: Int64
        let unavailable: Bool
    }
    struct Report: Sendable {
        let roots: [Item]
        let directories: [Item]
        let files: [Item]
        let fileCount: Int
        let errorCount: Int
        var logicalBytes: Int64 { roots.reduce(0) { $0 + $1.logicalBytes } }
        var allocatedBytes: Int64 { roots.reduce(0) { $0 + $1.allocatedBytes } }
        static func format(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
        var text: String {
            func line(_ item: Item) -> String {
                item.path + (item.unavailable ? "：不可访问" : "：文件 " + Self.format(item.logicalBytes) + " / 分配 " + Self.format(item.allocatedBytes))
            }
            return (["存储诊断（只读）", "可访问范围合计：文件 \(Self.format(logicalBytes)) / 分配 \(Self.format(allocatedBytes))", "文件 \(fileCount) 个；读取失败/不可访问 \(errorCount) 项", "目录明细（子项已包含在父项中，不要重复相加）"] + roots.map(line) + directories.map(line) + ["最大文件（最多 20 项）"] + files.map(line) + ["仅扫描当前 App 数据容器及当前 App Group；不含安装包、其他扩展私有容器或系统管理的 WidgetKit 数据。分配大小可能因压缩、共享块而不等于独占物理空间。扫描期间文件可能变化。文件名可能含账号标识，分享前请检查；未读取文件内容。文件名不代表可安全删除。"]).joined(separator: "\n")
        }
    }

    static func scan(roots: [Root]) async -> Report {
        await Task.detached(priority: .utility) { collect(roots) }.value
    }
    private static func collect(_ roots: [Root]) -> Report {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        var directories: [Item] = []
        var files: [Item] = []
        var count = 0
        var errors = 0
        func walk(_ url: URL, path: String, depth: Int) -> Item {
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { return Item(path: path, logicalBytes: 0, allocatedBytes: 0, unavailable: false) }
                if values.isDirectory == true {
                    let children = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys))
                    var logical: Int64 = 0
                    var allocated: Int64 = 0
                    for child in children {
                        let item = walk(child, path: path + "/" + child.lastPathComponent, depth: depth + 1)
                        logical += item.logicalBytes; allocated += item.allocatedBytes
                    }
                    let item = Item(path: path, logicalBytes: logical, allocatedBytes: allocated, unavailable: false)
                    if depth == 1 || depth == 2 { directories.append(item) }
                    return item
                }
                guard values.isRegularFile == true else { return Item(path: path, logicalBytes: 0, allocatedBytes: 0, unavailable: false) }
                count += 1
                let item = Item(path: path, logicalBytes: Int64(values.fileSize ?? 0), allocatedBytes: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0), unavailable: false)
                files.append(item)
                files.sort { $0.logicalBytes == $1.logicalBytes ? $0.path < $1.path : $0.logicalBytes > $1.logicalBytes }
                if files.count > 20 { files.removeLast() }
                return item
            } catch {
                errors += 1
                return Item(path: path, logicalBytes: 0, allocatedBytes: 0, unavailable: true)
            }
        }
        let totals = roots.map { root -> Item in
            guard let url = root.url else {
                errors += 1
                return Item(path: root.name, logicalBytes: 0, allocatedBytes: 0, unavailable: true)
            }
            return walk(url, path: root.name, depth: 0)
        }
        directories.sort { $0.path < $1.path }
        return Report(roots: totals, directories: directories, files: files, fileCount: count, errorCount: errors)
    }
}
