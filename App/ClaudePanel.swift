import SwiftUI
import SafariServices
import WidgetKit

/// In-app browser for the consent page: our own process keeps running, so the loopback redirect is
/// always caught. This is the same presentation the reference app uses for its system sign-in
/// sheet, without a custom scheme (which this client rejects). `ASWebAuthenticationSession` cannot
/// receive a loopback redirect (it only hands back a custom scheme), which is why the listener is
/// a local `LoopbackCallbackServer`.
struct ClaudeWebSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

@MainActor
final class ClaudeLogin: ObservableObject {
    @Published var authorizeURL: URL?
    @Published var message: String?
    @Published var busy = false
    /// The console flow shows a copyable `code#state`; the field only ever holds that one-time code.
    @Published var showCodePaste = false
    @Published var codeInput = ""
    private var listener: LoopbackCallbackServer?
    private var verifier = ""
    private var state = ""
    private var redirect = ClaudeOAuth.redirectURI

    /// Primary path: approve in-app and let the code come back on 127.0.0.1.
    func start() {
        guard authorizeURL == nil, !busy else { return }
        begin(redirectURI: ClaudeOAuth.redirectURI, showPaste: false)
    }
    /// Fallback when the loopback callback cannot be used on this device or network: approve in the
    /// same in-app browser, copy the one-time code the page shows, paste it here.
    func startCodePaste() {
        guard !busy else { return }
        // Any loopback attempt is abandoned first: the sheet is rebuilt around the console redirect
        // so the page the user is looking at is the one that shows the copyable code.
        listener?.stop()
        listener = nil
        authorizeURL = nil
        showCodePaste = true
        Task { @MainActor in begin(redirectURI: ClaudeOAuth.consoleRedirectURI, showPaste: true) }
    }

    private func begin(redirectURI: String, showPaste: Bool) {
        message = nil
        busy = true
        let verifier = ClaudeOAuth.codeVerifier()
        let state = ClaudeOAuth.codeVerifier()
        self.verifier = verifier
        self.state = state
        self.redirect = redirectURI
        self.showCodePaste = showPaste
        self.codeInput = ""
        let challenge = ClaudeOAuth.codeChallenge(verifier)
        guard redirectURI == ClaudeOAuth.redirectURI else {
            // No loopback listener for the console redirect: the code is copied by the user.
            authorizeURL = ClaudeOAuth.authorizeURL(state: state, challenge: challenge, redirectURI: redirectURI)
            listener = nil
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // The Claude Code client registers exactly this loopback redirect, so the port is
            // fixed: the shared server is given one candidate and never falls back to another.
            let listener = LoopbackCallbackServer(configuration: .init(
                path: ClaudeOAuth.callbackPath, ports: [ClaudeOAuth.callbackPort], timeout: 300,
                pages: .init(successTitle: "登录完成", successDetail: "可以关闭此页，回到 Codex 用量继续。",
                             failureTitle: "登录未完成", failureDetail: "Claude 未完成授权，请回到 App 重试。",
                             waitingTitle: "等待登录", waitingDetail: "这个地址只用于接收 Claude 登录回调。")))
            do {
                _ = try await listener.start(expectedState: state) { [weak self] result in
                    Task { @MainActor in await self?.finished(result) }
                }
                self.listener = listener
                authorizeURL = ClaudeOAuth.authorizeURL(state: state, challenge: challenge, redirectURI: redirectURI)
            } catch {
                listener.stop()
                busy = false
                // Same copy as before the refactor: a busy fixed port is the only realistic
                // failure and it sends the user to the paste-code fallback.
                message = ClaudeFailure.listenerBusy.localizedDescription
            }
        }
    }

    /// Exchange the pasted one-time code. Only a code for this login's state is accepted.
    func submitPastedCode() {
        guard case .code(let code, let state)? = ClaudeOAuth.parsePastedCode(codeInput, expectedState: self.state) else {
            message = self.state.isEmpty
                ? "登录已失效，请重新点「打开授权页面」。"
                : "授权码格式无法识别，或不属于本次登录，请粘贴本次授权页面上显示的整段内容。"
            return
        }
        codeInput = ""
        showCodePaste = false
        authorizeURL = nil
        busy = true
        Task { @MainActor in await complete(code: code, state: state, redirectURI: ClaudeOAuth.consoleRedirectURI) }
    }

    /// The consent sheet was swiped away. In the paste flow that is the expected next step — the
    /// user copied the code and now pastes it — so the verifier and state must survive; only the
    /// loopback flow is abandoned.
    func sheetDismissed() {
        guard showCodePaste else { cancel(); return }
        authorizeURL = nil
        busy = false   // "完成登录" is disabled while busy; the paste step starts now.
    }

    func cancel() {
        listener?.stop()
        listener = nil
        authorizeURL = nil
        busy = false
        verifier = ""
        state = ""
        codeInput = ""
        showCodePaste = false
    }

    private func finished(_ result: Result<LoopbackCallback, Error>) async {
        authorizeURL = nil
        switch result {
        case .success(let callback):
            switch callback {
            case .code(let code):
                let state = self.state
                busy = true
                await complete(code: code, state: state, redirectURI: redirect)
            case .failure:
                busy = false
                message = ClaudeFailure.unauthorized.localizedDescription
            }
        case .failure(let error):
            busy = false
            message = error.localizedDescription
        }
        listener = nil
        verifier = ""
        state = ""
    }

    private func complete(code: String, state: String, redirectURI: String) async {
        defer { busy = false; verifier = ""; self.state = "" }   // one exchange per login attempt
        do {
            let tokens = try await ClaudeAPI().exchange(code: code, verifier: verifier, state: state, redirectURI: redirectURI)
            try await ClaudeService.shared.install(tokens: tokens)
            message = "登录成功，令牌已存入本机钥匙串。"
            NotificationCenter.default.post(name: .claudeSignedIn, object: nil)
        } catch {
            message = (error as? ClaudeFailure)?.localizedDescription ?? "Claude 登录失败，请重试。"
        }
    }
}

extension Notification.Name {
    static let claudeSignedIn = Notification.Name("CodexUsage.claudeSignedIn")
}

struct ClaudePanel: View {
    @ObservedObject var model: UsageModel
    let palette: AppPalette
    @StateObject private var login = ClaudeLogin()
    @State private var consent = false
    @State private var message: String?
    var body: some View {
        AppCard(title: "Claude · Claude 账号登录", caption: "Claude Code 的 OAuth 客户端 · 非官方兼容方式",
                systemImage: "sparkle", palette: palette, mark: AnyView(BrandMark(brand: .claude, palette: palette))) {
            VStack(alignment: .leading, spacing: 12) {
                // Said plainly and up front: this is a compatibility mechanism, not an approval.
                Text("Anthropic 不授权第三方 App 提供 Claude.ai 登录，也不授权收集、存储或转交 Claude.ai 会话令牌。此面板用 Claude Code 自己的 OAuth 客户端登录（与你本机 CLIProxyAPI 用的是同一机制），只读取订阅用量；它是兼容做法，可能随时被更改或封禁，随时可能失效。App 不会接收你的密码。")
                    .font(.footnote).foregroundStyle(palette.warning)
                if model.claudeInstalled {
                    Text("已在本机钥匙串保存刷新令牌和当前访问令牌（与 CLIProxyAPI 相同：访问令牌到期前 5 分钟才换新，一天只换几次）。只调用账号用量接口，不代你发起任何模型请求。若失效，请在下方移除后重新登录。")
                        .font(.footnote).foregroundStyle(palette.secondary)
                    HStack(spacing: 12) {
                        Button("立即刷新用量") { Task { await model.refresh() } }.disabled(model.busy)
                        Button("移除 Claude 授权", role: .destructive) {
                            Task {
                                do {
                                    try await ClaudeService.shared.remove()
                                    try DashboardStore.publish()
                                    model.reloadAccounts()
                                    WidgetCenter.shared.reloadAllTimelines()
                                    message = "已移除 Claude 授权"
                                } catch { message = (error as? ClaudeFailure)?.localizedDescription ?? "移除失败，请检查本机储存" }
                            }
                        }
                    }.font(.footnote)
                } else {
                    Toggle("我理解这不是 Anthropic 授权的方式、存在合规与兼容风险，并同意在本机保存刷新令牌", isOn: $consent)
                        .font(.footnote).tint(palette.accent)
                    Button {
                        login.start()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.key")
                            Text(login.busy ? "正在等待 Claude 登录…" : "用 Claude 账号登录")
                        }
                    }.disabled(!consent || login.busy || model.busy).font(.footnote.bold())
                    Text("会弹出 Claude 的官方登录页面（App 内浏览器，与你见到的其他 App 的登录方式一致）。登录完成后授权码直接回到本机 127.0.0.1:54545，只经过 Anthropic。")
                        .font(.footnote).foregroundStyle(palette.secondary)
                    DisclosureGroup("回调端口被占用，或页面无法回到本机？改用授权码") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("打开授权页面") { login.startCodePaste() }
                                .font(.footnote).disabled(!consent || login.busy)
                            Text("在页面里同意后，页面会显示一段 code#state；长按拷贝，关闭页面后粘贴到这里。这只接受一次性的登录授权码。")
                                .font(.footnote).foregroundStyle(palette.secondary)
                            TextField("粘贴一次性授权码（形如 code#state）", text: $login.codeInput)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(.system(.footnote, design: .monospaced))
                            Button("完成登录") { login.submitPastedCode() }
                                .font(.footnote).disabled(login.codeInput.isEmpty || login.busy)
                        }.padding(.top, 4)
                    }.font(.footnote).tint(palette.accent)
                }
                Text("刷新令牌只写入本机 Keychain（本机专用、首次解锁后可用），不写共享快照、不写日志、不进聊天。同一签名组的其他 App 可能读取该项目；service 名不是权限隔离。小组件需先通过共享权限握手并明确同意才能自行刷新，否则它显示「打开 App 刷新」按钮——那个按钮只是打开 App，不是组件内刷新。")
                    .font(.footnote).foregroundStyle(palette.secondary)
                if let message { Text(message).font(.footnote).foregroundStyle(palette.secondary) }
                if let loginMessage = login.message { Text(loginMessage).font(.footnote).foregroundStyle(palette.secondary) }
            }
        }
        .sheet(isPresented: Binding(get: { login.authorizeURL != nil }, set: { presented in if !presented { login.sheetDismissed() } })) {
            if let url = login.authorizeURL { ClaudeWebSheet(url: url).ignoresSafeArea() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .claudeSignedIn)) { _ in
            model.reloadAccounts()
            Task { await model.refresh() }
        }
    }
}

struct ClaudeAccountCard: View {
    let snapshot: ClaudeSnapshot?
    @Binding var expanded: Bool
    let palette: AppPalette
    let onRefresh: () -> Void
    let onReauthorize: () -> Void
    let onRemove: () -> Void
    let busy: Bool
    var refreshError: String? = nil
    var summary: QuotaSummary.Window? {
        QuotaSummary.tightest([.init(label: "5 小时", remaining: snapshot?.fiveHour?.remaining, reset: snapshot?.fiveHour?.reset),
                               .init(label: "7 天", remaining: snapshot?.sevenDay?.remaining, reset: snapshot?.sevenDay?.reset)])
    }
    var body: some View {
        AppCard(title: "Claude", caption: "订阅额度 · 非官方 OAuth 兼容", systemImage: "sparkle", palette: palette,
                expanded: $expanded,
                menu: AnyView(CardMenu(palette: palette, accountContext: "Claude") {
                    Button("刷新 Claude 用量", action: onRefresh).disabled(busy)
                    Button("重新授权", action: onReauthorize)
                    Button("移除 Claude 授权", role: .destructive, action: onRemove)
                }),
                mark: AnyView(BrandMark(brand: .claude, palette: palette))) {
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    QuotaRow(label: "5 小时", remaining: snapshot?.fiveHour?.remaining, reset: snapshot?.fiveHour?.reset, brand: .claude, palette: palette)
                    QuotaRow(label: "7 天", remaining: snapshot?.sevenDay?.remaining, reset: snapshot?.sevenDay?.reset, brand: .claude, palette: palette)
                    Rectangle().fill(palette.divider).frame(height: 1).padding(.vertical, 4)
                    AppRow(label: "更新时间", value: snapshot.map { RelativeTime.stamp($0.updatedAt) + ($0.isStale() ? " · 已过期" : "") } ?? "—", palette: palette)
                }
            } else {
                SummaryLine(window: summary, brand: .claude, palette: palette)
            }
            CardRefreshFeedback(error: refreshError, updatedAt: snapshot?.updatedAt, palette: palette, busy: busy, onRetry: onRefresh)
        }
    }
}
