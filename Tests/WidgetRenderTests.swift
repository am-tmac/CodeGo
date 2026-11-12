#if os(iOS) && DEBUG
import XCTest
import SwiftUI
import WidgetKit
@testable import CodeGo

/// Repeatable simulator artifact: render the production widget view at both supported sizes.
/// Failure modes: missing account removes the button; wrong family hides the right column;
/// clipping, crowded headers, missing windows and appearance contrast are reviewed in the exported PNGs and retained xcresult attachments.
final class WidgetRenderTests: XCTestCase {
    @MainActor
    func testRenderSmallAndMediumWithInteractiveControl() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"rate_limit":{"primary_window":{"used_percent":23,"reset_at":1800003600},"secondary_window":{"used_percent":41,"reset_at":1800259200}}}"#.utf8))
        let balance = try JSONDecoder().decode(DeepSeekBalance.self, from: Data(#"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"12.50"}]}"#.utf8))
        let left = DashboardColumn(id: "render-codex", provider: "codex", title: "Codex · 账号 1", usage: UsageSnapshot(usage: usage, updatedAt: now), balance: nil, antigravity: nil, claude: nil, tokensci: nil, canRefresh: true, failed: false, refreshing: false)
        let right = DashboardColumn(id: "render-deepseek", provider: "deepseek", title: "DeepSeek · 账号 1", usage: nil, balance: DeepSeekSnapshot(balance: balance, updatedAt: now), antigravity: nil, claude: nil, tokensci: nil, canRefresh: true, failed: false, refreshing: false)
        let entry = UsageEntry(date: now, left: left, right: left, display: .used)

        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Design/widget-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let threeWindows = DashboardColumn(id: "render-go", provider: "opencodego", title: "OpenCode Go", usage: nil, balance: nil,
            openCodeGo: OpenCodeGoSnapshot(usage: OpenCodeGoUsage(rolling: usage.rateLimit?.primaryWindow,
                weekly: usage.rateLimit?.secondaryWindow, monthly: usage.rateLimit?.primaryWindow, renewAt: nil), updatedAt: now),
            antigravity: nil, claude: nil, tokensci: nil, canRefresh: true, failed: false, refreshing: false)
        let cache = DashboardColumn(id: "render-cache", provider: "claude", title: "Claude", usage: nil, balance: nil,
            antigravity: nil, claude: nil, tokensci: nil, canRefresh: false, failed: false, refreshing: false, needsAppRefresh: true)
        let deep = DashboardColumn(id: "render-deepseek-left", provider: "deepseek", title: "DeepSeek · 账号 1",
            usage: nil, balance: DeepSeekSnapshot(balance: balance, updatedAt: now),
            antigravity: nil, claude: nil, tokensci: nil, canRefresh: true, failed: false, refreshing: false)
        let review = output.appendingPathComponent("review")
        try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
        let brands = ["antigravity", "commandcode", "openrouter", "ollamacloud", "qoder", "tokensci"].map { provider in
            let column = DashboardColumn(id: "render-\(provider)", provider: provider, title: provider,
                usage: nil, balance: nil, antigravity: nil, claude: nil, tokensci: nil,
                canRefresh: true, failed: false, refreshing: false)
            return (provider, UsageEntry(date: now, left: column, right: column, display: .used))
        }
        // Failure modes covered: three windows, currency amounts, missing authorisation and data.
        let fixtures = [("", entry),
            ("go", UsageEntry(date: now, left: threeWindows, right: right, display: .used)),
            ("cache", UsageEntry(date: now, left: cache, right: right, display: .used)),
            ("deepseek", UsageEntry(date: now, left: deep, right: right, display: .used))] + brands
        for (variant, fixture) in fixtures {
            for scheme in [ColorScheme.dark, .light] {
                for (name, family, width) in [("small", WidgetFamily.systemSmall, 170.0), ("medium", WidgetFamily.systemMedium, 364.0)] {
                    let view = DashboardWidgetView(family: family, entry: fixture)
                        .environment(\.colorScheme, scheme)
                        .environment(\.displayScale, 3)
                        .frame(width: width, height: 170)
                        .background(ThemePalette.widget(scheme: scheme).background)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.uiImage)
                    let data = try XCTUnwrap(image.pngData())
                    let filename = "\(name)-\(scheme == .dark ? "dark" : "light")"
                    try data.write(to: (variant.isEmpty ? output : review).appendingPathComponent(variant.isEmpty ? "\(filename).png" : "\(variant)-\(filename).png"))
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "widget-\(variant)-\(filename)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    XCTAssertEqual(image.size.width, width)
                    XCTAssertEqual(image.size.height, 170)
                    XCTAssertEqual(image.cgImage?.width, Int(width * 2))
                }
            }
        }
    }
}
#endif
