import Foundation

public struct CodexResetCredits: Codable, Equatable, Sendable {
    public struct Credit: Codable, Equatable, Sendable {
        // Status is intentionally open-ended, preserving future server values.
        let status: String?
        let expiresAt: Date?
        let grantedAt: Date?
        let redeemStartedAt: Date?
        let redeemedAt: Date?
    }
    let credits: [Credit]
    let availableCount: Int?
    let totalEarnedCount: Int?
    static func parse(_ data: Data) throws -> Self {
        let root = try ProviderParsing.object(data)
        func count(_ key: String) throws -> Int? {
            guard let raw = root[key], !(raw is NSNull) else { return nil }
            guard let n = ProviderParsing.number(raw), n >= 0, n < Double(Int.max), n.rounded() == n else { throw ServiceError.malformed }
            return Int(n)
        }
        guard let rows = root["credits"] as? [[String: Any]] else { throw ServiceError.malformed }
        return Self(credits: rows.map {
            Credit(status: $0["status"] as? String, expiresAt: ProviderParsing.date($0["expires_at"]),
                   grantedAt: ProviderParsing.date($0["granted_at"]), redeemStartedAt: ProviderParsing.date($0["redeem_started_at"]),
                   redeemedAt: ProviderParsing.date($0["redeemed_at"]))
        }, availableCount: try count("available_count"), totalEarnedCount: try count("total_earned_count"))
    }
    func usable(now: Date = Date()) -> [Credit] {
        credits.filter { $0.status == "available" && ($0.expiresAt == nil || $0.expiresAt! > now) }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }
    func expiryText(now: Date = Date()) -> String? {
        guard let expiry = usable(now: now).first?.expiresAt else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "M月d日 HH:mm"
        return "最早 \(formatter.string(from: expiry)) 过期"
    }
}

extension UsageResponse {
    func resetCreditsText(now: Date) -> String {
        (resetCreditDetails.map { $0.usable(now: now).count } ?? rateLimitResetCredits?.availableCount).map(String.init) ?? "—"
    }
}
