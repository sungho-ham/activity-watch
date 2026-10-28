import SwiftUI

struct WebPageEditor: View {
    @ObservedObject var model: AppModel
    @State private var title: String
    @State private var address: String
    @State private var error: String?
    init(model: AppModel) {
        self.model = model
        _title = State(initialValue: model.settings.webPage?.title ?? "웹페이지")
        _address = State(initialValue: model.settings.webPage?.url ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("웹페이지 설정").font(.headline)
            TextField("버튼 이름", text: $title)
            TextField("https://example.com", text: $address)
            Text("이름과 주소는 이 Mac의 설정 파일에 저장합니다.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("취소") { model.editingWebPage = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("저장하고 열기") {
                    do { try model.saveWebPage(title: title, address: address) } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 380)
    }
}

struct AdjustmentEditor: View {
    @ObservedObject var model: AppModel
    @State var value: Adjustment
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.entries.contains { $0.id == value.id } ? "시간 보정 수정" : "시간 보정").font(.headline)
            Picker("구분", selection: $value.kind) { ForEach(AdjustmentKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            DatePicker("시작", selection: $value.span.start, displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.field)
            DatePicker("종료", selection: $value.span.end, displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.field)
            if let summary = model.summary {
                Text("반영될 \(value.kind.title) 시간  \(Display.duration(summary.effect(value)))").font(.callout.weight(.medium))
                Text(value.kind == .exclude ? "이 구간에서 활동이 있던 시간만 뺍니다." : "이 구간에서 활동이 없던 시간만 더합니다.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("취소") { model.draft = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("저장") { do { try model.saveAdjustment(value) } catch { self.error = error.localizedDescription } }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 360)
    }
}

struct DayRangeEditor: View {
    @ObservedObject var model: AppModel
    @State private var start: Date
    @State private var end: Date
    @State private var nextDay: Bool
    @State private var error: String?
    init(model: AppModel) {
        self.model = model
        _start = State(initialValue: model.range.start)
        _end = State(initialValue: model.range.end)
        _nextDay = State(initialValue: DaySchedule.key(model.range.end) != model.day)
    }
    var span: Span {
        let cal = Calendar.current
        let date = DaySchedule.date(model.day)!
        let endDay = cal.date(byAdding: .day, value: nextDay ? 1 : 0, to: date)!
        let a = cal.dateComponents([.hour, .minute], from: start)
        let b = cal.dateComponents([.hour, .minute], from: end)
        return Span(start: cal.date(bySettingHour: a.hour!, minute: a.minute!, second: 0, of: date)!, end: cal.date(bySettingHour: b.hour!, minute: b.minute!, second: 0, of: endDay)!)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(model.day) 하루 범위").font(.headline)
            HStack {
                DatePicker("시작", selection: $start, displayedComponents: .hourAndMinute).datePickerStyle(.field)
                Text("선택 날짜").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                DatePicker("종료", selection: $end, displayedComponents: .hourAndMinute).datePickerStyle(.field)
                Picker("종료 날짜", selection: $nextDay) { Text("당일").tag(false); Text("다음 날").tag(true) }.labelsHidden().frame(width: 100)
            }
            Text("기본: ActivityWatch \(model.startOfDay)부터 다음 날 같은 시각까지. 날짜별로 적용되며, 이웃 날짜와 겹칠 수 없습니다.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("기본값 복원") { save(nil) }
                Spacer()
                Button("취소") { model.editingDay = false }.keyboardShortcut(.cancelAction)
                Button("저장") { save(span) }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 390)
    }
    func save(_ span: Span?) { do { try model.saveDayRange(span) } catch { self.error = error.localizedDescription } }
}
