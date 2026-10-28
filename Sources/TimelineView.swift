import SwiftUI

struct TimelineView: View {
    @ObservedObject var model: AppModel
    @State private var dragging: Span?
    private let rowHeight: CGFloat = 58
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let range = model.range
                let half = range.seconds / 2
                let width = size.width - 10
                let selected = model.entries.first { $0.id == model.selectedAdjustment }
                for row in 0..<2 {
                    let rowRange = Span(start: range.start.addingTimeInterval(Double(row) * half), end: range.start.addingTimeInterval(Double(row + 1) * half))
                    let y = CGFloat(row) * rowHeight + 20
                    func x(_ date: Date) -> CGFloat { 5 + CGFloat(date.timeIntervalSince(rowRange.start) / half) * width }
                    func rect(_ span: Span, y: CGFloat, height: CGFloat) -> CGRect? {
                        guard let clipped = span.intersection(rowRange) else { return nil }
                        return CGRect(x: x(clipped.start), y: y, width: max(1, x(clipped.end) - x(clipped.start)), height: height)
                    }
                    context.fill(Path(roundedRect: CGRect(x: 5, y: y, width: width, height: 15), cornerRadius: 3), with: .color(Color.primary.opacity(0.065)))
                    if let summary = model.summary {
                        for span in summary.base {
                            if let r = rect(span, y: y, height: 15) { context.fill(Path(r), with: .color(.blue.opacity(0.8))) }
                        }
                        for entry in summary.entries {
                            if let r = rect(entry.span, y: y + 18, height: 5) { context.fill(Path(roundedRect: r, cornerRadius: 1), with: .color(entry.kind == .add ? .green : .orange)) }
                        }
                        if summary.capturedAt < rowRange.end, let r = rect(Span(start: max(summary.capturedAt, rowRange.start), end: rowRange.end), y: y, height: 15) {
                            context.fill(Path(r), with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.6)))
                        }
                    }
                    for tick in 0...4 {
                        let date = rowRange.start.addingTimeInterval(half * Double(tick) / 4)
                        let anchor: UnitPoint = tick == 0 ? .leading : tick == 4 ? .trailing : .center
                        context.draw(Text(Display.time(date, relativeTo: model.day)).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: x(date), y: y - 10), anchor: anchor)
                    }
                    if let selection = dragging ?? selected?.span, let r = rect(selection, y: y - 2, height: 27) {
                        context.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(.primary), lineWidth: 2)
                        let endpoints = [selection.start, selection.end].filter { rowRange.contains($0) || $0 == rowRange.end }
                        if endpoints.count == 2 && r.width < 75 {
                            let label = "\(Display.time(selection.start))–\(Display.time(selection.end))"
                            context.draw(Text(label).font(.system(size: 9, weight: .semibold)), at: CGPoint(x: min(width - 45, max(50, r.midX)), y: y + 33))
                        } else {
                            for date in endpoints {
                                context.draw(Text(Display.time(date)).font(.system(size: 9, weight: .semibold)), at: CGPoint(x: min(width - 25, max(30, x(date))), y: y + 33))
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard model.editable else { return }
                let a = date(at: value.startLocation, width: geometry.size.width)
                let b = date(at: value.location, width: geometry.size.width)
                dragging = Span(start: min(a, b), end: max(a, b))
            }.onEnded { value in
                defer { dragging = nil }
                guard model.editable else { return }
                let a = date(at: value.startLocation, width: geometry.size.width)
                let b = date(at: value.location, width: geometry.size.width)
                let span = Span(start: min(a, b), end: max(a, b))
                if span.seconds >= 60 { model.beginDraft(span) }
                else if let entry = model.entries.first(where: { $0.span.contains(a) }) { model.select(entry) }
            })
            .accessibilityLabel("활동 타임라인, \(Display.range(model.range, day: model.day)). 파랑은 활동, 초록은 추가, 주황은 제외. 시간 지정 버튼으로도 편집할 수 있습니다.")
        }.frame(height: rowHeight * 2)
    }
    private func date(at point: CGPoint, width: CGFloat) -> Date {
        let row = point.y < rowHeight ? 0.0 : 1.0
        let fraction = min(1, max(0, (point.x - 5) / (width - 10)))
        let value = model.range.start.addingTimeInterval((row + fraction) * model.range.seconds / 2)
        let snapped = Date(timeIntervalSince1970: (value.timeIntervalSince1970 / 60).rounded() * 60)
        return min(model.range.end, max(model.range.start, snapped))
    }
}
