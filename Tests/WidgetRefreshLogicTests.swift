import XCTest
@testable import CodeGo

/// Build 50: the widget's own refresh path. These tests pin the decision logic that both the
/// timeline and the interactive button share: authorization, backoff, freshness and a single
/// request per account. Additional failure cases are specified before changing the coordinator.
final class WidgetRefreshLogicTests: XCTestCase {
    override class func setUp() { super.setUp(); TestContainer.install() }

    private func account(_ id: String, _ provider: String) -> DashboardAccount {
        DashboardAccount(id: id, provider: provider, ordinal: 1, credentialGroup: "TEAM.shared")
    }

    // MARK: intent surface

    func testRefreshWidgetIntentExistsAndItsParametersRoundTrip() throws {
        let request = WidgetRefreshRequest(leftID: "account-a", rightID: "account-b")
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(WidgetRefreshRequest.self, from: data), request)

        let empty = try JSONDecoder().decode(WidgetRefreshRequest.self, from: Data("{}".utf8))
        XCTAssertNil(empty.leftID)
        XCTAssertNil(empty.rightID)

        let intent = RefreshWidgetIntent(leftID: "account-a", rightID: nil)
        XCTAssertEqual(intent.request, WidgetRefreshRequest(leftID: "account-a", rightID: nil))
        // Encode the AppIntent itself, not only its separate request value.
        for original in [intent, RefreshWidgetIntent(leftID: nil, rightID: "b"), RefreshWidgetIntent()] {
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(RefreshWidgetIntent.self, from: encoded)
            XCTAssertEqual(decoded.request, original.request)
        }
        XCTAssertEqual(RefreshWidgetIntent.title.key, "刷新组件账号")
        XCTAssertFalse(RefreshWidgetIntent.openAppWhenRun)
    }

    func testIntentPerformDoesNotCallTheServiceWhenUnauthorizedOrBackedOff() async throws {
        var calls = 0
        var coordinator = WidgetRefreshCoordinator()
        coordinator.accounts = { [self] in [account("a", "deepseek"), account("b", "deepseek")] }
        coordinator.canRefresh = { _ in false }
        coordinator.refresh = { _, _, _ in calls += 1 }
        let previous = RefreshWidgetIntent.coordinator
        RefreshWidgetIntent.coordinator = coordinator
        defer { RefreshWidgetIntent.coordinator = previous }

        _ = try await RefreshWidgetIntent(leftID: "a", rightID: "b").perform()
        XCTAssertEqual(calls, 0, "unauthorized tap must only reload the timeline")

        var backedOff = WidgetRefreshAttempt()
        backedOff.fail(Date())
        coordinator.canRefresh = { _ in true }
        coordinator.attempt = { _ in backedOff }
        RefreshWidgetIntent.coordinator = coordinator
        _ = try await RefreshWidgetIntent(leftID: "a", rightID: "b").perform()
        XCTAssertEqual(calls, 0, "a backoff window must suppress the request")

        coordinator.attempt = { _ in WidgetRefreshAttempt() }
        RefreshWidgetIntent.coordinator = coordinator
        _ = try await RefreshWidgetIntent(leftID: "a", rightID: "b").perform()
        XCTAssertEqual(calls, 2)
    }

    // MARK: shared decision logic

    func testUnauthorizedSlotNeverRefreshes() async {
        var calls = 0
        var coordinator = WidgetRefreshCoordinator()
        coordinator.accounts = { [self] in [account("a", "codex")] }
        coordinator.canRefresh = { _ in false }
        coordinator.refresh = { _, _, _ in calls += 1 }
        let done = await coordinator.perform([WidgetRefreshSlot(id: "a", provider: "codex")])
        XCTAssertEqual(done, [])
        XCTAssertEqual(calls, 0)
    }

    func testBackoffWindowSuppressesTheRequest() async {
        var calls = 0
        var state = WidgetRefreshAttempt()
        state.fail(Date())
        var coordinator = WidgetRefreshCoordinator()
        coordinator.accounts = { [self] in [account("a", "openrouter")] }
        coordinator.canRefresh = { _ in true }
        coordinator.attempt = { _ in state }
        coordinator.refresh = { _, _, _ in calls += 1 }
        let done = await coordinator.perform([WidgetRefreshSlot(id: "a", provider: "openrouter")])
        XCTAssertEqual(done, [])
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(coordinator.targets([WidgetRefreshSlot(id: "a", provider: "openrouter")], respectFreshness: false).isEmpty)
    }

    func testInFlightRefreshIsNotStartedTwice() async {
        var calls = 0
        var state = WidgetRefreshAttempt()
        state.begin(Date())
        var coordinator = WidgetRefreshCoordinator()
        coordinator.canRefresh = { _ in true }
        coordinator.attempt = { _ in state }
        coordinator.refresh = { _, _, _ in calls += 1 }
        _ = await coordinator.perform([WidgetRefreshSlot(id: "a", provider: "deepseek")])
        XCTAssertEqual(calls, 0)
    }

    func testOneRequestPerAccountEvenWhenBothSlotsPointAtIt() async {
        let counter = CallCounter()
        var coordinator = WidgetRefreshCoordinator()
        coordinator.accounts = { [self] in [account("a", "codex")] }
        coordinator.canRefresh = { _ in true }
        coordinator.attempt = { _ in WidgetRefreshAttempt() }
        coordinator.refresh = { _, _, _ in await counter.increment() }
        let slots = [WidgetRefreshSlot(id: "a", provider: "codex"), WidgetRefreshSlot(id: "a", provider: "codex")]
        let done = await coordinator.perform(slots)
        XCTAssertEqual(done, ["a"])
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testAuthorizedRefreshWritesTheSnapshotBackOnce() async throws {
        let id = "test-widget-" + UUID().uuidString
        try DeepSeekStore.saveKey("synthetic-key-only", id: id)
        defer { try? DeepSeekStore.remove(id) }
        let body = #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"12.50"}]}"#
        let transport = ScriptedTransport([(body, 200)])
        let service = DeepSeekService(api: DeepSeekAPI(transport: transport))
        var coordinator = WidgetRefreshCoordinator()
        coordinator.accounts = { [DashboardAccount(id: id, provider: "deepseek", ordinal: 1, credentialGroup: "TEAM.shared")] }
        coordinator.canRefresh = { _ in true }
        coordinator.attempt = { _ in WidgetRefreshAttempt() }
        coordinator.refresh = { accountID, provider, _ in
            XCTAssertEqual(provider, "deepseek")
            _ = try await service.refresh(id: accountID, widget: true, permission: { true })
        }
        let done = await coordinator.perform([WidgetRefreshSlot(id: id, provider: "deepseek")])
        XCTAssertEqual(done, [id])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(DeepSeekStore.snapshot(id)?.balance.balanceInfos.first?.total, Decimal(string: "12.50"))
    }

    // Failure modes: permission denied or backoff must issue zero HTTP requests;
    // HTTP failure must retain snapshot bytes, persist backoff, and return the attempted id
    // so the timeline re-reads the failure state immediately.
    func testServiceGatesAndFailurePreserveCache() async throws {
        let id = "test-widget-" + UUID().uuidString
        try DeepSeekStore.saveKey("synthetic-key-only", id: id)
        defer { try? DeepSeekStore.remove(id) }
        let cached = DeepSeekSnapshot(balance: try JSONDecoder().decode(DeepSeekBalance.self, from: Data(#"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"9"}]}"#.utf8)), updatedAt: Date())
        try DeepSeekStore.save(cached, id: id)
        let before = try Data(contentsOf: DeepSeekStore.snapshotURL(id))
        let transport = ScriptedTransport([("{}", 500)])
        let service = DeepSeekService(api: DeepSeekAPI(transport: transport))
        do {
            _ = try await service.refresh(id: id, widget: true, permission: { false })
            XCTFail("unauthorized service must reject")
        } catch {}
        var state = WidgetRefreshAttempt()
        state.fail(Date()); try state.save(id)
        _ = try await service.refresh(id: id, widget: true, permission: { true })
        let suppressed = await transport.requests
        XCTAssertTrue(suppressed.isEmpty)
        try WidgetRefreshAttempt().save(id)
        var coordinator = WidgetRefreshCoordinator()
        coordinator.canRefresh = { _ in true }
        coordinator.refresh = { accountID, _, _ in
            _ = try await service.refresh(id: accountID, widget: true, permission: { true })
        }
        let attempted = await coordinator.perform([WidgetRefreshSlot(id: id, provider: "deepseek")])
        XCTAssertEqual(attempted, [id], "failed attempts must re-read persisted failure copy")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try Data(contentsOf: DeepSeekStore.snapshotURL(id)), before)
        XCTAssertTrue(WidgetRefreshAttempt.load(id).failed)
        XCTAssertFalse(WidgetRefreshAttempt.load(id).allows(Date()))
    }

    func testTimelineRefreshesOnlyStaleCache() async {
        let now = Date(timeIntervalSince1970: 10_000)
        var coordinator = WidgetRefreshCoordinator()
        coordinator.now = { now }
        coordinator.canRefresh = { _ in true }
        coordinator.attempt = { _ in WidgetRefreshAttempt() }
        let fresh = WidgetRefreshSlot(id: "fresh", provider: "codex", updatedAt: now.addingTimeInterval(-60))
        let stale = WidgetRefreshSlot(id: "stale", provider: "codex", updatedAt: now.addingTimeInterval(-600))
        XCTAssertEqual(coordinator.targets([fresh], respectFreshness: true), [])
        XCTAssertEqual(coordinator.targets([stale], respectFreshness: true).map(\.id), ["stale"])
        // The button is not freshness-gated; it has its own throttle.
        XCTAssertEqual(coordinator.targets([fresh], respectFreshness: false).map(\.id), ["fresh"])
    }

    func testTokensCISharesTheSameRefreshPathAndUsesItsPrefixedAttemptFile() async throws {
        XCTAssertEqual(WidgetRefreshAttempt.attemptID("alice", provider: "tokensci"), "tokensci:alice")
        XCTAssertEqual(WidgetRefreshAttempt.attemptID("codex-a", provider: "codex"), "codex-a")
        var state = WidgetRefreshAttempt()
        state.fail(Date())
        var coordinator = WidgetRefreshCoordinator()
        coordinator.canRefresh = { _ in true }
        coordinator.attempt = { key in
            XCTAssertEqual(key, "tokensci:alice")
            return state
        }
        coordinator.refresh = { _, _, _ in XCTFail("backoff must not fetch") }
        _ = await coordinator.perform([WidgetRefreshSlot(id: "alice", provider: "tokensci")])
    }

    /// The per-provider Keychain audit, pinned as a regression test: in the extension every
    /// credential query carries the permitted access-group (never the App's default group) and
    /// every read is refused unless that account's credential group was published as permitted.
    func testEveryProviderReadsItsCredentialFromThePermittedGroup() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sharedQuery = "if SharedStorage.isWidget, let group = SharedStorage.permittedGroup { q[kSecAttrAccessGroup as String] = group }"
        let guarded = "if SharedStorage.isWidget && !DashboardStore.canRefresh"
        let files = ["DashboardStore": "DeepSeek", "OpenCodeGo": "OpenCodeGo", "CommandCode": "CommandCode",
                     "OpenRouter": "OpenRouter", "OllamaCloud": "OllamaCloud", "Qoder": "Qoder",
                     "Antigravity": "Antigravity", "TokensCI": "TokensCI"]
        for (name, label) in files {
            let source = try String(contentsOf: root.appendingPathComponent("Shared/\(name).swift"))
            XCTAssertTrue(source.contains(sharedQuery), "\(label) must pin the widget query to the permitted group")
            XCTAssertTrue(source.contains(guarded), "\(label) must refuse a widget read without permission")
        }
        // Claude takes the same decision through its `widget:` parameter instead of the process flag.
        let claude = try String(contentsOf: root.appendingPathComponent("Shared/Claude.swift"))
        XCTAssertTrue(claude.contains("if widget, let group = SharedStorage.permittedGroup"))
        XCTAssertTrue(claude.contains("if widget && !DashboardStore.canRefresh"))
        // Codex routes through StorageRouting, which only attaches a group when the widget was
        // granted one; the read then requires that shared route.
        let storage = try String(contentsOf: root.appendingPathComponent("Shared/Storage.swift"))
        XCTAssertTrue(storage.contains("authorizedGroup: isWidget ? permittedGroup : nil"))
        XCTAssertTrue(storage.contains("if isShared { q[kSecAttrAccessGroup as String] = authorizedGroup }"))
    }

    func testEveryRefreshGoesThroughTheWidgetPermissionPath() throws {
        let views = try String(contentsOfFile: #filePath.replacingOccurrences(of: "Tests/WidgetRefreshLogicTests.swift", with: "Shared/WidgetRefreshLogic.swift"), encoding: .utf8)
        // Every provider call in the shared refresh entry point names widget: true explicitly:
        // relying on SharedStorage.isWidget would silently send an App-mode request from tests.
        let entry = views.split(separator: "static func one(", maxSplits: 1).last.map(String.init) ?? ""
        let body = entry.split(separator: "enum ").first.map(String.init) ?? entry
        XCTAssertTrue(body.contains("widget: true"))
        for provider in ["OpenCodeGo", "CommandCode", "OpenRouter", "OllamaCloud", "Qoder", "DeepSeek", "Claude", "Antigravity"] {
            let line = body.split(separator: "\n").first { $0.contains(provider) }
            XCTAssertNotNil(line, provider)
            XCTAssertTrue(line?.contains("widget: true") == true, "\(provider) must pass widget: true")
        }
        XCTAssertTrue(body.contains("TokensCIService.shared.refresh"), "tokens.ci must not stay cache-only")
    }
}

actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
