import Foundation

struct Bucket: Decodable, Identifiable, Sendable {
    let id: String
    let created: Date
    let lastUpdated: Date?
    enum CodingKeys: String, CodingKey { case id, created; case lastUpdated = "last_updated" }
    var recentDate: Date { lastUpdated ?? created }
}

struct AWEvent: Decodable {
    let timestamp: Date
    let duration: Double
    let data: Status
    struct Status: Decodable { let status: String }
    var activeSpan: Span? {
        guard data.status == "not-afk", duration.isFinite, duration > 0 else { return nil }
        return Span(start: timestamp, end: timestamp.addingTimeInterval(duration))
    }
}

enum JSONDates {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: text) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: text) { return date }
            throw AppError("시간 형식을 읽을 수 없습니다.")
        }
        return decoder
    }
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(iso(date))
        }
        return encoder
    }
}

struct ActivityWatchAPI {
    var baseURL = URL(string: "http://localhost:5600")!
    var session: URLSession = .shared

    private func request(_ path: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw AppError("ActivityWatch 응답 오류입니다. 서버 상태를 확인하고 새로고침하세요.")
        }
        return data
    }
    func buckets() async throws -> [Bucket] {
        let data = try await request("api/0/buckets/")
        return try JSONDates.decoder().decode([String: Bucket].self, from: data).values
            .filter { $0.id.hasPrefix("aw-watcher-afk_") }
            .sorted { $0.recentDate == $1.recentDate ? $0.id < $1.id : $0.recentDate > $1.recentDate }
    }
    func startOfDay() async throws -> String {
        let value = try JSONDecoder().decode(String.self, from: await request("api/0/settings/startOfDay"))
        guard DaySchedule.validStart(value) else { throw AppError("ActivityWatch의 하루 시작 설정을 읽을 수 없습니다.") }
        return value
    }
    func activity(bucket: String, periods: [Span]) async throws -> [[Span]] {
        guard !periods.isEmpty else { return [] }
        guard periods.allSatisfy(\.isValid) else { throw AppError("조회 시간 범위가 올바르지 않습니다.") }
        // JSON-quote the bucket ID rather than interpolating query-language syntax.
        let quoted = String(data: try JSONEncoder().encode(bucket), encoding: .utf8)!
        let body = try JSONSerialization.data(withJSONObject: [
            "timeperiods": periods.map { "\(JSONDates.iso($0.start))/\(JSONDates.iso($0.end))" },
            "query": ["events = flood(query_bucket(\(quoted)));", "RETURN = events;"]
        ])
        let rows = try JSONDates.decoder().decode([[AWEvent]].self, from: await request("api/0/query/", body: body))
        guard rows.count == periods.count else { throw AppError("ActivityWatch 조회 결과의 날짜 수가 일치하지 않습니다.") }
        return zip(rows, periods).map { events, period in
            Intervals.union(events.compactMap(\.activeSpan), within: period)
        }
    }
}
