import Foundation
import Security

/// tokens.ci profile, read-only.
///
/// The read token only ever reaches the Keychain; it is never written to a snapshot, a log or
/// the shared container. The snapshot the widget reads is a plain JSON file with no credential.
struct TokensCISnapshot: Codable, Equatable {
    let username: String
    let displayName: String?
    let isPrivate: Bool
    let rank: Int?
    let totalTokens: Double
    let totalCost: Double
    let inputTokens: Double
    let outputTokens: Double
    let cacheReadTokens: Double
    let cacheWriteTokens: Double
    let reasoningTokens: Double
    let activeDays: Int
    let sessionCount: Int
    var todayTokens: Double
    var todayCost: Double
    let monthCost: Double
    let cacheHitRate: Double
    var clients: [TokensCIClient]
    /// When tokens.ci last received a submission (server clock), not when we fetched it.
    let dataUpdatedAt: Date
    let fetchedAt: Date
    var isStale: Bool
    /// Calendar key used at fetch time; nil on pre-build36 caches (not period-aligned).
    var selectedDay: String? = nil
    var selectedTimeZone: String? = nil
    /// Transient App-only history; stripped before publishing the minimal widget snapshot.
    @TokensCILossyHistory var history: TokensCIHistory? = nil
    var avatarURL: String? = nil

    var periodLabel: String {
        guard let selectedDay else { return "日数据待刷新" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"
        return selectedDay == f.string(from: Date()) && selectedTimeZone == TimeZone.current.identifier
            ? "今日 Token · 上报日" : "缓存日 " + selectedDay
    }
    var periodNote: String {
        "按设备日历日 \(selectedDay ?? "未验证")（\(selectedTimeZone ?? "旧缓存")）匹配上报日期；电脑分桶时区须一致。旧版或异区整日桶无法精确换算，不按首条消息拆分。"
    }

    /// Sparse uploads do not define a reliable daily run rate.
    var monthlyEstimate: Double? { nil }
}

struct TokensCIClient: Codable, Equatable, Identifiable {
    let name: String
    let tokens: Double
    let cost: Double
    let topModel: TokensCIModel?
    var id: String { name }
    var displayName: String {
        ["hermes": "Hermes Agent", "codex": "Codex CLI", "claude": "Claude Code", "claudecode": "Claude Code", "opencode": "OpenCode", "pi": "Pi", "cursor": "Cursor", "gemini": "Gemini CLI"][name] ?? name
    }
}

struct TokensCIModel: Codable, Equatable {
    let name: String
    let tokens: Double
    let cost: Double
}

enum TokensCIError: Error, LocalizedError {
    case invalidUsername, invalidToken, unauthorized, notFound, ambiguous, rateLimited
    case unavailable, malformed, network, storage

    var errorDescription: String? {
        switch self {
        case .invalidUsername: return "用户名无效，请填写 GitHub 用户名或 tokens.ci 个人主页链接"
        case .invalidToken: return "Read token 格式不对，应以 tkr_ 开头"
        case .unauthorized: return "Read token 无效或已撤销，请在 tokens.ci Settings 重新生成"
        case .notFound: return "tokens.ci 上还没有这个用户的用量"
        case .ambiguous: return "该用户名对应多个 tokens.ci 资料"
        case .rateLimited: return "tokens.ci 请求过于频繁，稍后重试"
        case .unavailable: return "tokens.ci 服务暂不可用"
        case .malformed: return "tokens.ci 返回格式异常"
        case .network: return "tokens.ci 网络失败，保留上次数据"
        case .storage: return "钥匙串或缓存不可用，请解锁并检查签名"
        }
    }
}

// MARK: - Wire format

/// Only the fields we display are decoded, and every optional stays optional: the endpoint is
/// undocumented, so an added or removed key must never fail the whole snapshot.
private struct TokensCIProfile: Decodable {
    struct User: Decodable {
        let username: String
        let displayName: String?
        let isPrivate: Bool?
        let rank: Int?
    }
    struct Stats: Decodable {
        let totalTokens: Double?
        let totalCost: Double?
        let inputTokens: Double?
        let outputTokens: Double?
        let cacheReadTokens: Double?
        let cacheWriteTokens: Double?
        let reasoningTokens: Double?
        let activeDays: Int?
        let sessionCount: Int?
    }
    struct Freshness: Decodable { let isStale: Bool? }
    struct Client: Decodable {
        struct Tokens: Decodable {
            let input: Double?
            let output: Double?
            let cacheRead: Double?
            let cacheWrite: Double?
            let reasoning: Double?
            var total: Double { (input ?? 0) + (output ?? 0) + (cacheRead ?? 0) + (cacheWrite ?? 0) + (reasoning ?? 0) }
        }
        let client: String
        let modelId: String?
        let tokens: Tokens?
        let cost: Double?
        let models: [String: Model]?
    }
    struct Model: Decodable {
        let tokens: Double?
        let cost: Double?
    }
    struct Contribution: Decodable {
        struct Totals: Decodable {
            let tokens: Double?
            let cost: Double?
        }
        let date: String?
        let totals: Totals?
        let clients: [Client]?
    }
    let user: User
    let stats: Stats?
    let updatedAt: String?
    let submissionFreshness: Freshness?
    let clients: [String]?
    let contributions: [Contribution]?
}

struct TokensCIAPI {
    let transport: any HTTPTransport
    init(transport: any HTTPTransport = URLTransport()) { self.transport = transport }

    /// Accepts a bare GitHub username or any tokens.ci profile link (`tokens.ci/u/<name>`).
    static func normalizedUsername(_ raw: String) throws -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: "tokens.ci/") {
            value = String(value[range.upperBound...])
            for prefix in ["u/", "@"] where value.hasPrefix(prefix) { value.removeFirst(prefix.count) }
        } else {
            for prefix in ["@"] where value.hasPrefix(prefix) { value.removeFirst(prefix.count) }
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !value.isEmpty, value.count <= 64,
              value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
        else { throw TokensCIError.invalidUsername }
        return value
    }

    /// A read token is `tkr_` + url-safe characters. A `tt_` submit token is rejected here
    /// rather than being sent and refused with a confusing 401.
    static func validatedToken(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^tkr_[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
              value.count <= 512 else { throw TokensCIError.invalidToken }
        return value
    }

    func profile(username: String, token: String, now: Date = Date(), timeZone: TimeZone = .current) async throws -> TokensCISnapshot {
        try Task.checkCancellation()
        let name = try Self.normalizedUsername(username)
        let credential = try Self.validatedToken(token)
        guard let url = URL(string: "https://tokens.ci/api/users/")?.appendingPathComponent(name) else {
            throw TokensCIError.invalidUsername
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = "period=all"
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data; let status: Int
        do { (data, status) = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw TokensCIError.network }
        try Task.checkCancellation()
        switch status {
        case 200: break
        case 401, 403: throw TokensCIError.unauthorized
        case 404: throw TokensCIError.notFound
        case 409: throw TokensCIError.ambiguous
        case 429: throw TokensCIError.rateLimited
        case 500...599: throw TokensCIError.unavailable
        default: throw TokensCIError.malformed
        }
        let profile: TokensCIProfile
        do {
            // Decode daily entries independently; one malformed history row must not discard
            // the otherwise valid profile or replace a good cache with an error.
            var raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let rows = raw["contributions"] as? [Any] ?? []
            raw["contributions"] = rows.compactMap { row -> [String: Any]? in
                guard let object = row as? [String: Any], let encoded = try? JSONSerialization.data(withJSONObject: object),
                      (try? JSONDecoder().decode(TokensCIProfile.Contribution.self, from: encoded)) != nil else { return nil }
                return object
            }
            profile = try JSONDecoder().decode(TokensCIProfile.self, from: JSONSerialization.data(withJSONObject: raw))
        }
        catch { throw TokensCIError.malformed }
        var value = try Self.snapshot(from: profile, fetchedAt: now, timeZone: timeZone)
        value.history = try? TokensCIHistory.decode(data)
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let user = raw["user"] as? [String: Any] { value.avatarURL = user["avatarUrl"] as? String }
        return value
    }

    fileprivate static func snapshot(from profile: TokensCIProfile, fetchedAt: Date, timeZone: TimeZone) throws -> TokensCISnapshot {
        let stats = profile.stats
        guard let totalTokens = stats?.totalTokens, let totalCost = stats?.totalCost,
              totalTokens.isFinite, totalTokens >= 0, totalCost.isFinite, totalCost >= 0 else { throw TokensCIError.malformed }
        let cacheRead = stats?.cacheReadTokens ?? 0
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        // Current CLI uses its pinned timezone for these date keys. Never reinterpret
        // timestampMs (an earliest-message hint) as the boundary of a whole day.
        // Legacy/other-zone buckets cannot be split into device-local days by this API.
        let todayKey = fmt.string(from: fetchedAt)
        let monthPrefix = String(todayKey.prefix(7))

        let contributions = profile.contributions ?? []
        var todayTokens = 0.0, todayCost = 0.0, monthCost = 0.0
        for day in contributions {
            let date = day.date ?? ""
            let tokens = day.totals?.tokens ?? 0
            let cost = day.totals?.cost ?? 0
            if date == todayKey { todayTokens += tokens; todayCost += cost }
            if date.hasPrefix(monthPrefix), date <= todayKey {
                monthCost += cost
            }
        }
        var totals: [String: (tokens: Double, cost: Double, models: [String: TokensCIModel])] = [:]
        let todayContributions = contributions.filter { $0.date == todayKey }
        for day in todayContributions {
            for client in day.clients ?? [] {
                var sum = totals[client.client] ?? (0, 0, [:])
                sum.tokens += client.tokens?.total ?? 0
                sum.cost += client.cost ?? 0
                for (name, model) in client.models ?? [:] where name != "<synthetic>" {
                    let old = sum.models[name]
                    sum.models[name] = TokensCIModel(name: name, tokens: (old?.tokens ?? 0) + (model.tokens ?? 0), cost: (old?.cost ?? 0) + (model.cost ?? 0))
                }
                if (client.models ?? [:]).isEmpty, let name = client.modelId, !name.isEmpty {
                    let old = sum.models[name]
                    sum.models[name] = TokensCIModel(name: name, tokens: (old?.tokens ?? 0) + (client.tokens?.total ?? 0), cost: (old?.cost ?? 0) + (client.cost ?? 0))
                }
                totals[client.client] = sum
            }
        }
        var clients: [TokensCIClient] = []
        for (name, sum) in totals {
            let models = sum.models.values.sorted { lhs, rhs in
                lhs.tokens == rhs.tokens ? lhs.name < rhs.name : lhs.tokens > rhs.tokens
            }
            clients.append(TokensCIClient(name: name, tokens: sum.tokens, cost: sum.cost, topModel: models.first))
        }
        clients.sort { lhs, rhs in lhs.tokens == rhs.tokens ? lhs.name < rhs.name : lhs.tokens > rhs.tokens }

        var updated = fetchedAt
        if let text = profile.updatedAt {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            updated = iso.date(from: text) ?? ISO8601DateFormatter().date(from: text) ?? fetchedAt
        }
        return TokensCISnapshot(
            username: profile.user.username,
            displayName: profile.user.displayName,
            isPrivate: profile.user.isPrivate ?? false,
            rank: profile.user.rank,
            totalTokens: totalTokens,
            totalCost: totalCost,
            inputTokens: stats?.inputTokens ?? 0,
            outputTokens: stats?.outputTokens ?? 0,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: stats?.cacheWriteTokens ?? 0,
            reasoningTokens: stats?.reasoningTokens ?? 0,
            activeDays: stats?.activeDays ?? 0,
            sessionCount: stats?.sessionCount ?? 0,
            todayTokens: todayTokens,
            todayCost: todayCost,
            monthCost: monthCost,
            cacheHitRate: totalTokens > 0 ? min(1, max(0, cacheRead / totalTokens)) : 0,
            clients: clients,
            dataUpdatedAt: updated,
            fetchedAt: fetchedAt,
            isStale: profile.submissionFreshness?.isStale ?? false,
            selectedDay: todayKey, selectedTimeZone: timeZone.identifier)
    }
}

// MARK: - Storage

enum TokensCIStore {
    static let service = "CodexUsage.TokensCI.read-token.v1"

    private static func query(_ username: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let username { q[kSecAttrAccount as String] = username }
        if SharedStorage.isWidget, let group = SharedStorage.permittedGroup { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    static func ids() -> [String] {
        guard !SharedStorage.isWidget else { return DashboardStore.accounts().filter { $0.provider == "tokensci" }.map(\.id) }
        var q = query(); q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return [] }
        return (result as? [[String: Any]] ?? []).compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    static func credentialGroup(_ username: String) -> String? {
        guard let group = SharedStorage.permittedGroup else { return nil }
        var q = query(username); q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let rows = result as? [[String: Any]], rows.count == 1,
              rows[0][kSecAttrAccessGroup as String] as? String == group else { return nil }
        return group
    }

    static func saveToken(_ token: String, username: String) throws {
        guard !SharedStorage.isWidget else { throw TokensCIError.storage }
        let value = try TokensCIAPI.validatedToken(token)
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let q = query(username)
        var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(q.merging(attrs) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw TokensCIError.storage }
    }

    static func token(_ username: String) throws -> String? {
        if SharedStorage.isWidget && !DashboardStore.canRefresh(username, provider: "tokensci") { throw TokensCIError.storage }
        var q = query(username); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw TokensCIError.storage
        }
        return value
    }

    static func snapshotURL(_ username: String) throws -> URL {
        try SharedStorage.snapshotURL("tokensci:" + username).appendingPathExtension("profile")
    }

    static func snapshot(_ username: String) -> TokensCISnapshot? {
        guard let url = try? snapshotURL(username), let data = try? Data(contentsOf: url) else { return nil }
        guard var value = try? JSONDecoder().decode(TokensCISnapshot.self, from: data) else { return nil }
        // Keep lifetime cache and credentials on upgrade, but do not show legacy
        // lifetime client rows beside a day total until a genuine refresh succeeds.
        if value.selectedDay == nil {
            value.todayTokens = 0; value.todayCost = 0; value.clients = []
        }
        if !SharedStorage.isWidget { value.history = TokensCIHistoryStore.load(username) }
        return value
    }

    static func save(_ value: TokensCISnapshot, username: String) throws {
        if !SharedStorage.isWidget, let history = value.history { try TokensCIHistoryStore.save(history, username: username) }
        var minimal = value; minimal.history = nil
        try JSONEncoder().encode(minimal).write(to: snapshotURL(username),
                                              options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(_ username: String) throws {
        guard !SharedStorage.isWidget else { throw TokensCIError.storage }
        let status = SecItemDelete(query(username) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TokensCIError.storage }
        try TokensCIHistoryStore.remove(username)
        for url in [try snapshotURL(username), try WidgetRefreshAttempt.url("tokensci:" + username)]
        where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

actor TokensCIService {
    static let shared = TokensCIService()
    let api: TokensCIAPI
    init(api: TokensCIAPI = TokensCIAPI()) { self.api = api }

    func install(username rawUsername: String, token: String, replacing: String? = nil) throws -> String {
        let username = try TokensCIAPI.normalizedUsername(rawUsername)
        // Same per-account lease as refresh: a token swap must not race an in-flight request.
        let lease = try CredentialLease(account: "tokensci:" + username); defer { withExtendedLifetime(lease) {} }
        let replacedLease = try replacing.flatMap { $0 == username ? nil : try CredentialLease(account: "tokensci:" + $0) }
        defer { withExtendedLifetime(replacedLease) {} }
        let existing = TokensCIStore.ids()

        if existing.contains(username), replacing == nil {
            // Re-entering the same profile only rotates the token; it never duplicates a card.
            try TokensCIStore.saveToken(token, username: username)
            try DashboardStore.publish()
            return username
        }
        try TokensCIStore.saveToken(token, username: username)
        if let replacing, replacing != username { try TokensCIStore.remove(replacing) }
        try WidgetRefreshAttempt().save("tokensci:" + username)
        try DashboardStore.publish()
        return username
    }

    func remove(_ username: String) throws {
        // Without the lease a running refresh could write its snapshot back after the delete.
        let lease = try CredentialLease(account: "tokensci:" + username); defer { withExtendedLifetime(lease) {} }
        try TokensCIStore.remove(username)
        try DashboardStore.publish()
    }

    func refresh(username: String, widget: Bool = SharedStorage.isWidget,
                 permission: (() -> Bool)? = nil) async throws -> TokensCISnapshot {
        func check() throws {
            try Task.checkCancellation()
            if widget && !(permission?() ?? DashboardStore.canRefresh(username, provider: "tokensci")) {
                throw TokensCIError.storage
            }
        }
        try check()
        let lease = try CredentialLease(account: "tokensci:" + username); defer { withExtendedLifetime(lease) {} }
        let attemptID = "tokensci:" + username
        var attempt = WidgetRefreshAttempt.load(attemptID)
        attempt.recoverInterrupted(Date())
        if widget && !attempt.allows(Date()) {
            try attempt.save(attemptID)
            if let cache = TokensCIStore.snapshot(username) { return cache }
            throw ServiceError.busy
        }
        attempt.begin(Date()); try attempt.save(attemptID)
        do {
            try check()
            guard let token = try TokensCIStore.token(username) else { throw TokensCIError.unauthorized }
            let value = try await api.profile(username: username, token: token)
            try check()
            try TokensCIStore.save(value, username: username)
            attempt.succeed(Date()); try attempt.save(attemptID)
            return value
        } catch {
            attempt.fail(Date()); try? attempt.save(attemptID)
            if error is CancellationError { throw CancellationError() }
            throw (error as? TokensCIError) ?? TokensCIError.storage
        }
    }
}

// MARK: - Display

enum TokensCIFormat {
    /// 12,345 → "1.2万"; 3,659,000,000 → "36.59亿". Same units Nowdex prints.
    static func compact(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        if value >= 100_000_000 { return trim(value / 100_000_000, digits: 2) + "亿" }
        if value >= 10_000 { return trim(value / 10_000, digits: 1) + "万" }
        return String(Int(value.rounded()))
    }

    static func money(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value >= 1000 { return "$" + trim(value, digits: 0) }
        if value >= 100 { return String(format: "$%.1f", value) }
        return String(format: "$%.2f", value)
    }

    static func percent(_ ratio: Double) -> String { String(format: "%.0f%%", ratio * 100) }

    private static func trim(_ value: Double, digits: Int) -> String {
        let text = String(format: "%.\(digits)f", value)
        return text.hasSuffix("." + String(repeating: "0", count: digits)) ? String(text.dropLast(digits + 1)) : text
    }
}
