import Foundation

@main
struct ModelChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("awtoday-model-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileStore(directory: root)
        let model = AppModel(store: store)
        var count = 0
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw AppError("FAIL: \(label)") }
            count += 1
        }
        func wait(_ model: AppModel) async throws {
            let deadline = Date().addingTimeInterval(40)
            while model.loading || model.trendLoading {
                guard Date() < deadline else { throw AppError("Timed out waiting for model") }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        model.refresh()
        try await wait(model)
        try check(model.summary != nil && model.error == nil, "initial live load")
        let today = model.day
        let latest = model.buckets[0].id
        let oldest = model.buckets.last!.id
        model.chooseBucket(oldest)
        try await wait(model)
        try check(!model.settings.automaticBucket && model.bucketID == oldest, "manual selection")
        model.moveDay(-1)
        try await wait(model)
        try check(model.bucketID == oldest, "manual selection across dates")
        let restored = AppModel(store: FileStore(directory: root))
        restored.refresh()
        try await wait(restored)
        try check(restored.bucketID == oldest && !restored.settings.automaticBucket, "manual selection after relaunch")
        // Start multiple requests without waiting; only the last selection may publish.
        restored.chooseBucket(latest)
        restored.chooseDay(DaySchedule.date(today)!)
        restored.moveDay(-1)
        restored.moveDay(-1)
        let requestedDay = restored.day
        try await wait(restored)
        try check(restored.summary?.key == requestedDay && restored.bucketID == latest, "cancelled requests cannot publish stale dates/buckets")
        restored.togglePanel(.trend)
        restored.trendDays = 30
        restored.loadTrend()
        try await wait(restored)
        try check(restored.trend.count == 30 && restored.trend.last?.key == requestedDay, "30-day trend replaces in-flight 7-day query")
        restored.togglePanel(.trend)
        let range = restored.range
        let edit = Adjustment(span: Span(start: range.start, end: range.start.addingTimeInterval(1800)), kind: .add)
        try restored.saveAdjustment(edit)
        try check(restored.entries.count == 1 && restored.summary!.addedSeconds >= 0, "save adjustment and recalculate")
        var overlapping = edit
        overlapping.id = UUID()
        do { try restored.saveAdjustment(overlapping); throw AppError("Overlap was accepted") }
        catch { try check(restored.entries.count == 1, "reject overlap without mutation") }
        var modified = edit
        modified.span.end = modified.span.end.addingTimeInterval(600)
        try restored.saveAdjustment(modified)
        try check(restored.entries.count == 1 && restored.entries[0].id == edit.id, "edit excludes itself from overlap checking")
        restored.deleteAdjustment(modified)
        try check(restored.entries.isEmpty, "delete adjustment")
        let fullRange = restored.range
        let defaultAggregation = restored.aggregationRange
        let fullActivity = restored.summary!.activity
        let defaultTotal = restored.summary!.adjustedSeconds
        let startParts = Calendar.current.dateComponents([.hour, .minute], from: defaultAggregation.start)
        let endParts = Calendar.current.dateComponents([.hour, .minute], from: defaultAggregation.end)
        try check(startParts.hour == 5 && startParts.minute == 0 && endParts.hour == 0 && endParts.minute == 0
                  && DaySchedule.key(defaultAggregation.end) == restored.schedule.adjacent(restored.day, 1), "new dates use 05:00 to the following midnight independently of the AW timeline")
        let limited = Span(start: fullRange.start.addingTimeInterval(3600), end: fullRange.end.addingTimeInterval(-7200))
        try restored.saveAggregationRange(limited)
        try await wait(restored)
        try check(restored.range == fullRange && restored.aggregationRange == limited && restored.summary?.range == limited, "aggregation limits do not change timeline scale")
        try check(restored.summary?.baseSeconds == Intervals.overlap(fullActivity, with: limited), "main total uses only the aggregation window")
        try check(restored.summary?.activity == fullActivity, "activity outside aggregation remains visible on the timeline")
        let outsideAggregation = Adjustment(span: Span(start: fullRange.start, end: fullRange.start.addingTimeInterval(1800)), kind: .add)
        try restored.saveAdjustment(outsideAggregation)
        try check(restored.summary?.effect(outsideAggregation) == 0 && restored.summary?.activity == fullActivity, "saving outside the aggregation window preserves timeline activity and has no effect on total")
        restored.togglePanel(.trend)
        try await wait(restored)
        try check(restored.trend.last?.range == limited && restored.trend.last?.adjustedSeconds == restored.summary?.adjustedSeconds, "trend uses the same saved aggregation limits as the main total")
        restored.togglePanel(.trend)
        let persisted = try FileStore(directory: root).load().1
        try check(persisted.dayOverrides[restored.day] == limited, "aggregation range survives a storage round trip")
        restored.deleteAdjustment(outsideAggregation)
        try restored.saveAggregationRange(nil)
        try await wait(restored)
        try check(restored.range == fullRange && restored.aggregationRange == defaultAggregation && restored.summary?.adjustedSeconds == defaultTotal, "reset restores the 05:00-to-midnight total without changing timeline scale")
        restored.selectBoundary(.start)
        let dragged = AggregationBoundary.start.moving(in: defaultAggregation, to: defaultAggregation.start.addingTimeInterval(1800), within: fullRange)
        try restored.saveAggregationRange(dragged)
        try await wait(restored)
        try check(restored.aggregationRange == dragged && restored.range == fullRange && restored.draft == nil
                  && restored.selectedAggregationBoundary == .start, "saving a boundary drag preserves its highlight and does not create an adjustment draft")
        restored.select(nil)
        try check(restored.selectedAggregationBoundary == nil, "background selection clears the boundary highlight")
        try restored.saveAggregationRange(nil)
        try await wait(restored)
        restored.chooseDay(DaySchedule.date(restored.schedule.adjacent(today, 2))!)
        try await wait(restored)
        try check(restored.editable && restored.summary?.elapsed == nil, "future day is editable without elapsed time")
        restored.newDraft()
        try check(restored.draft?.span.start == restored.range.start && restored.draft?.span.seconds == 1800, "time button creates a draft on a future day")
        let futureAdd = Adjustment(span: Span(start: restored.range.start, end: restored.range.start.addingTimeInterval(1800)), kind: .add)
        let futureExclude = Adjustment(span: Span(start: futureAdd.span.end, end: futureAdd.span.end.addingTimeInterval(1800)), kind: .exclude)
        restored.beginDraft(futureExclude.span)
        try check(restored.draft?.span == futureExclude.span, "future timeline draft is not clipped to elapsed time")
        try restored.saveAdjustment(futureAdd)
        try restored.saveAdjustment(futureExclude)
        try check(restored.entries.count == 2 && restored.summary?.adjustedSeconds == 0, "future additions and exclusions save without affecting the total")
        let futureState = try FileStore(directory: root).load().1
        try check(futureState.entries(day: restored.day, bucket: latest) == [futureAdd, futureExclude], "future adjustments persist unchanged")
        for span in [Span(start: restored.range.start.addingTimeInterval(-60), end: restored.range.start.addingTimeInterval(60)),
                     Span(start: restored.range.end.addingTimeInterval(-60), end: restored.range.end.addingTimeInterval(60))] {
            var rejected = false
            do { try restored.saveAdjustment(Adjustment(span: span, kind: .add)) }
            catch { rejected = true }
            try check(rejected && restored.entries.count == 2, "adjustment outside the selected day is rejected without mutation")
        }
        let current = try FileStore(directory: root).load()
        var missing = current.0
        missing.automaticBucket = false
        missing.manualBucketID = "aw-watcher-afk_missing_test_bucket"
        let external = FileStore(directory: root)
        _ = try external.load()
        try external.saveSettings(missing)
        restored.onActivate()
        try await wait(restored)
        try check(restored.settings.automaticBucket && restored.bucketID == latest, "successful bucket listing proves missing manual bucket and switches to auto")
        let offlineRoot = root.appendingPathComponent("offline")
        let offlineStore = FileStore(directory: offlineRoot)
        _ = try offlineStore.load()
        try offlineStore.initializeIfNeeded(settings: missing, state: SavedState())
        var unavailable = ActivityWatchAPI()
        unavailable.baseURL = URL(string: "http://127.0.0.1:1")!
        let offline = AppModel(store: offlineStore, api: unavailable)
        offline.refresh()
        try await wait(offline)
        try check(offline.summary == nil && offline.error != nil, "network failure is not zero activity")
        try check(!offline.settings.automaticBucket && offline.settings.manualBucketID == missing.manualBucketID, "network failure preserves manual selection")
        print("PASS: \(count) model integration checks (temporary storage, read-only ActivityWatch queries)")
    }
}
