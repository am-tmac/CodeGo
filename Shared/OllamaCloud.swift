import Foundation

/// Ollama Cloud's `/api/balance` has no public schema (the endpoint is real: it answers
/// `401 {"error":"invalid credentials"}` for a bad bearer). Parsing is therefore deliberately
/// tolerant — several names for the same number, nested containers, numbers as strings — and
/// refuses to invent a value: if no usable number is present the response is `malformed` and the
/// UI says plainly that this account's balance format is unrecognised.
struct OllamaCloudUsage: Codable, Equatable {
    /// Used share of the quota, 0–100, as the API reported it.
    let percent: Double?
    let used: Decimal?
    let limit: Decimal?
    let resetAt: Date?
    let window: UsageWindow?
    /// Money form of the same reading: "US$3.00 / US$12.00" when both numbers exist.
    var moneyText: String? {
        guard let used, let limit else { return nil }
        return Money.text(used, currency: "USD") + " / " + Money.text(limit, currency: "USD")
    }
    static func parse(_ data: Data, now: Date = Date()) throws -> Self {
        let root: [String: Any]
        do { root = try ProviderParsing.object(data) } catch { throw OllamaCloudError.malformed }
        // Accept the numbers at the top level or inside one of the usual envelopes.
        var object = root
        for key in ["data", "balance", "usage", "quota"] {
            if let nested = root[key] as? [String: Any] { object = nested; break }
        }
        let used = ProviderParsing.decimal(ProviderParsing.first(object, ["used", "usage", "consumed"]))
        let limit = ProviderParsing.decimal(ProviderParsing.first(object, ["limit", "total", "quota", "max", "cap"]))
        let explicitPercent = ProviderParsing.number(ProviderParsing.first(object, ["percent", "usedPercent", "usagePercent"]))
        var percent = explicitPercent
        if percent == nil, let used, let limit, limit > 0 {
            percent = NSDecimalNumber(decimal: used / limit * 100).doubleValue
        }
        guard let percent, percent.isFinite else { throw OllamaCloudError.malformed }
        let reset: Date?
        if let seconds = ProviderParsing.number(ProviderParsing.first(object, ["resetInSec", "resetInSeconds", "resetSeconds"])) {
            reset = now.addingTimeInterval(seconds)
        } else {
            reset = ProviderParsing.date(ProviderParsing.first(object, ["resetAt", "resetsAt", "reset_at", "resets_at"]))
        }
        return Self(percent: percent, used: used, limit: limit, resetAt: reset,
                    window: UsageWindow(usedPercent: min(100, max(0, percent)), resetAt: reset?.timeIntervalSince1970, limitWindowSeconds: nil))
    }
}

enum OllamaCloudError: Error, LocalizedError, Equatable {
    case invalidKey, unauthorized, rateLimited, malformed, network, storage, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "API Key 为空或包含无效字符"
        case .unauthorized: return "Ollama Cloud Key 无效或无权访问"
        case .rateLimited: return "Ollama Cloud 请求过于频繁，稍后重试"
        case .malformed: return "无法识别该账号的余额格式"
        case .network: return "Ollama Cloud 网络失败，保留上次用量"
        case .storage: return "Ollama Cloud 钥匙串或缓存不可用，请解锁并检查签名"
        case .http(let code): return "Ollama Cloud 请求失败（HTTP \(code)）"
        }
    }
}

struct OllamaCloudAPI {
    let transport: any HTTPTransport
    init(transport: any HTTPTransport = URLTransport()) { self.transport = transport }
    static func validatedKey(_ key: String) throws -> String {
        do { return try DeepSeekAPI.validatedKey(key) } catch { throw OllamaCloudError.invalidKey }
    }
    func usage(key: String) async throws -> OllamaCloudUsage {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://ollama.com/api/balance")!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(try Self.validatedKey(key))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data; let status: Int
        do { (data, status) = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw OllamaCloudError.network }
        try Task.checkCancellation()
        switch status {
        case 200: return try OllamaCloudUsage.parse(data)
        case 401, 403: throw OllamaCloudError.unauthorized
        case 429: throw OllamaCloudError.rateLimited
        default: throw OllamaCloudError.http(status)
        }
    }
}

struct OllamaCloudSnapshot: Codable, Equatable {
    let usage: OllamaCloudUsage
    let updatedAt: Date
    func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > 1800 || now < updatedAt }
}

import Security
enum OllamaCloudStore {
    static let service = "CodexUsage.OllamaCloud.api-key.v1"
    static func query(_ id: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let id { q[kSecAttrAccount as String] = id }
        if SharedStorage.isWidget, let group = SharedStorage.permittedGroup { q[kSecAttrAccessGroup as String] = group }
        return q
    }
    static func ids() throws -> [String] {
        guard !SharedStorage.isWidget else { return DashboardStore.accounts().filter { $0.provider == "ollamacloud" }.map(\.id) }
        var q = query(); q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw OllamaCloudError.storage }
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
        guard !SharedStorage.isWidget else { throw OllamaCloudError.storage }
        let value = try OllamaCloudAPI.validatedKey(key)
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let q = query(id)
        var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(q.merging(attrs) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw OllamaCloudError.storage }
    }
    static func key(_ id: String) throws -> String? {
        if SharedStorage.isWidget && !DashboardStore.canRefresh(id, provider: "ollamacloud") { throw OllamaCloudError.storage }
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw OllamaCloudError.storage }
        return value
    }
    static func snapshotURL(_ id: String) throws -> URL { try SharedStorage.snapshotURL("ollamacloud:" + id).appendingPathExtension("usage") }
    static func snapshot(_ id: String) -> OllamaCloudSnapshot? {
        guard let url = try? snapshotURL(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OllamaCloudSnapshot.self, from: data)
    }
    static func save(_ value: OllamaCloudSnapshot, id: String) throws {
        try JSONEncoder().encode(value).write(to: snapshotURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func remove(_ id: String) throws {
        guard !SharedStorage.isWidget else { throw OllamaCloudError.storage }
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw OllamaCloudError.storage }
        for url in [try snapshotURL(id), try WidgetRefreshAttempt.url(id)] where FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try? ProviderPreferences.remove(accountID: id)
    }
}

actor OllamaCloudService {
    static let shared = OllamaCloudService()
    let api: OllamaCloudAPI
    init(api: OllamaCloudAPI = OllamaCloudAPI()) { self.api = api }
    func install(key: String, replacing id: String? = nil) throws -> String {
        let id = id ?? "ollamacloud-" + UUID().uuidString
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        try OllamaCloudStore.saveKey(key, id: id)
        let url = try OllamaCloudStore.snapshotURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try WidgetRefreshAttempt().save(id)
        try DashboardStore.publish()
        return id
    }
    func remove(_ id: String) throws {
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        try OllamaCloudStore.remove(id); try DashboardStore.publish()
    }
    func refresh(id: String, widget: Bool = SharedStorage.isWidget, permission: (() -> Bool)? = nil) async throws -> OllamaCloudSnapshot {
        func check() throws {
            try Task.checkCancellation()
            if widget && !(permission?() ?? DashboardStore.canRefresh(id, provider: "ollamacloud")) { throw OllamaCloudError.storage }
        }
        try check()
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        var attempt = WidgetRefreshAttempt.load(id)
        attempt.recoverInterrupted(Date())
        if widget && !attempt.allows(Date()) {
            try attempt.save(id)
            if let cache = OllamaCloudStore.snapshot(id) { return cache }
            throw ServiceError.busy
        }
        attempt.begin(Date()); try attempt.save(id)
        do {
            try check()
            guard let key = try OllamaCloudStore.key(id) else { throw OllamaCloudError.unauthorized }
            let usage = try await api.usage(key: key)
            try check()
            let value = OllamaCloudSnapshot(usage: usage, updatedAt: Date())
            try OllamaCloudStore.save(value, id: id)
            attempt.succeed(Date()); try attempt.save(id)
            return value
        } catch {
            attempt.fail(Date()); try? attempt.save(id)
            if error is CancellationError { throw CancellationError() }
            throw (error as? OllamaCloudError) ?? OllamaCloudError.storage
        }
    }
}
