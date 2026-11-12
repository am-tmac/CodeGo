import Foundation

/// OpenCode Go's two published plans (opencode.ai/console/go, checked 2026-11-12).
///
/// This is a *local* display choice: the usage API does not report which plan an account is on,
/// so the plan is stored per account next to the app's other non-secret preferences. It never
/// changes how usage is fetched or parsed, and an account that predates the option keeps showing
/// `Go` exactly as before.
public enum OpenCodeGoPlan: String, CaseIterable, Codable, Identifiable, Sendable {
    case go
    case goPlus = "go-plus"
    public var id: String { rawValue }
    public var displayName: String { self == .go ? "Go" : "Go Plus" }
    public var monthlyPriceUSD: Int { self == .go ? 10 : 40 }
    /// No cents for whole-dollar prices, matching the console's own "$10 / month" wording.
    public var priceText: String { "US$\(monthlyPriceUSD)/月" }
    /// What a card shows: "Go · US$10/月".
    public var detailText: String { displayName + " · " + priceText }
    /// Unknown or legacy strings (including the old implicit "Go") fall back to Go.
    public static func stored(_ raw: String?) -> OpenCodeGoPlan {
        guard let raw, let value = OpenCodeGoPlan(rawValue: raw) else { return .go }
        return value
    }
}

/// Qoder has two independent deployments with different openapi hosts and account pages.
public enum QoderRegion: String, CaseIterable, Codable, Identifiable, Sendable {
    case china
    case global
    public var id: String { rawValue }
    public var displayName: String { self == .china ? "国内" : "国际" }
    public var baseURL: String { self == .china ? "https://openapi.qoder.com.cn" : "https://openapi.qoder.sh" }
    public var integrationsURL: String { self == .china ? "https://qoder.cn/account/integrations" : "https://qoder.com/account/integrations" }
}

/// Non-secret per-account preferences kept in one JSON file in the shared container (never the
/// Keychain). Keys are prefixed with the provider and contain the full account id, so two accounts
/// of the same provider never share a plan or a region.
public struct ProviderPreferenceStore: Sendable {
    public let url: URL?
    public init(url: URL?) { self.url = url }
    struct Record: Codable, Equatable {
        var openCodeGoPlan: String?
        var qoderRegion: String?
    }
    private func load() -> [String: Record] {
        guard let url, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Record].self, from: data)) ?? [:]
    }
    private func write(_ rows: [String: Record]) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(rows).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private static func key(_ provider: String, _ accountID: String) -> String { provider + ":" + accountID }

    public func openCodeGoPlan(accountID: String) -> OpenCodeGoPlan {
        OpenCodeGoPlan.stored(load()[Self.key("opencodego", accountID)]?.openCodeGoPlan)
    }
    public func setOpenCodeGoPlan(_ plan: OpenCodeGoPlan, accountID: String) throws {
        var rows = load()
        let key = Self.key("opencodego", accountID)
        var row = rows[key] ?? Record()
        row.openCodeGoPlan = plan.rawValue
        rows[key] = row
        try write(rows)
    }
    public func qoderRegion(accountID: String) -> QoderRegion {
        QoderRegion(rawValue: load()[Self.key("qoder", accountID)]?.qoderRegion ?? "") ?? .china
    }
    public func setQoderRegion(_ region: QoderRegion, accountID: String) throws {
        var rows = load()
        let key = Self.key("qoder", accountID)
        var row = rows[key] ?? Record()
        row.qoderRegion = region.rawValue
        rows[key] = row
        try write(rows)
    }
    /// Removes one account's preferences without touching any other account.
    public func remove(accountID: String) throws {
        var rows = load()
        for provider in ["opencodego", "qoder"] { rows.removeValue(forKey: Self.key(provider, accountID)) }
        try write(rows)
    }
}

public enum ProviderPreferences {
    /// Shared container location; nil when the container cannot be resolved (writes then fail
    /// loudly instead of silently using a private file the widget could not read).
    public static var store: ProviderPreferenceStore {
        ProviderPreferenceStore(url: try? SharedStorage.container().appendingPathComponent("provider-preferences.json"))
    }
    public static func openCodeGoPlan(accountID: String) -> OpenCodeGoPlan { store.openCodeGoPlan(accountID: accountID) }
    public static func setOpenCodeGoPlan(_ plan: OpenCodeGoPlan, accountID: String) throws {
        try store.setOpenCodeGoPlan(plan, accountID: accountID)
    }
    public static func qoderRegion(accountID: String) -> QoderRegion { store.qoderRegion(accountID: accountID) }
    public static func setQoderRegion(_ region: QoderRegion, accountID: String) throws {
        try store.setQoderRegion(region, accountID: accountID)
    }
    public static func remove(accountID: String) throws { try store.remove(accountID: accountID) }
}
