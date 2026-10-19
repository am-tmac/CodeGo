import Foundation

/// API scalars only; never infer a limit or a reset from a plan's advertised duration.
enum ProviderParsing {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.malformed }
        return value
    }
    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
        let n = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return n.flatMap { $0.isFinite ? $0 : nil }
    }
    static func decimal(_ value: Any?) -> Decimal? {
        guard number(value) != nil else { return nil }
        let text = (value as? String) ?? (value as? NSNumber)?.stringValue
        guard let text, text.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return nil }
        return amount
    }
    static func first(_ object: [String: Any], _ keys: [String]) -> Any? {
        keys.lazy.compactMap { object[$0] }.first
    }
    static func date(_ value: Any?) -> Date? {
        if let seconds = number(value) { return Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1000 : seconds) }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: text) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
    static func window(_ raw: [String: Any]?, now: Date = Date()) -> UsageWindow? {
        guard let raw else { return nil }
        let object = raw.merging(raw["window"] as? [String: Any] ?? [:]) { outer, _ in outer }
        var percent = number(first(object, ["usagePercent", "usedPercent", "percentUsed", "percent"]))
        if percent == nil, let used = number(first(object, ["used", "usage", "consumed"])),
           let limit = number(first(object, ["limit", "total", "quota", "max", "cap"])), limit > 0 {
            percent = used / limit * 100
        }
        guard let percent, percent.isFinite else { return nil }
        let reset: Date?
        if let seconds = number(first(object, ["resetInSec", "resetInSeconds", "resetSeconds"])) {
            reset = now.addingTimeInterval(seconds)
        } else { reset = date(first(object, ["resetAt", "resetsAt", "reset_at", "resets_at"])) }
        return UsageWindow(usedPercent: min(100, max(0, percent)), resetAt: reset?.timeIntervalSince1970, limitWindowSeconds: nil)
    }
}
import CoreFoundation
