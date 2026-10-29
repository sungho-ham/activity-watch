import Foundation

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Span: Codable, Equatable, Sendable {
    var start: Date
    var end: Date
    var seconds: Double { max(0, end.timeIntervalSince(start)) }
    var isValid: Bool { start < end && seconds.isFinite }
    func intersection(_ other: Span) -> Span? {
        let result = Span(start: max(start, other.start), end: min(end, other.end))
        return result.isValid ? result : nil
    }
    func overlaps(_ other: Span) -> Bool { intersection(other) != nil }
    func contains(_ date: Date) -> Bool { start <= date && date < end }
}

enum Intervals {
    static func union(_ spans: [Span], within limit: Span? = nil) -> [Span] {
        let sorted = spans.compactMap { span -> Span? in
            guard span.isValid else { return nil }
            if let limit { return span.intersection(limit) }
            return span
        }.sorted { $0.start < $1.start }
        var result: [Span] = []
        for span in sorted {
            if let last = result.last, span.start <= last.end {
                result[result.count - 1].end = max(last.end, span.end)
            } else { result.append(span) }
        }
        return result
    }
    static func duration(_ spans: [Span]) -> Double { union(spans).reduce(0) { $0 + $1.seconds } }
    static func overlap(_ spans: [Span], with span: Span) -> Double {
        duration(spans.compactMap { $0.intersection(span) })
    }
}

enum AdjustmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case exclude, add
    var id: String { rawValue }
    var title: String { self == .exclude ? "제외" : "추가" }
    var symbol: String { self == .exclude ? "−" : "+" }
}

struct Adjustment: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var span: Span
    var kind: AdjustmentKind
}

struct Settings: Codable, Equatable {
    var version = 1
    var automaticBucket = true
    var manualBucketID: String?
    var webPage: WebPagePreferences?
}

struct WebPagePreferences: Codable, Equatable {
    var title: String
    var url: String
    var validatedURL: URL? {
        guard let value = URL(string: url), value.scheme?.lowercased() == "https",
              let host = value.host, !host.isEmpty, value.user == nil, value.password == nil else { return nil }
        return value
    }
}

struct SavedState: Codable, Equatable {
    var version = 1
    var dayOverrides: [String: Span] = [:]
    var adjustments: [String: [String: [Adjustment]]] = [:]
    func entries(day: String, bucket: String) -> [Adjustment] {
        (adjustments[day]?[bucket] ?? []).sorted { $0.span.start < $1.span.start }
    }
    mutating func setEntries(_ entries: [Adjustment], day: String, bucket: String) {
        adjustments[day, default: [:]][bucket] = entries
    }
    func validate() throws {
        guard version == 1 else { throw AppError("지원하지 않는 state.json 버전입니다.") }
        let schedule = DaySchedule(startOfDay: "00:00", overrides: dayOverrides)
        for (key, span) in dayOverrides { try schedule.validateShape(span, key: key) }
        for (day, buckets) in adjustments {
            guard DaySchedule.date(day) != nil else { throw AppError("보정 기록의 날짜가 올바르지 않습니다.") }
            for entries in buckets.values {
                guard Set(entries.map(\.id)).count == entries.count else { throw AppError("중복된 보정 ID가 있습니다.") }
                for entry in entries {
                    guard entry.span.isValid else { throw AppError("보정 기록의 시간 범위가 올바르지 않습니다.") }
                    try validateAdjustment(entry, among: entries.filter { $0.id != entry.id })
                }
            }
        }
    }
}

func validateAdjustment(_ entry: Adjustment, among others: [Adjustment]) throws {
    guard entry.span.isValid else { throw AppError("종료 시각은 시작 시각보다 뒤여야 합니다.") }
    if others.contains(where: { $0.id != entry.id && $0.span.overlaps(entry.span) }) {
        throw AppError("이미 지정한 시간대와 겹칩니다. 기존 항목을 수정하거나 다른 시간대를 선택하세요.")
    }
}

struct DaySchedule {
    var startOfDay: String
    var overrides: [String: Span]
    var calendar: Calendar = .current

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              Self.key(date, calendar: calendar) == key else { return nil }
        return date
    }
    static func validStart(_ value: String) -> Bool {
        let p = value.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 && (0..<24).contains(p[0]) && (0..<60).contains(p[1])
    }
    func adjacent(_ key: String, _ days: Int) -> String {
        Self.key(calendar.date(byAdding: .day, value: days, to: Self.date(key, calendar: calendar)!)!, calendar: calendar)
    }
    func defaultRange(_ key: String) -> Span {
        let parts = startOfDay.split(separator: ":").compactMap { Int($0) }
        let date = Self.date(key, calendar: calendar)!
        let next = calendar.date(byAdding: .day, value: 1, to: date)!
        // Calendar arithmetic preserves the configured local time on DST transitions.
        let start = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)!
        let end = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: next)!
        return Span(start: start, end: end)
    }
    func range(_ key: String) -> Span { overrides[key] ?? defaultRange(key) }
    func validateShape(_ span: Span, key: String) throws {
        guard let date = Self.date(key, calendar: calendar), span.isValid else { throw AppError("하루 범위가 올바르지 않습니다.") }
        let next = calendar.date(byAdding: .day, value: 1, to: date)!
        let after = calendar.date(byAdding: .day, value: 2, to: date)!
        guard date <= span.start, span.start < next, span.end < after else {
            throw AppError("시작은 선택 날짜, 종료는 같은 날 또는 다음 날이어야 합니다.")
        }
    }
    func validate(_ span: Span, key: String) throws {
        try validateShape(span, key: key)
        for offset in [-1, 1] {
            let other = adjacent(key, offset)
            if span.overlaps(range(other)) {
                throw AppError("\(other)의 하루 범위와 겹칩니다. 해당 날짜의 범위를 먼저 조정하세요.")
            }
        }
    }
    func currentKey(now: Date) -> String {
        let today = Self.key(now, calendar: calendar)
        for key in [adjacent(today, -1), today] where range(key).contains(now) { return key }
        return today
    }
}

struct DaySummary: Identifiable {
    var id: String { key }
    let key: String
    let range: Span
    let elapsed: Span?
    let base: [Span]
    let entries: [Adjustment]
    let capturedAt: Date

    init(key: String, range: Span, activity: [Span], entries: [Adjustment], now: Date) {
        self.key = key
        self.range = range
        capturedAt = now
        let elapsed = Span(start: range.start, end: min(range.end, now))
        self.elapsed = elapsed.isValid ? elapsed : nil
        self.base = elapsed.isValid ? Intervals.union(activity, within: elapsed) : []
        self.entries = entries
    }
    var baseSeconds: Double { Intervals.duration(base) }
    func effect(_ entry: Adjustment) -> Double {
        guard let elapsed, let span = entry.span.intersection(elapsed) else { return 0 }
        let activity = Intervals.overlap(base, with: span)
        return entry.kind == .exclude ? activity : max(0, span.seconds - activity)
    }
    var excludedSeconds: Double { entries.filter { $0.kind == .exclude }.reduce(0) { $0 + effect($1) } }
    var addedSeconds: Double { entries.filter { $0.kind == .add }.reduce(0) { $0 + effect($1) } }
    var adjustedSeconds: Double { max(0, baseSeconds - excludedSeconds + addedSeconds) }
    func explanation(_ entry: Adjustment) -> String? {
        if entry.span.intersection(range) == nil { return "하루 범위 밖" }
        if effect(entry) == 0 { return entry.kind == .exclude ? "제외할 활동 없음" : "추가할 빈 시간 없음" }
        if entry.span.intersection(range) != entry.span { return "하루 범위 안의 분량만 반영" }
        return nil
    }
}

enum Display {
    static func exactDuration(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return "\(value / 3600)시간 \((value % 3600) / 60)분 \(value % 60)초"
    }
    static func duration(_ seconds: Double) -> String {
        if seconds > 0 && seconds < 60 { return "1분 미만" }
        let minutes = Int(max(0, seconds) / 60)
        return minutes >= 60 ? "\(minutes / 60)시간 \(minutes % 60)분" : "\(minutes)분"
    }
    static func time(_ date: Date, relativeTo day: String? = nil) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = day != nil && DaySchedule.key(date) != day ? "M/d HH:mm" : "HH:mm"
        return f.string(from: date)
    }
    static func range(_ span: Span, day: String) -> String {
        "\(time(span.start, relativeTo: day))–\(time(span.end, relativeTo: day))"
    }
}
