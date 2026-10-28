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
