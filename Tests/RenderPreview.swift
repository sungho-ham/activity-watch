import AppKit
import SwiftUI

/// Render our own view hierarchy offscreen; no windows or desktop screenshots.
@main
struct RenderPreview {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("awtoday-preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = FileStore(directory: temporary)
        let model = AppModel(store: store)
        model.refresh()
        while model.loading { try await Task.sleep(nanoseconds: 50_000_000) }
        guard model.summary != nil else { throw AppError(model.error ?? "Preview data unavailable") }
        let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func render<V: View>(_ view: V, _ name: String, _ width: CGFloat, _ height: CGFloat, dark: Bool = false) throws {
            let host = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: "ko_KR"))
                .environment(\.colorScheme, dark ? .dark : .light).background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.sizingOptions = []
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw AppError("Cannot create render bitmap") }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw AppError("Cannot encode render") }
            try png.write(to: output.appendingPathComponent(name + ".png"))
        }
        try render(MainView(model: model), "main-light", 560, 400)
        try render(MainView(model: model), "main-dark", 560, 400, dark: true)
        model.selectBoundary(.start)
        try render(MainView(model: model), "boundary-start-selected", 560, 400)
        model.selectBoundary(.end)
        try render(MainView(model: model), "boundary-end-selected", 560, 400)
        model.select(nil)
        let timelineRange = model.range
        try model.saveAggregationRange(Span(start: timelineRange.start.addingTimeInterval(3600), end: timelineRange.end.addingTimeInterval(-7200)))
        while model.loading { try await Task.sleep(nanoseconds: 50_000_000) }
        try render(MainView(model: model), "aggregation-light", 560, 400)
        try render(MainView(model: model), "aggregation-dark", 560, 400, dark: true)
        try render(AggregationRangeEditor(model: model), "aggregation-editor", 430, 280)
        try model.saveAggregationRange(Span(start: timelineRange.start.addingTimeInterval(3600), end: timelineRange.start.addingTimeInterval(5400)))
        while model.loading { try await Task.sleep(nanoseconds: 50_000_000) }
        try render(MainView(model: model), "aggregation-short", 560, 400)
        try model.saveAggregationRange(nil)
        while model.loading { try await Task.sleep(nanoseconds: 50_000_000) }
        try render(CalendarPicker(selection: .constant(DaySchedule.date(model.day)!)), "calendar", 300, 280)
        let range = model.range
        let exclusion = Adjustment(span: Span(start: range.start.addingTimeInterval(5 * 3600), end: range.start.addingTimeInterval(6 * 3600)), kind: .exclude)
        let addition = Adjustment(span: Span(start: range.start.addingTimeInterval(8 * 3600), end: range.start.addingTimeInterval(9 * 3600)), kind: .add)
        try model.saveAdjustment(exclusion)
        try model.saveAdjustment(addition)
        model.selectedAdjustment = exclusion.id
        try render(MainView(model: model), "stable-collapsed", 560, 400)
        model.togglePanel(.adjustments)
        try render(MainView(model: model), "adjustments", 560, 639)
        try render(AdjustmentEditor(model: model, value: exclusion), "editor", 400, 300)
        model.togglePanel(.trend)
        while model.trendLoading { try await Task.sleep(nanoseconds: 50_000_000) }
        try render(MainView(model: model), "trend", 560, 639)
        model.error = "ActivityWatch에 연결할 수 없습니다. 서버를 실행한 뒤 새로고침하세요."
        model.togglePanel(.trend)
        try render(MainView(model: model), "error", 560, 430)
        print("Rendered previews at \(output.path)")
    }
}
