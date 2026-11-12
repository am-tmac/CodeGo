import SwiftUI
import WidgetKit

/// Qoder personal-access-token management. Two deployments (国内 / 国际) with different openapi
/// hosts; the choice is stored per account next to the plan preferences, never in the Keychain.
struct QoderPanel: View {
    @ObservedObject var model: UsageModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    @State private var key = ""
    @State private var replacing: String?
    @State private var region: QoderRegion
    @State private var busy = false
    @State private var consent = false
    @State private var message: String?
    init(model: UsageModel, replacing: String? = nil) {
        self.model = model
        _replacing = State(initialValue: replacing)
        _region = State(initialValue: replacing.map { ProviderPreferences.qoderRegion(accountID: $0) } ?? .china)
    }
    var palette: AppPalette { .resolve(scheme) }
    func reload() {
        model.reloadAccounts()
        WidgetCenter.shared.reloadAllTimelines()
    }
    var body: some View {
        AppCard(title: "Qoder 个人访问令牌", caption: replacing == nil ? "添加独立账号" : "更新所选账号令牌（不回显旧令牌）",
                systemImage: "key.horizontal", palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("区域", selection: $region) {
                    ForEach(QoderRegion.allCases) { item in Text(item.displayName).tag(item) }
                }.pickerStyle(.segmented)
                Link("获取 Qoder 个人访问令牌", destination: URL(string: region.integrationsURL)!)
                SecureField("在 iPhone 输入 Qoder 个人访问令牌（PAT）", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    .textFieldStyle(.roundedBorder)
                Toggle("知悉同组钥匙串风险，允许保存此令牌", isOn: $consent).tint(palette.accent)
                Text("令牌仅写入本机 Keychain，不写快照或日志。购买证书的同组其他 App 可能读取令牌，service 名不是权限隔离；此操作不自动授权组件联网。")
                    .font(.caption).foregroundStyle(palette.secondary)
                Text("国内用 openapi.qoder.com.cn，国际用 openapi.qoder.sh。Qoder 的 job token 与额度接口没有公开文档，字段名按别名兼容读取；格式不符时会提示无法识别，不会推算额度。")
                    .font(.caption).foregroundStyle(palette.secondary)
                HStack(spacing: 10) {
                    Button("保存并读取用量") {
                        let entered = key
                        let replacingID = replacing
                        let selected = region
                        key = ""; busy = true; message = nil
                        Task {
                            do {
                                let id = try await QoderService.shared.install(key: entered, region: selected, replacing: replacingID)
                                if replacing == replacingID { replacing = nil; consent = false }
                                _ = try await QoderService.shared.refresh(id: id, widget: false)
                            } catch is CancellationError {
                            } catch { message = (error as? QoderError)?.localizedDescription ?? "保存或读取失败，请解锁并检查签名" }
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
