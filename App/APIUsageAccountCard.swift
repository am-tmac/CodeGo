import SwiftUI

struct APIUsageAccountCard: View {
    let brand: ServiceBrand
    let snapshot: ProviderCardData?
    @Binding var expanded: Bool
    var palette: AppPalette
    let onRefresh: () -> Void
    let onUpdateKey: () -> Void
    let onRemove: () -> Void
    let busy: Bool
    var refreshError: String?
    let accountContext: String
    var rows: [ProviderCardData.Row] {
        snapshot?.rows ?? ProviderCardData.emptyRows(labels: emptyRowLabels)
    }
    /// Placeholder labels before the first snapshot, matching the provider's real rows.
    var emptyRowLabels: [String] {
        switch brand {
        case .openrouter: return ["剩余额度", "本 Key 限额", "免费档"]
        case .ollamacloud: return ["余额"]
        case .qoder: return ["每周", "每月"]
        case .commandcode: return ["5 小时", "每周", "本月额度"]
        default: return ["5 小时", "每周", "每月"]
        }
    }
    var caption: String {
        switch brand {
        case .openrouter: return "API Key 余额与限额"
        case .ollamacloud: return "API Key 余额"
        case .qoder: return "个人访问令牌额度"
        default: return "API Key 订阅额度"
        }
    }
    var body: some View {
        AppCard(title: brand.title, caption: caption, systemImage: "chart.bar", palette: palette,
                accessibilityContext: accountContext, expanded: $expanded,
                menu: AnyView(CardMenu(palette: palette, accountContext: accountContext) {
                    Button("刷新此账号", action: onRefresh).disabled(busy)
                    Button("更新 Key", action: onUpdateKey)
                    Button("移除账号", role: .destructive, action: onRemove)
                }), mark: AnyView(BrandMark(brand: brand, palette: palette))) {
            VStack(alignment: .leading, spacing: 10) {
                if expanded {
                    ForEach(rows) { row in
                        if row.window != nil {
                            QuotaRow(label: row.label, remaining: row.window?.remaining, reset: row.reset ?? row.window?.resetDate, brand: brand, palette: palette)
                        }
                        if let money = row.money {
                            Text((row.window == nil ? row.label + " " : row.moneyPrefix) + money).font(.footnote).foregroundStyle(palette.secondary)
                        }
                        if let detail = row.detail { AppRow(label: row.label, value: detail, palette: palette) }
                    }
                    if let purchased = snapshot?.purchased { AppRow(label: "加购额度", value: purchased, palette: palette) }
                    if let note = snapshot?.grantNote { Text(note).font(.caption).foregroundStyle(palette.secondary) }
                    if let plan = snapshot?.plan { AppRow(label: "套餐", value: plan, palette: palette) }
                    AppRow(label: "更新时间", value: snapshot.map { RelativeTime.text($0.updatedAt) + ($0.stale ? " · 已过期" : "") } ?? "—", palette: palette)
                } else {
                    SummaryLine(window: QuotaSummary.tightest(rows.map { .init(label: $0.label, remaining: $0.window?.remaining, reset: $0.reset ?? $0.window?.resetDate) }), brand: brand, palette: palette)
                    if let moneyRow = rows.first(where: { $0.money != nil }), let money = moneyRow.money {
                        Text((moneyRow.window == nil ? moneyRow.label + " " : moneyRow.moneyPrefix) + money).font(.footnote).foregroundStyle(palette.secondary)
                    }
                    if let detailRow = rows.first(where: { $0.detail != nil }), let detail = detailRow.detail {
                        Text(detailRow.label + " " + detail).font(.footnote).foregroundStyle(palette.secondary)
                    }
                    if let plan = snapshot?.plan { Text(plan).font(.footnote).foregroundStyle(palette.secondary) }
                    if let note = snapshot?.grantNote { Text(note).font(.caption).foregroundStyle(palette.secondary) }
                }
                CardRefreshFeedback(error: refreshError, updatedAt: snapshot?.updatedAt, palette: palette, busy: busy, onRetry: onRefresh)
            }
        }
    }
}
