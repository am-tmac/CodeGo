import SwiftUI
import Charts

/// App-only native analytics. No fixture or credential access in this view.
struct TokensCIAnalyticsView: View {
    let value: TokensCISnapshot
    @Environment(\.colorScheme) private var scheme
    @State private var selectedDay: String?
    @State private var range = 30
    @State private var totalRange = 0
    @State private var showCost = false
    @State private var allProviders = false
    @State private var allModels = false
    private let colors: [Color] = [.cyan, .blue, .orange, .purple, .green]
    private var history: TokensCIHistory { value.history ?? TokensCIHistory(days: []) }
    private var end: String { history.latestDay ?? value.selectedDay ?? "" }
    private var analytics: TokensCIAnalytics { history.analytics(ending: end, days: range) }
    private var dayKey: String { selectedDay ?? end }
    private var day: TokensCIDay? { history.day(dayKey) }
    private var surface: Color { scheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.17) : .white }
    private var muted: Color { scheme == .dark ? Color(red: 0.63, green: 0.67, blue: 0.75) : .secondary }
    private func pct(_ x: Double) -> String { x.isFinite ? String(format: "%.1f%%", x * 100) : "—" }
    private func money(_ x: Double) -> String { TokensCIFormat.money(x) }
    private func tokens(_ x: Double) -> String { TokensCIFormat.compact(x) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            hero.id("overview")
            activity.id("activity")
            tiles.id("analytics")
            usageChart.id("chart")
            rankings.id("rankings")
            composition.id("composition")
            habits.id("habits")
            Text(value.periodNote).font(.caption2).foregroundStyle(muted)
            Text("Token 用量由 tokens.ci 提供支持").font(.caption).foregroundStyle(muted).frame(maxWidth: .infinity)
        }
        .foregroundStyle(scheme == .dark ? Color.white : Color.primary)
        .onChange(of: value.username) { _, _ in selectedDay = nil }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(Color(red: 0.40, green: 0.25, blue: 0.30))
                    Text(String((value.displayName ?? value.username).prefix(1)).uppercased()).font(.title.bold()).foregroundStyle(.white)
                }.frame(width: 60, height: 60).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(value.displayName ?? value.username).font(.title2.bold())
                    HStack {
                        Text("@" + value.username)
                        Label(value.isPrivate ? "私密资料" : "公开资料", systemImage: value.isPrivate ? "lock.fill" : "checkmark.shield")
                            .font(.caption2).foregroundStyle(.green)
                    }.font(.caption).foregroundStyle(muted)
                }.privacySensitive()
            }
            HStack {
                Text(totalRange == 0 ? "总 Token" : "已报 Token").foregroundStyle(muted)
                Spacer()
                Picker("总量时段", selection: $totalRange) {
                    Text("全部时间").tag(0); Text("最近 7 天").tag(7); Text("最近 30 天").tag(30)
                }.pickerStyle(.menu).tint(muted)
            }
            let totals = history.analytics(ending: end, days: totalRange == 0 ? 1 : totalRange)
            Text(tokens(totalRange == 0 ? value.totalTokens : totals.tokens))
                .font(.system(size: 57, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            HStack(alignment: .firstTextBaseline) {
                Text(money(totalRange == 0 ? value.totalCost : totals.cost)).font(.title2)
                Text(totalRange == 0 ? "累计估算费用" : "所选窗口估算费用").font(.caption)
            }.foregroundStyle(muted)
            Text("上报于 " + value.dataUpdatedAt.formatted() + (value.isStale ? " · 上报已过期" : "") + "\n读取于 " + value.fetchedAt.formatted())
                .font(.caption2).foregroundStyle(muted)
            Text("保存账号不代表授权或读取已成功；费用为模型定价估算，非账单。")
                .font(.caption2).foregroundStyle(muted)
        }
        .padding(.top, 12)
        .background(alignment: .topLeading) {
            RadialGradient(colors: [Color(red: 0.40, green: 0.24, blue: 0.30).opacity(scheme == .dark ? 0.55 : 0.15), .clear], center: .topLeading, startRadius: 0, endRadius: 390)
                .padding(-20).allowsHitTesting(false)
        }
    }
    private func title(_ name: String, _ subtitle: String, rangePicker: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.title2.bold()); Text(subtitle).font(.caption2).foregroundStyle(muted)
            }
            Spacer()
            if rangePicker {
                Picker("统计范围", selection: $range) {
                    Text("7 天").tag(7); Text("30 天").tag(30); Text("90 天").tag(90)
                }.pickerStyle(.menu).tint(muted)
            }
        }
    }
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 25))
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 13) {
            title("每日活动", "真实日期 · 未上报不补数")
            card {
                HStack {
                    Text("\(value.activeDays) 个活跃日 · 累计").font(.caption.bold()); Spacer()
                    Text("低").font(.caption2)
                    ForEach(1..<5, id: \.self) { level in RoundedRectangle(cornerRadius: 1).fill(Color.blue.opacity(Double(level) / 4)).frame(width: 7, height: 7) }
                    Text("高").font(.caption2)
                }
                heatmap
                Text("斜线：无上报记录 · 描边：所选上报日").font(.caption2).foregroundStyle(muted)
                Divider()
                HStack {
                    Text(selectedDay == nil ? "最近上报日" : "所选上报日").font(.subheadline.bold())
                    Spacer(); Text(dayKey).font(.caption).foregroundStyle(muted)
                }
                if let day {
                    Text(tokens(day.tokens)).font(.system(size: 35, weight: .bold)).monospacedDigit() + Text(" Token").font(.caption).foregroundStyle(muted)
                    HStack {
                        metric("估算费用", money(day.cost)); Spacer(); metric("消息数", day.messages.map { String(format: "%.0f", $0) } ?? "—")
                    }
                    Text("消息口径缺失或与客户端不一致时显示 —，不补造消息总数。").font(.caption2).foregroundStyle(muted)
                    Divider()
                    Text("同日客户端").font(.subheadline.bold())
                    let clients = history.analytics(ending: dayKey, days: 1).clients
                    ForEach(clients) { client in
                        dataRow(client.displayName, tokens(client.tokens), client.topModel?.name ?? "无模型明细", money(client.topModel?.cost ?? client.cost) + (client.topModel == nil ? " · 客户端" : " · 模型"), ratio: day.tokens > 0 ? client.tokens / day.tokens : 0, color: .blue)
                    }
                    if clients.isEmpty { Text("暂无客户端明细").font(.caption).foregroundStyle(muted) }
                } else {
                    Text("该上报日无记录 · 不补零或借用最近一天").font(.subheadline).foregroundStyle(muted)
                }
                Text("条形为客户端 / 同日总 Token；不同来源 totals 与明细可能不一致。今日仅匹配设备同日期，不将最近上报日冒充今天。").font(.caption2).foregroundStyle(muted)
                Text(value.periodLabel + " · " + tokens(value.todayTokens)).font(.caption2).foregroundStyle(muted)
                if value.history == nil { Text("历史待刷新 · 旧快照仍保留，请刷新此账号").font(.caption).foregroundStyle(muted) }
            }
        }
    }
    private var heatmap: some View {
        let last = TokensCIHistory.date(end) ?? Date()
        let first = TokensCIHistory.calendar.date(byAdding: .day, value: -146, to: last)!
        let weekday = (TokensCIHistory.calendar.component(.weekday, from: first) + 5) % 7
        let start = TokensCIHistory.calendar.date(byAdding: .day, value: -weekday, to: first)!
        let startKey = TokensCIHistory.key(start)
        let maximum = max(1, history.days.map(\.tokens).max() ?? 1)
        return VStack(spacing: 5) {
            HStack { ForEach(0..<5, id: \.self) { offset in
                let date = TokensCIHistory.calendar.date(byAdding: .month, value: offset, to: first)!
                Text("\(TokensCIHistory.calendar.component(.month, from: date))月").frame(maxWidth: .infinity)
            }}.font(.system(size: 9)).foregroundStyle(muted)
            HStack(spacing: 3) {
                ForEach(0..<22, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let key = TokensCIHistory.offset(startKey, week * 7 + weekday)
                            let record = history.day(key)
                            Button { selectedDay = key } label: {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(record.map { Color.blue.opacity($0.tokens == 0 ? 0.08 : 0.25 + 0.75 * min(1, $0.tokens / maximum)) } ?? muted.opacity(0.13))
                                    .overlay { if record == nil { Text("╱").font(.system(size: 9)).foregroundStyle(muted.opacity(0.5)) } }
                                    .overlay { RoundedRectangle(cornerRadius: 2).stroke(key == dayKey ? (scheme == .dark ? Color.white : Color.blue) : .clear, lineWidth: 1.5) }
                                    .aspectRatio(1, contentMode: .fit)
                            }.buttonStyle(.plain).disabled(key > end)
                                .accessibilityLabel(key + (record.map { "，" + tokens($0.tokens) + " Token" } ?? "，无上报"))
                        }
                    }
                }
            }
        }
    }
    private func metric(_ name: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(name).font(.caption).foregroundStyle(muted); Text(text).font(.title3.bold()).minimumScaleFactor(0.6).lineLimit(1) }
    }
    private func tile(_ name: String, _ text: String, _ note: String, _ color: Color) -> some View {
        card {
            Label { Text(name) } icon: { Circle().fill(color).frame(width: 7, height: 7) }.font(.caption).foregroundStyle(muted)
            Text(text).font(.system(size: 28, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
            Text(note).font(.caption2).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxHeight: .infinity, alignment: .top)
    }
    private var tiles: some View {
        let a = analytics
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                tile("连续活跃", "\(a.streak) 天", "截至最近上报日\n一年内最长 \(a.longestStreak) 天", .orange)
                tile("月度预估", "—", "不外推 · \(range)天已报 " + money(a.cost), .purple)
            }
            HStack(alignment: .top, spacing: 12) {
                tile("每个活跃日", a.activeDays > 0 ? money(a.cost / Double(a.activeDays)) : "—", (a.activeDays > 0 ? tokens(a.tokens / Double(a.activeDays)) : "—") + " Token\n\(range) 天中有 \(a.activeDays) 个活跃上报日", .blue)
                tile("缓存读取占比", a.cacheReadRatio.map(pct) ?? "—", "每 1M Token " + (a.tokens > 0 ? money(a.cost / a.tokens * 1_000_000) : "—") + "\n最近 \(range) 天 · 非请求命中率", .cyan)
            }
        }
    }
    private func chartSeries(_ client: TokensCIHistoryClient) -> String {
        analytics.clients.prefix(3).contains { $0.name == client.name } ? client.displayName : "其他"
    }
    private var usageChart: some View {
        VStack(alignment: .leading, spacing: 13) {
            title("用量", "按日 · 客户端分桶", rangePicker: true)
            card {
                Picker("图表单位", selection: $showCost) { Text("Token").tag(false); Text("费用").tag(true) }.pickerStyle(.segmented)
                Chart {
                    ForEach(analytics.days) { day in
                        let sums = day.clients
                        ForEach(sums) { client in
                            BarMark(x: .value("上报日", TokensCIHistory.date(day.date)!, unit: .day), y: .value(showCost ? "费用" : "Token", showCost ? client.cost : client.tokens))
                                .foregroundStyle(by: .value("客户端", chartSeries(client)))
                                .accessibilityLabel(day.date + " " + client.displayName)
                                .accessibilityValue(showCost ? money(client.cost) : tokens(client.tokens))
                        }
                    }
                }
                .chartXScale(domain: (TokensCIHistory.date(analytics.start) ?? Date())...(TokensCIHistory.date(end) ?? Date()))
                .chartYAxis { AxisMarks(position: .trailing) { v in AxisGridLine(stroke: StrokeStyle(dash: [3])); AxisValueLabel { if let n = v.as(Double.self) { Text(showCost ? money(n) : tokens(n)) } } } }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: range > 30 ? 30 : 7)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                .chartForegroundStyleScale(domain: analytics.clients.prefix(3).map(\.displayName) + ["其他"], range: [Color.cyan, .blue, .orange, .gray])
                .chartLegend(.hidden)
                .frame(height: 245)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(analytics.clients.prefix(3)) { client in
                        Label { Text(client.displayName).lineLimit(1) } icon: {
                            Circle().fill(colors[(analytics.clients.firstIndex { $0.name == client.name } ?? 0) % 3]).frame(width: 6, height: 6)
                        }.font(.caption2).foregroundStyle(muted)
                    }
                    Label { Text("其他") } icon: { Circle().fill(.gray).frame(width: 6, height: 6) }.font(.caption2).foregroundStyle(muted)
                }
                Text("缺报日留空；堆叠按客户端明细合计，可能与每日 totals 不同。切换费用使用同日 cost，不按 Token 换算。").font(.caption2).foregroundStyle(muted)
            }
            card {
                Text("统计口径").font(.subheadline.bold())
                Text("\(range) 天窗口：\(analytics.start) — \(end)，锚定最近上报日，不冒充今天。只比较已上报记录；缺报并不代表没有使用，月度预估不线性外推。").font(.caption).foregroundStyle(muted)
            }
        }
    }
    private func dataRow(_ name: String, _ number: String, _ detail: String, _ cost: String, ratio: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) { Text(name).font(.subheadline.bold()); Spacer(minLength: 8); Text(number).font(.subheadline.bold()).monospacedDigit() }
            HStack(alignment: .top) { Text(detail).lineLimit(2); Spacer(); Text(cost).multilineTextAlignment(.trailing) }.font(.caption2).foregroundStyle(muted)
            GeometryReader { proxy in
                Capsule().fill(muted.opacity(0.18)).overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, ratio.isFinite ? ratio : 0)))
                }
            }.frame(height: 4)
            Divider().padding(.top, 7)
        }
    }
    private var rankings: some View {
        VStack(alignment: .leading, spacing: 13) {
            title("Provider", "按客户端归属 · Token 占比", rangePicker: true)
            card {
                let denominator = analytics.clients.reduce(0) { $0 + $1.tokens }
                ForEach(Array(analytics.clients.prefix(allProviders ? analytics.clients.count : 3))) { client in
                    let share = denominator > 0 ? client.tokens / denominator : 0
                    dataRow(client.displayName, pct(share), client.topModel?.name ?? "无模型明细", tokens(client.tokens) + " · " + money(client.cost), ratio: share, color: colors[(analytics.clients.firstIndex { $0.name == client.name } ?? 0) % colors.count])
                }
                Button(allProviders ? "收起 Provider" : "显示全部 Provider") { allProviders.toggle() }.font(.subheadline).frame(minHeight: 44)
                Text("占比基于全部客户端 Token；其他仍计入分母，不推断服务商归属。").font(.caption2).foregroundStyle(muted)
            }
            title("模型", "按 Token 排序 · 已上报模型", rangePicker: true)
            card {
                ForEach(Array(analytics.models.prefix(allModels ? analytics.models.count : 5)), id: \.name) { model in
                    dataRow(model.name, tokens(model.tokens), "已上报模型费用", money(model.cost), ratio: (analytics.models.first?.tokens ?? 0) > 0 ? model.tokens / analytics.models[0].tokens : 0, color: .blue)
                }
                Button(allModels ? "收起模型" : "显示全部模型") { allModels.toggle() }.font(.subheadline).frame(minHeight: 44)
                Text("跳过 <synthetic> 项，不推断缺失模型；条形相对于最高模型。").font(.caption2).foregroundStyle(muted)
            }
        }
    }
    private var composition: some View {
        VStack(alignment: .leading, spacing: 13) {
            title("Token 占比", "输入、输出、缓存与推理", rangePicker: true)
            card {
                if let c = analytics.composition, c.values.count == 5, c.total > 0 {
                    GeometryReader { proxy in
                        HStack(spacing: 0) { ForEach(0..<5, id: \.self) { i in colors[(i + 1) % 5].frame(width: proxy.size.width * c.values[i] / c.total) } }
                    }.frame(height: 10).clipShape(Capsule())
                    ForEach(0..<5, id: \.self) { i in
                        HStack { Circle().fill(colors[(i + 1) % 5]).frame(width: 7, height: 7); Text(["输入", "输出", "缓存读取", "缓存写入", "推理"][i]); Spacer(); Text(tokens(c.values[i])).bold(); Text(pct(c.values[i] / c.total)).foregroundStyle(muted).frame(width: 54, alignment: .trailing) }.font(.caption)
                        Divider()
                    }
                } else { Text("Token 组成明细不足 · —").foregroundStyle(muted) }
                Text("分母为五类 Token 合计；不将缓存再次并入输入。缓存读取占比不是请求命中率。").font(.caption2).foregroundStyle(muted)
            }
        }
    }
    private var habits: some View {
        let a = analytics
        let best = a.weekdays.indices.max { a.weekdays[$0] < a.weekdays[$1] } ?? 0
        let sum = a.weekdays.reduce(0, +)
        return VStack(alignment: .leading, spacing: 13) {
            title("习惯", "最近 12 个月 · 截至最近上报日")
            HStack(alignment: .top, spacing: 12) {
                tile("最高产的星期", sum > 0 ? "星期" + ["一","二","三","四","五","六","日"][best] : "—", tokens(a.weekdays[best]) + " Token\n占已报总量 " + (sum > 0 ? pct(a.weekdays[best] / sum) : "—"), .blue)
                tile("用量最高的一天", a.peakDay.map { tokens($0.tokens) } ?? "—", (a.peakDay?.date ?? "无记录") + "\n" + (a.peakDay.map { money($0.cost) } ?? "—") + " · 估算费用", .orange)
            }
            card {
                Text("按星期的 Token").font(.subheadline.bold())
                Chart { ForEach(0..<7, id: \.self) { i in
                    BarMark(x: .value("星期", ["一","二","三","四","五","六","日"][i]), y: .value("Token", a.weekdays[i]))
                        .foregroundStyle(i == best ? Color.blue : muted.opacity(0.5)).cornerRadius(4)
                }}.chartYAxis(.hidden).frame(height: 160)
                Text("按日期键聚合；无记录不补造活动。").font(.caption2).foregroundStyle(muted)
            }
        }
    }
}
