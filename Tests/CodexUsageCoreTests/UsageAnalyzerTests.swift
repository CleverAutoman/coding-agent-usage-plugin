import Foundation
import Testing
@testable import CodexUsageCore

struct UsageAnalyzerTests {
    @Test
    func aggregatesLastUsageByDayAndMonth() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let lines = [
            "{\"timestamp\":\"2026-08-23T01:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{}}",
            event("2026-08-23T02:00:00.000Z", input: 100, cached: 25, output: 20, total: 120, used: 4),
            event("2026-08-24T02:00:00.000Z", input: 200, cached: 80, output: 30, total: 230, used: 7),
            event("2026-08-24T03:00:00.000Z", input: 300, cached: 120, output: 40, total: 340, used: 8)
        ].joined(separator: "\n")
        try lines.write(to: root.appendingPathComponent("rollout-test.jsonl"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-24T12:00:00Z")!
        let snapshot = try UsageAnalyzer(sessionsURL: root, calendar: calendar).analyze(now: now)

        #expect(snapshot.today.tokens.total == 570)
        #expect(snapshot.today.tokens.input == 500)
        #expect(snapshot.today.tokens.cachedInput == 200)
        #expect(snapshot.today.requestCount == 2)
        #expect(snapshot.today.sessionCount == 1)
        #expect(snapshot.month.total == 690)
        #expect(snapshot.monthRequestCount == 3)
        #expect(snapshot.latestRateLimit?.usedPercent == 8)
        #expect(snapshot.quotaWindowTokens.total == 570)
        #expect(snapshot.estimatedQuota?.estimatedTotalTokens == 7_125)
        #expect(snapshot.estimatedQuota?.estimatedRemainingTokens == 6_555)
    }

    private func event(_ timestamp: String, input: Int, cached: Int, output: Int, total: Int, used: Int) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(total)},"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(total)}},"rate_limits":{"primary":{"used_percent":\(used),"window_minutes":10080,"resets_at":1788134400},"plan_type":"test"}}}
        """
    }
}
