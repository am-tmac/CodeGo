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
    var rows: [ProviderCardData.Row] { snapshot?.rows ?? ProviderCardData.emptyRows(command: brand == .commandcode) }
    var body: some View {
        AppCard(title: brand.title, caption: "API Key 订阅额度", systemImage: "chart.bar", palette: palette,
                accessibilityContext: accountContext, expanded: $expanded,
                menu: AnyView(CardMenu(palette: palette, accountContext: accountContext) {
                    Button("刷新此账号", action: onRefresh).disabled(busy)
                    Button("更新 Key", action: onUpdateKey)
                    Button("移除账号", role: .destructive, action: onRemove)
                }), mark: AnyView(BrandMark(brand: brand, palette: palette))) {
            VStack(alignment: .leading, spacing: 10) {
                if expanded {
                    ForEach(rows) { row in
                        QuotaRow(label: row.label, remaining: row.window?.remaining, reset: row.reset ?? row.window?.resetDate, brand: brand, palette: palette)
                        if let money = row.money { Text("剩余 " + money).font(.footnote).foregroundStyle(palette.secondary) }
                    }
                    if let purchased = snapshot?.purchased { AppRow(label: "加购额度", value: purchased, palette: palette) }
                    if let note = snapshot?.grantNote { Text(note).font(.caption).foregroundStyle(palette.secondary) }
                    if brand == .opencodego {
                        Text("Go 套餐：5 小时 $12 / 每周 $30 / 每月 $60（套餐说明）").font(.caption).foregroundStyle(palette.secondary)
                    }
                    AppRow(label: "套餐", value: snapshot?.plan ?? "—", palette: palette)
                    AppRow(label: "更新时间", value: snapshot.map { RelativeTime.text($0.updatedAt) + ($0.stale ? " · 已过期" : "") } ?? "—", palette: palette)
                } else {
                    SummaryLine(window: QuotaSummary.tightest(rows.map { .init(label: $0.label, remaining: $0.window?.remaining, reset: $0.reset ?? $0.window?.resetDate) }), brand: brand, palette: palette)
                    if let money = rows.last?.money { Text("本月剩余 " + money).font(.footnote).foregroundStyle(palette.secondary) }
                    if let note = snapshot?.grantNote { Text(note).font(.caption).foregroundStyle(palette.secondary) }
                }
                CardRefreshFeedback(error: refreshError, updatedAt: snapshot?.updatedAt, palette: palette, busy: busy, onRetry: onRefresh)
            }
        }
    }
}
