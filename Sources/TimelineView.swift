import SwiftUI

struct TimelineView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragging: Span?
    @State private var boundaryDrag: BoundaryDrag?
    @State private var hoveredBoundary: AggregationBoundary?
    private let rowHeight: CGFloat = 58
    private struct BoundaryDrag {
        let boundary: AggregationBoundary
        let initial: Span
        var range: Span
    }
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let range = model.range
                let aggregationRange = boundaryDrag?.range ?? model.aggregationRange
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
                        for span in summary.activity {
                            if let r = rect(span, y: y, height: 15) { context.fill(Path(r), with: .color(.blue.opacity(0.8))) }
                        }
                        for entry in summary.entries {
                            if let r = rect(entry.span, y: y + 18, height: 5) { context.fill(Path(roundedRect: r, cornerRadius: 1), with: .color(entry.kind == .add ? .green : .orange)) }
                        }
                        for outside in [Span(start: rowRange.start, end: aggregationRange.start),
                                        Span(start: aggregationRange.end, end: rowRange.end)] {
                            if let r = rect(outside, y: y, height: 23) {
                                context.fill(Path(r), with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.7)))
                            }
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
                    }
                    let boundaries = AggregationBoundary.allCases.filter { boundary in
                        let position = min(range.end, max(range.start, boundary.date(in: aggregationRange)))
                        return boundary == .start ? rowRange.contains(position) : rowRange.start < position && position <= rowRange.end
                    }
                    for boundary in boundaries {
                        let position = min(range.end, max(range.start, boundary.date(in: aggregationRange)))
                        let active = model.selectedAggregationBoundary == boundary
                        let hovered = hoveredBoundary == boundary
                        if active || hovered {
                            let highlight = CGRect(x: x(position) - 11, y: y - 7, width: 22, height: 37)
                            context.fill(Path(roundedRect: highlight, cornerRadius: 5), with: .color(.primary.opacity(active ? 0.16 : 0.08)))
                        }
                        var line = Path()
                        line.move(to: CGPoint(x: x(position), y: y - 2))
                        line.addLine(to: CGPoint(x: x(position), y: y + 25))
                        var cap = Path()
                        cap.move(to: CGPoint(x: x(position), y: y - 2))
                        cap.addLine(to: CGPoint(x: x(position) + (boundary == .start ? 1 : -1) * (active ? 10 : 7), y: y - 2))
                        cap.addLine(to: CGPoint(x: x(position), y: y + (active ? 8 : 5)))
                        cap.closeSubpath()
                        if colorScheme == .dark {
                            context.stroke(line, with: .color(.white), lineWidth: active ? 5 : 4)
                            context.stroke(cap, with: .color(.white), lineWidth: 2)
                        }
                        context.stroke(line, with: .color(.black), lineWidth: active ? 3 : hovered ? 2 : 1.5)
                        context.fill(cap, with: .color(.black))
                    }
                    func drawTime(_ label: String, at point: CGPoint, anchor: UnitPoint = .center) {
                        let text = context.resolve(Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(.black))
                        if colorScheme == .dark {
                            let labelSize = text.measure(in: CGSize(width: size.width, height: 20))
                            let bounds = CGRect(x: point.x - labelSize.width * anchor.x, y: point.y - labelSize.height * anchor.y,
                                                width: labelSize.width, height: labelSize.height).insetBy(dx: -3, dy: -1)
                            context.fill(Path(roundedRect: bounds, cornerRadius: 2), with: .color(.white))
                        }
                        context.draw(text, at: point, anchor: anchor)
                    }
                    if boundaries.count == 2, x(aggregationRange.end) - x(aggregationRange.start) < 220 {
                        let midpoint = (x(aggregationRange.start) + x(aggregationRange.end)) / 2
                        drawTime(Display.range(aggregationRange, day: model.day),
                                 at: CGPoint(x: min(width - 80, max(85, midpoint)), y: y + 33))
                    } else {
                        for boundary in boundaries {
                            let date = boundary.date(in: aggregationRange)
                            let position = min(range.end, max(range.start, date))
                            drawTime(Display.time(date, relativeTo: model.day),
                                     at: CGPoint(x: x(position), y: y + 33), anchor: x(position) < size.width / 2 ? .leading : .trailing)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard model.editable else { return }
                if boundaryDrag == nil, dragging == nil, let boundary = boundary(at: value.startLocation, width: geometry.size.width) {
                    model.selectBoundary(boundary)
                    boundaryDrag = BoundaryDrag(boundary: boundary, initial: model.aggregationRange, range: model.aggregationRange)
                }
                if var drag = boundaryDrag {
                    let offset = date(at: value.location, width: geometry.size.width).timeIntervalSince(date(at: value.startLocation, width: geometry.size.width))
                    let target = drag.boundary.date(in: drag.initial).addingTimeInterval(offset)
                    var bounds = model.range
                    if drag.boundary == .start {
                        bounds.end = min(bounds.end, DaySchedule.date(model.schedule.adjacent(model.day, 1))!)
                    }
                    drag.range = drag.boundary.moving(in: drag.initial, to: target, within: bounds)
                    boundaryDrag = drag
                    NSCursor.resizeLeftRight.set()
                    return
                }
                model.selectedAggregationBoundary = nil
                let a = date(at: value.startLocation, width: geometry.size.width)
                let b = date(at: value.location, width: geometry.size.width)
                dragging = Span(start: min(a, b), end: max(a, b))
            }.onEnded { value in
                defer { dragging = nil; boundaryDrag = nil }
                guard model.editable else { return }
                if let drag = boundaryDrag {
                    if drag.range != drag.initial {
                        do { try model.saveAggregationRange(drag.range) }
                        catch { model.error = error.localizedDescription }
                    }
                    return
                }
                let a = date(at: value.startLocation, width: geometry.size.width)
                let b = date(at: value.location, width: geometry.size.width)
                let span = Span(start: min(a, b), end: max(a, b))
                if span.seconds >= 60 { model.beginDraft(span) }
                else { model.select(model.entries.first(where: { $0.span.contains(a) })) }
            })
            .onChange(of: model.day) { _ in
                boundaryDrag = nil
                dragging = nil
                hoveredBoundary = nil
            }
            .onContinuousHover { phase in
                if case let .active(point) = phase, model.editable {
                    hoveredBoundary = boundary(at: point, width: geometry.size.width)
                    if hoveredBoundary != nil || boundaryDrag != nil { NSCursor.resizeLeftRight.set() }
                    else { NSCursor.arrow.set() }
                } else {
                    hoveredBoundary = nil
                    NSCursor.arrow.set()
                }
            }
            .accessibilityLabel("활동 타임라인, \(Display.range(model.range, day: model.day)). 합산 시작 \(Display.time(model.aggregationRange.start, relativeTo: model.day)), 합산 끝 \(Display.time(model.aggregationRange.end, relativeTo: model.day)). 검정 막대를 드래그하면 합산 구간을 바꿉니다. 빈 구간을 드래그하면 시간을 보정합니다. 흐린 구간은 합산하지 않습니다. 상단 합산 버튼으로도 시각을 입력할 수 있습니다.")
        }.frame(height: rowHeight * 2)
    }
    private func boundary(at point: CGPoint, width: CGFloat) -> AggregationBoundary? {
        let row = point.y < rowHeight ? 0.0 : 1.0
        let y = CGFloat(row) * rowHeight + 20
        guard y - 7 <= point.y, point.y <= y + 29 else { return nil }
        let range = model.range
        let half = range.seconds / 2
        let rowRange = Span(start: range.start.addingTimeInterval(row * half), end: range.start.addingTimeInterval((row + 1) * half))
        let aggregation = boundaryDrag?.range ?? model.aggregationRange
        return AggregationBoundary.allCases.compactMap { boundary -> (AggregationBoundary, CGFloat)? in
            let position = min(range.end, max(range.start, boundary.date(in: aggregation)))
            let inRow = boundary == .start ? rowRange.contains(position) : rowRange.start < position && position <= rowRange.end
            let x = 5 + CGFloat(position.timeIntervalSince(rowRange.start) / half) * (width - 10)
            let distance = abs(point.x - x)
            return inRow && distance <= 11 ? (boundary, distance) : nil
        }.min { $0.1 < $1.1 }?.0
    }
    private func date(at point: CGPoint, width: CGFloat) -> Date {
        let row = point.y < rowHeight ? 0.0 : 1.0
        let fraction = min(1, max(0, (point.x - 5) / (width - 10)))
        let value = model.range.start.addingTimeInterval((row + fraction) * model.range.seconds / 2)
        let snapped = Date(timeIntervalSince1970: (value.timeIntervalSince1970 / 60).rounded() * 60)
        return min(model.range.end, max(model.range.start, snapped))
    }
}
