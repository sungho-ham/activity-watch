import Foundation
import CoreGraphics

@main
struct CoreTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !condition() { throw AppError("FAIL: \(message)") }
    }
    static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        checks += 1
        do { try operation() } catch { return }
        throw AppError("FAIL: expected rejection: \(message)")
    }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static let epoch = date("2026-10-28T00:00:00Z")
    static func span(_ a: Double, _ b: Double) -> Span { Span(start: epoch.addingTimeInterval(a), end: epoch.addingTimeInterval(b)) }

    static func main() async {
        do {
            try intervalTests()
            try dayTests()
            try persistenceTests()
            try decodingTests()
            try windowLayoutTests()
            if CommandLine.arguments.contains("--live") { try await liveTests() }
            print("PASS: \(checks) checks")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    static func intervalTests() throws {
        let activity = [span(-10, 20), span(10, 30), span(30, 40), span(60, 80), span(200, 300)]
        try expect(Intervals.union(activity, within: span(0, 100)) == [span(0, 40), span(60, 80)], "clip and merge overlap/touch, retain gap")
        try expect(Intervals.union([span(101, 200)], within: span(0, 100)).isEmpty, "outside intervals must not survive clipping")
        let exclude = Adjustment(span: span(20, 70), kind: .exclude)
        let add = Adjustment(span: span(70, 100), kind: .add)
        let summary = DaySummary(key: "2026-10-28", range: span(0, 100), activity: activity, entries: [exclude, add], now: epoch.addingTimeInterval(1000))
        try expect(summary.baseSeconds == 60, "base uses normalized union")
        try expect(summary.excludedSeconds == 30, "exclusion subtracts only active time")
        try expect(summary.addedSeconds == 20, "addition counts only empty/AFK time")
        try expect(summary.adjustedSeconds == 50, "adjusted equation")
        let outside = Adjustment(span: span(110, 200), kind: .add)
        try expect(summary.effect(outside) == 0, "out of range entry kept with zero effect")
        try expect(summary.explanation(outside) == "하루 범위 밖", "out of range explanation")
        let partial = DaySummary(key: "2026-10-28", range: span(0, 100), activity: activity, entries: [add], now: epoch.addingTimeInterval(90))
        try expect(partial.addedSeconds == 10, "future time is not counted")
        let future = DaySummary(key: "2026-10-28", range: span(0, 100), activity: activity, entries: [add], now: epoch.addingTimeInterval(-1))
        try expect(future.adjustedSeconds == 0 && future.base.isEmpty, "entire future day")
        try validateAdjustment(add, among: [exclude])
        try validateAdjustment(exclude, among: [exclude])
        try rejects("same kind overlap") { try validateAdjustment(Adjustment(span: span(25, 35), kind: .exclude), among: [exclude]) }
        try rejects("different kind overlap") { try validateAdjustment(Adjustment(span: span(69, 100), kind: .add), among: [exclude]) }
        let shortened = DaySummary(key: "2026-10-28", range: span(40, 100), activity: activity, entries: [exclude, add], now: epoch.addingTimeInterval(1000))
        try expect(shortened.excludedSeconds == 10 && shortened.entries[0].span == exclude.span, "changing day clips effect and preserves original timestamps")
        try expect(Display.duration(0) == "0분" && Display.duration(0.5) == "1분 미만", "subminute display")
        // Independent second-by-second oracle exercises unions and add/exclude algebra.
        var seed: UInt64 = 1031
        func next(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1; return Int((seed >> 32) % UInt64(n)) }
        for _ in 0..<150 {
            var spans: [Span] = []
            var occupied = Array(repeating: false, count: 200)
            for _ in 0..<12 {
                let a = next(260) - 30
                let b = a + next(70) + 1
                spans.append(span(Double(a), Double(b)))
                let lo = max(0, a), hi = min(200, b)
                if lo < hi { for i in lo..<hi { occupied[i] = true } }
            }
            let entries = [Adjustment(span: span(10, 70), kind: .exclude), Adjustment(span: span(90, 180), kind: .add)]
            let result = DaySummary(key: "2026-10-28", range: span(0, 200), activity: spans, entries: entries, now: epoch.addingTimeInterval(200))
            let base = occupied.filter { $0 }.count
            let removed = occupied[10..<70].filter { $0 }.count
            let added = occupied[90..<180].filter { !$0 }.count
            try expect(result.adjustedSeconds == Double(base - removed + added), "random interval oracle")
            try expect(result.adjustedSeconds <= 200, "total bounded by elapsed day")
        }
    }
    static func dayTests() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var schedule = DaySchedule(startOfDay: "04:00", overrides: [:], calendar: calendar)
        let day = "2026-10-28"
        let range = schedule.range(day)
        try expect(range.start == date("2026-10-28T04:00:00+09:00") && range.end == date("2026-10-29T04:00:00+09:00"), "full 04-to-04 day")
        try expect(schedule.currentKey(now: date("2026-10-29T03:59:00+09:00")) == day, "before AW boundary selects yesterday")
        try expect(schedule.currentKey(now: range.end) == "2026-10-29", "half-open day boundary")
        try schedule.validate(range, key: day)
        let extended = Span(start: range.start, end: range.end.addingTimeInterval(7200))
        try rejects("overlap next day") { try schedule.validate(extended, key: day) }
        schedule.overrides["2026-10-29"] = Span(start: extended.end, end: date("2026-10-30T04:00:00+09:00"))
        try schedule.validate(extended, key: day)
        schedule.overrides[day] = extended
        try expect(schedule.overrides["2026-10-29"]?.start == extended.end, "neighbor explicit adjustment allowed")
        let old = schedule.overrides
        try rejects("reject overlap without shifting neighbors") { try schedule.validate(Span(start: range.start, end: extended.end.addingTimeInterval(60)), key: day) }
        try expect(old == schedule.overrides, "validation never changes neighboring dates")
        schedule.overrides[day] = Span(start: range.start, end: date("2026-10-29T02:00:00+09:00"))
        try expect(schedule.currentKey(now: date("2026-10-29T03:00:00+09:00")) == "2026-10-29", "gap falls back to calendar date")
        try rejects("end cannot reach second following day") { try schedule.validateShape(Span(start: range.start, end: date("2026-10-30T00:00:00+09:00")), key: day) }
        try expect(!DaySchedule.validStart("24:00") && DaySchedule.validStart("04:00"), "AW start validation")
        try expect(DaySchedule.date("2026-02-30", calendar: calendar) == nil, "invalid calendar date rejected")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dst = DaySchedule(startOfDay: "00:00", overrides: [:], calendar: calendar)
        try expect(dst.range("2026-03-08").seconds == 23 * 3600, "spring DST day")
        try expect(dst.range("2026-11-01").seconds == 25 * 3600, "fall DST day")
    }
    static func persistenceTests() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("awtoday-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileStore(directory: root)
        let initial = try store.load()
        try store.initializeIfNeeded(settings: initial.0, state: initial.1)
        var settings = Settings()
        settings.automaticBucket = false
        settings.manualBucketID = "aw-watcher-afk_previous"
        settings.webPage = WebPagePreferences(title: "Example", url: "https://example.com", windowSize: WindowSize(width: 1250, height: 820))
        try store.saveSettings(settings)
        var state = SavedState()
        let entry = Adjustment(span: span(0, 60), kind: .exclude)
        state.setEntries([entry], day: "2026-10-28", bucket: "one")
        state.setEntries([Adjustment(span: span(0, 60), kind: .add)], day: "2026-10-28", bucket: "two")
        try store.saveState(state)
        let restored = try FileStore(directory: root).load()
        try expect(restored.0 == settings && restored.1 == state, "relaunch round trip")
        try expect(restored.0.webPage?.windowSize == WindowSize(width: 1250, height: 820), "saved web-page window size survives relaunch")
        try expect(restored.1.entries(day: "2026-10-28", bucket: "one")[0].kind == .exclude, "per-bucket independent adjustments")
        try expect(restored.1.entries(day: "2026-10-29", bucket: "one").isEmpty, "per-date independent adjustments")
        let url = root.appendingPathComponent("settings.json")
        let external = try JSONDates.encoder().encode(Settings())
        try external.write(to: url, options: .atomic)
        try expect(try store.externallyChanged(), "external change detection")
        try rejects("do not overwrite external edit") { try store.saveSettings(settings) }
        try expect(try Data(contentsOf: url) == external, "external file preserved")
        _ = try store.load()
        try store.saveSettings(settings)
        let corrupt = Data("{broken json".utf8)
        try corrupt.write(to: root.appendingPathComponent("state.json"))
        try rejects("corrupt state rejected") { _ = try store.load() }
        try rejects("no overwrite after corrupt external state") { try store.saveState(SavedState()) }
        try expect(try Data(contentsOf: root.appendingPathComponent("state.json")) == corrupt, "corrupt original preserved")
        var bad = SavedState()
        bad.setEntries([entry, Adjustment(span: span(10, 30), kind: .add)], day: "2026-10-28", bucket: "one")
        try rejects("stored overlap rejected") { try bad.validate() }
    }
    static func decodingTests() throws {
        let oldSettings = Data("{\"version\":1,\"automaticBucket\":true}".utf8)
        try expect(try JSONDates.decoder().decode(Settings.self, from: oldSettings).webPage == nil, "old settings without window size remain readable")
        let payload = Data("""
        [{"id":1,"timestamp":"2026-10-28T00:00:00.123456+00:00","duration":5.5,"data":{"status":"not-afk"}},
         {"id":2,"timestamp":"2026-10-28T00:00:10+00:00","duration":500000,"data":{"status":"afk"}}]
        """.utf8)
        let rows = try JSONDates.decoder().decode([AWEvent].self, from: payload)
        try expect(rows[0].activeSpan?.seconds == 5.5 && rows[1].activeSpan == nil, "fractional timestamps and AFK filtering")
    }
    static func windowLayoutTests() throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let original = CGRect(x: 300, y: 300, width: 560, height: 428)
        var frame = original
        for _ in 0..<5 {
            frame = PopupLayout.frame(from: frame, chromeHeight: 28, screen: screen, expanded: true)
            try expect(frame.maxY == original.maxY && frame.minX == original.minX, "expansion preserves title bar position")
            frame = PopupLayout.frame(from: frame, chromeHeight: 28, screen: screen, expanded: false)
            try expect(frame == original, "repeated toggles do not accumulate window drift")
        }
        let nearBottom = CGRect(x: 300, y: 80, width: 560, height: 428)
        let limited = PopupLayout.frame(from: nearBottom, chromeHeight: 28, screen: screen, expanded: true)
        try expect(limited.maxY == nearBottom.maxY && limited.minY == screen.minY, "short screens reduce detail height instead of moving the title bar")
        try expect(limited.height - nearBottom.height == 80, "only available space below the summary is used")
    }
    static func liveTests() async throws {
        let api = ActivityWatchAPI()
        async let fetched = api.buckets()
        async let start = api.startOfDay()
        let (buckets, startOfDay) = try await (fetched, start)
        try expect(!buckets.isEmpty, "live AFK buckets")
        try expect(buckets == buckets.sorted { $0.recentDate > $1.recentDate }, "latest bucket first")
        let schedule = DaySchedule(startOfDay: startOfDay, overrides: [:])
        let now = Date()
        let key = schedule.currentKey(now: now)
        let range = schedule.range(key)
        let period = Span(start: range.start, end: min(now, range.end))
        let result = try await api.activity(bucket: buckets[0].id, periods: [period])
        let summary = DaySummary(key: key, range: range, activity: result[0], entries: [], now: now)
        try expect(summary.baseSeconds >= 0 && summary.baseSeconds <= period.seconds, "live total within elapsed day")
        try expect(summary.baseSeconds > 0, "current live bucket no longer reports zero")
        let periods = (1...7).map { schedule.range(schedule.adjacent(key, -$0)) }
        let weekly = try await api.activity(bucket: buckets[0].id, periods: periods)
        try expect(weekly.count == 7, "live multi-day trend query")
        print("Live: \(buckets.count) AFK buckets, selected \(buckets[0].id), day \(key), start \(startOfDay), active \(Display.duration(summary.baseSeconds))")
        var unavailable = api
        unavailable.baseURL = URL(string: "http://127.0.0.1:1")!
        do {
            _ = try await unavailable.activity(bucket: buckets[0].id, periods: [period])
            throw AppError("FAIL: unavailable server must throw, not return empty activity")
        } catch let error as AppError { throw error }
        catch { checks += 1 }
    }
}

extension Bucket: Equatable {
    static func == (lhs: Bucket, rhs: Bucket) -> Bool { lhs.id == rhs.id }
}
