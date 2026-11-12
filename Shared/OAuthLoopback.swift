import Foundation
#if canImport(Network)
import Network
#endif

// MARK: - Loopback callback parsing

/// One redirect received on the local callback listener.
public enum LoopbackCallback: Equatable, Sendable {
    case code(String)
    case failure(String)
}

/// Pure parser for a loopback redirect: only the registered path is accepted, the one-time OAuth
/// `state` must match exactly, and a provider `error` wins over a code. No socket is needed, so the
/// security-relevant part is unit-testable.
public enum LoopbackCallbackParser {
    public static func parse(requestLine: String, path: String, expectedState: String) -> LoopbackCallback? {
        guard !expectedState.isEmpty else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let target = String(parts[1])
        guard let components = URLComponents(string: "http://localhost" + target), components.path == path else { return nil }
        func value(_ name: String) -> String? { components.queryItems?.first { $0.name == name }?.value }
        guard value("state") == expectedState else { return nil }
        if let error = value("error"), !error.isEmpty { return .failure(error) }
        if let code = value("code"), !code.isEmpty { return .code(code) }
        return nil
    }
}

// MARK: - Loopback server

public enum LoopbackCallbackServerError: Error, LocalizedError, Equatable {
    case alreadyStarted, noAvailablePort, timedOut
    public var errorDescription: String? {
        switch self {
        case .alreadyStarted: return "登录已在进行中"
        case .noAvailablePort: return "本机端口被占用，登录无法开始（可改用手动粘贴刷新令牌）"
        case .timedOut: return "等待登录超时，请重试"
        }
    }
}

/// Copy for the page the in-app browser lands on. Providers pass their existing wording so the
/// refactor is invisible to the user.
public struct LoopbackCallbackPages: Sendable {
    public var successTitle: String
    public var successDetail: String
    public var failureTitle: String
    public var failureDetail: String
    public var waitingTitle: String
    public var waitingDetail: String
    public init(successTitle: String = "登录完成", successDetail: String = "可以关闭此页，回到 App 继续。",
                failureTitle: String = "登录未完成", failureDetail: String = "未完成授权，请回到 App 重试。",
                waitingTitle: String = "等待登录", waitingDetail: String = "这个地址只用于接收登录回调。") {
        self.successTitle = successTitle; self.successDetail = successDetail
        self.failureTitle = failureTitle; self.failureDetail = failureDetail
        self.waitingTitle = waitingTitle; self.waitingDetail = waitingDetail
    }
}

public struct LoopbackCallbackConfiguration: Sendable {
    /// Only this path is accepted, exactly as the provider registered it.
    public var path: String
    /// Fixed ports in the order they should be tried. Empty means a random loopback port.
    public var ports: [UInt16]
    /// How long the listener waits for the user before failing with `.timedOut`.
    public var timeout: TimeInterval
    public var pages: LoopbackCallbackPages
    public init(path: String, ports: [UInt16] = [], timeout: TimeInterval = 300, pages: LoopbackCallbackPages = .init()) {
        self.path = path
        self.ports = ports
        self.timeout = timeout
        self.pages = pages
    }
    /// 127.0.0.1 only; a random high port when the provider allows one.
    func candidatePorts() -> [UInt16] {
        if !ports.isEmpty { return ports }
        return (0..<24).map { _ in UInt16.random(in: 49_152...65_535) }
    }
}

#if canImport(Network)
/// One-shot listener on 127.0.0.1. It accepts exactly one valid callback, verifies `state`, closes
/// itself on success/failure/timeout/cancel, and never exposes the port off-device.
public final class LoopbackCallbackServer: @unchecked Sendable {
    public typealias Completion = @Sendable (Result<LoopbackCallback, Error>) -> Void
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; guard !claimed else { return false }; claimed = true; return true }
    }
    private let configuration: LoopbackCallbackConfiguration
    private let lock = NSLock()
    private var listener: NWListener?
    private var finish: Completion?
    private var expectedState = ""
    private var settled = true
    private var timeoutTask: Task<Void, Never>?

    public init(configuration: LoopbackCallbackConfiguration) { self.configuration = configuration }

    /// Binds the first available candidate and returns the port the redirect URI must name.
    public func start(expectedState: String, onCallback: @escaping Completion) async throws -> UInt16 {
        guard prepare(expectedState: expectedState, onCallback: onCallback) else { throw LoopbackCallbackServerError.alreadyStarted }
        for port in configuration.candidatePorts() {
            if let bound = await bind(port) { return bound }
        }
        clear()
        throw LoopbackCallbackServerError.noAvailablePort
    }

    /// Synchronous so the lock is never taken inside an async context.
    private func prepare(expectedState: String, onCallback: @escaping Completion) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard listener == nil else { return false }
        finish = onCallback
        self.expectedState = expectedState
        settled = false
        return true
    }

    private func install(_ candidate: NWListener) {
        lock.lock(); listener = candidate; lock.unlock()
    }

    private func discard(_ candidate: NWListener) {
        lock.lock()
        if listener === candidate { listener = nil }
        lock.unlock()
    }

    private func bind(_ port: UInt16) async -> UInt16? {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        guard let candidate = try? NWListener(using: parameters) else { return nil }
        candidate.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        install(candidate)
        let bound = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let gate = Gate()
            candidate.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    candidate.stateUpdateHandler = nil
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    guard gate.claim() else { return }
                    candidate.cancel()
                    self?.discard(candidate)
                    continuation.resume(returning: false)
                default: break
                }
            }
            candidate.start(queue: .main)
        }
        guard bound else { return nil }
        scheduleTimeout()
        return port
    }

    private func scheduleTimeout() {
        let seconds = configuration.timeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.settle(.failure(LoopbackCallbackServerError.timedOut))
        }
    }

    /// Cancels the listener and discards the pending completion (no callback is delivered).
    public func stop() { clear(cancelListener: true) }

    private func clear(cancelListener: Bool = false) {
        lock.lock()
        let listener = self.listener
        let timeout = timeoutTask
        self.listener = nil
        self.finish = nil
        self.timeoutTask = nil
        self.settled = true
        self.expectedState = ""
        lock.unlock()
        if cancelListener { listener?.cancel() }
        timeout?.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { connection.cancel(); return }
            let line = text.split(separator: "\r\n").first.map(String.init) ?? text
            self.lock.lock()
            let state = self.expectedState
            self.lock.unlock()
            let result = LoopbackCallbackParser.parse(requestLine: line, path: self.configuration.path, expectedState: state)
            let pages = self.configuration.pages
            let body: String
            switch result {
            case .code: body = Self.page(title: pages.successTitle, detail: pages.successDetail)
            case .failure: body = Self.page(title: pages.failureTitle, detail: pages.failureDetail)
            case nil: body = Self.page(title: pages.waitingTitle, detail: pages.waitingDetail)
            }
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            guard let result else { return }   // Not our callback (e.g. /favicon.ico): keep waiting.
            switch result {
            case .code: self.settle(.success(result))
            case .failure: self.settle(.success(result))
            }
        }
    }

    /// Delivers the first terminal result and closes the listener. Later events are ignored.
    private func settle(_ result: Result<LoopbackCallback, Error>) {
        lock.lock()
        guard !settled else { lock.unlock(); return }
        settled = true
        let completion = finish
        finish = nil
        let listener = self.listener
        self.listener = nil
        let timeout = timeoutTask
        timeoutTask = nil
        expectedState = ""
        lock.unlock()
        listener?.cancel()
        timeout?.cancel()
        completion?(result)
    }

    private static func page(title: String, detail: String) -> String {
        "<!doctype html><meta name=viewport content=\"width=device-width,initial-scale=1\"><body style=\"font-family:-apple-system;padding:2rem;background:#0b0b0f;color:#fff\"><h2>\(title)</h2><p style=\"color:#aaa\">\(detail)</p></body>"
    }
}
#endif

// MARK: - Device code flow

public struct OAuthToken: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let expiresIn: Double?
    public init(accessToken: String, refreshToken: String?, idToken: String?, expiresIn: Double?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.expiresIn = expiresIn
    }
}

public struct DeviceCodeGrant: Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL?
    /// The provider's requested poll interval in seconds.
    public let interval: TimeInterval
    /// How long the code itself stays valid.
    public let expiresIn: TimeInterval
    public init(deviceCode: String, userCode: String, verificationURL: URL?, interval: TimeInterval, expiresIn: TimeInterval) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.interval = interval
        self.expiresIn = expiresIn
    }
}

public enum DeviceCodePoll: Equatable, Sendable {
    case pending
    case slowDown
    case expired
    case authorized(OAuthToken)
}

public enum DeviceCodeError: Error, LocalizedError, Equatable {
    case expired, malformed
    public var errorDescription: String? {
        switch self {
        case .expired: return "设备代码已过期，请重新登录。"
        case .malformed: return "设备授权返回了无法识别的凭据。"
        }
    }
}

/// Provider-agnostic RFC 8628 polling loop: waits `interval`, adds five seconds on `slow_down`,
/// stops at the code's expiry (or `maximumLifetime`), and propagates cancellation. A future
/// provider only supplies the two provider-specific calls through `poller`.
public struct DeviceCodeFlow: Sendable {
    public typealias Poller = @Sendable (DeviceCodeGrant) async throws -> DeviceCodePoll
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void
    public typealias Clock = @Sendable () -> Date
    public var slowDownStep: TimeInterval = 5
    public var maximumInterval: TimeInterval = 60
    public var maximumLifetime: TimeInterval = 900
    private let poller: Poller
    private let sleep: Sleeper
    private let now: Clock
    public init(poller: @escaping Poller,
                sleep: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) },
                now: @escaping Clock = { Date() }) {
        self.poller = poller
        self.sleep = sleep
        self.now = now
    }
    public func run(_ grant: DeviceCodeGrant, onAuthorization: (@Sendable (OAuthToken) -> Void)? = nil) async throws -> OAuthToken {
        let lifetime = min(max(grant.expiresIn, 1), maximumLifetime)
        let deadline = now().addingTimeInterval(lifetime)
        var interval = min(max(grant.interval, 1), maximumInterval)
        while true {
            try Task.checkCancellation()
            switch try await poller(grant) {
            case .pending:
                break
            case .slowDown:
                interval = min(maximumInterval, interval + slowDownStep)
            case .expired:
                throw DeviceCodeError.expired
            case .authorized(let token):
                guard !token.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeviceCodeError.malformed }
                onAuthorization?(token)
                return token
            }
            try Task.checkCancellation()
            if now() >= deadline { throw DeviceCodeError.expired }
            try await sleep(interval)
        }
    }
}
