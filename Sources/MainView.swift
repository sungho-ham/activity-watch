import SwiftUI
import Charts

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var calendarShown = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) { header; total; timeline; footer }
                .padding(20).frame(height: PopupLayout.baseHeight, alignment: .top)
            if model.panel != nil {
                Divider()
                if model.panel == .adjustments { adjustments.frame(height: model.detailHeight) }
                else {
                    ScrollView { TrendView(model: model).frame(height: PopupLayout.detailHeight) }
                        .frame(height: model.detailHeight)
                }
            }
        }.frame(width: PopupLayout.width).frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).onTapGesture { model.select(nil) })
        .transaction { $0.animation = nil }
        .sheet(item: $model.draft) { AdjustmentEditor(model: model, value: $0) }
        .sheet(isPresented: $model.editingAggregation) { AggregationRangeEditor(model: model) }
        .sheet(isPresented: $model.editingWebPage) { WebPageEditor(model: model) }
        .onExitCommand { model.escape() }
        .environment(\.locale, Locale(identifier: "ko_KR"))
    }
    private var header: some View {
        HStack(spacing: 8) {
            Button { model.moveDay(-1) } label: { Image(systemName: "chevron.left") }.help("이전 날짜").accessibilityLabel("이전 날짜")
            Button { calendarShown.toggle() } label: {
                HStack(spacing: 5) { Text(model.day).monospacedDigit(); Image(systemName: "calendar") }
            }.popover(isPresented: $calendarShown) {
                CalendarPicker(selection: Binding(get: { DaySchedule.date(model.day)! }, set: { model.chooseDay($0); calendarShown = false }))
            }
            Button { model.moveDay(1) } label: { Image(systemName: "chevron.right") }.help("다음 날짜").accessibilityLabel("다음 날짜")
            Button("오늘") { model.today() }
            Spacer(minLength: 0)
            Menu {
                Button("자동 · 최신 AFK 버킷\(model.settings.automaticBucket ? " ✓" : "")") { model.chooseBucket(nil) }
                Divider()
                ForEach(model.buckets) { bucket in
                    Button(bucket.id + (!model.settings.automaticBucket && model.bucketID == bucket.id ? " ✓" : "")) { model.chooseBucket(bucket.id) }
                }
            } label: { Text(model.settings.automaticBucket ? "버킷 · 자동" : model.bucketID ?? "버킷").lineLimit(1).truncationMode(.middle) }
            .frame(width: 105).help(model.bucketID ?? "AFK 버킷 선택").disabled(model.buckets.isEmpty)
        }.controlSize(.small)
    }
    private var total: some View {
        VStack(spacing: 7) {
            Button { model.editingAggregation = true } label: {
                HStack(spacing: 4) {
                    Text("합산 \(Display.range(model.aggregationRange, day: model.day))")
                    Text(model.saved.dayOverrides[model.day] == nil ? "· 기본값" : "· 직접 설정")
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }.font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.plain).help("활동 합산 시작·종료 설정 · 타임라인 눈금은 유지됩니다").disabled(!model.hasServerSettings)
            Text(model.summary.map { Display.duration($0.adjustedSeconds) } ?? (model.loading ? "불러오는 중" : "—"))
                .font(.system(size: model.summary == nil ? 28 : 36, weight: .semibold, design: .rounded)).monospacedDigit().frame(height: 44)
                .help(model.summary.map { Display.exactDuration($0.adjustedSeconds) } ?? "")
            HStack(spacing: 20) {
                metric("활동", value: model.summary?.baseSeconds, color: .secondary, action: nil)
                metric("− 제외", value: model.summary?.excludedSeconds, color: .orange) { model.togglePanel(.adjustments) }
                metric("+ 추가", value: model.summary?.addedSeconds, color: .green) { model.togglePanel(.adjustments) }
            }
            if let summary = model.summary {
                Text(summary.base.first.map { "첫 활동 \(Display.time($0.start, relativeTo: model.day))  ·  마지막 \(Display.time(summary.base.last!.end, relativeTo: model.day))" } ?? "활동 기록 없음").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(model.loading ? "ActivityWatch에서 기록을 확인하고 있습니다." : "새로고침으로 다시 확인할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func metric(_ title: String, value: Double?, color: Color, action: (() -> Void)?) -> some View {
        let label = HStack(spacing: 5) {
                Text(title).foregroundStyle(color)
                Text(value.map(Display.duration) ?? "—").foregroundStyle(.primary).monospacedDigit()
            }.font(.system(size: 12)).help(value.map(Display.exactDuration) ?? "")
        if let action { Button(action: action) { label }.buttonStyle(.plain) }
        else { label }
    }
    private var timeline: some View {
        VStack(spacing: 0) {
            TimelineView(model: model)
            HStack(spacing: 10) {
                Text("● 활동").foregroundStyle(.blue)
                Text("━ + 추가").foregroundStyle(.green)
                Text("━ − 제외").foregroundStyle(.orange)
                Spacer()
                if let selected = model.entries.first(where: { $0.id == model.selectedAdjustment }) {
                    Text(Display.range(selected.span, day: model.day)).foregroundStyle(.secondary).monospacedDigit()
                }
            }.font(.system(size: 10))
        }
    }
    private var footer: some View {
        VStack(spacing: 6) {
            if let error = model.error {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }.font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let notice = model.notice {
                HStack(alignment: .top) {
                    Text(notice).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { model.togglePanel(.trend) } label: { Label("추이", systemImage: model.panel == .trend ? "chevron.up" : "chart.bar") }
                Button("시간 지정") { model.newDraft() }.disabled(!model.editable)
                Spacer()
                Button { model.browserAction?() } label: {
                    Text(model.settings.webPage?.title ?? "웹페이지").lineLimit(1).truncationMode(.tail).frame(maxWidth: 100)
                }.foregroundStyle(Color.accentColor).help(model.settings.webPage?.title ?? "웹페이지 열기")
                if model.loading { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14) }
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 28, height: 28).contentShape(Rectangle())
                }.help("새로고침").accessibilityLabel("새로고침").keyboardShortcut("r", modifiers: .command)
                Menu {
                    Button("ActivityWatch 열기") { NSWorkspace.shared.open(URL(string: "http://localhost:5600/#/timeline")!) }
                    Button("웹페이지 설정") { model.editingWebPage = true }
                    Divider()
                    Button("저장 폴더 열기") { NSWorkspace.shared.open(model.store.directory) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 32, height: 28)
                    .help("더 보기").accessibilityLabel("더 보기")
            }.buttonStyle(.plain).font(.system(size: 12))
        }
    }
    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("시간 보정").font(.headline)
                Text("\(model.entries.count)개").foregroundStyle(.secondary)
                Spacer()
                Button { model.togglePanel(.adjustments) } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain)
            }
            if model.entries.isEmpty {
                Text("타임라인에서 드래그해 추가·제외할 시간대를 지정하세요.").foregroundStyle(.secondary).font(.callout).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.entries) { entry in
                            HStack(spacing: 8) {
                                Button { model.select(entry) } label: {
                                    HStack(spacing: 10) {
                                        Text(entry.kind.symbol).font(.headline).foregroundStyle(entry.kind == .add ? .green : .orange).frame(width: 18)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("\(entry.kind.title)  \(Display.range(entry.span, day: model.day))").monospacedDigit()
                                            if let reason = model.summary?.explanation(entry) { Text(reason).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                        Text(model.summary.map { Display.duration($0.effect(entry)) } ?? "—").monospacedDigit()
                                    }.padding(8).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Menu {
                                    Button("수정") { model.draft = entry }.disabled(!model.editable)
                                    Button("삭제", role: .destructive) { model.deleteAdjustment(entry) }
                                } label: { Image(systemName: "ellipsis") }
                                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 32, height: 28)
                                    .help("보정 수정·삭제").accessibilityLabel("보정 수정·삭제").padding(.trailing, 8)
                            }.background(model.selectedAdjustment == entry.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.025))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }.padding(16)
    }
}

struct CalendarPicker: View {
    @Binding var selection: Date
    var body: some View {
        DatePicker("날짜", selection: $selection, displayedComponents: .date)
            .datePickerStyle(.graphical).labelsHidden().fixedSize().padding(12)
    }
}

struct TrendView: View {
    @ObservedObject var model: AppModel
    @State private var hovered: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("활동 추이").font(.headline)
                Spacer()
                Picker("기간", selection: $model.trendDays) { Text("7일").tag(7); Text("30일").tag(30) }.pickerStyle(.segmented).frame(width: 120)
                    .onChange(of: model.trendDays) { _ in model.loadTrend() }
            }
            if model.trendLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error = model.trendError { Text(error).foregroundStyle(.red).font(.caption).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                Chart(model.trend) { item in
                    BarMark(x: .value("날짜", DaySchedule.date(item.key)!, unit: .day), y: .value("시간", item.adjustedSeconds / 3600))
                        .foregroundStyle(hovered == item.key ? Color.blue : Color.blue.opacity(0.65)).cornerRadius(2)
                }.chartYAxisLabel("시간")
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: model.trendDays == 7 ? 1 : 5)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                            if case let .active(location) = phase {
                                let x = location.x - geo[proxy.plotAreaFrame].origin.x
                                if let date: Date = proxy.value(atX: x) { hovered = DaySchedule.key(date) }
                            } else { hovered = nil }
                        }
                    }
                }.frame(height: 140)
                if let item = model.trend.first(where: { $0.key == hovered }) {
                    Text("\(item.key)  \(Display.duration(item.adjustedSeconds))  ·  활동 \(Display.duration(item.baseSeconds))  − \(Display.duration(item.excludedSeconds))  + \(Display.duration(item.addedSeconds))").font(.system(size: 10)).monospacedDigit()
                } else { Text("막대 위에 포인터를 올리면 계산 내역이 보입니다.").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(16)
    }
}
