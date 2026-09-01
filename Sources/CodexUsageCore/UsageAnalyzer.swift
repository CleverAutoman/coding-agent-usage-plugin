import Foundation

public enum UsageAnalyzerError: LocalizedError {
    case sessionsDirectoryMissing(String)

    public var errorDescription: String? {
        switch self {
        case .sessionsDirectoryMissing(let path):
            return "Codex sessions directory was not found: \(path)"
        }
    }
}

public struct UsageAnalyzer: Sendable {
    public let sessionsURL: URL
    public let calendar: Calendar

    public init(
        sessionsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.sessionsURL = sessionsURL
        self.calendar = calendar
    }

    public func analyze(now: Date = Date(), recentDayCount: Int = 14) throws -> UsageSnapshot {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionsURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw UsageAnalyzerError.sessionsDirectoryMissing(sessionsURL.path)
        }

        let startOfToday = calendar.startOfDay(for: now)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday
        let chartStart = calendar.date(byAdding: .day, value: -(recentDayCount - 1), to: startOfToday) ?? monthStart
        let earliestRelevant = min(monthStart, chartStart)
        var buckets: [Date: MutableDay] = [:]
        var latestRate: (timestamp: Date, value: RateLimitSnapshot)?
        var tokenEvents: [TimestampedUsage] = []

        guard let enumerator = FileManager.default.enumerator(at: sessionsURL, includingPropertiesForKeys: nil, options: []) else {
            return UsageSnapshot.empty(now: now, calendar: calendar)
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            parseFile(fileURL, earliestRelevant: earliestRelevant, now: now, buckets: &buckets, latestRate: &latestRate, tokenEvents: &tokenEvents)
        }

        let recentDays = (0..<recentDayCount).compactMap { offset -> DailyUsage? in
            guard let date = calendar.date(byAdding: .day, value: offset - recentDayCount + 1, to: startOfToday) else { return nil }
            let bucket = buckets[date]
            return DailyUsage(date: date, tokens: bucket?.tokens ?? TokenUsage(), requestCount: bucket?.requestCount ?? 0, sessionCount: bucket?.sessions.count ?? 0)
        }

        let today = recentDays.last ?? DailyUsage(date: startOfToday)
        var monthTokens = TokenUsage()
        var monthRequests = 0
        for (date, bucket) in buckets where date >= monthStart && date <= startOfToday {
            monthTokens += bucket.tokens
            monthRequests += bucket.requestCount
        }

        let comparisonDays = recentDays.dropLast().suffix(7).filter { $0.requestCount > 0 }
        let frequencyChange: Double?
        if comparisonDays.isEmpty {
            frequencyChange = nil
        } else {
            let average = Double(comparisonDays.reduce(0) { $0 + $1.requestCount }) / Double(comparisonDays.count)
            frequencyChange = (Double(today.requestCount) - average) / average * 100
        }

        var quotaWindowTokens = TokenUsage()
        if let rate = latestRate?.value, let reset = rate.resetsAt {
            let windowStart = reset.addingTimeInterval(-Double(rate.windowMinutes * 60))
            for event in tokenEvents where event.timestamp >= windowStart && event.timestamp <= now {
                quotaWindowTokens += event.tokens
            }
        }

        return UsageSnapshot(today: today, month: monthTokens, monthRequestCount: monthRequests, recentDays: recentDays, frequencyChangePercent: frequencyChange, latestRateLimit: latestRate?.value, quotaWindowTokens: quotaWindowTokens, generatedAt: now)
    }

    private func parseFile(
        _ fileURL: URL,
        earliestRelevant: Date,
        now: Date,
        buckets: inout [Date: MutableDay],
        latestRate: inout (timestamp: Date, value: RateLimitSnapshot)?,
        tokenEvents: inout [TimestampedUsage]
    ) {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let sessionID = fileURL.deletingPathExtension().lastPathComponent
        var previousTotal: TokenUsage?
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for lineSlice in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(lineSlice)
            guard line.contains("\"token_count\"") else { continue }
            guard
                let data = line.data(using: .utf8),
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let timestampText = root["timestamp"] as? String,
                let timestamp = formatter.date(from: timestampText),
                timestamp <= now,
                let payload = root["payload"] as? [String: Any],
                payload["type"] as? String == "token_count"
            else { continue }

            let info = payload["info"] as? [String: Any]
            let currentTotal = Self.tokenUsage(from: info?["total_token_usage"] as? [String: Any])
            var usage = Self.tokenUsage(from: info?["last_token_usage"] as? [String: Any])
            if usage == nil, let total = currentTotal {
                usage = Self.nonNegativeDifference(total, previousTotal ?? TokenUsage())
            }
            previousTotal = currentTotal ?? previousTotal

            if let usage {
                tokenEvents.append(TimestampedUsage(timestamp: timestamp, tokens: usage))
            }

            let day = calendar.startOfDay(for: timestamp)
            if day >= earliestRelevant, let usage {
                var bucket = buckets[day] ?? MutableDay()
                bucket.tokens += usage
                bucket.requestCount += 1
                bucket.sessions.insert(sessionID)
                buckets[day] = bucket
            }

            if let rate = Self.rateLimit(from: payload), latestRate == nil || timestamp > latestRate!.timestamp {
                latestRate = (timestamp, rate)
            }
        }
    }

    private static func tokenUsage(from object: [String: Any]?) -> TokenUsage? {
        guard let object else { return nil }
        return TokenUsage(input: int64(object["input_tokens"]), cachedInput: int64(object["cached_input_tokens"]), output: int64(object["output_tokens"]), reasoningOutput: int64(object["reasoning_output_tokens"]), total: int64(object["total_tokens"]))
    }

    private static func nonNegativeDifference(_ lhs: TokenUsage, _ rhs: TokenUsage) -> TokenUsage {
        TokenUsage(input: max(0, lhs.input - rhs.input), cachedInput: max(0, lhs.cachedInput - rhs.cachedInput), output: max(0, lhs.output - rhs.output), reasoningOutput: max(0, lhs.reasoningOutput - rhs.reasoningOutput), total: max(0, lhs.total - rhs.total))
    }

    private static func rateLimit(from payload: [String: Any]) -> RateLimitSnapshot? {
        guard let limits = payload["rate_limits"] as? [String: Any], let primary = limits["primary"] as? [String: Any], let used = double(primary["used_percent"]) else { return nil }
        return RateLimitSnapshot(usedPercent: used, windowMinutes: Int(int64(primary["window_minutes"])), resetsAt: double(primary["resets_at"]).map(Date.init(timeIntervalSince1970:)), planType: limits["plan_type"] as? String)
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) ?? 0 }
        return 0
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}

private struct MutableDay {
    var tokens = TokenUsage()
    var requestCount = 0
    var sessions: Set<String> = []
}

private struct TimestampedUsage {
    let timestamp: Date
    let tokens: TokenUsage
}
