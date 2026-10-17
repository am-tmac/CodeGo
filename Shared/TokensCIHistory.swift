import Foundation

@propertyWrapper struct TokensCILossyHistory: Codable, Equatable {
    var wrappedValue: TokensCIHistory?
    init(wrappedValue: TokensCIHistory?) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws { wrappedValue = try? TokensCIHistory(from: decoder) }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(wrappedValue)
    }
}
extension KeyedDecodingContainer {
    func decode(_ type: TokensCILossyHistory.Type, forKey key: Key) throws -> TokensCILossyHistory {
        (try? decodeIfPresent(type, forKey: key)) ?? TokensCILossyHistory(wrappedValue: nil)
    }
}

/// Daily aggregates only. Stored separately in Application Support, never the widget container.
struct TokensCIHistory: Codable, Equatable {
    var days: [TokensCIDay]
    static func validNumber(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }; return value
    }
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }
    static func date(_ key: String) -> Date? {
        guard key.count == 10 else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), Self.key(date) == key else { return nil }
        return date
    }
    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func offset(_ key: String, _ days: Int) -> String {
        guard let d = date(key), let result = calendar.date(byAdding: .day, value: days, to: d) else { return key }
        return Self.key(result)
    }
    static func decode(_ data: Data) throws -> Self {
        let raw = try JSONSerialization.jsonObject(with: data)
        let array = (raw as? [Any]) ?? (raw as? [String: Any])?["contributions"] as? [Any] ?? []
        var grouped: [String: TokensCIDay] = [:]
        for item in array {
            guard let raw = item as? [String: Any], let date = raw["date"] as? String, Self.date(date) != nil,
                  let total = raw["totals"] as? [String: Any],
                  let tokens = validNumber((total["tokens"] as? NSNumber)?.doubleValue),
                  let cost = validNumber((total["cost"] as? NSNumber)?.doubleValue) else { continue }
            func number(_ x: Any?) -> Double { validNumber((x as? NSNumber)?.doubleValue) ?? 0 }
            let clients = (raw["clients"] as? [[String: Any]] ?? []).compactMap { c -> TokensCIHistoryClient? in
                guard let name = c["client"] as? String, !name.isEmpty else { return nil }
                let breakdown = c["tokens"] as? [String: Any] ?? [:]
                var models: [TokensCIModel] = []
                for (name, value) in c["models"] as? [String: [String: Any]] ?? [:] where name != "<synthetic>" {
                    models.append(TokensCIModel(name: name, tokens: number(value["tokens"]), cost: number(value["cost"])))
                }
                let tokens = TokensCIComposition.keys.reduce(0) { $0 + number(breakdown[$1]) }
                if models.isEmpty, let model = c["modelId"] as? String, !model.isEmpty, model != "<synthetic>" {
                    models = [TokensCIModel(name: model, tokens: tokens, cost: number(c["cost"]))]
                }
                return TokensCIHistoryClient(name: name, tokens: tokens, cost: number(c["cost"]), models: models, messages: validNumber((c["messages"] as? NSNumber)?.doubleValue))
            }
            let rawBreakdown = raw["tokenBreakdown"] as? [String: Any]
            let composition = rawBreakdown.map { b in TokensCIComposition(values: TokensCIComposition.keys.map { number(b[$0]) }) }
            let reportedMessages = validNumber((total["messages"] as? NSNumber)?.doubleValue)
            let clientMessages = clients.compactMap(\.messages)
            let messages: Double? = reportedMessages.flatMap { m in
                guard !clients.isEmpty, clientMessages.count == clients.count, abs(clientMessages.reduce(0, +) - m) < 0.5 else { return nil }; return m
            }
            let day = TokensCIDay(date: date, tokens: tokens, cost: cost, messages: messages, composition: composition, clients: clients)
            if let old = grouped[date] {
                grouped[date] = TokensCIDay(date: date, tokens: old.tokens + tokens, cost: old.cost + cost,
                    messages: old.messages.flatMap { a in messages.map { a + $0 } },
                    composition: old.composition.flatMap { a in composition.map { a.adding($0) } }, clients: old.clients + clients)
            } else { grouped[date] = day }
        }
        return Self(days: grouped.values.sorted { $0.date < $1.date }.map { day in
            var clients: [String: TokensCIHistoryClient] = [:]
            for c in day.clients {
                let old = clients[c.name]
                clients[c.name] = TokensCIHistoryClient(name: c.name, tokens: (old?.tokens ?? 0) + c.tokens, cost: (old?.cost ?? 0) + c.cost, models: (old?.models ?? []) + c.models, messages: nil)
            }
            return TokensCIDay(date: day.date, tokens: day.tokens, cost: day.cost, messages: day.messages, composition: day.composition, clients: clients.values.sorted { $0.name < $1.name })
        })
    }
    init(days: [TokensCIDay]) { self.days = days }
    /// One malformed cached entry must not invalidate the remaining history or quota snapshot.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard var array = try? c.nestedUnkeyedContainer(forKey: .days) else { days = []; return }
        var result: [TokensCIDay] = []
        while !array.isAtEnd {
            guard let element = try? array.superDecoder() else { break }
            if let day = try? TokensCIDay(from: element), Self.date(day.date) != nil,
               Self.validNumber(day.tokens) != nil, Self.validNumber(day.cost) != nil { result.append(day) }
        }
        days = result.sorted { $0.date < $1.date }
    }
    func day(_ key: String) -> TokensCIDay? { days.first { $0.date == key } }
    var latestDay: String? { days.last?.date }
    func analytics(ending end: String, days count: Int) -> TokensCIAnalytics {
        let start = Self.offset(end, -(max(1, count) - 1))
        let selected = days.filter { $0.date >= start && $0.date <= end }
        var clientSums: [String: TokensCIHistoryClient] = [:]
        var modelSums: [String: TokensCIModel] = [:]
        for day in selected {
            for c in day.clients {
                let old = clientSums[c.name]
                clientSums[c.name] = TokensCIHistoryClient(name: c.name, tokens: (old?.tokens ?? 0) + c.tokens, cost: (old?.cost ?? 0) + c.cost, models: (old?.models ?? []) + c.models, messages: nil)
                for m in c.models {
                    let old = modelSums[m.name]
                    modelSums[m.name] = TokensCIModel(name: m.name, tokens: (old?.tokens ?? 0) + m.tokens, cost: (old?.cost ?? 0) + m.cost)
                }
            }
        }
        let active = Set(days.filter { $0.tokens > 0 && $0.date <= end }.map(\.date))
        var streak = 0, cursor = end
        while active.contains(cursor) { streak += 1; cursor = Self.offset(cursor, -1) }
        var longest = 0, run = 0
        let annualStart = Self.offset(end, -364)
        for i in 0..<365 {
            run = active.contains(Self.offset(annualStart, i)) ? run + 1 : 0; longest = max(longest, run)
        }
        let composition = selected.isEmpty || selected.contains(where: { $0.composition == nil }) ? nil : selected.compactMap(\.composition).reduce(TokensCIComposition(values: [0,0,0,0,0])) { $0.adding($1) }
        let annual = days.filter { $0.date >= annualStart && $0.date <= end }
        var weekdays = Array(repeating: 0.0, count: 7)
        for d in annual { if let date = Self.date(d.date) { let index = (Self.calendar.component(.weekday, from: date) + 5) % 7; weekdays[index] += d.tokens } }
        return TokensCIAnalytics(start: start, end: end, days: selected, tokens: selected.reduce(0) { $0 + $1.tokens }, cost: selected.reduce(0) { $0 + $1.cost }, activeDays: selected.filter { $0.tokens > 0 }.count, streak: streak, longestStreak: longest, clients: clientSums.values.sorted { $0.tokens == $1.tokens ? $0.name < $1.name : $0.tokens > $1.tokens }, models: modelSums.values.sorted { $0.tokens == $1.tokens ? $0.name < $1.name : $0.tokens > $1.tokens }, composition: composition, weekdays: weekdays, peakDay: annual.max { $0.tokens == $1.tokens ? $0.date > $1.date : $0.tokens < $1.tokens })
    }
}
struct TokensCIComposition: Codable, Equatable {
    static let keys = ["input", "output", "cacheRead", "cacheWrite", "reasoning"]
    let values: [Double]
    var total: Double { values.reduce(0, +) }
    func adding(_ other: Self) -> Self { Self(values: zip(values, other.values).map(+)) }
}
struct TokensCIDay: Codable, Equatable, Identifiable {
    let date: String
    let tokens: Double
    let cost: Double
    let messages: Double?
    let composition: TokensCIComposition?
    let clients: [TokensCIHistoryClient]
    var id: String { date }
}
struct TokensCIHistoryClient: Codable, Equatable, Identifiable {
    let name: String
    let tokens: Double
    let cost: Double
    let models: [TokensCIModel]
    let messages: Double?
    var id: String { name }
    var displayName: String { TokensCIClient(name: name, tokens: tokens, cost: cost, topModel: nil).displayName }
    var topModel: TokensCIModel? {
        var sums: [String: TokensCIModel] = [:]
        for m in models { let old = sums[m.name]; sums[m.name] = TokensCIModel(name: m.name, tokens: (old?.tokens ?? 0) + m.tokens, cost: (old?.cost ?? 0) + m.cost) }
        return sums.values.sorted { $0.tokens == $1.tokens ? $0.name < $1.name : $0.tokens > $1.tokens }.first
    }
}
struct TokensCIAnalytics {
    let start: String
    let end: String
    let days: [TokensCIDay]
    let tokens: Double
    let cost: Double
    let activeDays: Int
    let streak: Int
    let longestStreak: Int
    let clients: [TokensCIHistoryClient]
    let models: [TokensCIModel]
    let composition: TokensCIComposition?
    let weekdays: [Double]
    let peakDay: TokensCIDay?
    var monthlyEstimate: Double? { nil }
    var cacheReadRatio: Double? { guard let c = composition, c.total > 0, c.values.count == 5 else { return nil }; return c.values[2] / c.total }
}

enum TokensCIHistoryStore {
    static var directoryOverride: URL?
    static func url(_ username: String) throws -> URL {
        guard !SharedStorage.isWidget else { throw TokensCIError.storage }
        let root = try directoryOverride ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("CodexUsage/TokensCIHistory", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = Data(username.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return root.appendingPathComponent(name + ".json")
    }
    static func load(_ username: String) -> TokensCIHistory? {
        guard let url = try? url(username), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TokensCIHistory.self, from: data)
    }
    static func save(_ value: TokensCIHistory, username: String) throws {
        try JSONEncoder().encode(value).write(to: url(username), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func remove(_ username: String) throws {
        let url = try url(username)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
