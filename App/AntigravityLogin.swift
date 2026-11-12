import SwiftUI
import SafariServices

/// In-app browser: the consent page runs inside our own process, so the App is never suspended
/// while the user signs in and the loopback redirect is caught immediately.
struct AntigravityWebSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Preserves the exact user-facing copy of the pre-refactor listener.
private enum AntigravityListenerError: LocalizedError {
    case busy, alreadyStarted
    var errorDescription: String? {
        switch self {
        case .busy: return "本机端口被占用，登录无法开始（可改用手动粘贴刷新令牌）"
        case .alreadyStarted: return "登录已在进行中"
        }
    }
}

@MainActor
final class AntigravityLogin: ObservableObject {
    @Published var authorizeURL: URL?
    @Published var message: String?
    @Published var busy = false
    private var listener: LoopbackCallbackServer?
    private var verifier = ""
    private var redirect = ""
    private var state = ""

    func start() {
        guard authorizeURL == nil, !busy else { return }
        guard AntigravityAPI.isConfigured else {
            message = "当前构建未配置 Antigravity OAuth 客户端"
            return
        }
        message = nil
        busy = true
        Task { @MainActor [weak self] in
          guard let self else { return }
          // Google allows any loopback port, so the IDE's port is preferred and one random high
          // port is the fallback. Only 127.0.0.1 is bound.
          let listener = LoopbackCallbackServer(configuration: .init(
            path: "/oauth2callback",
            ports: [AntigravityOAuth.preferredPort, UInt16.random(in: 49_152...65_535)],
            timeout: 300,
            pages: .init(successTitle: "登录完成", successDetail: "可以关闭此页，回到 Codex 用量继续。",
                         failureTitle: "登录未完成", failureDetail: "Google 未完成授权，请回到 App 重试。",
                         waitingTitle: "等待登录", waitingDetail: "这个地址只用于接收 Google 登录回调。")))
          do {
            let verifier = AntigravityOAuth.codeVerifier()
            let challenge = AntigravityOAuth.codeChallenge(verifier)
            let state = AntigravityOAuth.codeVerifier()
            let port = try await listener.start(expectedState: state) { [weak self] result in
                Task { @MainActor in await self?.finished(result) }
            }
            self.verifier = verifier
            self.state = state
            self.redirect = AntigravityOAuth.redirectURI(port: port)
            self.listener = listener
            authorizeURL = AntigravityOAuth.authorizeURL(redirectURI: redirect, challenge: challenge, state: state)
          } catch {
            listener.stop()
            busy = false
            message = (error as? LoopbackCallbackServerError) == .alreadyStarted
                ? AntigravityListenerError.alreadyStarted.localizedDescription
                : AntigravityListenerError.busy.localizedDescription
          }
        }
    }

    func cancel() {
        listener?.stop()
        listener = nil
        authorizeURL = nil
        busy = false
        verifier = ""
        state = ""
    }

    private func finished(_ result: Result<LoopbackCallback, Error>) async {
        authorizeURL = nil
        // Stay busy until the exchange is done: a second tap on 登录 during the await would
        // otherwise start a new flow whose verifier/state this one then wipes.
        defer { busy = false; listener = nil; verifier = ""; state = "" }
        switch result {
        case .success(let callback):
            switch callback {
            case .code(let code):
                do {
                    let api = AntigravityAPI()
                    let refresh = try await api.exchange(code: code, verifier: verifier, redirectURI: redirect)
                    try await AntigravityService.shared.install(token: refresh)
                    message = "登录成功，已保存刷新令牌"
                    NotificationCenter.default.post(name: .antigravitySignedIn, object: nil)
                } catch { message = error.localizedDescription }
            case .failure:
                message = AntigravityError.unauthorized.localizedDescription
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}

extension Notification.Name {
    static let antigravitySignedIn = Notification.Name("CodexUsage.antigravitySignedIn")
}
