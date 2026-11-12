import SwiftUI

struct CacheSettingsCard: View {
    let palette: AppPalette
    @Environment(\.scenePhase) private var scenePhase
    @State private var size: Int64?
    @State private var busy = false
    @State private var confirming = false
    @State private var message: String?
    @State private var showDiagnostics = false

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    var body: some View {
        AppCard(title: "存储空间", caption: "仅清理可重新生成的缓存", systemImage: "internaldrive", palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("可清理缓存").foregroundStyle(palette.primary)
                    Spacer()
                    Text(size.map(formatted) ?? "正在计算…")
                        .foregroundStyle(palette.secondary)
                        .accessibilityIdentifier("cacheSize")
                }
                Text("保留账号、登录状态、设置、用量快照与历史。仅删除 App 缓存及超过 24 小时未修改的临时文件；不清除网页登录数据。此数值不等于 iOS 的「文稿与数据」总量。")
                    .font(.footnote).foregroundStyle(palette.secondary)
                Button {
                    confirming = true
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text(busy ? "正在清理…" : "清理缓存")
                    }.frame(minHeight: 44)
                }
                .disabled(busy || size == nil || size == 0)
                .accessibilityIdentifier("clearCache")
                Divider()
                Button("查看存储占用明细") { showDiagnostics = true }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("storageDiagnostics")
                Text("只读扫描全部 App 数据目录和当前共享容器，帮助定位大文件；不读取内容、不删除文件。")
                    .font(.footnote).foregroundStyle(palette.secondary)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(palette.secondary)
                        .accessibilityIdentifier("cacheResult")
                }
            }
        }
        .confirmationDialog("清理缓存？", isPresented: $confirming, titleVisibility: .visible) {
            Button("清理缓存", role: .destructive) {
                busy = true
                Task {
                    do {
                        let result = try await CacheMaintenance.shared.clear()
                        size = result.remainingBytes
                        message = "已释放 \(formatted(result.freedBytes))" + (result.failedItems > 0 ? "；\(result.failedItems) 项未能清理，可稍后重试。" : "，账号及设置已保留。")
                    } catch { message = "清理未完成：" + error.localizedDescription }
                    busy = false
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅删除可重新生成的缓存和过期临时文件，不退出账号，不删除用量历史。")
        }
        .sheet(isPresented: $showDiagnostics) { StorageDiagnosticsView() }
        .task { await measure() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !busy { Task { await measure() } }
        }
    }
    private func measure() async {
        do { size = try await CacheMaintenance.shared.size() }
        catch { message = "无法计算缓存：" + error.localizedDescription }
    }
}
