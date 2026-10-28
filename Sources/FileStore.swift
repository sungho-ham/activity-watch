import Foundation

/// Single-Mac backup/restore store. Detect external changes instead of overwriting them.
final class FileStore {
    let directory: URL
    private var baseline: [String: Data] = [:]
    private var loaded = false
    private let names = ["settings.json", "state.json"]
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppData/awtoday", isDirectory: true)
    }
    private func read(_ name: String) throws -> Data? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    func load() throws -> (Settings, SavedState) {
        var data: [String: Data] = [:]
        for name in names { data[name] = try read(name) }
        let settings = try data["settings.json"].map { try JSONDates.decoder().decode(Settings.self, from: $0) } ?? Settings()
        let state = try data["state.json"].map { try JSONDates.decoder().decode(SavedState.self, from: $0) } ?? SavedState()
        guard settings.version == 1 else { throw AppError("지원하지 않는 settings.json 버전입니다.") }
        if !settings.automaticBucket && settings.manualBucketID == nil { throw AppError("수동 버킷 설정이 올바르지 않습니다.") }
        try state.validate()
        baseline = data
        loaded = true
        return (settings, state)
    }
    func externallyChanged() throws -> Bool {
        guard loaded else { return true }
        for name in names where try read(name) != baseline[name] { return true }
        return false
    }
    func initializeIfNeeded(settings: Settings, state: SavedState) throws {
        if baseline["settings.json"] == nil { try saveSettings(settings) }
        if baseline["state.json"] == nil { try saveState(state) }
    }
    func saveSettings(_ value: Settings) throws { try write(JSONDates.encoder().encode(value), name: "settings.json") }
    func saveState(_ value: SavedState) throws {
        try value.validate()
        try write(JSONDates.encoder().encode(value), name: "state.json")
    }
    private func write(_ data: Data, name: String) throws {
        guard loaded else { throw AppError("저장 파일을 정상적으로 읽기 전에는 변경할 수 없습니다.") }
        guard try !externallyChanged() else { throw AppError("다른 프로그램이 저장 파일을 변경했습니다. 새로고침 후 다시 시도하세요.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                guard try read(name) == baseline[name] else { throw AppError("저장 중 외부 변경이 감지되었습니다. 새로고침하세요.") }
                try data.write(to: coordinatedURL, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError ?? (writeError as NSError?) { throw error }
        baseline[name] = data
    }
}
