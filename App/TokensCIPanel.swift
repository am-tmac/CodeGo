import SwiftUI
import WidgetKit

/// Usage lives only on 用量. Profile snapshots and refresh errors belong to UsageModel.
struct TokensCIPanel: View {
    @ObservedObject var model: UsageModel
    let onConnect: () -> Void
    @Environment(\.colorScheme) private var scheme
    var palette: AppPalette { .resolve(scheme) }
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(model.tokensCIIDs, id: \.self) { name in
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let value = model.tokensCISnapshots[name] {
                            TokensCIAnalyticsView(value: value)
                        } else {
                            Text("暂无数据 · 请刷新以验证读取权限")
                                .font(.subheadline).foregroundStyle(palette.secondary)
                        }
                        if let error = model.refreshErrors[.tokensCI(name)] {
                            Text(error + (model.tokensCISnapshots[name] == nil ? " · 暂无缓存" : " · 保留上次数据"))
                                .font(.caption).foregroundStyle(palette.warning)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("tokensciError-" + name)
                        }
                        HStack(spacing: 16) {
                            Button("刷新") { Task { await model.refresh(target: .tokensCI(name)) } }
                            Button("移除", role: .destructive) {
                                Task {
                                    do {
                                        try await TokensCIService.shared.remove(name)
                                        model.reloadAccounts()
                                        WidgetCenter.shared.reloadAllTimelines()
                                    } catch { message = "移除失败，请解锁后重试" }
                                }
                            }
                        }.buttonStyle(.bordered).disabled(model.busy)
                    }
                }
            }
            if model.tokensCIIDs.isEmpty {
                AppCard(title: "尚未连接 tokens.ci", caption: "连接账号后查看电脑上报的实际用量", systemImage: "chart.bar.xaxis", palette: palette) {
                    Button("连接 tokens.ci", action: onConnect)
                        .buttonStyle(.borderedProminent).tint(palette.accent)
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(palette.warning) }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(palette.primary)
            Text(label).font(.caption).foregroundStyle(palette.secondary)
        }
    }
}

/// Credential entry exists only for the lifetime of this routed sheet.
struct TokensCIConnectSheet: View {
    @ObservedObject var model: UsageModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var token = ""
    @State private var consent = false
    @State private var saving = false
    @State private var message: String?
    var palette: AppPalette { .resolve(scheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                AppCard(title: "连接 tokens.ci", caption: "用户名 + read token", systemImage: "key.horizontal", palette: palette) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("GitHub 用户名或 tokens.ci 主页链接", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    SecureField("tkr_ 开头的 read token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().textFieldStyle(.roundedBorder)
                    Toggle("知悉同组钥匙串风险，允许保存此 token", isOn: $consent).tint(palette.accent)
                    Text("read token 只写本机 Keychain，不进快照、日志或共享容器；它只能读取用量，不能上报。购买证书的同组其他 App 可能读取它。小组件只读取缓存，打开 App 更新。")
                        .font(.caption).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(saving ? "正在读取…" : "保存并读取") {
                        let enteredName = username, enteredToken = token
                        token = ""; saving = true; message = nil
                        Task {
                            do {
                                let name = try await TokensCIService.shared.install(username: enteredName, token: enteredToken)
                                model.reloadAccounts()
                                if !(await model.refresh(target: .tokensCI(name))) { model.message = "账号已保存，正在刷新其他账号；请稍后点此账号的刷新。" }
                                username = ""; consent = false
                                dismiss()
                            } catch { message = (error as? TokensCIError)?.localizedDescription ?? "保存失败，请解锁后重试" }
                            saving = false
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(palette.accent)
                    .disabled(!consent || username.isEmpty || token.isEmpty || saving || model.busy)
                    if let message { Text(message).font(.caption).foregroundStyle(palette.warning).fixedSize(horizontal: false, vertical: true) }
                }
                }
                .padding(16)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("连接 tokens.ci")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { clearCredentials(); dismiss() }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clearCredentials(); dismiss() } }
        .onDisappear { clearCredentials() }
    }
    private func clearCredentials() {
        username = ""; token = ""; consent = false
    }
}
