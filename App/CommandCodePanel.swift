import SwiftUI
import WidgetKit

/// CommandCode key management. Same black-card visual language as the status page; every original
/// string (including the keychain risk notice) is kept word for word.
///
/// Reads and writes through the App's single `UsageModel`, so a key added or removed here shows up
/// on 状态 at once, and a return to the foreground refreshes each account once (the model does it),
/// not once per screen.
struct CommandCodePanel: View {
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
    /// Keychain or snapshot changed: republish through the model (it also rebuilds the widget
    /// dashboard) and ask WidgetKit to redraw.
    func reload() {
        model.reloadAccounts()
        WidgetCenter.shared.reloadAllTimelines()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppCard(title: "Command Code API 用量", caption: replacing == nil ? "添加独立 API 账号" : "更新所选账号 Key（不回显旧 Key）",
                    systemImage: "key.horizontal", palette: palette) {
                VStack(alignment: .leading, spacing: 12) {
                    Link("获取 Command Code Key", destination: URL(string: "https://commandcode.ai/settings/keys")!)
                    SecureField("在 iPhone 输入 Command Code API Key", text: $key)
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
                                    let id = try await CommandCodeService.shared.install(key: entered, replacing: replacingID)
                                    if replacing == replacingID { replacing = nil; consent = false }
                                    _ = try await CommandCodeService.shared.refresh(id: id, widget: false)
                                } catch is CancellationError {
                                } catch { message = (error as? CommandCodeError)?.localizedDescription ?? "保存或读取失败，请解锁并检查签名" }
                                busy = false; reload()
                            }
                        }.buttonStyle(.borderedProminent).tint(palette.accent).disabled(!consent || key.isEmpty || busy)
                        if replacing != nil { Button("取消") { replacing = nil; key = ""; consent = false }.disabled(busy).tint(palette.secondary) }
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(palette.warning) }
                }
            }
        }
        // Foreground refresh and the widget's open-App link are handled once by ContentView; this
        // panel only has to wipe the half-typed key when the App leaves the foreground.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { key = ""; consent = false }
        }
        .onDisappear { key = ""; consent = false }
    }
}
