import SwiftUI

struct IncomingIPACleanupView: View {
    @State private var items: [IncomingIPACleaner.Item] = []
    @State private var selected = Set<String>()
    @State private var pending: [IncomingIPACleaner.Item] = []
    @State private var busy = false
    @State private var confirming = false
    @State private var message: String?
    @State private var tasksStopped = false
    private var chosen: [IncomingIPACleaner.Item] { items.filter { selected.contains($0.id) } }
    private func size(_ value: Int64) -> String { StorageDiagnosticsScanner.Report.format(value) }

    var body: some View {
        List {
            Section {
                Text("仅列出当前 App Group/Incoming 直属的全部普通 IPA 文件，默认不选中。这里可能是全能签等 App 共用的目录，不是普通缓存。")
                Text("请先停止全能签的导入、签名和安装任务。删除不可撤销；不会卸载已安装 App，但重新签名或重装可能需要重新导入原包。唯一备份请先转存。")
                    .foregroundStyle(.orange)
                Toggle("已停止相关任务，并确认原包不再需要", isOn: $tasksStopped)
                Button("重新读取 IPA 列表") { Task { await load() } }.disabled(busy)
                if busy { ProgressView() }
                if let message { Text(message).font(.footnote).textSelection(.enabled) }
            }
            Section("Incoming · \(items.count) 个 IPA") {
                if items.isEmpty && !busy { Text("没有可列出的普通 IPA 文件").foregroundStyle(.secondary) }
                ForEach(items) { item in
                    Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { value in
                        if value { selected.insert(item.id) } else { selected.remove(item.id) }
                    })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.callout).lineLimit(nil)
                            Text(size(item.size)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(busy)
                }
            }
            Section {
                Text("已选 \(chosen.count) 个 · 文件大小 \(size(chosen.reduce(0) { $0 + $1.size }))")
                Button("删除所选 IPA…", role: .destructive) {
                    pending = chosen
                    confirming = true
                }.disabled(busy || chosen.isEmpty || !tasksStopped)
                Text("只删除你勾选的 IPA，不删除其他文件、共享设置、账号和用量历史。显示的文件大小不保证等于手机实际释放空间。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("清理 Incoming 安装包")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("永久删除 \(pending.count) 个 IPA？", isPresented: $confirming) {
            Button("取消", role: .cancel) { pending = [] }
            Button("永久删除", role: .destructive) { Task { await remove() } }
        } message: {
            Text(pending.map { $0.name + " · " + size($0.size) }.joined(separator: "\n") + "\n\n删除不可撤销。不会卸载 App，但原包将不能用于重新签名或安装。")
        }
    }
    private func load() async {
        guard !busy else { return }
        busy = true
        selected = []
        do { items = try await SharedStorage.incomingIPACleaner.list() }
        catch { items = []; message = error.localizedDescription }
        busy = false
    }
    private func remove() async {
        guard !busy, tasksStopped else { return }
        busy = true
        let manager = SharedStorage.incomingIPACleaner
        do {
            let result = try await manager.delete(pending)
            message = "已删除 \(result.deletedCount) 个 IPA（文件大小 \(size(result.deletedBytes))）。" + (result.failures.isEmpty ? "请重新扫描存储占用。" : "\n未完成：\n" + result.failures.joined(separator: "\n"))
        } catch { message = "未完成删除：" + error.localizedDescription }
        pending = []; selected = []
        do { items = try await manager.list() }
        catch { items = []; message = (message ?? "") + "\n重新读取失败：" + error.localizedDescription }
        busy = false
    }
}
