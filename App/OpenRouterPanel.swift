import SwiftUI
import WidgetKit

/// OpenRouter key management: key info (limit window) plus the organisation's credit balance.
struct OpenRouterPanel: View {
    @ObservedObject var model: UsageModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    @State private var key = ""
    @State private var replacing: String?
    @State private var busy = false
    @State private var consent = false
    @State private var message: String?
    init(model: UsageModel, replacing: String? = nil) {
        self.model = model
        _replacing = State(initialValue: replacing)
    }
    var palette: AppPalette { .resolve(scheme) }
    func reload() {
        model.reloadAccounts()
        WidgetCenter.shared.reloadAllTimelines()
    }
    var body: some View {
        AppCard(title: "OpenRouter API 用量", caption: replacing == nil ? "添加独立 API 账号" : "更新所选账号 Key（不回显旧 Key）",
                systemImage: "key.horizontal", palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                Link("获取 OpenRouter Key", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                SecureField("在 iPhone 输入 OpenRouter API Key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    .textFieldStyle(.roundedBorder)
                Toggle("知悉同组钥匙串风险，允许保存此 Key", isOn: $consent).tint(palette.accent)
                Text("Key 仅写入本机 Keychain，不写快照或日志。购买证书的同组其他 App 可能读取 Key，service 名不是权限隔离；此操作不自动授权组件联网。组件沿用下方握手及独立刷新同意开关。")
                    .font(.caption).foregroundStyle(palette.secondary)
                HStack(spacing: 10) {
                    Button("保存并读取用量") {
                        let entered = key
                        let replacingID = replacing
                        key = ""; busy = true; message = nil
                        Task {
                            do {
                                let id = try await OpenRouterService.shared.install(key: entered, replacing: replacingID)
                                if replacing == replacingID { replacing = nil; consent = false }
                                _ = try await OpenRouterService.shared.refresh(id: id, widget: false)
                            } catch is CancellationError {
                            } catch { message = (error as? OpenRouterError)?.localizedDescription ?? "保存或读取失败，请解锁并检查签名" }
                            busy = false; reload()
                        }
                    }.buttonStyle(.borderedProminent).tint(palette.accent).disabled(!consent || key.isEmpty || busy)
                    if replacing != nil { Button("取消") { replacing = nil; key = ""; consent = false }.disabled(busy).tint(palette.secondary) }
                }
                if let message { Text(message).font(.caption).foregroundStyle(palette.warning) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { key = ""; consent = false }
        }
        .onDisappear { key = ""; consent = false }
    }
}
