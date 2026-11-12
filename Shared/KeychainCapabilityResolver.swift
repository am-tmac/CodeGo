import Foundation
import Security

/// Resolves the keychain access-group this process may use, without caching failures forever.
///
/// Invariant (unchanged from the old `static let`): once a non-nil group is resolved it never
/// changes within the process, so lock/keychain domains cannot switch during token rotation.
/// Only the transition nil → group is allowed; nil means cache-only (no credential writes from
/// the widget). An unresolved state — typically -25308 errSecInteractionNotAllowed because the
/// extension process started while the phone was locked, or -34018 — is re-probed on the next
/// access, at most once per `retryInterval`. iOS reuses widget extension processes for hours,
/// so a one-shot probe kept the widget cache-only until the process happened to die.
final class KeychainCapabilityResolver: @unchecked Sendable {
    typealias Probe = (_ group: String?) -> (OSStatus, String?)
    struct Capabilities {
        let routing: StorageRouting
        let diagnostics: StorageDiagnostics
    }

    private let sharedURL: URL?
    private let appGroup: String
    private let configuredKeychainGroup: String?
    private let suffix: String
    private let isWidget: Bool
    private let retryInterval: TimeInterval
    private let now: () -> Date
    private let probe: Probe
    private let lock = NSLock()
    private var cached: Capabilities?
    private var lastProbe: Date?

    init(sharedURL: URL?, appGroup: String, configuredKeychainGroup: String?, suffix: String, isWidget: Bool,
         retryInterval: TimeInterval = 30, now: @escaping () -> Date = Date.init, probe: @escaping Probe) {
        self.sharedURL = sharedURL
        self.appGroup = appGroup
        self.configuredKeychainGroup = configuredKeychainGroup
        self.suffix = suffix
        self.isWidget = isWidget
        self.retryInterval = retryInterval
        self.now = now
        self.probe = probe
    }

    var current: Capabilities {
        lock.lock(); defer { lock.unlock() }
        if let cached, cached.diagnostics.selectedGroup != nil { return cached }
        let time = now()
        if let cached, let lastProbe, time.timeIntervalSince(lastProbe) < retryInterval, time >= lastProbe { return cached }
        let fresh = resolve(at: time)
        lastProbe = time
        cached = fresh
        return fresh
    }

    private func resolve(at time: Date) -> Capabilities {
        let baseline = probe(nil)
        var probes: [String: OSStatus] = [:]
        let group = SharedStorage.authorizedGroup(configured: configuredKeychainGroup, actualDefaultGroup: baseline.1, suffix: suffix) { candidate in
            let status = probe(candidate).0
            probes[candidate] = status
            return status == errSecSuccess
        }
        var diagnostics = StorageDiagnostics(configuredAppGroup: appGroup, configuredKeychainGroup: configuredKeychainGroup,
                                             containerAvailable: sharedURL != nil, defaultProbeStatus: baseline.0,
                                             observedDefaultGroup: baseline.1, probes: probes, selectedGroup: group, isWidget: isWidget)
        diagnostics.observedAt = time
        diagnostics.probedAt = time
        return Capabilities(routing: StorageRouting(sharedURL: sharedURL, authorizedGroup: group, isWidget: isWidget),
                            diagnostics: diagnostics)
    }
}
