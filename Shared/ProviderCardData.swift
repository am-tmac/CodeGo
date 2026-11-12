import Foundation

/// Presentation values shared by App and widget. Missing windows keep their place as “—”.
struct ProviderCardData {
    struct Row: Identifiable {
        let label: String
        let window: UsageWindow?
        var money: String? = nil
        var reset: Date? = nil
        /// A short non-monetary reading (e.g. whether an OpenRouter key is on the free tier).
        var detail: String? = nil
        /// Prefix printed before `money` on cards and in the widget. Existing rows keep "剩余 ";
        /// a "limit" row leaves it empty because the value is already "remaining / limit".
        var moneyPrefix: String = "剩余 "
        var id: String { label }
    }
    let rows: [Row]
    let updatedAt: Date
    let stale: Bool
    let plan: String?
    let grantNote: String?
    let purchased: String?
    /// The OpenCode Go plan is a local per-account choice; the usage API does not report it.
    /// Defaults to Go so an account created before the option existed renders exactly as before.
    init(_ snapshot: OpenCodeGoSnapshot, plan: OpenCodeGoPlan = .go) {
        let usage = snapshot.usage
        rows = [Row(label: "5 小时", window: usage.rolling), Row(label: "每周", window: usage.weekly),
                Row(label: "每月", window: usage.monthly)]
        updatedAt = snapshot.updatedAt; stale = snapshot.isStale()
        self.plan = plan.detailText; grantNote = nil; purchased = nil
    }
    init(_ snapshot: CommandCodeSnapshot) {
        let usage = snapshot.usage
        let money = Money.text(usage.monthlyCredits, currency: "USD") + (usage.monthlyGrant.map { " / " + Money.text($0, currency: "USD") } ?? "")
        rows = [Row(label: "5 小时", window: usage.fiveHour), Row(label: "每周", window: usage.weekly),
                Row(label: "本月额度", window: usage.monthly, money: money, reset: usage.periodEnd)]
        updatedAt = snapshot.updatedAt; stale = snapshot.isStale(); plan = usage.planName
        grantNote = usage.grantFromPlan ? "按套餐 \(usage.planName ?? "—") 计" : nil
        purchased = usage.purchasedCredits.flatMap { $0 > 0 ? Money.text($0, currency: "USD") : nil }
    }
    init(_ snapshot: OpenRouterSnapshot) {
        let usage = snapshot.usage
        let limitMoney: String? = {
            guard let limit = usage.key.limit, let remaining = usage.key.limitRemaining else { return nil }
            return Money.text(remaining, currency: "USD") + " / " + Money.text(limit, currency: "USD")
        }()
        rows = [Row(label: "剩余额度", window: nil, money: usage.remainingCredits.map { Money.text($0, currency: "USD") }),
                Row(label: "本 Key 限额", window: usage.limitWindow, money: limitMoney, moneyPrefix: ""),
                Row(label: "免费档", window: nil, detail: usage.key.isFreeTier.map { $0 ? "是" : "否" } ?? "—")]
        updatedAt = snapshot.updatedAt; stale = snapshot.isStale()
        plan = nil
        if let label = usage.key.label { grantNote = "Key：\(label)" } else if usage.key.isProvisioningKey == true { grantNote = "Provisioning Key" } else { grantNote = nil }
        purchased = nil
    }
    init(_ snapshot: OllamaCloudSnapshot) {
        let usage = snapshot.usage
        rows = [Row(label: "余额", window: usage.window, money: usage.moneyText, reset: usage.resetAt)]
        updatedAt = snapshot.updatedAt; stale = snapshot.isStale()
        plan = nil; grantNote = nil; purchased = nil
    }
    init(_ snapshot: QoderSnapshot) {
        let usage = snapshot.usage
        rows = [Row(label: "每周", window: usage.weekly,
                    money: QoderUsage.moneyText(used: usage.weeklyUsed, limit: usage.weeklyLimit)),
                Row(label: "每月", window: usage.monthly,
                    money: QoderUsage.moneyText(used: usage.monthlyUsed, limit: usage.monthlyLimit))]
        updatedAt = snapshot.updatedAt; stale = snapshot.isStale()
        plan = usage.planName; grantNote = nil
        purchased = usage.addOn.flatMap { $0 > 0 ? Money.text($0, currency: "USD") : nil }
    }
    static func emptyRows(command: Bool) -> [Row] {
        [Row(label: "5 小时", window: nil), Row(label: "每周", window: nil), Row(label: command ? "本月额度" : "每月", window: nil)]
    }
    /// Placeholder rows before the first snapshot; labels match the provider's real rows.
    static func emptyRows(labels: [String]) -> [Row] { labels.map { Row(label: $0, window: nil) } }
}
