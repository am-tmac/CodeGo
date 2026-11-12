import SwiftUI

struct StorageDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: StorageDiagnosticsScanner.Report?
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("仅读取目录、文件名和大小，不读取文件内容，也不删除数据。文件名可能包含账号标识，分享前请检查。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if scanning { ProgressView("正在扫描存储空间…") }
                    Button(report == nil ? "开始扫描" : "重新扫描") { Task { await scan() } }
                        .disabled(scanning).accessibilityIdentifier("scanStorage")
                }
                Section {
                    NavigationLink("选择清理 Incoming 中的 IPA") { IncomingIPACleanupView() }
                    Text("独立于只读诊断；只在你勾选并二次确认后删除所选安装包。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let report {
                    Section("可访问范围合计") {
                        row("文件大小", report.logicalBytes)
                        row("已分配空间", report.allocatedBytes)
                        Text("\(report.fileCount) 个文件 · \(report.errorCount) 项不可访问/读取失败")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("不等于 iOS 文稿与数据总量。分配空间可能受压缩及共享块影响；子目录已计入父目录，不要重复相加。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("目录占用") {
                        ForEach(report.roots) { item in itemRow(item) }
                        ForEach(report.directories) { item in itemRow(item) }
                    }
                    Section("最大文件 · 最多 20 项") {
                        ForEach(report.files) { item in itemRow(item) }
                    }
                    Section {
                        ShareLink(item: report.text) { Label("分享诊断文本", systemImage: "square.and.arrow.up") }
                        Text("未扫描安装包、其他扩展的私有目录和系统管理的 WidgetKit 数据。扫描只反映当前可访问范围，不代表已定位全部占用。文件名不代表可安全删除。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("存储占用明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { if report == nil { await scan() } }
        }
    }
    private func row(_ label: String, _ bytes: Int64) -> some View {
        HStack { Text(label); Spacer(); Text(StorageDiagnosticsScanner.Report.format(bytes)).monospacedDigit() }
    }
    private func itemRow(_ item: StorageDiagnosticsScanner.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.path).font(.caption.monospaced()).textSelection(.enabled)
            Text(item.unavailable ? "不可访问，未计入合计" : "文件 \(StorageDiagnosticsScanner.Report.format(item.logicalBytes)) · 分配 \(StorageDiagnosticsScanner.Report.format(item.allocatedBytes))")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding(.vertical, 2)
    }
    private func scan() async {
        guard !scanning else { return }
        scanning = true
        report = await StorageDiagnosticsScanner.scan(roots: SharedStorage.storageDiagnosticsRoots)
        scanning = false
    }
}
