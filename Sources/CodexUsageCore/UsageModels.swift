import Foundation

public struct TokenUsage: Equatable, Sendable {
    public var input: Int64 = 0
    public var cachedInput: Int64 = 0
    public var output: Int64 = 0
    public var reasoningOutput: Int64 = 0
    public var total: Int64 = 0

    public init(input: Int64 = 0, cachedInput: Int64 = 0, output: Int64 = 0, reasoningOutput: Int64 = 0, total: Int64 = 0) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.reasoningOutput = reasoningOutput
        self.total = total
    }

    public static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs.input += rhs.input
        lhs.cachedInput += rhs.cachedInput
        lhs.output += rhs.output
        lhs.reasoningOutput += rhs.reasoningOutput
        lhs.total += rhs.total
    }
}

public struct DailyUsage: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public var tokens: TokenUsage
    public var requestCount: Int
    public var sessionCount: Int

    public init(date: Date, tokens: TokenUsage = TokenUsage(), requestCount: Int = 0, sessionCount: Int = 0) {
        self.date = date
        self.tokens = tokens
        self.requestCount = requestCount
        self.sessionCount = sessionCount
    }
}

public struct RateLimitSnapshot: Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int
    public let resetsAt: Date?
    public let planType: String?

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date?, planType: String?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.planType = planType
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let today: DailyUsage
    public let month: TokenUsage
    public let monthRequestCount: Int
    public let recentDays: [DailyUsage]
    public let frequencyChangePercent: Double?
    public let latestRateLimit: RateLimitSnapshot?
    public let quotaWindowTokens: TokenUsage
    public let generatedAt: Date

    public init(today: DailyUsage, month: TokenUsage, monthRequestCount: Int, recentDays: [DailyUsage], frequencyChangePercent: Double?, latestRateLimit: RateLimitSnapshot?, quotaWindowTokens: TokenUsage, generatedAt: Date) {
        self.today = today
        self.month = month
        self.monthRequestCount = monthRequestCount
        self.recentDays = recentDays
        self.frequencyChangePercent = frequencyChangePercent
        self.latestRateLimit = latestRateLimit
        self.quotaWindowTokens = quotaWindowTokens
        self.generatedAt = generatedAt
    }

    public var estimatedQuota: QuotaEstimate? {
        guard let rate = latestRateLimit,
              rate.usedPercent > 0,
              quotaWindowTokens.total > 0 else { return nil }
        let estimatedTotal = Int64((Double(quotaWindowTokens.total) * 100 / rate.usedPercent).rounded())
        return QuotaEstimate(
            observedTokens: quotaWindowTokens.total,
            estimatedTotalTokens: estimatedTotal,
            estimatedRemainingTokens: max(0, estimatedTotal - quotaWindowTokens.total),
            remainingPercent: max(0, 100 - rate.usedPercent)
        )
    }

    public static func empty(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> UsageSnapshot {
        UsageSnapshot(today: DailyUsage(date: calendar.startOfDay(for: now)), month: TokenUsage(), monthRequestCount: 0, recentDays: [], frequencyChangePercent: nil, latestRateLimit: nil, quotaWindowTokens: TokenUsage(), generatedAt: now)
    }
}

public struct QuotaEstimate: Equatable, Sendable {
    public let observedTokens: Int64
    public let estimatedTotalTokens: Int64
    public let estimatedRemainingTokens: Int64
    public let remainingPercent: Double
}
