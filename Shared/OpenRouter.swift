import Foundation

/// OpenRouter's `/api/v1/key` document. Every amount is optional: an unlimited key reports
/// `limit: null`, and a brand-new organisation may omit credits entirely. A missing number is
/// never rendered as zero.
struct OpenRouterKeyInfo: Codable, Equatable {
    let label: String?
    let limit: Decimal?
    let usage: Decimal?
    let limitRemaining: Decimal?
    let isFreeTier: Bool?
    let isProvisioningKey: Bool?
    static func parse(_ data: Data) throws -> Self {
        let root: [String: Any]
        do { root = try ProviderParsing.object(data) } catch { throw OpenRouterError.malformed }
        guard let object = root["data"] as? [String: Any] else { throw OpenRouterError.malformed }
        let label = object["label"] as? String
        return Self(label: label?.isEmpty == true ? nil : label,
                    limit: ProviderParsing.decimal(ProviderParsing.first(object, ["limit"])),
                    usage: ProviderParsing.decimal(ProviderParsing.first(object, ["usage"])),
                    limitRemaining: ProviderParsing.decimal(ProviderParsing.first(object, ["limit_remaining", "limitRemaining"])),
                    isFreeTier: ProviderParsing.flag(ProviderParsing.first(object, ["is_free_tier", "isFreeTier"])),
                    isProvisioningKey: ProviderParsing.flag(ProviderParsing.first(object, ["is_provisioning_key", "isProvisioningKey"])))
    }
}

struct OpenRouterCredits: Codable, Equatable {
    let totalCredits: Decimal?
    let totalUsage: Decimal?
    /// Credits purchased minus credits used. Nil unless both numbers were reported.
    var remaining: Decimal? {
        guard let totalCredits, let totalUsage else { return nil }
        return max(0, totalCredits - totalUsage)
    }
    static func parse(_ data: Data) throws -> Self {
        let root: [String: Any]
        do { root = try ProviderParsing.object(data) } catch { throw OpenRouterError.malformed }
        guard let object = root["data"] as? [String: Any] else { throw OpenRouterError.malformed }
        return Self(totalCredits: ProviderParsing.decimal(ProviderParsing.first(object, ["total_credits", "totalCredits"])),
                    totalUsage: ProviderParsing.decimal(ProviderParsing.first(object, ["total_usage", "totalUsage"])))
    }
}

struct OpenRouterUsage: Codable, Equatable {
    let key: OpenRouterKeyInfo
    let credits: OpenRouterCredits?
    /// Credits first; the key's own remaining limit is the fallback when no credits document was
    /// available. Nil when neither reported a usable number.
    var remainingCredits: Decimal? { credits?.remaining ?? key.limitRemaining }
    /// Remaining share of this key's own spend limit (`limit_remaining / limit`). An unlimited key
    /// has no denominator, so there is no window — not 100 %.
    var limitWindow: UsageWindow? {
        guard let limit = key.limit, let remaining = key.limitRemaining, limit > 0 else { return nil }
        let used = max(0, limit - remaining)
        let percent = NSDecimalNumber(decimal: used / limit * 100).doubleValue
        return UsageWindow(usedPercent: min(100, max(0, percent)), resetAt: nil, limitWindowSeconds: nil)
    }
    static func parse(key: Data, credits: Data?) throws -> Self {
        Self(key: try OpenRouterKeyInfo.parse(key), credits: credits.flatMap { try? OpenRouterCredits.parse($0) })
    }
}

enum OpenRouterError: Error, LocalizedError, Equatable {
    case invalidKey, unauthorized, rateLimited, malformed, network, storage, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "API Key 为空或包含无效字符"
        case .unauthorized: return "OpenRouter Key 无效或无权访问"
        case .rateLimited: return "OpenRouter 请求过于频繁，稍后重试"
        case .malformed: return "OpenRouter 用量响应格式异常"
        case .network: return "OpenRouter 网络失败，保留上次用量"
        case .storage: return "OpenRouter 钥匙串或缓存不可用，请解锁并检查签名"
        case .http(let code): return "OpenRouter 请求失败（HTTP \(code)）"
        }
    }
}

struct OpenRouterAPI {
    let transport: any HTTPTransport
    init(transport: any HTTPTransport = URLTransport()) { self.transport = transport }
    static func validatedKey(_ key: String) throws -> String {
        do { return try DeepSeekAPI.validatedKey(key) } catch { throw OpenRouterError.invalidKey }
    }
    private func get(_ path: String, key: String) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://openrouter.ai" + path)!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(try Self.validatedKey(key))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data; let status: Int
        do { (data, status) = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw OpenRouterError.network }
        try Task.checkCancellation()
        switch status {
        case 200: return data
        case 401, 403: throw OpenRouterError.unauthorized
        case 429: throw OpenRouterError.rateLimited
        default: throw OpenRouterError.http(status)
        }
    }
    /// `/key` is authoritative for the credential; `/credits` is supplementary, so a failure or
    /// an older organisation without credits still shows the key's own limit.
    func usage(key: String) async throws -> OpenRouterUsage {
        let keyData = try await get("/api/v1/key", key: key)
        let credits = try? await get("/api/v1/credits", key: key)
        try Task.checkCancellation()
        return try OpenRouterUsage.parse(key: keyData, credits: credits)
    }
}

struct OpenRouterSnapshot: Codable, Equatable {
    let usage: OpenRouterUsage
    let updatedAt: Date
    func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > 1800 || now < updatedAt }
}

import Security
enum OpenRouterStore {
    static let service = "CodexUsage.OpenRouter.api-key.v1"
    static func query(_ id: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let id { q[kSecAttrAccount as String] = id }
        if SharedStorage.isWidget, let group = SharedStorage.permittedGroup { q[kSecAttrAccessGroup as String] = group }
        return q
    }
    static func ids() throws -> [String] {
        guard !SharedStorage.isWidget else { return DashboardStore.accounts().filter { $0.provider == "openrouter" }.map(\.id) }
        var q = query(); q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw OpenRouterError.storage }
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
        guard !SharedStorage.isWidget else { throw OpenRouterError.storage }
        let value = try OpenRouterAPI.validatedKey(key)
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let q = query(id)
        var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(q.merging(attrs) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw OpenRouterError.storage }
    }
    static func key(_ id: String) throws -> String? {
        if SharedStorage.isWidget && !DashboardStore.canRefresh(id, provider: "openrouter") { throw OpenRouterError.storage }
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw OpenRouterError.storage }
        return value
    }
    static func snapshotURL(_ id: String) throws -> URL { try SharedStorage.snapshotURL("openrouter:" + id).appendingPathExtension("usage") }
    static func snapshot(_ id: String) -> OpenRouterSnapshot? {
        guard let url = try? snapshotURL(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OpenRouterSnapshot.self, from: data)
    }
    static func save(_ value: OpenRouterSnapshot, id: String) throws {
        try JSONEncoder().encode(value).write(to: snapshotURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func remove(_ id: String) throws {
        guard !SharedStorage.isWidget else { throw OpenRouterError.storage }
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw OpenRouterError.storage }
        for url in [try snapshotURL(id), try WidgetRefreshAttempt.url(id)] where FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try? ProviderPreferences.remove(accountID: id)
    }
}

actor OpenRouterService {
    static let shared = OpenRouterService()
    let api: OpenRouterAPI
    init(api: OpenRouterAPI = OpenRouterAPI()) { self.api = api }
    func install(key: String, replacing id: String? = nil) throws -> String {
        let id = id ?? "openrouter-" + UUID().uuidString
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        try OpenRouterStore.saveKey(key, id: id)
        let url = try OpenRouterStore.snapshotURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try WidgetRefreshAttempt().save(id)
        try DashboardStore.publish()
        return id
    }
    func remove(_ id: String) throws {
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        try OpenRouterStore.remove(id); try DashboardStore.publish()
    }
    func refresh(id: String, widget: Bool = SharedStorage.isWidget, permission: (() -> Bool)? = nil) async throws -> OpenRouterSnapshot {
        func check() throws {
            try Task.checkCancellation()
            if widget && !(permission?() ?? DashboardStore.canRefresh(id, provider: "openrouter")) { throw OpenRouterError.storage }
        }
        try check()
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        var attempt = WidgetRefreshAttempt.load(id)
        attempt.recoverInterrupted(Date())
        if widget && !attempt.allows(Date()) {
            try attempt.save(id)
            if let cache = OpenRouterStore.snapshot(id) { return cache }
            throw ServiceError.busy
        }
        attempt.begin(Date()); try attempt.save(id)
        do {
            try check()
            guard let key = try OpenRouterStore.key(id) else { throw OpenRouterError.unauthorized }
            let usage = try await api.usage(key: key)
            try check()
            let value = OpenRouterSnapshot(usage: usage, updatedAt: Date())
            try OpenRouterStore.save(value, id: id)
            attempt.succeed(Date()); try attempt.save(id)
            return value
        } catch {
            attempt.fail(Date()); try? attempt.save(id)
            if error is CancellationError { throw CancellationError() }
            throw (error as? OpenRouterError) ?? OpenRouterError.storage
        }
    }
}
