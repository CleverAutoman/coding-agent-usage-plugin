import CodexUsageCore
import Foundation

do {
    let analyzer = UsageAnalyzer()
    let snapshot = try analyzer.analyze()
    let output: [String: Any] = [
        "today": [
            "total_tokens": snapshot.today.tokens.total,
            "input_tokens": snapshot.today.tokens.input,
            "cached_input_tokens": snapshot.today.tokens.cachedInput,
            "output_tokens": snapshot.today.tokens.output,
            "requests": snapshot.today.requestCount,
            "sessions": snapshot.today.sessionCount
        ],
        "month": [
            "total_tokens": snapshot.month.total,
            "requests": snapshot.monthRequestCount
        ],
        "frequency_change_percent": snapshot.frequencyChangePercent.map { $0 as Any } ?? NSNull(),
        "quota_window": [
            "observed_tokens": snapshot.quotaWindowTokens.total,
            "estimated_total_tokens": snapshot.estimatedQuota?.estimatedTotalTokens as Any? ?? NSNull(),
            "estimated_remaining_tokens": snapshot.estimatedQuota?.estimatedRemainingTokens as Any? ?? NSNull(),
            "remaining_percent": snapshot.estimatedQuota?.remainingPercent as Any? ?? NSNull()
        ],
        "generated_at": ISO8601DateFormatter().string(from: snapshot.generatedAt)
    ]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("codex-usage: \(error.localizedDescription)\n".utf8))
    exit(1)
}
