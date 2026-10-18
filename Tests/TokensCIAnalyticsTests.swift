import XCTest
@testable import CodexUsageCore

final class TokensCIAnalyticsTests: XCTestCase {
    func testCalendarMissingDuplicateLeapAndStreak() throws {
        let json = """
        [{"date":"2024-02-28","totals":{"tokens":10,"cost":1}},
         {"date":"2024-02-29","totals":{"tokens":20,"cost":2}},
         {"date":"2024-02-29","totals":{"tokens":3,"cost":0.5}},
         {"date":"2024-03-02","totals":{"tokens":7,"cost":1}},
         {"date":"2024-02-30","totals":{"tokens":999,"cost":9}},null,{"bad":true}]
        """
        let history = try TokensCIHistory.decode(Data(json.utf8))
        XCTAssertEqual(history.days.count, 3)
        XCTAssertEqual(history.day("2024-02-29")?.tokens, 23)
        XCTAssertNil(history.day("2024-03-01"))
        let a = history.analytics(ending: "2024-03-02", days: 4)
        XCTAssertEqual(a.tokens, 40)
        XCTAssertEqual(a.activeDays, 3)
        XCTAssertEqual(a.streak, 1)
        XCTAssertEqual(a.longestStreak, 2)
        XCTAssertNil(history.day("2024-03-02")?.messages)
        XCTAssertNil(history.analytics(ending: "2024-03-03", days: 4).cacheReadRatio)
    }
    func testNonfiniteAndSourceTotalsStayHonest() throws {
        let data = Data("""
        [{"date":"2024-01-01","totals":{"tokens":100,"cost":5,"messages":0},"tokenBreakdown":{"input":10,"cacheRead":90},"clients":[{"client":"codex","tokens":{"input":20},"cost":2,"messages":3,"models":{"real":{"tokens":20,"cost":2},"<synthetic>":{"tokens":80,"cost":3}}}]}]
        """.utf8)
        let h = try TokensCIHistory.decode(data)
        let a = h.analytics(ending: "2024-01-01", days: 30)
        XCTAssertEqual(a.tokens, 100)
        XCTAssertEqual(a.clients.first?.tokens, 20)
        XCTAssertEqual(a.models.map(\.name), ["real"])
        XCTAssertEqual(a.cacheReadRatio, 0.9)
        XCTAssertNil(h.days.first?.messages)
        XCTAssertNil(TokensCIHistory.validNumber(.nan))
        XCTAssertNil(TokensCIHistory.validNumber(.infinity))
        XCTAssertNil(TokensCIHistory.validNumber(-1))
    }
    func testPrivateHistoryNeverPublishedAndTolerantWire() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let privateDirectory = directory.appendingPathComponent("private")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        SharedStorage.containerOverride = directory
        TokensCIHistoryStore.directoryOverride = privateDirectory
        defer { SharedStorage.containerOverride = nil; TokensCIHistoryStore.directoryOverride = nil; try? FileManager.default.removeItem(at: directory) }
        let source = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/tokensci-public.json"))
        var wire = try JSONSerialization.jsonObject(with: source) as! [String: Any]
        var entries = wire["contributions"] as! [Any]; entries.append(NSNull()); entries.append(["date": "invalid"])
        wire["contributions"] = entries
        let value = try await TokensCIAPI(transport: TokensCITests.Wire(data: JSONSerialization.data(withJSONObject: wire), status: 200)).profile(username: "fixture", token: "tkr_fixture")
        try TokensCIStore.save(value, username: "../../fixture")
        let shared = try JSONSerialization.jsonObject(with: Data(contentsOf: TokensCIStore.snapshotURL("../../fixture"))) as! [String: Any]
        XCTAssertTrue(shared["history"] == nil || shared["history"] is NSNull)
        XCTAssertFalse(try Data(contentsOf: TokensCIStore.snapshotURL("../../fixture")).contains(Data("deepseek-v4-flash".utf8)))
        XCTAssertEqual(try TokensCIHistoryStore.url("../../fixture").deletingLastPathComponent().standardizedFileURL.path, privateDirectory.standardizedFileURL.path)
        XCTAssertEqual(TokensCIStore.snapshot("../../fixture")?.history, value.history)
        let cacheURL = try TokensCIHistoryStore.url("../../fixture")
        try Data("{\"days\":[null,{},42]}".utf8).write(to: cacheURL)
        XCTAssertNotNil(TokensCIStore.snapshot("../../fixture"))
        XCTAssertEqual(TokensCIHistoryStore.load("../../fixture")?.days.count, 0)
    }
    func testPublicHistoryAndOldSnapshotCompatibility() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/tokensci-public.json"))
        let snapshot = try await TokensCIAPI(transport: TokensCITests.Wire(data: data, status: 200)).profile(username: "Alice39s", token: "tkr_fixture")
        let history = try XCTUnwrap(snapshot.history)
        let a = history.analytics(ending: "2026-10-04", days: 30)
        XCTAssertEqual(a.tokens, 225540807855, accuracy: 1)
        XCTAssertEqual(a.cost, 63482.6795, accuracy: 0.001)
        XCTAssertEqual(a.activeDays, 30)
        XCTAssertEqual(a.streak, 153)
        XCTAssertEqual(a.longestStreak, 153)
        XCTAssertNil(history.day("2026-10-04")?.messages)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        old.removeValue(forKey: "history")
        let decoded = try JSONDecoder().decode(TokensCISnapshot.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.history)
        old["history"] = ["days": [NSNull(), ["oops": true]]]
        XCTAssertNoThrow(try JSONDecoder().decode(TokensCISnapshot.self, from: JSONSerialization.data(withJSONObject: old)))
    }
}
