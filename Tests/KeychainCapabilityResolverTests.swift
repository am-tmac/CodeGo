import XCTest
import Security
@testable import CodeGo

/// Build 48: a widget extension started while the phone was locked saw -25308 from its
/// keychain probe and kept that failure for the life of the (reused) process.
final class KeychainCapabilityResolverTests: XCTestCase {
    private final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }
    private final class Script {
        var results: [(OSStatus, String?)]
        var calls: [String?] = []
        init(_ results: [(OSStatus, String?)]) { self.results = results }
        func probe(_ group: String?) -> (OSStatus, String?) {
            calls.append(group)
            return results.count > 1 ? results.removeFirst() : results[0]
        }
    }
    private let team = "ABCDE12345.*"
    private func resolver(_ script: Script, clock: Clock) -> KeychainCapabilityResolver {
        KeychainCapabilityResolver(sharedURL: URL(fileURLWithPath: "/unused-group"), appGroup: "group.test",
                                   configuredKeychainGroup: nil, suffix: "shared", isWidget: true,
                                   retryInterval: 30, now: { clock.now }, probe: script.probe)
    }

    func testLockedProbeIsRetriedAfterTheRateLimitWindowAndResolvesTheGroup() {
        let clock = Clock()
        // Locked: default probe -25308. Unlocked later: default probe 0 + exact group probe 0.
        let script = Script([(errSecInteractionNotAllowed, nil), (errSecSuccess, team), (errSecSuccess, team)])
        let sut = resolver(script, clock: clock)
        XCTAssertNil(sut.current.diagnostics.selectedGroup)
        XCTAssertEqual(sut.current.diagnostics.defaultProbeStatus, errSecInteractionNotAllowed)
        XCTAssertNil(sut.current.routing.authorizedGroup)
        clock.now += 31
        let resolved = sut.current
        XCTAssertEqual(resolved.diagnostics.selectedGroup, team)
        XCTAssertEqual(resolved.diagnostics.observedDefaultGroup, team)
        XCTAssertEqual(resolved.routing.authorizedGroup, team)
        XCTAssertEqual(resolved.diagnostics.probedAt, clock.now)
    }

    func testNoReprobeInsideTheRateLimitWindow() {
        let clock = Clock()
        let script = Script([(errSecInteractionNotAllowed, nil), (errSecSuccess, team), (errSecSuccess, team)])
        let sut = resolver(script, clock: clock)
        _ = sut.current
        XCTAssertEqual(script.calls.count, 1)
        for step in [1.0, 10, 29] {
            clock.now = Date(timeIntervalSince1970: 1_800_000_000 + step)
            XCTAssertNil(sut.current.diagnostics.selectedGroup)
        }
        XCTAssertEqual(script.calls.count, 1, "re-probed inside the 30 s window")
    }

    func testMissingEntitlementIsAlsoRetriedOnlyAtTheRateLimit() {
        let clock = Clock()
        let script = Script([(errSecMissingEntitlement, nil)])
        let sut = resolver(script, clock: clock)
        _ = sut.current; clock.now += 5; _ = sut.current
        XCTAssertEqual(script.calls.count, 1)
        clock.now += 30; _ = sut.current
        XCTAssertEqual(script.calls.count, 2)
        XCTAssertNil(sut.current.diagnostics.selectedGroup)
    }

    func testResolvedGroupNeverChangesWithinTheProcess() {
        let clock = Clock()
        let script = Script([(errSecSuccess, team), (errSecSuccess, team),
                             (errSecInteractionNotAllowed, nil), (errSecSuccess, "OTHER.group")])
        let sut = resolver(script, clock: clock)
        XCTAssertEqual(sut.current.diagnostics.selectedGroup, team)
        let calls = script.calls.count
        for _ in 0..<5 {
            clock.now += 3600
            XCTAssertEqual(sut.current.diagnostics.selectedGroup, team)
            XCTAssertEqual(sut.current.routing.authorizedGroup, team)
        }
        XCTAssertEqual(script.calls.count, calls, "a resolved group must never be re-probed")
    }

    func testConcurrentAccessProbesOnce() {
        let clock = Clock()
        let script = Script([(errSecInteractionNotAllowed, nil)])
        let lock = NSLock()
        let sut = KeychainCapabilityResolver(sharedURL: nil, appGroup: "g", configuredKeychainGroup: nil, suffix: "s",
                                             isWidget: true, retryInterval: 30, now: { clock.now },
                                             probe: { g in lock.lock(); defer { lock.unlock() }; return script.probe(g) })
        DispatchQueue.concurrentPerform(iterations: 64) { _ in _ = sut.current }
        XCTAssertEqual(script.calls.count, 1)
    }

    func testWidgetDiagnosticsCarryTheTimeOfWriting() {
        let probed = Date(timeIntervalSince1970: 1_800_000_000)
        var base = StorageDiagnostics(configuredAppGroup: "group.test", configuredKeychainGroup: nil, containerAvailable: true,
                                      defaultProbeStatus: errSecInteractionNotAllowed, observedDefaultGroup: nil, probes: [:],
                                      selectedGroup: nil, isWidget: true)
        base.observedAt = probed
        base.probedAt = probed
        let written = probed.addingTimeInterval(4200)
        let report = SharedStorage.widgetDiagnosticsReport(base, handshakeStatus: "none", at: written)
        XCTAssertEqual(report.observedAt, written)
        XCTAssertEqual(report.probedAt, probed)
        XCTAssertEqual(report.handshakeStatus, "none")
        XCTAssertTrue(report.text.contains("探针时间"))
        // Old diagnostics files (no probedAt) still decode.
        let legacy = try? JSONDecoder().decode(StorageDiagnostics.self, from: Data(#"{"configuredAppGroup":"g","containerAvailable":true,"defaultProbeStatus":0,"probes":{},"isWidget":true,"observedAt":0}"#.utf8))
        XCTAssertNotNil(legacy)
        XCTAssertNil(legacy?.probedAt)
    }
}
