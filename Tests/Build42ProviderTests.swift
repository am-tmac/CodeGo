import XCTest
@testable import CodeGo

// Failure inventory (written before implementation): unknown/expired credits; negative counts;
// missing optional dates; supplementary HTTP failure; wrong auth routing; absent Go subscription;
// aliases/precedence, clamping, missing denominators, fractional/epoch/ms dates; numeric strings;
// remaining vs used money; unknown plans; explicit grant precedence; enrichment failure;
// invalid keys, authorization, throttling, cancellation; cache isolation/order/round-trip.
final class Build42ProviderTests: XCTestCase {
    func data(_ text: String) -> Data { Data(text.utf8) }
    func testResetCreditsLenientStatusesExpiryAndOrdering() throws {
        let value = try CodexResetCredits.parse(data(#"{"available_count":4,"total_earned_count":7,"credits":[{"status":"available"},{"status":"future-status","expires_at":"2030-01-01T00:00:00Z"},{"status":"available","expires_at":"2026-07-18T00:39:53.731630Z"},{"status":"available","expires_at":"2030-01-01T00:00:00Z"}]}"#))
        XCTAssertEqual(value.credits[1].status, "future-status")
        let usable = value.usable(now: Date(timeIntervalSince1970: 1800000000))
        XCTAssertEqual(usable.count, 2)
        XCTAssertNotNil(usable.first?.expiresAt)
        XCTAssertNil(usable.last?.expiresAt)
        XCTAssertEqual(value.totalEarnedCount, 7)
        XCTAssertThrowsError(try CodexResetCredits.parse(data(#"{"available_count":-1,"credits":[]}"#)))
        XCTAssertEqual(try CodexResetCredits.parse(data(#"{"credits":[],"available_count":0}"#)).availableCount, 0)
    }
    func testResetCreditsSupplementaryRequestAndFallback() async throws {
        let credentials = Credentials(accessToken: "fixture", refreshToken: "refresh", accountID: "workspace", email: nil, expiresAt: .distantFuture)
        for status in [200, 500] {
            let transport = ScriptedTransport([(#"{"rate_limit_reset_credits":{"available_count":3}}"#, 200), (#"{"available_count":0,"credits":[]}"#, status)])
            let value = try await AuthAPI(transport: transport).usageWithResetCredits(credentials)
            XCTAssertEqual(value.resetCreditDetails?.availableCount, status == 200 ? 0 : nil)
            XCTAssertEqual(value.rateLimitResetCredits?.availableCount, 3)
            let requests = await transport.requests
            XCTAssertEqual(requests.map { $0.url!.path }, ["/backend-api/wham/usage", "/backend-api/wham/rate-limit-reset-credits"])
            XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture" && $0.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "workspace" })
        }
    }
    func testOpenCodeAliasesPrecedenceClampingAndMissingFields() throws {
        let now = Date(timeIntervalSince1970: 1000)
        for name in ["usagePercent", "usedPercent", "percentUsed", "percent"] {
            let value = try OpenCodeGoUsage.parse(data("{\"usage\":{\"rolling\":{\"\(name)\":125,\"used\":1,\"limit\":4,\"resetInSec\":60}}}"), now: now)
            XCTAssertEqual(value.rolling?.usedPercent, 100)
            XCTAssertEqual(value.rolling?.resetAt, 1060)
            XCTAssertNil(value.weekly)
        }
        let value = try OpenCodeGoUsage.parse(data(#"{"usage":{"rollingUsage":{"window":{"consumed":1,"cap":4,"resetAt":1780300000000}},"weeklyUsage":{"usage":2,"total":10,"resets_at":"2026-06-18T00:39:53.731630Z"},"monthlyUsage":{}},"renewAt":"2026-07-18T00:39:53Z"}文"#.replacingOccurrences(of: "文", with: "")))
        XCTAssertEqual(value.rolling?.usedPercent, 25)
        XCTAssertEqual(value.rolling?.resetAt, 1780300000)
        XCTAssertEqual(value.weekly?.usedPercent, 20)
        XCTAssertNil(value.monthly)
        XCTAssertNotNil(value.renewAt)
        XCTAssertThrowsError(try OpenCodeGoUsage.parse(data(#"{"usage":{}}"#)))
        XCTAssertNil(try OpenCodeGoUsage.parse(data(#"{"usage":{"rolling":{"used":2,"limit":0}}}"#)).rolling)
    }
    func testCommandRemainingGrantWindowsAndPlans() throws {
        let sub = data(#"{"success":true,"data":{"status":"active","planId":"individual-go","currentPeriodEnd":"2026-06-06T07:28:50.000Z"}}"#)
        let value = try CommandCodeUsage.parse(data(#"{"credits":{"monthlyCredits":"7.25","purchasedCredits":2,"windowLimits":{"fiveHour":{"cap":"4","used":"1","resetAt":"1780200000"},"weekly":{"cap":20,"used":4,"resetAt":1780300000000}}}}"#), subscription: sub)
        XCTAssertEqual(value.monthlyCredits, Decimal(string: "7.25"))
        XCTAssertEqual(value.monthlyGrant, 10)
        XCTAssertTrue(value.grantFromPlan)
        XCTAssertEqual(value.monthly?.remaining, 72.5)
        XCTAssertEqual(value.fiveHour?.usedPercent, 25)
        XCTAssertEqual(value.weekly?.resetAt, 1780300000)
        XCTAssertEqual(value.planName, "Go")
        XCTAssertNotNil(value.periodEnd)
        let explicit = try CommandCodeUsage.parse(data(#"{"credits":{"monthlyCredits":8,"monthlyCreditsGranted":20},"windowLimits":{"fiveHour":{"used":1,"cap":4}}}"#), subscription: sub)
        XCTAssertEqual(explicit.monthly?.remaining, 40)
        XCTAssertFalse(explicit.grantFromPlan)
        XCTAssertEqual(explicit.fiveHour?.remaining, 75)
        let bare = try CommandCodeUsage.parse(data(#"{"credits":{"monthlyCredits":8.7784}}"#))
        XCTAssertNil(bare.monthly)
        XCTAssertNil(bare.monthlyGrant)
        XCTAssertThrowsError(try CommandCodeUsage.parse(data(#"{}"#)))
        for (plan, grant) in [("individual-go-v1", 10), ("individual-goat", 70), ("individual-pro", 30), ("individual-pro-v1", 80), ("individual-max", 150), ("individual-ultra", 300)] {
            let result = try CommandCodeUsage.parse(data(#"{"credits":{"monthlyCredits":1}}"#), subscription: data("{\"data\":{\"planId\":\"\(plan)\"}}"))
            XCTAssertEqual(result.monthlyGrant, Decimal(grant))
        }
        let unknown = try CommandCodeUsage.parse(data(#"{"credits":{}}"#), subscription: data(#"{"data":{"planId":"new-plan"}}"#))
        XCTAssertNil(unknown.monthlyGrant)
        XCTAssertNil(unknown.monthlyCredits)
    }
    func testProviderTransportErrorsAndOptionalSubscription() async throws {
        let go = ScriptedTransport([(#"{"usage":{"rolling":{"percent":33}}}"#, 200)])
        _ = try await OpenCodeGoAPI(transport: go).usage(key: "fixture")
        let requests = await go.requests
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://opencode.ai/zen/go/v1/usage")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
        let command = ScriptedTransport([(#"{"credits":{"monthlyCredits":8}}"#, 200), ("{}", 503)])
        let value = try await CommandCodeAPI(transport: command).usage(key: "user_fixture")
        XCTAssertEqual(value.monthlyCredits, 8)
        XCTAssertNil(value.monthlyGrant)
        let paths = await command.requests.map { $0.url!.path }
        XCTAssertEqual(paths, ["/alpha/billing/credits", "/alpha/billing/subscriptions"])
        for status in [401, 403, 429, 500] {
            do { _ = try await OpenCodeGoAPI(transport: ScriptedTransport([("{}", status)])).usage(key: "fixture"); XCTFail() }
            catch { XCTAssertTrue(error is OpenCodeGoError) }
            do { _ = try await CommandCodeAPI(transport: ScriptedTransport([("{}", status)])).usage(key: "fixture"); XCTFail() }
            catch { XCTAssertTrue(error is CommandCodeError) }
        }
        XCTAssertThrowsError(try OpenCodeGoAPI.validatedKey("bad\nkey"))
        XCTAssertThrowsError(try CommandCodeAPI.validatedKey(" "))
    }
    func testNewProviderSnapshotCacheIsolationAndCardOrder() throws {
        TestContainer.install()
        let go = OpenCodeGoSnapshot(usage: try OpenCodeGoUsage.parse(data(#"{"usage":{"rolling":{"percent":50}}}"#)), updatedAt: Date())
        try OpenCodeGoStore.save(go, id: "fixture")
        XCTAssertEqual(OpenCodeGoStore.snapshot("fixture"), go)
        XCTAssertNil(CommandCodeStore.snapshot("fixture"))
        let command = CommandCodeSnapshot(usage: try CommandCodeUsage.parse(data(#"{"credits":{"monthlyCredits":8}}"#)), updatedAt: Date())
        try CommandCodeStore.save(command, id: "fixture")
        XCTAssertEqual(CommandCodeStore.snapshot("fixture"), command)
        XCTAssertEqual(OpenCodeGoStore.snapshot("fixture"), go)
        let keys = ["codex:a", "opencodego:b", "commandcode:c"]
        XCTAssertEqual(CardOrder.sorted(keys, by: [keys[2], keys[1]]), [keys[2], keys[1], keys[0]])
    }
    func testProviderCancellationAndNetworkMapping() async {
        do { _ = try await OpenCodeGoAPI(transport: CancelledBalanceTransport()).usage(key: "fixture"); XCTFail() }
        catch is CancellationError {} catch { XCTFail("Expected cancellation") }
        do { _ = try await CommandCodeAPI(transport: CancelledBalanceTransport()).usage(key: "fixture"); XCTFail() }
        catch is CancellationError {} catch { XCTFail("Expected cancellation") }
    }
    #if os(iOS)
    @MainActor func testAppNewProviderFailureKeepsSnapshotAndRefreshIsIsolated() async throws {
        let cached = OpenCodeGoSnapshot(usage: try OpenCodeGoUsage.parse(data(#"{"usage":{"rolling":{"percent":25}}}"#)), updatedAt: Date())
        let model = UsageModel(loadStoredAccounts: false, fetchers: AppRefreshFetchers(
            openCodeGo: { _ in throw OpenCodeGoError.network },
            commandCode: { _ in XCTFail("Unselected provider fetched"); throw CommandCodeError.network }))
        model.openCodeGoIDs = ["fixture"]
        model.openCodeGoSnapshots = ["fixture": cached]
        model.commandCodeIDs = ["other"]
        await model.refresh(target: .openCodeGo("fixture"))
        XCTAssertEqual(model.openCodeGoSnapshots["fixture"], cached)
        XCTAssertNotNil(model.refreshErrors[.openCodeGo("fixture")])
        XCTAssertNil(model.refreshErrors[.commandCode("other")])
    }
    #endif

}
