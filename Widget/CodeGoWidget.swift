#if CODEX_WIDGET || (DEBUG && CODEGO_WIDGET_RENDER_TESTS)
import SwiftUI
import WidgetKit
import AppIntents
#if CODEGO_WIDGET_RENDER_TESTS
@testable import CodeGo
#endif

struct DashboardEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "服务 / 账号"
    static var defaultQuery = DashboardQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}
struct DashboardQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DashboardEntity] {
        // Keep deleted identifiers resolvable as empty selections; never silently switch accounts.
        identifiers.map { id in DashboardEntity(id: id, title: DashboardStore.accounts().first(where: { $0.id == id })?.title ?? "账号已移除") }
    }
    func suggestedEntities() async throws -> [DashboardEntity] {
        DashboardStore.accounts().map { DashboardEntity(id: $0.id, title: $0.title) }
    }
}
struct DashboardConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "服务与独立账号"
    static var description = IntentDescription("小号显示左栏；中号显示两栏。每栏独立选择 Codex、Claude 或其他服务。")
    @Parameter(title: "左栏 / 小号账号") var leftAccount: DashboardEntity?
    @Parameter(title: "右栏账号") var rightAccount: DashboardEntity?
}
struct DashboardColumn {
    let id: String?
    let provider: String
    let title: String
    let usage: UsageSnapshot?
    let balance: DeepSeekSnapshot?
    var openCodeGo: OpenCodeGoSnapshot? = nil
    var commandCode: CommandCodeSnapshot? = nil
    var openRouter: OpenRouterSnapshot? = nil
    var ollamaCloud: OllamaCloudSnapshot? = nil
    var qoder: QoderSnapshot? = nil
    let antigravity: AntigravitySnapshot?
    let claude: ClaudeSnapshot?
    let tokensci: TokensCISnapshot?
    let canRefresh: Bool
    let failed: Bool
    let refreshing: Bool
    var needsAppRefresh = false
    var updatedAt: Date? {
        switch provider {
        case "opencodego": return openCodeGo?.updatedAt
        case "commandcode": return commandCode?.updatedAt
        case "openrouter": return openRouter?.updatedAt
        case "ollamacloud": return ollamaCloud?.updatedAt
        case "qoder": return qoder?.updatedAt
        case "deepseek": return balance?.updatedAt
        case "antigravity": return antigravity?.updatedAt
        case "claude": return claude?.updatedAt
        case "tokensci": return tokensci?.dataUpdatedAt
        default: return usage?.updatedAt
        }
    }
    static func load(_ id: String?, defaultProvider: String = "codex", accounts: [DashboardAccount] = DashboardStore.accounts()) -> Self {
        let row = accounts.first { $0.id == id }
        let provider = row?.provider ?? defaultProvider
        let attempt = id.map { WidgetRefreshAttempt.load(WidgetRefreshAttempt.attemptID($0, provider: provider)) }
        let needsAppRefresh = provider == "claude" && attempt?.requiresAppRefresh == true
        // Only the slot's own provider cache is read; the others would always be misses.
        return Self(id: id, provider: provider, title: row?.title ?? "未选择 / 账号已移除",
                    usage: provider == "codex" ? id.flatMap { SharedStorage.snapshot(account: $0) } : nil,
                    balance: provider == "deepseek" ? id.flatMap { DeepSeekStore.snapshot($0) } : nil,
                    openCodeGo: provider == "opencodego" ? id.flatMap { OpenCodeGoStore.snapshot($0) } : nil,
                    commandCode: provider == "commandcode" ? id.flatMap { CommandCodeStore.snapshot($0) } : nil,
                    openRouter: provider == "openrouter" ? id.flatMap { OpenRouterStore.snapshot($0) } : nil,
                    ollamaCloud: provider == "ollamacloud" ? id.flatMap { OllamaCloudStore.snapshot($0) } : nil,
                    qoder: provider == "qoder" ? id.flatMap { QoderStore.snapshot($0) } : nil,
                    antigravity: provider == "antigravity" && id != nil ? AntigravityStore.snapshot() : nil,
                    claude: provider == "claude" ? ClaudeStore.snapshot() : nil,
                    tokensci: provider == "tokensci" ? id.flatMap { TokensCIStore.snapshot($0) } : nil,
                    // Every provider with a credential in the permitted group can refresh here,
                    // including tokens.ci (build 50). Claude still waits for the App when only
                    // the App may rotate its token.
                    canRefresh: !needsAppRefresh && (id.map { DashboardStore.canRefreshAnyProvider($0) } ?? false),
                    failed: attempt?.failed ?? false, refreshing: attempt?.isRefreshing(at: Date()) ?? false,
                    needsAppRefresh: needsAppRefresh)
    }
}
struct UsageEntry: TimelineEntry {
    let date: Date
    let left: DashboardColumn
    let right: DashboardColumn
    var theme: ThemePreference = .system
    var display: UsageDisplay = .remaining
}
struct UsageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), left: .load(nil), right: .load(nil, defaultProvider: "deepseek"))
    }
    func entry(_ configuration: DashboardConfiguration) -> UsageEntry {
        let accounts = DashboardStore.accounts()
        let leftID = configuration.leftAccount?.id ?? SharedStorage.selectedAccount() ?? accounts.first?.id
        let rightID = configuration.rightAccount?.id ?? accounts.first(where: { $0.id != leftID && $0.provider == "deepseek" })?.id ?? accounts.first(where: { $0.id != leftID })?.id
        return UsageEntry(date: Date(), left: .load(leftID, accounts: accounts), right: .load(rightID, defaultProvider: "deepseek", accounts: accounts),
                          theme: ThemePreference.load(), display: UsageDisplay.load())
    }
    func snapshot(for configuration: DashboardConfiguration, in context: Context) async -> UsageEntry {
        SharedStorage.recordWidgetDiagnostics()
        return entry(configuration)
    }
    func timeline(for configuration: DashboardConfiguration, in context: Context) async -> Timeline<UsageEntry> {
        SharedStorage.recordWidgetDiagnostics()
        let cached = entry(configuration)
        let columns = context.family == .systemMedium ? [cached.left, cached.right] : [cached.left]
        // Both columns are refreshed through one coordinator: authorization, the persisted
        // throttle/backoff and cache freshness are decided once, then each permitted account is
        // fetched concurrently with `widget: true`. Failures keep the last good cache.
        let slots = columns.compactMap { column in
            column.id.map { WidgetRefreshSlot(id: $0, provider: column.provider, updatedAt: column.updatedAt) }
        }
        let refreshed = await WidgetRefreshCoordinator().perform(slots, respectFreshness: true)
        // WidgetKit may throttle timelines; this path never throws, never shows an alert, and
        // simply re-renders the cached entry when nothing could be fetched.
        return Timeline(entries: [refreshed.isEmpty ? cached : entry(configuration)], policy: .after(Date().addingTimeInterval(900)))
    }
}
struct DashboardWidgetView: View {
#if CODEGO_WIDGET_RENDER_TESTS
    // WidgetKit owns a read-only environment value. Simulator render tests supply that family.
    var family: WidgetFamily = .systemSmall
#else
    @Environment(\.widgetFamily) var family
#endif
    @Environment(\.colorScheme) var scheme
    let entry: UsageEntry
    var palette: ThemePalette { .widget(scheme: entry.theme == .light ? .light : (entry.theme == .dark ? .dark : scheme)) }
    /// DeepSeek keeps its own card (stacked on the small family, compact on the medium one);
    /// the Nowdex-style readings card is for the usage/subscription providers only.
    @ViewBuilder func deepSeekCard(_ value: DashboardColumn) -> some View {
        if family == .systemSmall {
            DeepSeekStackedCardView(snapshot: value.balance, failed: value.failed, cacheOnly: !value.canRefresh)
        } else {
            DeepSeekCompactView(snapshot: value.balance, label: value.title, failed: value.failed,
                                cacheOnly: !value.canRefresh, palette: palette)
        }
    }
    func column(_ value: DashboardColumn) -> AnyView {
        if value.provider == "deepseek" { return AnyView(deepSeekCard(value)) }
        var readings: [WidgetReading] = []
        var plan: String?
        var footer: String?
        var data: ProviderCardData?
        let tint = MeterTint(rawValue: value.provider) ?? .codex
        let titles = ["codex": "Codex", "claude": "Claude", "deepseek": "DeepSeek", "opencodego": "OpenCode Go",
                      "commandcode": "Command Code", "openrouter": "OpenRouter", "ollamacloud": "Ollama Cloud",
                      "qoder": "Qoder", "antigravity": "Antigravity", "tokensci": "tokens.ci"]
        let logos = ["codex": "LogoOpenAI", "claude": "LogoClaude", "deepseek": "LogoDeepSeek",
                     "opencodego": "LogoOpenCodeGo", "commandcode": "LogoCommandCode", "antigravity": "LogoAntigravity"]
        switch value.provider {
        case "codex":
            readings = [("5h", value.usage?.usage.rateLimit?.primaryWindow), ("7d", value.usage?.usage.rateLimit?.secondaryWindow)].map {
                WidgetReading(title: $0.0, remaining: $0.1?.remaining, reset: $0.1?.resetDate)
            }
            footer = "重置积分 " + (value.usage?.usage.resetCreditsText(now: entry.date) ?? "—")
        case "claude":
            readings = [("5h", value.claude?.fiveHour), ("7d", value.claude?.sevenDay)].map {
                WidgetReading(title: $0.0, remaining: $0.1?.remaining, reset: $0.1?.reset)
            }
        case "opencodego":
            data = value.openCodeGo.map { ProviderCardData($0, plan: value.id.map { ProviderPreferences.openCodeGoPlan(accountID: $0) } ?? .go) }
        case "commandcode": data = value.commandCode.map { ProviderCardData($0) }
        case "openrouter": data = value.openRouter.map { ProviderCardData($0) }
        case "ollamacloud": data = value.ollamaCloud.map { ProviderCardData($0) }
        case "qoder": data = value.qoder.map { ProviderCardData($0) }
        case "antigravity":
            let total = QuotaSummary.tightest((value.antigravity?.usage.quotas ?? []).map { .init(label: "模型额度", remaining: $0.remaining, reset: $0.reset) })
            readings = [WidgetReading(title: "总用量", remaining: total?.remaining, reset: total?.reset)]
            plan = value.antigravity?.usage.tier
        case "deepseek":
            readings = (value.balance?.balance.balanceInfos.prefix(2) ?? []).map {
                WidgetReading(title: $0.currency + " 余额", value: NSDecimalNumber(decimal: $0.total).stringValue)
            }
            if readings.isEmpty { readings = [WidgetReading(title: "余额", value: "—")] }
            footer = value.balance.map { $0.balance.isAvailable ? "API 可用余额" : "API 余额不可用" }
        case "tokensci":
            readings = [WidgetReading(title: value.tokensci?.periodLabel ?? "今日 Tokens", value: value.tokensci.map { TokensCIFormat.compact($0.todayTokens) } ?? "—"),
                        WidgetReading(title: "费用", value: value.tokensci.map { TokensCIFormat.money($0.todayCost) } ?? "—")]
        default: break
        }
        if let data {
            readings = data.rows.map { row in
                WidgetReading(title: row.label, remaining: row.window?.remaining, reset: row.reset ?? row.window?.resetDate,
                              value: row.window == nil ? (row.money ?? row.detail ?? "—") : nil,
                              detail: row.window == nil ? nil : row.money.map { row.moneyPrefix + $0 })
            }
            plan = value.provider == "opencodego"
                ? (value.id.map { ProviderPreferences.openCodeGoPlan(accountID: $0) } ?? .go).displayName : data.plan
            footer = [data.grantNote, data.purchased.map { "加购 " + $0 }].compactMap { $0 }.joined(separator: " · ")
        }
        if readings.isEmpty {
            let labels: [String]
            switch value.provider {
            case "openrouter": labels = ["剩余额度", "本 Key 限额", "免费档"]
            case "ollamacloud": labels = ["余额"]
            case "qoder": labels = ["每周", "每月"]
            default: labels = ["5 小时", "每周", "每月"]
            }
            readings = labels.map { WidgetReading(title: $0) }
        }
        let status: String?
        if value.needsAppRefresh {
            status = value.updatedAt == nil ? "无缓存 · 打开 App 更新授权" : "仅缓存 · 打开 App 更新授权"
        } else if !value.canRefresh {
            status = value.updatedAt == nil ? "无缓存 · 组件无刷新授权，打开 App" : "仅缓存 · 组件无刷新授权，打开 App"
        } else if value.refreshing { status = "刷新中…" }
        else if value.failed { status = "刷新失败 · 保留缓存" }
        else if value.updatedAt == nil { status = "未授权/无数据 · 打开 App" }
        else if value.provider == "codex", value.usage?.isStale(at: entry.date) == true { status = "数据已过期" }
        else if let updatedAt = value.updatedAt, value.provider != "tokensci", value.provider != "codex",
                entry.date.timeIntervalSince(updatedAt) > 1800 || entry.date < updatedAt { status = "数据已过期" }
        else { status = nil }
        return AnyView(NowdexWidgetCard(title: titles[value.provider] ?? value.provider, logo: logos[value.provider], symbol: "circle.hexagongrid.fill",
                                readings: readings, tint: tint, updatedAt: value.updatedAt, now: entry.date,
                                medium: isMedium, reservesRefresh: !isMedium || value.id == entry.right.id,
                                palette: palette, display: entry.display, plan: plan, status: status, footer: footer))
    }
    var isMedium: Bool { family == .systemMedium }
    /// The DeepSeek small widget is a full-bleed black stack that paints its own card, so the
    /// shared 14pt inset would double-pad it.
    var stackedCard: Bool { !isMedium && entry.left.provider == "deepseek" }
    /// Exactly one control per widget, pinned to the top-right corner of both families.
    /// The medium control carries both slots and refreshes them with a single tap; the small
    /// widget passes no right slot, so it never refreshes an account it does not display.
    /// Columns never draw their own button.
    var hasConfiguredAccount: Bool { isMedium ? (entry.left.id != nil || entry.right.id != nil) : entry.left.id != nil }
    /// A Claude slot awaiting App renewal is excluded from the tap (its column's `canRefresh` is
    /// already false and the intent filters it), but it must not disable the other slot: the
    /// control reloads cache when no displayed slot can refresh here.
    var slotCanRefresh: Bool { isMedium ? (entry.left.canRefresh || entry.right.canRefresh) : entry.left.canRefresh }
    var needsAppRefresh: Bool { !slotCanRefresh && (entry.left.needsAppRefresh || (isMedium && entry.right.needsAppRefresh)) }
    var refreshControl: some View {
        RefreshAffordance(canRefresh: slotCanRefresh,
                          leftID: entry.left.id, rightID: isMedium ? entry.right.id : nil,
                          palette: palette, label: isMedium ? "刷新组件内的账号" : "刷新该账号",
                          inset: stackedCard ? 4 : 0, topInset: 0,
                          bottomInset: stackedCard ? 4 : 0, bottomAligned: stackedCard)
            .accessibilityHint(needsAppRefresh ? "需要在 App 中更新授权" : "")
    }
    var body: some View {
        Group {
            if stackedCard {
                column(entry.left)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    column(entry.left)
                    if isMedium {
                        Rectangle().fill(palette.divider).frame(width: 1)
                        column(entry.right)
                    }
                }
                .padding(14)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hasConfiguredAccount { refreshControl }
        }
    }
}
struct DashboardWidgetRoot: View {
    @Environment(\.colorScheme) var scheme
    let entry: UsageEntry
    var body: some View {
        let palette = ThemePalette.widget(scheme: entry.theme == .light ? .light : (entry.theme == .dark ? .dark : scheme))
        DashboardWidgetView(entry: entry)
            .environment(\.colorScheme, entry.theme == .light ? .light : (entry.theme == .dark ? .dark : scheme))
            .containerBackground(palette.background, for: .widget)
    }
}
struct CodexUsageWidget: Widget {
    let kind = "CodexUsageWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DashboardConfiguration.self, provider: UsageProvider()) { entry in
            DashboardWidgetRoot(entry: entry)
        }.configurationDisplayName("订阅额度与 API 余额")
            .description("长按编辑组件，独立选择服务与账号；中号右上角一个刷新按钮同时刷新两栏。")
            .supportedFamilies([.systemSmall, .systemMedium])
            // The widget card supplies its own consistent 14pt content inset.
            .contentMarginsDisabled()
    }
}

// MARK: - tokens.ci

/// Slot rendering: one service inside the shared dashboard widget.
struct TokensCICompactView: View {
    let snapshot: TokensCISnapshot?
    var palette: ThemePalette = .dark
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("tokens.ci").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.secondary)
            if let snapshot {
                Text(TokensCIFormat.compact(snapshot.todayTokens))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primary).lineLimit(1).minimumScaleFactor(0.6)
                Text(snapshot.periodLabel).font(.system(size: 10)).foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
                Text(TokensCIFormat.money(snapshot.todayCost))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.primary)
                Text("费用 · 更新于 \(snapshot.dataUpdatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9)).foregroundStyle(palette.secondary).lineLimit(1)
            } else {
                Text("暂无数据").font(.system(size: 12)).foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
                Text("打开 App 刷新").font(.system(size: 9)).foregroundStyle(palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The dedicated tokens.ci widget: the Nowdex layout, two panels, medium size.
struct TokensCIWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: TokensCISnapshot?
    var palette: ThemePalette = .dark

    var body: some View {
        Group {
            if let snapshot, family == .systemMedium {
                medium(snapshot)
            } else if let snapshot {
                compact(snapshot)
            } else {
                empty
            }
        }
        .padding(16)
    }

    private func medium(_ value: TokensCISnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(TokensCIFormat.compact(value.todayTokens))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primary).lineLimit(1).minimumScaleFactor(0.5)
                Text(value.periodLabel).font(.system(size: 10)).foregroundStyle(palette.secondary)
                Spacer(minLength: 8)
                Text(TokensCIFormat.money(value.todayCost))
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                Text("估算费用 · 非账单").font(.system(size: 10)).foregroundStyle(palette.secondary)
                Spacer(minLength: 8)
                Text("上报 \(value.dataUpdatedAt.formatted(date: .numeric, time: .omitted))")
                    .font(.system(size: 9)).foregroundStyle(palette.secondary).lineLimit(1)
                Text("仅缓存 · 打开 App 更新").font(.system(size: 8)).foregroundStyle(palette.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(value.clients.prefix(2).enumerated()), id: \.offset) { index, client in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(client.displayName).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.primary).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(TokensCIFormat.compact(client.tokens)).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.primary).lineLimit(1)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(client.topModel?.name ?? "—").font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(palette.secondary).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(TokensCIFormat.money(client.topModel?.cost ?? client.cost) + (client.topModel == nil ? " 客户端" : "")).font(.system(size: 9))
                                .foregroundStyle(palette.secondary).lineLimit(1)
                        }
                        GeometryReader { proxy in
                            let share = value.todayTokens > 0 ? client.tokens / value.todayTokens : 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.track)
                                Capsule().fill(palette.primary.opacity(index == 0 ? 0.92 : 0.55))
                                    .frame(width: proxy.size.width * min(1, max(0, share)))
                            }
                        }.frame(height: 3)
                    }
                }
                if value.clients.isEmpty {
                    Text("暂无客户端明细").font(.system(size: 10)).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
                Text("累计 " + TokensCIFormat.compact(value.totalTokens) + " · 缓存 " + TokensCIFormat.percent(value.cacheHitRate))
                    .font(.system(size: 8)).foregroundStyle(palette.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(8)
            .background(palette.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func compact(_ value: TokensCISnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TokensCIFormat.compact(value.todayTokens))
                .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(palette.primary)
            Text(value.periodLabel).font(.system(size: 10)).foregroundStyle(palette.secondary)
            Spacer(minLength: 0)
            Text(TokensCIFormat.money(value.todayCost) + " · 估算").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.primary)
            Text("上报 \(value.dataUpdatedAt.formatted(date: .numeric, time: .omitted))")
                .font(.system(size: 9)).foregroundStyle(palette.secondary)
            Text("仅缓存 · 打开 App 更新").font(.system(size: 8)).foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("tokens.ci").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.secondary)
            Spacer(minLength: 0)
            Text("打开 App 连接账号").font(.system(size: 10)).foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TokensCIEntry: TimelineEntry {
    let date: Date
    let snapshot: TokensCISnapshot?
    var theme: ThemePreference = .system
}

struct TokensCIWidgetProvider: TimelineProvider {
    private func current() -> TokensCISnapshot? {
        DashboardStore.accounts().first { $0.provider == "tokensci" }.flatMap { TokensCIStore.snapshot($0.id) }
    }
    func placeholder(in context: Context) -> TokensCIEntry {
        TokensCIEntry(date: Date(), snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (TokensCIEntry) -> Void) {
        completion(TokensCIEntry(date: Date(), snapshot: current(), theme: ThemePreference.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TokensCIEntry>) -> Void) {
        let entry = TokensCIEntry(date: Date(), snapshot: current(), theme: ThemePreference.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
    }
}

struct TokensCIWidget: Widget {
    let kind = "TokensCIWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokensCIWidgetProvider()) { entry in
            TokensCIWidgetRoot(entry: entry)
        }
        .configurationDisplayName("tokens.ci 用量")
        .description("今日 Token、费用与客户端拆分；数据由电脑上的 tokens CLI 上报，组件只读缓存。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct TokensCIWidgetRoot: View {
    @Environment(\.colorScheme) private var scheme
    let entry: TokensCIEntry
    var body: some View {
        let palette = ThemePalette.resolve(entry.theme, scheme: scheme)
        TokensCIWidgetView(snapshot: entry.snapshot, palette: palette)
            .containerBackground(palette.background, for: .widget)
            .widgetURL(URL(string: "codexusage://usage"))
    }
}

#if !CODEGO_WIDGET_RENDER_TESTS
@main struct CodexUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokensCIWidget()
        CodexUsageWidget()
    }
}

#endif
#endif
