#!/usr/bin/env python3
"""Regenerate an isolated simulator-only public-data preview; production stays fixture-free."""
from pathlib import Path
import shutil,subprocess,json
r=Path(__file__).resolve().parents[1]; out=r/'Build37Preview'; out.mkdir(exist_ok=True)
for name in ['App','Shared','Widget','Configuration','CodexUsage.xcodeproj']:
    shutil.copytree(r/name,out/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns('Private.xcconfig','xcuserdata'))
p=out/'App/CodexUsageApp.swift'; s=p.read_text(); s=s.replace('else { ContentView(model: model) }','else { Build37PreviewRoot() }');p.write_text(s)
p=out/'App/TokensCIAnalyticsView.swift';s=p.read_text().replace('@State private var selectedDay: String?', '@State private var selectedDay: String? = ProcessInfo.processInfo.environment["PREVIEW_DAY"]').replace('@State private var range = 30','@State private var range = Int(ProcessInfo.processInfo.environment["PREVIEW_RANGE"] ?? "30") ?? 30').replace('@State private var allModels = false','@State private var allModels = ProcessInfo.processInfo.environment["PREVIEW_EXPANDED"] == "1"').replace('@State private var allProviders = false','@State private var allProviders = ProcessInfo.processInfo.environment["PREVIEW_EXPANDED"] == "1"').replace('@State private var showCost = false','@State private var showCost = ProcessInfo.processInfo.environment["PREVIEW_COST"] == "1"')
p.write_text(s)
fixture=json.loads((r/'Tests/Fixtures/tokensci-public.json').read_text())
# No token/network call even in isolated preview: decode public history and source stats locally.
public=json.dumps(fixture,separators=(',',':'))
import base64
payload=base64.b64encode(public.encode()).decode()
with (out/'App/CodexUsageApp.swift').open('a') as f:f.write('''
struct Build37PreviewRoot: View {
    let value: TokensCISnapshot
    init() {
        let data = Data(base64Encoded: "'''+payload+'''")!
        let raw = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let stats = raw["stats"] as! [String: Any]
        var v = TokensCISnapshot(username: "Alice39s", displayName: "Alice39s", isPrivate: false, rank: nil,
            totalTokens: stats["totalTokens"] as! Double, totalCost: stats["totalCost"] as! Double,
            inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0,
            activeDays: stats["activeDays"] as! Int, sessionCount: 0, todayTokens: 0, todayCost: 0, monthCost: 0, cacheHitRate: 0, clients: [],
            dataUpdatedAt: ISO8601DateFormatter().date(from: "2026-10-04T02:31:16Z")!, fetchedAt: Date(), isStale: true,
            selectedDay: "2026-10-18", selectedTimeZone: "Asia/Shanghai")
        v.history = try! TokensCIHistory.decode(data); value = v
    }
    var body: some View {
        TabView {
            VStack(spacing: 0) {
                HStack { Spacer(); Text("用量").font(.title3.bold()); Spacer(); Image(systemName: "plus.circle"); Image(systemName: "arrow.clockwise.circle") }.padding(20)
                Text("公开数据示例 · @Alice39s · 非用户私密数据").font(.caption2).foregroundStyle(.secondary)
                ScrollViewReader { proxy in
                    ScrollView { TokensCIAnalyticsView(value: value).padding(20) }
                    .task { try? await Task.sleep(for: .seconds(1)); proxy.scrollTo(ProcessInfo.processInfo.environment["PREVIEW_SECTION"] ?? "overview", anchor: .top) }
                }
            }.background(Color(UIColor.systemGroupedBackground)).tabItem { Label("用量", systemImage: "chart.xyaxis.line") }
        }
    }
}
''')
print('Isolated public preview regenerated:',out)
