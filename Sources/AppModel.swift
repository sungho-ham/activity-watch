import Foundation
import SwiftUI

enum DetailPanel { case adjustments, trend }

@MainActor
final class AppModel: ObservableObject {
    @Published var day = DaySchedule.key(Date())
    @Published private(set) var settings = Settings()
    @Published private(set) var saved = SavedState()
    @Published private(set) var buckets: [Bucket] = []
    @Published private(set) var startOfDay = "00:00"
    @Published private(set) var hasServerSettings = false
    @Published private(set) var summary: DaySummary?
    @Published private(set) var loading = false
    @Published var error: String?
    @Published var notice: String?
    @Published var panel: DetailPanel?
    @Published var detailHeight = PopupLayout.detailHeight
    @Published var selectedAdjustment: UUID?
    @Published var selectedAggregationBoundary: AggregationBoundary?
    @Published var draft: Adjustment?
    @Published var editingAggregation = false
    @Published var editingWebPage = false
    @Published var trendDays = 7
    @Published private(set) var trend: [DaySummary] = []
    @Published private(set) var trendLoading = false
    @Published private(set) var trendError: String?
    let store: FileStore
    private let api: ActivityWatchAPI
    private var initializedDay = false
    private var storageReady = false
    private var requestID = UUID()
    private var trendID = UUID()
    private var refreshTask: Task<Void, Never>?
    private var trendTask: Task<Void, Never>?
    var browserAction: (() -> Void)?
    var resizeAction: ((Bool) -> Void)?
    var closeAction: (() -> Void)?

    init(store: FileStore = FileStore(), api: ActivityWatchAPI = ActivityWatchAPI()) {
        self.store = store
        self.api = api
        reloadStorage()
    }
    var schedule: DaySchedule { DaySchedule(startOfDay: startOfDay, overrides: [:]) }
    var range: Span { schedule.range(day) }
    private var aggregationSchedule: DaySchedule { DaySchedule(startOfDay: "05:00", overrides: saved.dayOverrides, endOfDay: "00:00") }
    var aggregationRange: Span { aggregationSchedule.range(day) }
    private var activityRange: Span {
        Span(start: min(range.start, aggregationRange.start), end: max(range.end, aggregationRange.end))
    }
    var bucketID: String? {
        settings.automaticBucket ? buckets.first?.id : settings.manualBucketID
    }
    var entries: [Adjustment] { bucketID.map { saved.entries(day: day, bucket: $0) } ?? [] }
    var editable: Bool { summary != nil && !loading && storageReady }

    private func reloadStorage() {
        do {
            let loaded = try store.load()
            settings = loaded.0
            saved = loaded.1
            try store.initializeIfNeeded(settings: settings, state: saved)
            storageReady = true
        } catch {
            storageReady = false
            self.error = "저장 파일을 읽거나 만들 수 없습니다. 원본을 보존했습니다. \(error.localizedDescription)"
        }
    }
    func onActivate() {
        do {
            if try !storageReady || store.externallyChanged() {
                reloadStorage()
                if storageReady { notice = "외부에서 변경된 저장 파일을 다시 읽었습니다." }
                draft = nil
                editingAggregation = false
                refresh()
            }
        } catch { self.error = error.localizedDescription }
    }
    func chooseDay(_ date: Date) {
        day = DaySchedule.key(date)
        initializedDay = true
        selectedAdjustment = nil
        selectedAggregationBoundary = nil
        draft = nil
        refresh()
    }
    func moveDay(_ offset: Int) { chooseDay(DaySchedule.date(schedule.adjacent(day, offset))!) }
    func today() { chooseDay(DaySchedule.date(schedule.currentKey(now: Date()))!) }
    func chooseBucket(_ id: String?) {
        var value = settings
        value.automaticBucket = id == nil
        if let id { value.manualBucketID = id }
        do {
            try store.saveSettings(value)
            settings = value
            selectedAdjustment = nil
            selectedAggregationBoundary = nil
            draft = nil
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() {
        refreshTask?.cancel()
        trendTask?.cancel()
        trendID = UUID()
        trendLoading = false
        trend = []
        let id = UUID()
        requestID = id
        loading = true
        summary = nil
        if storageReady { error = nil }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.requestID == id { self.loading = false } }
            do {
                if try !self.storageReady || self.store.externallyChanged() {
                    self.reloadStorage()
                    if self.storageReady { self.notice = "외부에서 변경된 저장 파일을 다시 읽었습니다." }
                }
                async let bucketResult = self.api.buckets()
                async let dayResult = self.api.startOfDay()
                let (buckets, start) = try await (bucketResult, dayResult)
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                self.buckets = buckets
                self.startOfDay = start
                self.hasServerSettings = true
                if !self.initializedDay {
                    self.day = self.schedule.currentKey(now: Date())
                    self.initializedDay = true
                }
                if !self.settings.automaticBucket,
                   !buckets.contains(where: { $0.id == self.settings.manualBucketID }) {
                    var settings = self.settings
                    settings.automaticBucket = true
                    try self.store.saveSettings(settings)
                    self.settings = settings
                    self.notice = "선택했던 버킷이 없어 최신 AFK 버킷으로 전환했습니다."
                }
                guard let bucket = self.bucketID else { throw AppError("AFK 버킷이 없습니다. ActivityWatch의 AFK watcher를 확인하세요.") }
                let key = self.day
                let range = self.aggregationRange
                try self.aggregationSchedule.validate(range, key: key)
                let now = Date()
                let elapsed = Span(start: self.activityRange.start, end: min(self.activityRange.end, now))
                let activity = elapsed.isValid ? try await self.api.activity(bucket: bucket, periods: [elapsed])[0] : []
                try Task.checkCancellation()
                guard self.requestID == id, self.day == key, self.bucketID == bucket else { return }
                self.summary = DaySummary(key: key, range: range, activity: activity,
                                          entries: self.saved.entries(day: key, bucket: bucket), now: now)
                if self.panel == .trend { self.loadTrend() }
            } catch is CancellationError {
            } catch {
                guard self.requestID == id, !Task.isCancelled else { return }
                self.error = "기록을 불러오지 못했습니다. \(error.localizedDescription)"
            }
        }
    }
    func togglePanel(_ value: DetailPanel) {
        let next: DetailPanel? = panel == value ? nil : value
        resizeAction?(next != nil)
        panel = next
        if panel == .trend { loadTrend() }
        else { trendTask?.cancel(); trendID = UUID(); trendLoading = false }
    }
    func saveWebPage(title: String, address: String) throws {
        var next = settings
        let profile = WebPagePreferences(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "웹페이지" : title,
                                         url: address.trimmingCharacters(in: .whitespacesAndNewlines))
        guard profile.validatedURL != nil else { throw AppError("유효한 HTTPS 주소를 입력하세요.") }
        next.webPage = profile
        try store.saveSettings(next)
        settings = next
        editingWebPage = false
        browserAction?()
    }
    func select(_ entry: Adjustment?) {
        selectedAggregationBoundary = nil
        selectedAdjustment = selectedAdjustment == entry?.id ? nil : entry?.id
    }
    func selectBoundary(_ boundary: AggregationBoundary) {
        selectedAdjustment = nil
        selectedAggregationBoundary = boundary
    }
    func beginDraft(_ span: Span, kind: AdjustmentKind = .exclude) {
        guard editable, let clipped = span.intersection(range), clipped.seconds >= 1 else { return }
        selectedAdjustment = nil
        selectedAggregationBoundary = nil
        draft = Adjustment(span: clipped, kind: kind)
    }
    func newDraft() {
        guard editable, let summary else { return }
        let elapsed = Span(start: range.start, end: min(range.end, summary.capturedAt))
        if elapsed.isValid {
            let end = Date(timeIntervalSince1970: floor(elapsed.end.timeIntervalSince1970 / 60) * 60)
            beginDraft(Span(start: max(elapsed.start, end.addingTimeInterval(-1800)), end: end))
        } else {
            beginDraft(Span(start: range.start, end: min(range.end, range.start.addingTimeInterval(1800))))
        }
    }
    func saveAdjustment(_ value: Adjustment) throws {
        guard editable, let bucket = bucketID else { throw AppError("기록을 먼저 새로고침하세요.") }
        guard value.span.intersection(activityRange) == value.span else { throw AppError("선택한 하루 범위 안의 시간만 지정할 수 있습니다.") }
        try validateAdjustment(value, among: entries)
        var next = saved
        var items = entries.filter { $0.id != value.id }
        items.append(value)
        next.setEntries(items, day: day, bucket: bucket)
        try store.saveState(next)
        saved = next
        selectedAdjustment = value.id
        selectedAggregationBoundary = nil
        draft = nil
        recalculate()
    }
    func deleteAdjustment(_ entry: Adjustment) {
        guard let bucket = bucketID else { return }
        do {
            var next = saved
            next.setEntries(entries.filter { $0.id != entry.id }, day: day, bucket: bucket)
            try store.saveState(next)
            saved = next
            if selectedAdjustment == entry.id { selectedAdjustment = nil }
            recalculate()
        } catch { self.error = error.localizedDescription }
    }
    private func recalculate() {
        if let current = summary {
            summary = DaySummary(key: day, range: aggregationRange, activity: current.activity, entries: entries, now: current.capturedAt)
        }
        if panel == .trend { loadTrend() }
    }
    func saveAggregationRange(_ span: Span?) throws {
        let nextSpan = span ?? aggregationSchedule.defaultRange(day)
        try aggregationSchedule.validate(nextSpan, key: day)
        var next = saved
        next.dayOverrides[day] = span
        try store.saveState(next)
        saved = next
        editingAggregation = false
        selectedAdjustment = nil
        refresh()
    }
    func loadTrend() {
        trendTask?.cancel()
        let id = UUID()
        trendID = id
        trendError = nil
        guard panel == .trend, let bucket = bucketID, summary != nil else { return }
        let ending = day
        let schedule = self.aggregationSchedule
        let state = saved
        let count = trendDays
        trendLoading = true
        trend = []
        trendTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.trendID == id { self.trendLoading = false } }
            do {
                let now = Date()
                let keys = (0..<count).reversed().map { schedule.adjacent(ending, -$0) }
                let ranges = keys.map { schedule.range($0) }
                for (key, range) in zip(keys, ranges) { try schedule.validate(range, key: key) }
                let periods = ranges.map { Span(start: $0.start, end: min(now, $0.end)) }
                let queryIndices = periods.indices.filter { periods[$0].isValid }
                let results = try await self.api.activity(bucket: bucket, periods: queryIndices.map { periods[$0] })
                try Task.checkCancellation()
                guard self.trendID == id, self.panel == .trend else { return }
                let byIndex = Dictionary(uniqueKeysWithValues: zip(queryIndices, results))
                self.trend = keys.indices.map { index in
                    DaySummary(key: keys[index], range: ranges[index], activity: byIndex[index] ?? [],
                               entries: state.entries(day: keys[index], bucket: bucket), now: now)
                }
            } catch is CancellationError {
            } catch {
                guard self.trendID == id, !Task.isCancelled else { return }
                self.trendError = error.localizedDescription
            }
        }
    }
    func escape() {
        if draft != nil { draft = nil }
        else if editingWebPage { editingWebPage = false }
        else if editingAggregation { editingAggregation = false }
        else if selectedAdjustment != nil { selectedAdjustment = nil }
        else if selectedAggregationBoundary != nil { selectedAggregationBoundary = nil }
        else { closeAction?() }
    }
}
