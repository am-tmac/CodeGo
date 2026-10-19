import XCTest
@testable import CodeGo

// Failure cases: legacy identity leaks on re-encode; missing/expired/unavailable
// credits override fallback incorrectly; expiry boundary uses stale render time.
final class Build43Tests: XCTestCase {
    func testLegacyIdentityIsDiscarded() throws {
        let data = Data(#"{"usage":{"rate_limit":null},"updatedAt":0,"accountLabel":"legacy@example.com"}"#.utf8)
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("legacy@example.com"))
        XCTAssertEqual(snapshot.updatedAt, Date(timeIntervalSinceReferenceDate: 0))
    }
    func testResetCreditsAtRenderTime() throws {
        var usage = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"rate_limit_reset_credits":{"available_count":7}}"#.utf8))
        XCTAssertEqual(usage.resetCreditsText(now: Date(timeIntervalSince1970: 100)), "7")
        usage.resetCreditDetails = try CodexResetCredits.parse(Data(#"{"credits":[{"status":"available","expires_at":"1970-01-01T00:01:40Z"},{"status":"available"},{"status":"used"}]}"#.utf8))
        XCTAssertEqual(usage.resetCreditsText(now: Date(timeIntervalSince1970: 99)), "2")
        XCTAssertEqual(usage.resetCreditsText(now: Date(timeIntervalSince1970: 100)), "1")
        usage.resetCreditDetails = try CodexResetCredits.parse(Data(#"{"credits":[]}"#.utf8))
        XCTAssertEqual(usage.resetCreditsText(now: Date()), "0")
        usage.resetCreditDetails = nil
        usage = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(usage.resetCreditsText(now: Date()), "—")
    }
}
