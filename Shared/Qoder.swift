import Foundation

/// Qoder's personal-access-token flow, reconstructed from the Nowdex client's reverse-engineered
/// strings: exchange the PAT for a short-lived job token, then read quota usage with that token.
///
/// Neither endpoint has public documentation and no real credential was available while writing
/// this, so every field name is alias-tolerant in both snake_case and camelCase and an
/// unrecognised payload is `malformed` with explicit copy — nothing is inferred.
struct QoderJobToken: Codable, Equatable {
    let token: String
    static func parse(_ data: Data) throws -> Self {
        let root: [String: Any]
        do { root = try ProviderParsing.object(data) } catch { throw QoderError.malformed }
        let object = (root["data"] as? [String: Any]) ?? root
        guard let raw = ProviderParsing.first(object, ["token", "jobToken", "job_token", "accessToken", "access_token"]) as? String,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QoderError.malformed }
        return Self(token: raw)
    }
}

struct QoderUsage: Codable, Equatable {
    let plan: String?
    let addOn: Decimal?
    let weeklyStart: Date?
    let weeklyUsed: Decimal?
    let weeklyLimit: Decimal?
    let monthlyUsed: Decimal?
    let monthlyLimit: Decimal?
    /// The plan label the card and drawer use.
    var planName: String { plan.map { "Agent Plan · \($0)" } ?? "Agent Plan" }
    var weekly: UsageWindow? { Self.window(used: weeklyUsed, limit: weeklyLimit) }
    var monthly: UsageWindow? { Self.window(used: monthlyUsed, limit: monthlyLimit) }
    /// Money line for a row: "US$5.00 / US$20.00".
    static func moneyText(used: Decimal?, limit: Decimal?) -> String? {
        guard let used, let limit else { return nil }
        return Money.text(used, currency: "USD") + " / " + Money.text(limit, currency: "USD")
    }
    private static func window(used: Decimal?, limit: Decimal?) -> UsageWindow? {
        guard let used, let limit, limit > 0 else { return nil }
        let percent = NSDecimalNumber(decimal: max(0, used) / limit * 100).doubleValue
        return UsageWindow(usedPercent: min(100, max(0, percent)), resetAt: nil, limitWindowSeconds: nil)
    }
    static func parse(_ data: Data) throws -> Self {
        let root: [String: Any]
        do { root = try ProviderParsing.object(data) } catch { throw QoderError.malformed }
        // Merge the usual envelopes (`data`, `quota`, their nested `usage`) into one dictionary so
        // both a flat and a wrapped payload parse the same way.
        var object = root
        for key in ["data", "quota", "usage", "result", "payload"] {
            guard let nested = root[key] as? [String: Any] else { continue }
            for (innerKey, value) in nested { object[innerKey] = value }
            for inner in ["usage", "quota", "data"] {
                if let second = nested[inner] as? [String: Any] {
                    for (innerKey, value) in second where object[innerKey] == nil { object[innerKey] = value }
                }
            }
        }
        func decimal(_ keys: [String]) -> Decimal? {
            let raw = ProviderParsing.first(object, keys)
            if let nested = raw as? [String: Any] {
                return ProviderParsing.decimal(ProviderParsing.first(nested, ["usd", "amount", "credits", "value"]))
            }
            return ProviderParsing.decimal(raw)
        }
        let weeklyUsed = decimal(["weekly_usage_usd", "weeklyUsageUsd", "weeklyUsage", "weekly_used_usd"])
        let weeklyLimit = decimal(["weekly_limit_usd", "weeklyLimitUsd", "weeklyLimit", "weekly_quota_usd"])
        let monthlyUsed = decimal(["monthly_usage_usd", "monthlyUsageUsd", "monthlyUsage", "monthly_used_usd"])
        let monthlyLimit = decimal(["monthly_limit_usd", "monthlyLimitUsd", "monthlyLimit", "monthly_quota_usd"])
        guard Self.window(used: weeklyUsed, limit: weeklyLimit) != nil || Self.window(used: monthlyUsed, limit: monthlyLimit) != nil else {
            throw QoderError.malformed
        }
        let plan = ProviderParsing.first(object, ["plan", "planName", "plan_name", "tier"]) as? String
        return Self(plan: plan?.isEmpty == true ? nil : plan,
                    addOn: decimal(["addOn", "addon", "add_on", "addOnUsd", "add_on_usd", "purchased", "purchasedCredits"]),
                    weeklyStart: ProviderParsing.date(ProviderParsing.first(object, ["weekly_window_start", "weeklyWindowStart", "weekStart"])),
                    weeklyUsed: weeklyUsed, weeklyLimit: weeklyLimit,
                    monthlyUsed: monthlyUsed, monthlyLimit: monthlyLimit)
    }
}

enum QoderError: Error, LocalizedError, Equatable {
    case invalidKey, unauthorized, rateLimited, malformed, network, storage, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "个人访问令牌为空或包含无效字符"
        case .unauthorized: return "Qoder 令牌无效或无权访问"
        case .rateLimited: return "Qoder 请求过于频繁，稍后重试"
        case .malformed: return "Qoder 用量响应格式异常，无法识别额度字段"
        case .network: return "Qoder 网络失败，保留上次用量"
        case .storage: return "Qoder 钥匙串或缓存不可用，请解锁并检查签名"
        case .http(let code): return "Qoder 请求失败（HTTP \(code)）"
        }
    }
}

struct QoderAPI {
    let transport: any HTTPTransport
    let region: QoderRegion
    init(transport: any HTTPTransport = URLTransport(), region: QoderRegion = .china) {
        self.transport = transport
        self.region = region
    }
    static func validatedToken(_ token: String) throws -> String {
        do { return try DeepSeekAPI.validatedKey(token) } catch { throw QoderError.invalidKey }
    }
    private func send(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let data: Data; let status: Int
        do { (data, status) = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw QoderError.network }
        try Task.checkCancellation()
        switch status {
        case 200: return data
        case 401, 403: throw QoderError.unauthorized
        case 429: throw QoderError.rateLimited
        default: throw QoderError.http(status)
        }
    }
    /// `POST api/v1/jobToken/exchange` with the PAT in the JSON body.
    func jobToken(personalAccessToken: String) async throws -> QoderJobToken {
        var request = URLRequest(url: URL(string: region.baseURL + "/api/v1/jobToken/exchange")!)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["personalAccessToken": try Self.validatedToken(personalAccessToken)])
        return try QoderJobToken.parse(try await send(request))
    }
    /// `GET api/v2/quota/usage` with the job token as bearer.
    func usage(personalAccessToken: String, region override: QoderRegion? = nil) async throws -> QoderUsage {
        let region = override ?? self.region
        let job = try await QoderAPI(transport: transport, region: region).jobToken(personalAccessToken: personalAccessToken)
        var request = URLRequest(url: URL(string: region.baseURL + "/api/v2/quota/usage")!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(job.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try QoderUsage.parse(try await send(request))
    }
}

struct QoderSnapshot: Codable, Equatable {
    let usage: QoderUsage
    let updatedAt: Date
    func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > 1800 || now < updatedAt }
}

import Security
enum QoderStore {
    static let service = "CodexUsage.Qoder.api-key.v1"
    static func query(_ id: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let id { q[kSecAttrAccount as String] = id }
        if SharedStorage.isWidget, let group = SharedStorage.permittedGroup { q[kSecAttrAccessGroup as String] = group }
        return q
    }
    static func ids() throws -> [String] {
        guard !SharedStorage.isWidget else { return DashboardStore.accounts().filter { $0.provider == "qoder" }.map(\.id) }
        var q = query(); q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw QoderError.storage }
        return (result as? [[String: Any]] ?? []).sorted {
            ($0[kSecAttrCreationDate as String] as? Date ?? .distantPast) < ($1[kSecAttrCreationDate as String] as? Date ?? .distantPast)
        }.compactMap { $0[kSecAttrAccount as String] as? String }
    }
    static func credentialGroup(_ id: String) -> String? {
        guard let group = SharedStorage.permittedGroup else { return nil }
        var q = query(id); q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let rows = result as? [[String: Any]], rows.count == 1,
              rows[0][kSecAttrAccessGroup as String] as? String == group else { return nil }
        return group
    }
    static func saveKey(_ key: String, id: String) throws {
        guard !SharedStorage.isWidget else { throw QoderError.storage }
        let value = try QoderAPI.validatedToken(key)
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let q = query(id)
        var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(q.merging(attrs) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw QoderError.storage }
    }
    static func key(_ id: String) throws -> String? {
        if SharedStorage.isWidget && !DashboardStore.canRefresh(id, provider: "qoder") { throw QoderError.storage }
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw QoderError.storage }
        return value
    }
    static func snapshotURL(_ id: String) throws -> URL { try SharedStorage.snapshotURL("qoder:" + id).appendingPathExtension("usage") }
    static func snapshot(_ id: String) -> QoderSnapshot? {
        guard let url = try? snapshotURL(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(QoderSnapshot.self, from: data)
    }
    static func save(_ value: QoderSnapshot, id: String) throws {
        try JSONEncoder().encode(value).write(to: snapshotURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func remove(_ id: String) throws {
        guard !SharedStorage.isWidget else { throw QoderError.storage }
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw QoderError.storage }
        for url in [try snapshotURL(id), try WidgetRefreshAttempt.url(id)] where FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try? ProviderPreferences.remove(accountID: id)
    }
}

actor QoderService {
    static let shared = QoderService()
    let api: QoderAPI
    init(api: QoderAPI = QoderAPI()) { self.api = api }
    func install(key: String, region: QoderRegion, replacing id: String? = nil) throws -> String {
        let id = id ?? "qoder-" + UUID().uuidString
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        try QoderStore.saveKey(key, id: id)
        try ProviderPreferences.setQoderRegion(region, accountID: id)
        let url = try QoderStore.snapshotURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try WidgetRefreshAttempt().save(id)
        try DashboardStore.publish()
        return id
    }
    func remove(_ id: String) throws {
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        try QoderStore.remove(id); try DashboardStore.publish()
    }
    func refresh(id: String, widget: Bool = SharedStorage.isWidget, permission: (() -> Bool)? = nil) async throws -> QoderSnapshot {
        func check() throws {
            try Task.checkCancellation()
            if widget && !(permission?() ?? DashboardStore.canRefresh(id, provider: "qoder")) { throw QoderError.storage }
        }
        try check()
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        var attempt = WidgetRefreshAttempt.load(id)
        attempt.recoverInterrupted(Date())
        if widget && !attempt.allows(Date()) {
            try attempt.save(id)
            if let cache = QoderStore.snapshot(id) { return cache }
            throw ServiceError.busy
        }
        attempt.begin(Date()); try attempt.save(id)
        do {
            try check()
            guard let key = try QoderStore.key(id) else { throw QoderError.unauthorized }
            let region = ProviderPreferences.qoderRegion(accountID: id)
            let usage = try await api.usage(personalAccessToken: key, region: region)
            try check()
            let value = QoderSnapshot(usage: usage, updatedAt: Date())
            try QoderStore.save(value, id: id)
            attempt.succeed(Date()); try attempt.save(id)
            return value
        } catch {
            attempt.fail(Date()); try? attempt.save(id)
            if error is CancellationError { throw CancellationError() }
            throw (error as? QoderError) ?? QoderError.storage
        }
    }
}
