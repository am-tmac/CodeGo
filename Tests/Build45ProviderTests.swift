import XCTest
@testable import CodeGo

// Failure inventory, written before the implementation:
//  - OpenRouter: missing/aliased/string numbers, null limit, credits failure, 401/403/422.
//  - Ollama Cloud: percent aliases, used/limit aliases, reset aliases, nested `data`,
//    and the required "malformed" answer when no number at all can be recognised.
//  - Qoder: PAT exchange body/endpoint, token aliases, region hosts, snake+camel quota fields,
//    missing quota numbers, 401.
//  - Preferences: default Go for accounts created before the option existed, per-account
//    isolation, Qoder region, unreadable file, plan price text.
//  - Keychain: service names and a real save/read/delete round trip per provider.
final class Build45ProviderTests: XCTestCase {
    func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: OpenRouter

    func testOpenRouterParsesKeyCreditsAndRemaining() throws {
        let key = data(#"{"data":{"label":"main","limit":"20","usage":4.5,"limit_remaining":"15.5","is_free_tier":false,"is_provisioning_key":true}}"#)
        let credits = data(#"{"data":{"total_credits":"100.25","total_usage":30}}"#)
        let value = try OpenRouterUsage.parse(key: key, credits: credits)
        XCTAssertEqual(value.key.label, "main")
        XCTAssertEqual(value.key.limit, Decimal(string: "20"))
        XCTAssertEqual(value.key.limitRemaining, Decimal(string: "15.5"))
        XCTAssertEqual(value.key.isFreeTier, false)
        XCTAssertEqual(value.key.isProvisioningKey, true)
        XCTAssertEqual(value.credits?.totalCredits, Decimal(string: "100.25"))
        XCTAssertEqual(value.remainingCredits, Decimal(string: "70.25"))
        XCTAssertEqual(value.limitWindow?.usedPercent ?? -1, 22.5, accuracy: 0.001)
    }

    func testOpenRouterNullLimitUnlimitedAndMissingCredits() throws {
        let key = data(#"{"data":{"label":"free","limit":null,"limit_remaining":null,"usage":0,"is_free_tier":true}}"#)
        let value = try OpenRouterUsage.parse(key: key, credits: nil)
        XCTAssertNil(value.key.limit)
        XCTAssertNil(value.key.limitRemaining)
        XCTAssertNil(value.limitWindow)
        XCTAssertNil(value.remainingCredits)
        XCTAssertEqual(value.key.isFreeTier, true)
        // A credits document that is unreadable must not donate a made-up balance.
        XCTAssertNil(try OpenRouterUsage.parse(key: key, credits: data("{}")).remainingCredits)
    }

    func testOpenRouterRejectsMissingDataAndBadNumbers() {
        XCTAssertThrowsError(try OpenRouterUsage.parse(key: data(#"{"key":{}}"#), credits: nil)) { error in
            XCTAssertEqual(error as? OpenRouterError, .malformed)
        }
        let key = data(#"{"data":{"limit":"abc","usage":null}}"#)
        XCTAssertNil(try? OpenRouterUsage.parse(key: key, credits: nil).key.limit)
        let value = try? OpenRouterUsage.parse(key: key, credits: nil)
        XCTAssertNil(value?.limitWindow)
    }

    func testOpenRouterHTTPFailureMappingAndCreditsTolerance() async throws {
        for status in [401, 403] {
            do {
                _ = try await OpenRouterAPI(transport: ScriptedTransport([("{}", status)])).usage(key: "fixture")
                XCTFail("expected unauthorized")
            } catch let error as OpenRouterError { XCTAssertEqual(error, .unauthorized) }
        }
        do {
            _ = try await OpenRouterAPI(transport: ScriptedTransport([("{}", 422)])).usage(key: "fixture")
            XCTFail("expected http")
        } catch let error as OpenRouterError { XCTAssertEqual(error, .http(422)) }

        let key = #"{"data":{"limit":10,"limit_remaining":7.5,"usage":2.5}}"#
        let transport = ScriptedTransport([(key, 200), ("{}", 500)])
        let value = try await OpenRouterAPI(transport: transport).usage(key: "fixture")
        XCTAssertEqual(value.key.limitRemaining, Decimal(string: "7.5"))
        XCTAssertNil(value.credits)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/v1/key", "/api/v1/credits"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture" })
    }

    // MARK: Ollama Cloud

    func testOllamaParsesPercentAliasesUsedLimitAndReset() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        for name in ["percent", "usedPercent", "usagePercent"] {
            let value = try OllamaCloudUsage.parse(data("{\"\(name)\":37.5}"), now: now)
            XCTAssertEqual(value.window?.usedPercent, 37.5)
            XCTAssertEqual(value.percent, 37.5)
        }
        let value = try OllamaCloudUsage.parse(data(#"{"data":{"used":"3","limit":12,"resetInSec":90}}"#), now: now)
        XCTAssertEqual(value.window?.usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(value.used, Decimal(3))
        XCTAssertEqual(value.limit, Decimal(12))
        XCTAssertEqual(value.window?.resetAt, 1_090)
        XCTAssertEqual(try OllamaCloudUsage.parse(data(#"{"resetsAt":"2026-06-18T00:40:00Z","percent":10}"#)).window?.resetAt, 1_781_743_200)
    }

    func testOllamaUnrecognisedBalanceIsMalformedWithTheExactUserCopy() {
        for text in [#"{}"#, #"{"balance":"n/a"}"#, #"{"used":4,"limit":0}"#] {
            XCTAssertThrowsError(try OllamaCloudUsage.parse(data(text))) { error in
                XCTAssertEqual(error as? OllamaCloudError, .malformed)
                XCTAssertEqual((error as? OllamaCloudError)?.localizedDescription, "无法识别该账号的余额格式")
            }
        }
    }

    func testOllamaHTTPMapping() async throws {
        do {
            _ = try await OllamaCloudAPI(transport: ScriptedTransport([(#"{"error":"invalid credentials"}"#, 401)])).usage(key: "fixture")
            XCTFail("expected unauthorized")
        } catch let error as OllamaCloudError { XCTAssertEqual(error, .unauthorized) }
        do {
            _ = try await OllamaCloudAPI(transport: ScriptedTransport([("{}", 503)])).usage(key: "fixture")
            XCTFail("expected http")
        } catch let error as OllamaCloudError { XCTAssertEqual(error, .http(503)) }
        let transport = ScriptedTransport([(#"{"percent":20}"#, 200)])
        _ = try await OllamaCloudAPI(transport: transport).usage(key: "fixture")
        let request = await transport.requests.first
        XCTAssertEqual(request?.url?.absoluteString, "https://ollama.com/api/balance")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
    }

    // MARK: Qoder

    func testQoderRegionHostsAndLinks() {
        XCTAssertEqual(QoderRegion.china.baseURL, "https://openapi.qoder.com.cn")
        XCTAssertEqual(QoderRegion.global.baseURL, "https://openapi.qoder.sh")
        XCTAssertEqual(QoderRegion.china.integrationsURL, "https://qoder.cn/account/integrations")
        XCTAssertEqual(QoderRegion.global.integrationsURL, "https://qoder.com/account/integrations")
        XCTAssertEqual(QoderRegion.china.displayName, "国内")
        XCTAssertEqual(QoderRegion.global.displayName, "国际")
    }

    func testQoderExchangesPatThenReadsQuota() async throws {
        let exchange = #"{"data":{"jobToken":"job-123"}}"#
        let quota = #"{"data":{"weekly_window_start":"2026-06-01T00:00:00Z","weekly_usage_usd":"3.5","weekly_limit_usd":20,"monthly_usage_usd":"12","monthly_limit_usd":"80","plan":"pro","addOn":5}}"#
        let transport = ScriptedTransport([(exchange, 200), (quota, 200)])
        let value = try await QoderAPI(transport: transport, region: .global).usage(personalAccessToken: "pat-fixture")
        XCTAssertEqual(value.plan, "pro")
        XCTAssertEqual(value.addOn, Decimal(5))
        XCTAssertEqual(value.weeklyUsed, Decimal(string: "3.5"))
        XCTAssertEqual(value.weeklyLimit, 20)
        XCTAssertEqual(value.weekly?.usedPercent ?? -1, 17.5, accuracy: 0.001)
        XCTAssertEqual(value.monthly?.usedPercent ?? -1, 15, accuracy: 0.001)
        XCTAssertNotNil(value.weeklyStart)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/v1/jobToken/exchange", "/api/v2/quota/usage"])
        XCTAssertEqual(requests.first?.url?.host, "openapi.qoder.sh")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body: Data = try XCTUnwrap(requests.first?.httpBody)
        let object = try JSONSerialization.jsonObject(with: body)
        let json = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(json["personalAccessToken"] as? String, "pat-fixture")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer job-123")
    }

    func testQoderParsesAliasesAndNestedContainers() throws {
        let value = try QoderUsage.parse(data(#"{"quota":{"weeklyWindowStart":1780000000,"weeklyUsageUsd":1,"weeklyLimitUsd":4,"monthlyUsageUsd":2,"monthlyLimitUsd":10,"planName":"plus","add_on":"2.5"}}"#))
        XCTAssertEqual(value.weeklyStart, Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertEqual(value.weekly?.usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(value.monthly?.usedPercent ?? -1, 20, accuracy: 0.001)
        XCTAssertEqual(value.plan, "plus")
        XCTAssertEqual(value.addOn, Decimal(string: "2.5"))
        XCTAssertEqual(value.planName, "Agent Plan · plus")
    }

    func testQoderRejectsMissingQuotaAndToken() {
        XCTAssertThrowsError(try QoderUsage.parse(data(#"{"plan":"pro"}"#))) { error in
            XCTAssertEqual(error as? QoderError, .malformed)
        }
        XCTAssertThrowsError(try QoderUsage.parse(data(#"{"weekly_limit_usd":0,"weekly_usage_usd":0}"#)))
        XCTAssertThrowsError(try QoderJobToken.parse(data(#"{"data":{}}"#))) { error in
            XCTAssertEqual(error as? QoderError, .malformed)
        }
        XCTAssertEqual(try QoderJobToken.parse(data(#"{"token":"t"}"#)).token, "t")
        XCTAssertEqual(try QoderJobToken.parse(data(#"{"data":{"accessToken":"a"}}"#)).token, "a")
    }

    func testQoderHTTPMapping() async throws {
        do {
            _ = try await QoderAPI(transport: ScriptedTransport([("{}", 401)]), region: .china).usage(personalAccessToken: "pat")
            XCTFail("expected unauthorized")
        } catch let error as QoderError { XCTAssertEqual(error, .unauthorized) }
        do {
            _ = try await QoderAPI(transport: ScriptedTransport([(#"{"data":{"jobToken":"job"}}"#, 200), ("{}", 429)]), region: .china).usage(personalAccessToken: "pat")
            XCTFail("expected rate limit")
        } catch let error as QoderError { XCTAssertEqual(error, .rateLimited) }
        do {
            _ = try await QoderAPI(transport: ScriptedTransport([("{}", 500)]), region: .china).usage(personalAccessToken: "pat")
            XCTFail("expected http")
        } catch let error as QoderError { XCTAssertEqual(error, .http(500)) }
    }

    // MARK: Card data

    func testCardDataForTheThreeProviders() throws {
        let openRouter = try OpenRouterUsage.parse(key: data(#"{"data":{"limit":20,"limit_remaining":15,"usage":5,"is_free_tier":false}}"#),
                                                   credits: data(#"{"data":{"total_credits":50,"total_usage":20}}"#))
        let card = ProviderCardData(OpenRouterSnapshot(usage: openRouter, updatedAt: Date()))
        XCTAssertEqual(card.rows.map(\.label), ["剩余额度", "本 Key 限额", "免费档"])
        XCTAssertEqual(card.rows[0].money, "US$30.00")
        XCTAssertEqual(card.rows[1].money, "US$15.00 / US$20.00")
        XCTAssertEqual(card.rows[2].detail, "否")

        let ollama = try OllamaCloudUsage.parse(data(#"{"percent":42,"used":2,"limit":10}"#))
        let ollamaCard = ProviderCardData(OllamaCloudSnapshot(usage: ollama, updatedAt: Date()))
        XCTAssertEqual(ollamaCard.rows.map(\.label), ["余额"])
        XCTAssertEqual(ollamaCard.rows[0].window?.usedPercent, 42)

        let qoder = try QoderUsage.parse(data(#"{"weekly_usage_usd":5,"weekly_limit_usd":20,"monthly_usage_usd":10,"monthly_limit_usd":40,"plan":"pro","addOn":3}"#))
        let qoderCard = ProviderCardData(QoderSnapshot(usage: qoder, updatedAt: Date()))
        XCTAssertEqual(qoderCard.rows.map(\.label), ["每周", "每月"])
        XCTAssertEqual(qoderCard.rows[0].money, "US$5.00 / US$20.00")
        XCTAssertEqual(qoderCard.plan, "Agent Plan · pro")
        XCTAssertEqual(qoderCard.purchased, "US$3.00")
    }

    func testOpenCodeGoPlanPricesAndCardPlan() {
        XCTAssertEqual(OpenCodeGoPlan.go.displayName, "Go")
        XCTAssertEqual(OpenCodeGoPlan.goPlus.displayName, "Go Plus")
        XCTAssertEqual(OpenCodeGoPlan.go.priceText, "US$10/月")
        XCTAssertEqual(OpenCodeGoPlan.goPlus.priceText, "US$40/月")
        let snapshot = OpenCodeGoSnapshot(usage: OpenCodeGoUsage(rolling: nil, weekly: nil, monthly: nil, renewAt: nil), updatedAt: Date())
        XCTAssertEqual(ProviderCardData(snapshot).plan, "Go · US$10/月")
        XCTAssertEqual(ProviderCardData(snapshot, plan: .goPlus).plan, "Go Plus · US$40/月")
        // Three windows stay exactly as before.
        XCTAssertEqual(ProviderCardData(snapshot, plan: .goPlus).rows.map(\.label), ["5 小时", "每周", "每月"])
    }

    // MARK: Preferences (plan + region)

    func testPreferencesDefaultToGoForAccountsCreatedBeforeTheOption() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prefs-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProviderPreferenceStore(url: url)
        XCTAssertEqual(store.openCodeGoPlan(accountID: "opencodego-old"), .go)
        XCTAssertEqual(store.qoderRegion(accountID: "qoder-old"), .china)
        XCTAssertTrue(ProviderPreferenceStore(url: nil).openCodeGoPlan(accountID: "any") == .go)
        _ = url

        try store.setOpenCodeGoPlan(.goPlus, accountID: "opencodego-a")
        try store.setOpenCodeGoPlan(.go, accountID: "opencodego-b")
        try store.setQoderRegion(.global, accountID: "qoder-a")
        XCTAssertEqual(store.openCodeGoPlan(accountID: "opencodego-a"), .goPlus)
        XCTAssertEqual(store.openCodeGoPlan(accountID: "opencodego-b"), .go)
        XCTAssertEqual(store.openCodeGoPlan(accountID: "opencodego-c"), .go)
        XCTAssertEqual(store.qoderRegion(accountID: "qoder-a"), .global)
        XCTAssertEqual(store.qoderRegion(accountID: "qoder-b"), .china)

        try store.remove(accountID: "opencodego-a")
        XCTAssertEqual(store.openCodeGoPlan(accountID: "opencodego-a"), .go)
        XCTAssertEqual(store.qoderRegion(accountID: "qoder-a"), .global)

        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(store.openCodeGoPlan(accountID: "opencodego-b"), .go)
        XCTAssertEqual(store.qoderRegion(accountID: "qoder-a"), .china)
    }

    // MARK: Keychain

    private func keychainQuery(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func testProviderKeychainNamesAndRoundTrip() throws {
        XCTAssertEqual(OpenRouterStore.service, "CodexUsage.OpenRouter.api-key.v1")
        XCTAssertEqual(OllamaCloudStore.service, "CodexUsage.OllamaCloud.api-key.v1")
        XCTAssertEqual(QoderStore.service, "CodexUsage.Qoder.api-key.v1")
        XCTAssertEqual(try OpenRouterStore.snapshotURL("openrouter-1").pathExtension, "usage")
        XCTAssertEqual(try QoderStore.snapshotURL("qoder-1").pathExtension, "usage")
        XCTAssertNotEqual(try OpenRouterStore.snapshotURL("openrouter-1"), try OpenRouterStore.snapshotURL("openrouter-2"))

        for (service, account, value) in [("CodexUsage.OpenRouter.test.\(UUID().uuidString)", "a", "or-key"),
                                          ("CodexUsage.OllamaCloud.test.\(UUID().uuidString)", "b", "ollama-key"),
                                          ("CodexUsage.Qoder.test.\(UUID().uuidString)", "c", "qoder-pat")] {
            let query = keychainQuery(service, account)
            defer { SecItemDelete(query as CFDictionary) }
            var attributes = query
            attributes[kSecValueData as String] = Data(value.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecMissingEntitlement { throw XCTSkip("Keychain unavailable in this signing configuration (\(status))") }
            XCTAssertEqual(status, errSecSuccess)
            var read = query
            read[kSecReturnData as String] = true
            var result: CFTypeRef?
            XCTAssertEqual(SecItemCopyMatching(read as CFDictionary, &result), errSecSuccess)
            XCTAssertEqual((result as? Data).flatMap { String(data: $0, encoding: .utf8) }, value)
        }
    }
}
