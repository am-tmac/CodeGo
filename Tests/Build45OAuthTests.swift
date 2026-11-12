import XCTest
import Foundation
@testable import CodeGo

/// Thread-safe fake clock: the device-code flow's `now` is synchronous, the sleep recorder is an actor.
private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value = value.addingTimeInterval(seconds); lock.unlock() }
}

/// Records the sleeps the flow asked for and advances the fake clock instead of waiting.
private actor SleepBox {
    private(set) var sleeps: [TimeInterval] = []
    private(set) var count = 0
    func record() { count += 1 }
    func sleep(_ seconds: TimeInterval, clock: FakeClock) {
        sleeps.append(seconds)
        clock.advance(seconds)
    }
}

// Failure inventory, written before the implementation:
//  - the shared callback parser must accept exactly the registered path and one-time state,
//    keep the provider `error` before `code`, and reject forged/stale/extra redirects;
//  - the two existing provider adapters must behave byte-for-byte as before;
//  - device-code polling must honour `slow_down`, `expired`, the overall deadline, cancellation,
//    and hand the token back only once.
final class Build45OAuthTests: XCTestCase {
    // MARK: callback parser

    func testCallbackParserAcceptsCodeForTheExpectedState() {
        let value = LoopbackCallbackParser.parse(requestLine: "GET /callback?code=abc%2F123&state=S1 HTTP/1.1",
                                                 path: "/callback", expectedState: "S1")
        XCTAssertEqual(value, .code("abc/123"))
    }

    func testCallbackParserAcceptsOnlyTheRegisteredPath() {
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "GET /other?code=x&state=S1 HTTP/1.1", path: "/callback", expectedState: "S1"))
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "GET /callback/extra?code=x&state=S1 HTTP/1.1", path: "/callback", expectedState: "S1"))
        XCTAssertEqual(LoopbackCallbackParser.parse(requestLine: "GET /oauth2callback?code=x&state=S1 HTTP/1.1", path: "/oauth2callback", expectedState: "S1"), .code("x"))
    }

    func testCallbackParserRejectsWrongOrMissingState() {
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "GET /callback?code=x&state=S2 HTTP/1.1", path: "/callback", expectedState: "S1"))
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "GET /callback?code=x HTTP/1.1", path: "/callback", expectedState: "S1"))
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "GET /callback?code=x&state=S1 HTTP/1.1", path: "/callback", expectedState: ""))
    }

    func testCallbackParserReportsProviderErrorsBeforeCodes() {
        XCTAssertEqual(LoopbackCallbackParser.parse(requestLine: "GET /callback?error=access_denied&state=S1 HTTP/1.1", path: "/callback", expectedState: "S1"),
                       .failure("access_denied"))
        XCTAssertEqual(LoopbackCallbackParser.parse(requestLine: "GET /callback?code=x&error=invalid_scope&state=S1 HTTP/1.1", path: "/callback", expectedState: "S1"),
                       .failure("invalid_scope"))
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "GET /callback?error=&state=S1 HTTP/1.1", path: "/callback", expectedState: "S1"))
    }

    func testCallbackParserRejectsMalformedRequestLines() {
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "not a request line", path: "/callback", expectedState: "S1"))
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "", path: "/callback", expectedState: "S1"))
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "GET", path: "/callback", expectedState: "S1"))
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "GET /callback?code= HTTP/1.1", path: "/callback", expectedState: "S1"))
        XCTAssertNil(LoopbackCallbackParser.parse(requestLine: "GET /callback?state=S1 HTTP/1.1", path: "/callback", expectedState: "S1"))
    }

    func testExistingProviderAdaptersKeepTheirContract() {
        XCTAssertEqual(ClaudeOAuth.parseCallback("GET /callback?code=abc&state=S1 HTTP/1.1", expectedState: "S1"), .code("abc", "S1"))
        XCTAssertNil(ClaudeOAuth.parseCallback("GET /callback?code=abc&state=S2 HTTP/1.1", expectedState: "S1"))
        XCTAssertEqual(AntigravityOAuth.parseCallback("GET /oauth2callback?code=4/0Abc&state=S", expectedState: "S"),
                       .code("4/0Abc"))
        XCTAssertNil(AntigravityOAuth.parseCallback("GET /oauth2callback?code=x&state=wrong HTTP/1.1", expectedState: "S"))
    }

    // MARK: device code

    private func grant(interval: TimeInterval = 5, expiresIn: TimeInterval = 900) -> DeviceCodeGrant {
        DeviceCodeGrant(deviceCode: "device", userCode: "ABCD-EFGH", verificationURL: URL(string: "https://example.com/device"),
                        interval: interval, expiresIn: expiresIn)
    }

    func testDeviceCodeFlowPollsUntilAuthorizedAndSleepsTheInterval() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let box = SleepBox()
        let token = OAuthToken(accessToken: "access", refreshToken: "refresh", idToken: nil, expiresIn: 3600)
        let flow = DeviceCodeFlow(poller: { _ in
            await box.record()
            let count = await box.count
            return count == 1 ? .pending : .authorized(token)
        }, sleep: { seconds in await box.sleep(seconds, clock: clock) }, now: { clock.now() })
        let value = try await flow.run(grant(), onAuthorization: { _ in })
        XCTAssertEqual(value, token)
        let sleeps = await box.sleeps
        XCTAssertEqual(sleeps, [5])
    }

    func testDeviceCodeFlowSlowDownAddsFiveSeconds() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let box = SleepBox()
        let token = OAuthToken(accessToken: "a", refreshToken: nil, idToken: nil, expiresIn: nil)
        let flow = DeviceCodeFlow(poller: { _ in
            await box.record()
            let count = await box.count
            switch count {
            case 1: return .pending
            case 2: return .slowDown
            default: return .authorized(token)
            }
        }, sleep: { seconds in await box.sleep(seconds, clock: clock) }, now: { clock.now() })
        _ = try await flow.run(grant(interval: 5))
        let sleeps = await box.sleeps
        XCTAssertEqual(sleeps, [5, 10])
    }

    func testDeviceCodeFlowExpiredAndDeadlineUseTheSameError() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let expiredBox = SleepBox()
        let expired = DeviceCodeFlow(poller: { _ in await expiredBox.record(); return .expired },
                                     sleep: { seconds in await expiredBox.sleep(seconds, clock: clock) }, now: { clock.now() })
        do {
            _ = try await expired.run(grant())
            XCTFail("expected expired")
        } catch let error as DeviceCodeError {
            XCTAssertEqual(error, .expired)
            XCTAssertEqual(error.localizedDescription, "设备代码已过期，请重新登录。")
        }

        let deadlineBox = SleepBox()
        let deadline = DeviceCodeFlow(poller: { _ in await deadlineBox.record(); return .pending },
                                      sleep: { seconds in await deadlineBox.sleep(seconds, clock: clock) }, now: { clock.now() })
        do {
            _ = try await deadline.run(grant(interval: 1, expiresIn: 3))
            XCTFail("expected deadline expiry")
        } catch let error as DeviceCodeError { XCTAssertEqual(error, .expired) }
        let polls = await deadlineBox.count
        XCTAssertLessThanOrEqual(polls, 5)
    }

    func testDeviceCodeFlowPropagatesCancellation() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let flow = DeviceCodeFlow(poller: { _ in throw CancellationError() }, sleep: { _ in }, now: { clock.now() })
        do {
            _ = try await flow.run(grant())
            XCTFail("expected cancellation")
        } catch is CancellationError {} catch { XCTFail("cancellation became \(error)") }
    }

    func testDeviceCodeFlowRejectsAnEmptyToken() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let flow = DeviceCodeFlow(poller: { _ in .authorized(OAuthToken(accessToken: "", refreshToken: nil, idToken: nil, expiresIn: nil)) },
                                  sleep: { seconds in clock.advance(seconds) }, now: { clock.now() })
        do {
            _ = try await flow.run(grant())
            XCTFail("expected malformed")
        } catch let error as DeviceCodeError { XCTAssertEqual(error, .malformed) } catch { XCTFail("unexpected \(error)") }
    }
}
