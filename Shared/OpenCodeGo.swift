import Foundation

struct OpenCodeGoUsage: Codable, Equatable {
    let rolling: UsageWindow?
    let weekly: UsageWindow?
    let monthly: UsageWindow?
    let renewAt: Date?
    static func parse(_ data: Data, now: Date = Date()) throws -> Self {
        let root: [String: Any]
        do { root = try ProviderParsing.object(data) } catch { throw OpenCodeGoError.malformed }
        guard let usage = root["usage"] as? [String: Any],
              let rolling = (usage["rolling"] ?? usage["rollingUsage"]) as? [String: Any] else { throw OpenCodeGoError.noSubscription }
        return Self(rolling: ProviderParsing.window(rolling, now: now),
                    weekly: ProviderParsing.window((usage["weekly"] ?? usage["weeklyUsage"]) as? [String: Any], now: now),
                    monthly: ProviderParsing.window((usage["monthly"] ?? usage["monthlyUsage"]) as? [String: Any], now: now),
                    renewAt: ProviderParsing.date(usage["renewAt"] ?? root["renewAt"]))
    }
}

enum OpenCodeGoError: Error, LocalizedError {
    case invalidKey, unauthorized, rateLimited, malformed, network, storage, noSubscription, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "API Key 为空或包含无效字符"
        case .unauthorized: return "OpenCode Go Key 无效或无权访问"
        case .rateLimited: return "OpenCode Go 请求过于频繁，稍后重试"
        case .malformed: return "OpenCode Go 用量响应格式异常"
        case .network: return "OpenCode Go 网络失败，保留上次用量"
        case .storage: return "OpenCode Go 钥匙串或缓存不可用，请解锁并检查签名"
        case .noSubscription: return "该 Key 没有有效的 OpenCode Go 订阅"
        case .http(let code): return "OpenCode Go 请求失败（HTTP \(code)）"
        }
    }
}
struct OpenCodeGoAPI {
    let transport: any HTTPTransport
    init(transport: any HTTPTransport = URLTransport()) { self.transport = transport }
    static func validatedKey(_ key: String) throws -> String {
        do { return try DeepSeekAPI.validatedKey(key) } catch { throw OpenCodeGoError.invalidKey }
    }
    private func get(_ url: String, key: String) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(try Self.validatedKey(key))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data; let status: Int
        do { (data, status) = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw OpenCodeGoError.network }
        try Task.checkCancellation()
        switch status {
        case 200: return data
        case 401, 403: throw OpenCodeGoError.unauthorized
        case 429: throw OpenCodeGoError.rateLimited
        default: throw OpenCodeGoError.http(status)
        }
    }
    func usage(key: String) async throws -> OpenCodeGoUsage {
        let data = try await get("https://opencode.ai/zen/go/v1/usage", key: key)
        return try OpenCodeGoUsage.parse(data)
    }
}
struct OpenCodeGoSnapshot: Codable, Equatable {
    let usage: OpenCodeGoUsage
    let updatedAt: Date
    func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > 1800 || now < updatedAt }
}

import Security
enum OpenCodeGoStore {
    static let service = "CodexUsage.OpenCodeGo.api-key.v1"
    static func query(_ id: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let id { q[kSecAttrAccount as String] = id }
        if SharedStorage.isWidget, let group = SharedStorage.permittedGroup { q[kSecAttrAccessGroup as String] = group }
        return q
    }
    static func ids() throws -> [String] {
        guard !SharedStorage.isWidget else { return DashboardStore.accounts().filter { $0.provider == "opencodego" }.map(\.id) }
        var q = query(); q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw OpenCodeGoError.storage }
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
        guard !SharedStorage.isWidget else { throw OpenCodeGoError.storage }
        let value = try OpenCodeGoAPI.validatedKey(key)
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let q = query(id)
        var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(q.merging(attrs) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw OpenCodeGoError.storage }
    }
    static func key(_ id: String) throws -> String? {
        if SharedStorage.isWidget && !DashboardStore.canRefresh(id, provider: "opencodego") { throw OpenCodeGoError.storage }
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw OpenCodeGoError.storage }
        return value
    }
    static func snapshotURL(_ id: String) throws -> URL { try SharedStorage.snapshotURL("opencodego:" + id).appendingPathExtension("usage") }
    static func snapshot(_ id: String) -> OpenCodeGoSnapshot? {
        guard let url = try? snapshotURL(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OpenCodeGoSnapshot.self, from: data)
    }
    static func save(_ value: OpenCodeGoSnapshot, id: String) throws {
        try JSONEncoder().encode(value).write(to: snapshotURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func remove(_ id: String) throws {
        guard !SharedStorage.isWidget else { throw OpenCodeGoError.storage }
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw OpenCodeGoError.storage }
        for url in [try snapshotURL(id), try WidgetRefreshAttempt.url(id)] where FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
actor OpenCodeGoService {
    static let shared = OpenCodeGoService()
    let api: OpenCodeGoAPI
    init(api: OpenCodeGoAPI = OpenCodeGoAPI()) { self.api = api }
    func install(key: String, replacing id: String? = nil) throws -> String {
        let id = id ?? "opencodego-" + UUID().uuidString
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        try OpenCodeGoStore.saveKey(key, id: id)
        let url = try OpenCodeGoStore.snapshotURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try WidgetRefreshAttempt().save(id)
        try DashboardStore.publish()
        return id
    }
    func remove(_ id: String) throws {
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        try OpenCodeGoStore.remove(id); try DashboardStore.publish()
    }
    func refresh(id: String, widget: Bool = SharedStorage.isWidget, permission: (() -> Bool)? = nil) async throws -> OpenCodeGoSnapshot {
        func check() throws {
            try Task.checkCancellation()
            if widget && !(permission?() ?? DashboardStore.canRefresh(id, provider: "opencodego")) { throw OpenCodeGoError.storage }
        }
        try check()
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        var attempt = WidgetRefreshAttempt.load(id)
        attempt.recoverInterrupted(Date())
        if widget && !attempt.allows(Date()) {
            try attempt.save(id)
            if let cache = OpenCodeGoStore.snapshot(id) { return cache }
            throw ServiceError.busy
        }
        attempt.begin(Date()); try attempt.save(id)
        do {
            try check()
            guard let key = try OpenCodeGoStore.key(id) else { throw OpenCodeGoError.unauthorized }
            let usage = try await api.usage(key: key)
            try check()
            let value = OpenCodeGoSnapshot(usage: usage, updatedAt: Date())
            try OpenCodeGoStore.save(value, id: id)
            attempt.succeed(Date()); try attempt.save(id)
            return value
        } catch {
            attempt.fail(Date()); try? attempt.save(id)
            if error is CancellationError { throw CancellationError() }
            throw (error as? OpenCodeGoError) ?? OpenCodeGoError.storage
        }
    }
}
