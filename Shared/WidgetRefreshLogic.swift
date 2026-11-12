import Foundation
import AppIntents
import WidgetKit

/// The two slots the single widget control can address. Codable so the intent's parameters can
/// be validated independently of WidgetKit, and so nothing is inferred from a stale configuration.
struct WidgetRefreshRequest: Codable, Equatable, Sendable {
    var leftID: String?
    var rightID: String?
    init(leftID: String? = nil, rightID: String? = nil) {
        self.leftID = leftID
        self.rightID = rightID
    }
}

/// One configured slot, with the cache age the timeline gate needs. The button leaves
/// `updatedAt` nil, because a manual tap is throttled by `WidgetRefreshAttempt`, not by freshness.
struct WidgetRefreshSlot: Equatable, Sendable {
    let id: String
    let provider: String
    var updatedAt: Date? = nil
}

/// The shared decision + execution path for the timeline and the interactive button.
///
/// Both entry points run the same rules:
///  1. the account still exists and its credential group equals the permitted group;
///  2. the persisted attempt state allows a request (not backing off, not already in flight,
///     and not a Claude slot that needs the App to renew its token);
///  3. the timeline additionally skips a cache younger than `timelineFreshness`.
///
/// Failures are swallowed per account: the last good snapshot is kept and the persisted failure
/// flag drives the existing "刷新失败 · 保留缓存" copy. A system-throttled timeline therefore
/// re-renders from cache instead of crashing.
struct WidgetRefreshCoordinator {
    var accounts: () -> [DashboardAccount] = { DashboardStore.accounts() }
    var canRefresh: (String) -> Bool = { DashboardStore.canRefreshAnyProvider($0) }
    var attempt: (String) -> WidgetRefreshAttempt = { WidgetRefreshAttempt.load($0) }
    var now: () -> Date = { Date() }
    /// Explicit `widget: true` in the live entry point: a request must never depend on how the
    /// extension's bundle happens to be classified at runtime.
    var refresh: (String, String, Bool) async throws -> Void = { id, provider, notifyProgress in
        try await WidgetRefresh.one(id: id, provider: provider, notifyProgress: notifyProgress)
    }

    init(accounts: @escaping () -> [DashboardAccount] = { DashboardStore.accounts() },
         canRefresh: @escaping (String) -> Bool = { DashboardStore.canRefreshAnyProvider($0) },
         attempt: @escaping (String) -> WidgetRefreshAttempt = { WidgetRefreshAttempt.load($0) },
         now: @escaping () -> Date = { Date() },
         refresh: @escaping (String, String, Bool) async throws -> Void = { id, provider, notifyProgress in
             try await WidgetRefresh.one(id: id, provider: provider, notifyProgress: notifyProgress)
         }) {
        self.accounts = accounts
        self.canRefresh = canRefresh
        self.attempt = attempt
        self.now = now
        self.refresh = refresh
    }

    /// Resolve the configured slots to provider rows. Unknown account ids are dropped, never
    /// re-pointed at another account.
    func slots(for request: WidgetRefreshRequest) -> [WidgetRefreshSlot] {
        let rows = accounts()
        return RefreshTargets.unique([request.leftID, request.rightID]).compactMap { id in
            guard let row = rows.first(where: { $0.id == id }) else { return nil }
            return WidgetRefreshSlot(id: id, provider: row.provider)
        }
    }

    /// The accounts this call may actually fetch, in input order, at most once each.
    func targets(_ slots: [WidgetRefreshSlot], respectFreshness: Bool) -> [WidgetRefreshSlot] {
        let timestamp = now()
        var seen = Set<String>()
        return slots.filter { slot in
            guard seen.insert(slot.id).inserted, canRefresh(slot.id) else { return false }
            let state = attempt(WidgetRefreshAttempt.attemptID(slot.id, provider: slot.provider))
            guard !state.requiresAppRefresh,
                  state.allows(timestamp),
                  !state.isRefreshing(at: timestamp) else { return false }
            if respectFreshness,
               !WidgetRefreshAttempt.timelineShouldFetch(updatedAt: slot.updatedAt, now: timestamp) {
                return false
            }
            return true
        }
    }

    /// Refresh every permitted slot concurrently. Returns the ids that were attempted; the caller
    /// uses that only to decide whether a fresh entry is worth re-reading. Errors stay per-slot.
    @discardableResult
    func perform(_ slots: [WidgetRefreshSlot], respectFreshness: Bool = false,
                 notifyProgress: Bool = false) async -> [String] {
        let selected = targets(slots, respectFreshness: respectFreshness)
        guard !selected.isEmpty else { return [] }
        let fetch = refresh
        return await withTaskGroup(of: String?.self) { group in
            for slot in selected {
                group.addTask {
                    do {
                        try await fetch(slot.id, slot.provider, notifyProgress)
                    } catch {
                        // Services persist failure/backoff while retaining the last good snapshot.
                        // Include failed attempts so the timeline re-reads that state this cycle.
                    }
                    return slot.id
                }
            }
            var done: [String] = []
            for await id in group {
                if let id { done.append(id) }
            }
            return done
        }
    }

    @discardableResult
    func perform(request: WidgetRefreshRequest) async -> [String] {
        await perform(slots(for: request), notifyProgress: true)
    }
}

/// iOS 17 interactive-widget button. It carries the current configuration's account ids because
/// a widget extension cannot read the widget's configuration outside `TimelineProvider`; the
/// coordinator re-checks authorization and backoff at tap time, so a stale parameter can never
/// turn into a request the timeline would not have made.
struct RefreshWidgetIntent: AppIntent, Codable {
    static var title: LocalizedStringResource = "刷新组件账号"
    static var openAppWhenRun = false
    @Parameter(title: "左栏账号") var leftID: String?
    @Parameter(title: "右栏账号") var rightID: String?

    /// Test seam. The extension always uses the live store-backed coordinator.
    nonisolated(unsafe) static var coordinator = WidgetRefreshCoordinator()

    init() {}
    init(leftID: String?, rightID: String?) {
        self.leftID = leftID
        self.rightID = rightID
    }

    init(from decoder: Decoder) throws {
        let request = try WidgetRefreshRequest(from: decoder)
        self.init(leftID: request.leftID, rightID: request.rightID)
    }

    func encode(to encoder: Encoder) throws { try request.encode(to: encoder) }

    var request: WidgetRefreshRequest { WidgetRefreshRequest(leftID: leftID, rightID: rightID) }

    func perform() async throws -> some IntentResult {
        let coordinator = Self.coordinator
        _ = await coordinator.perform(request: request)
        // Always reload: an unauthorized or backed-off tap must still re-read the cache.
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        return .result()
    }
}

/// One slot's refresh, shared by the timeline and the button. Every provider is called with
/// `widget: true`; the last good cache and the persisted failure flag survive any error.
enum WidgetRefresh {
    static func one(id: String, provider: String, notifyProgress: Bool = false) async throws {
        switch provider {
        case "opencodego": _ = try await OpenCodeGoService.shared.refresh(id: id, widget: true)
        case "commandcode": _ = try await CommandCodeService.shared.refresh(id: id, widget: true)
        case "openrouter": _ = try await OpenRouterService.shared.refresh(id: id, widget: true)
        case "ollamacloud": _ = try await OllamaCloudService.shared.refresh(id: id, widget: true)
        case "qoder": _ = try await QoderService.shared.refresh(id: id, widget: true)
        case "deepseek": _ = try await DeepSeekService.shared.refresh(id: id, widget: true)
        case "claude": _ = try await ClaudeService.shared.refresh(widget: true)
        case "antigravity": _ = try await AntigravityService.shared.refresh(widget: true)
        case "tokensci": _ = try await TokensCIService.shared.refresh(username: id, widget: true)
        default:
            _ = try await UsageService.shared.refresh(account: id, widget: true, notifyProgress: notifyProgress,
                                                       permission: { DashboardStore.canRefresh(id, provider: "codex") })
        }
    }
}
