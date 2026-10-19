import XCTest
@testable import CodeGo

final class TokensCITests: XCTestCase {
    struct Wire: HTTPTransport {
        let data: Data
        let status: Int
        func send(_ request: URLRequest) async throws -> (Data, Int) { (data, status) }
    }
    func fixture() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/tokensci-public.json"))
    }
    func read(_ data: Data, status: Int = 200) async throws -> TokensCISnapshot {
        try await TokensCIAPI(transport: Wire(data: data, status: status)).profile(username: "Alice39s", token: "tkr_test_fixture_only")
    }
    func testLocalCalendarDayRowsMatchTotalAtMidnight() async throws {
        var payload = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        payload["contributions"] = [
            ["date": "2001-01-01", "timestampMs": Date().timeIntervalSince1970 * 1000, "totals": ["tokens": 9000, "cost": 99], "clients": [["client": "codex", "tokens": ["input": 9000], "cost": 99]]],
            ["date": today, "totals": ["tokens": 120, "cost": 3], "clients": [["client": "hermes", "tokens": ["input": 100, "output": 20], "cost": 3, "models": ["model-a": ["tokens": 80, "cost": 1], "model-b": ["tokens": 40, "cost": 2]]]]]
        ]
        let value = try await read(JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(value.todayTokens, 120)
        XCTAssertEqual(value.clients.map(\.name), ["hermes"])
        XCTAssertEqual(value.clients.reduce(0) { $0 + $1.tokens }, value.todayTokens)
        XCTAssertEqual(value.clients.reduce(0) { $0 + $1.cost }, value.todayCost)
        XCTAssertEqual(value.clients.first?.topModel?.cost, 1)
    }
    func testLocalMidnightFractionalUpdateAndMissingDay() async throws {
        var payload = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        payload["updatedAt"] = "2026-10-17T16:54:00.246Z"
        payload["contributions"] = [
            ["date": "2026-10-17", "totals": ["tokens": 90, "cost": 9], "clients": [["client": "codex", "tokens": ["input": 90], "cost": 9]]],
            ["date": "2026-10-18", "totals": ["tokens": 12, "cost": 1], "clients": [["client": "hermes", "tokens": ["input": 12], "cost": 1]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let api = TokensCIAPI(transport: Wire(data: data, status: 200))
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let iso = ISO8601DateFormatter()
        for (instant, expected, name) in [("2026-10-17T15:59:59Z", 90.0, "codex"), ("2026-10-17T16:00:00Z", 12.0, "hermes"), ("2026-10-18T16:00:00Z", 0.0, "")] {
            let result = try await api.profile(username: "fixture", token: "tkr_fixture", now: iso.date(from: instant)!, timeZone: zone)
            XCTAssertEqual(result.todayTokens, expected)
            XCTAssertEqual(result.clients.first?.name ?? "", name)
            XCTAssertEqual(result.dataUpdatedAt.timeIntervalSince1970, iso.date(from: "2026-10-17T16:54:00Z")!.timeIntervalSince1970 + 0.246, accuracy: 0.001)
        }
    }
    func testOldCacheCannotExposeLifetimeRows() async throws {
        let value = try await read(fixture())
        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        encoded.removeValue(forKey: "selectedDay")
        encoded["todayTokens"] = 999
        encoded["clients"] = [["name": "codex", "tokens": 999, "cost": 5]]
        encoded.removeValue(forKey: "selectedTimeZone")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        SharedStorage.containerOverride = directory
        defer { SharedStorage.containerOverride = nil; try? FileManager.default.removeItem(at: directory) }
        try JSONSerialization.data(withJSONObject: encoded).write(to: TokensCIStore.snapshotURL("fixture"))
        XCTAssertTrue(TokensCIStore.snapshot("fixture")?.clients.isEmpty ?? false)
        XCTAssertEqual(TokensCIStore.snapshot("fixture")?.todayTokens, 0)
    }
    func testRealPublicWireDecodesClientArrayAndDailyModels() async throws {
        let value = try await TokensCIAPI(transport: Wire(data: fixture(), status: 200)).profile(username: "Alice39s", token: "tkr_fixture", now: ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(value.totalTokens, 455594761292)
        XCTAssertFalse(value.clients.isEmpty)
        XCTAssertGreaterThan(value.clients.first?.tokens ?? 0, 0)
        XCTAssertNotNil(value.clients.first?.topModel)
        XCTAssertEqual(value.clients.first?.name, "pi")
        XCTAssertEqual(value.clients.first?.tokens ?? 0, 1061210925, accuracy: 1)
        XCTAssertEqual(value.clients.reduce(0) { $0 + $1.tokens }, value.todayTokens, accuracy: 1)
        XCTAssertEqual(value.clients.reduce(0) { $0 + $1.cost }, value.todayCost, accuracy: 0.001)
        XCTAssertEqual(value.dataUpdatedAt.timeIntervalSince1970, 1791052276.246, accuracy: 0.001)
    }
    func testMissingTodayNeverUsesLatestReportedDay() async throws {
        var payload = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        payload["contributions"] = [["date": "2001-01-01", "totals": ["tokens": 999, "cost": 50], "clients": []]]
        let value = try await read(JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(value.todayTokens, 0)
        XCTAssertEqual(value.todayCost, 0)
        XCTAssertTrue(value.clients.isEmpty)
    }
    func testErrorsDoNotReplaceCachedSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        SharedStorage.containerOverride = directory
        defer { SharedStorage.containerOverride = nil; try? FileManager.default.removeItem(at: directory) }
        let value = try await read(fixture())
        try TokensCIStore.save(value, username: "Alice39s")
        let before = try Data(contentsOf: TokensCIStore.snapshotURL("Alice39s"))
        for status in [401, 403, 404, 409, 429, 500] {
            do { _ = try await read(Data("{}".utf8), status: status); XCTFail("Expected failure") } catch {}
            XCTAssertEqual(try Data(contentsOf: TokensCIStore.snapshotURL("Alice39s")), before)
        }
        do { _ = try await read(Data("{}".utf8)); XCTFail("Expected malformed") } catch {}
        XCTAssertEqual(TokensCIStore.snapshot("Alice39s"), value)
    }
    func testRejectsSubmitTokenAndEmptyReadToken() throws {
        XCTAssertThrowsError(try TokensCIAPI.validatedToken("tt_wrong"))
        XCTAssertThrowsError(try TokensCIAPI.validatedToken("tkr_"))
    }
}
