import Foundation

struct CommandCodeUsage: Codable, Equatable {
    let monthlyCredits: Decimal?
    let purchasedCredits: Decimal?
    let monthlyGrant: Decimal?
    let grantFromPlan: Bool
    let planID: String?
    let periodEnd: Date?
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    var planName: String? {
        guard let planID else { return nil }
        switch planID {
        case "individual-go", "individual-go-v1": return "Go"
        case "individual-goat": return "GOAT"
        case "individual-pro", "individual-pro-v1": return "Pro"
        case "individual-max": return "Max"
        case "individual-ultra": return "Ultra"
        default: return planID
        }
    }
    var monthly: UsageWindow? {
        guard let monthlyCredits, let monthlyGrant, monthlyGrant > 0 else { return nil }
        let remaining = NSDecimalNumber(decimal: monthlyCredits / monthlyGrant * 100).doubleValue
        return UsageWindow(usedPercent: min(100, max(0, 100 - remaining)), resetAt: periodEnd?.timeIntervalSince1970, limitWindowSeconds: nil)
    }
    static func parse(_ data: Data, subscription: Data? = nil) throws -> Self {
        let root: [String: Any]
        do { root = try ProviderParsing.object(data) } catch { throw CommandCodeError.malformed }
        guard let credits = root["credits"] as? [String: Any] else { throw CommandCodeError.malformed }
        let sub = subscription.flatMap { try? ProviderParsing.object($0) }?["data"] as? [String: Any]
        let plan = sub?["planId"] as? String
        let plans: [String: Decimal] = ["individual-go": 10, "individual-go-v1": 10, "individual-goat": 70,
                                       "individual-pro": 30, "individual-pro-v1": 80, "individual-max": 150, "individual-ultra": 300]
        let explicit = ProviderParsing.decimal(credits["monthlyCreditsGranted"])
        // A present but unreadable grant must not silently acquire a plan-table denominator.
        let fallback = credits["monthlyCreditsGranted"] == nil ? plan.flatMap { plans[$0] } : nil
        let windows = (root["windowLimits"] ?? credits["windowLimits"]) as? [String: Any]
        return Self(monthlyCredits: ProviderParsing.decimal(credits["monthlyCredits"]),
                    purchasedCredits: ProviderParsing.decimal(credits["purchasedCredits"]),
                    monthlyGrant: explicit ?? fallback, grantFromPlan: fallback != nil, planID: plan,
                    periodEnd: ProviderParsing.date(sub?["currentPeriodEnd"]),
                    fiveHour: ProviderParsing.window(windows?["fiveHour"] as? [String: Any]),
                    weekly: ProviderParsing.window(windows?["weekly"] as? [String: Any]))
    }
}

enum CommandCodeError: Error, LocalizedError {
    case invalidKey, unauthorized, rateLimited, malformed, network, storage, noSubscription, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "API Key 为空或包含无效字符"
        case .unauthorized: return "Command Code Key 无效或无权访问"
        case .rateLimited: return "Command Code 请求过于频繁，稍后重试"
        case .malformed: return "Command Code 用量响应格式异常"
        case .network: return "Command Code 网络失败，保留上次用量"
        case .storage: return "Command Code 钥匙串或缓存不可用，请解锁并检查签名"
        case .noSubscription: return "该 Key 没有有效的 Command Code 订阅"
        case .http(let code): return "Command Code 请求失败（HTTP \(code)）"
        }
    }
}
struct CommandCodeAPI {
    let transport: any HTTPTransport
    init(transport: any HTTPTransport = URLTransport()) { self.transport = transport }
    static func validatedKey(_ key: String) throws -> String {
        do { return try DeepSeekAPI.validatedKey(key) } catch { throw CommandCodeError.invalidKey }
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
        catch { throw CommandCodeError.network }
        try Task.checkCancellation()
        switch status {
        case 200: return data
        case 401, 403: throw CommandCodeError.unauthorized
        case 429: throw CommandCodeError.rateLimited
        default: throw CommandCodeError.http(status)
        }
    }
    func usage(key: String) async throws -> CommandCodeUsage {
        let data = try await get("https://api.commandcode.ai/alpha/billing/credits", key: key)
        let subscription = try? await get("https://api.commandcode.ai/alpha/billing/subscriptions", key: key)
        try Task.checkCancellation()
        return try CommandCodeUsage.parse(data, subscription: subscription)
    }
}
struct CommandCodeSnapshot: Codable, Equatable {
    let usage: CommandCodeUsage
    let updatedAt: Date
    func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > 1800 || now < updatedAt }
}

import Security
enum CommandCodeStore {
    static let service = "CodexUsage.CommandCode.api-key.v1"
    static func query(_ id: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let id { q[kSecAttrAccount as String] = id }
        if SharedStorage.isWidget, let group = SharedStorage.permittedGroup { q[kSecAttrAccessGroup as String] = group }
        return q
    }
    static func ids() throws -> [String] {
        guard !SharedStorage.isWidget else { return DashboardStore.accounts().filter { $0.provider == "commandcode" }.map(\.id) }
        var q = query(); q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw CommandCodeError.storage }
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
        guard !SharedStorage.isWidget else { throw CommandCodeError.storage }
        let value = try CommandCodeAPI.validatedKey(key)
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let q = query(id)
        var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(q.merging(attrs) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw CommandCodeError.storage }
    }
    static func key(_ id: String) throws -> String? {
        if SharedStorage.isWidget && !DashboardStore.canRefresh(id, provider: "commandcode") { throw CommandCodeError.storage }
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw CommandCodeError.storage }
        return value
    }
    static func snapshotURL(_ id: String) throws -> URL { try SharedStorage.snapshotURL("commandcode:" + id).appendingPathExtension("usage") }
    static func snapshot(_ id: String) -> CommandCodeSnapshot? {
        guard let url = try? snapshotURL(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CommandCodeSnapshot.self, from: data)
    }
    static func save(_ value: CommandCodeSnapshot, id: String) throws {
        try JSONEncoder().encode(value).write(to: snapshotURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func remove(_ id: String) throws {
        guard !SharedStorage.isWidget else { throw CommandCodeError.storage }
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CommandCodeError.storage }
        for url in [try snapshotURL(id), try WidgetRefreshAttempt.url(id)] where FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
actor CommandCodeService {
    static let shared = CommandCodeService()
    let api: CommandCodeAPI
    init(api: CommandCodeAPI = CommandCodeAPI()) { self.api = api }
    func install(key: String, replacing id: String? = nil) throws -> String {
        let id = id ?? "commandcode-" + UUID().uuidString
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        try CommandCodeStore.saveKey(key, id: id)
        let url = try CommandCodeStore.snapshotURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try WidgetRefreshAttempt().save(id)
        try DashboardStore.publish()
        return id
    }
    func remove(_ id: String) throws {
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        try CommandCodeStore.remove(id); try DashboardStore.publish()
    }
    func refresh(id: String, widget: Bool = SharedStorage.isWidget, permission: (() -> Bool)? = nil) async throws -> CommandCodeSnapshot {
        func check() throws {
            try Task.checkCancellation()
            if widget && !(permission?() ?? DashboardStore.canRefresh(id, provider: "commandcode")) { throw CommandCodeError.storage }
        }
        try check()
        let lease = try CredentialLease(account: id); defer { withExtendedLifetime(lease) {} }
        var attempt = WidgetRefreshAttempt.load(id)
        attempt.recoverInterrupted(Date())
        if widget && !attempt.allows(Date()) {
            try attempt.save(id)
            if let cache = CommandCodeStore.snapshot(id) { return cache }
            throw ServiceError.busy
        }
        attempt.begin(Date()); try attempt.save(id)
        do {
            try check()
            guard let key = try CommandCodeStore.key(id) else { throw CommandCodeError.unauthorized }
            let usage = try await api.usage(key: key)
            try check()
            let value = CommandCodeSnapshot(usage: usage, updatedAt: Date())
            try CommandCodeStore.save(value, id: id)
            attempt.succeed(Date()); try attempt.save(id)
            return value
        } catch {
            attempt.fail(Date()); try? attempt.save(id)
            if error is CancellationError { throw CancellationError() }
            throw (error as? CommandCodeError) ?? CommandCodeError.storage
        }
    }
}
