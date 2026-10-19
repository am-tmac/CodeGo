import Foundation

/// Presentation values shared by App and widget. Missing windows keep their place as “—”.
struct ProviderCardData {
    struct Row: Identifiable {
        let label: String
        let window: UsageWindow?
        var money: String? = nil
        var reset: Date? = nil
        var id: String { label }
    }
    let rows: [Row]
    let updatedAt: Date
    let stale: Bool
    let plan: String?
    let grantNote: String?
    let purchased: String?
    init(_ snapshot: OpenCodeGoSnapshot) {
        let usage = snapshot.usage
        rows = [Row(label: "5 小时", window: usage.rolling), Row(label: "每周", window: usage.weekly),
                Row(label: "每月", window: usage.monthly)]
        updatedAt = snapshot.updatedAt; stale = snapshot.isStale()
        plan = "Go"; grantNote = nil; purchased = nil
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
    static func emptyRows(command: Bool) -> [Row] {
        [Row(label: "5 小时", window: nil), Row(label: "每周", window: nil), Row(label: command ? "本月额度" : "每月", window: nil)]
    }
}
