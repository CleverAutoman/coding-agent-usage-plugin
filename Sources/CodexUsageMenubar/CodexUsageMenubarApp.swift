import Charts
import CodexUsageCore
import ServiceManagement
import SwiftUI

@main
struct CodexUsageMenubarApp: App {
    @StateObject private var model = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(model: model)
        } label: {
            HStack(spacing: 3) {
                Text("⚡️")
                Text(model.menuBarTitle).fontWeight(.semibold)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty()
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var officialPlan: OfficialPlanInfo?
    @Published private(set) var officialPlanError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let analyzer = UsageAnalyzer()
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var menuBarTitle: String { compact(snapshot.today.tokens.total) }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        let analyzer = analyzer
        Task {
            do {
                snapshot = try await Task.detached(priority: .utility) { try analyzer.analyze() }.value
                refreshOfficialPlan()
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    func refreshOfficialPlan(force: Bool = false) {
        let rawPlan = snapshot.latestRateLimit?.planType
        if !force, officialPlan?.rawPlanType == rawPlan { return }
        Task {
            do {
                officialPlan = try await OfficialPricingService.fetch(planType: rawPlan)
                officialPlanError = nil
            } catch {
                officialPlan = OfficialPricingService.fallback(planType: rawPlan)
                officialPlanError = "官网刷新失败，显示最近内置规则"
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            errorMessage = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    func compact(_ value: Int64) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var model: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            usageRings
            activity
            chart
            rateLimit
            footer
        }
        .padding(18)
        .frame(width: 390)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.orange.gradient)
                    .frame(width: 34, height: 34)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex 使用情况").font(.title2.bold())
                Text("数据仅在本机统计").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.refreshOfficialPlan(force: true) } label: {
                Image(systemName: "network")
            }
            .buttonStyle(.plain)
            .help("刷新官网套餐额度")
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .disabled(model.isRefreshing)
                .help("立即刷新")
        }
    }

    private var usageRings: some View {
        HStack(spacing: 14) {
            TokenTotalRing(
                title: "今天",
                used: model.snapshot.today.tokens.total,
                color: .orange,
                compact: model.compact
            )
            TokenTotalRing(
                title: "本月",
                used: model.snapshot.month.total,
                color: .purple,
                compact: model.compact
            )
        }
    }

    private var cacheRatio: String {
        let input = model.snapshot.today.tokens.input
        guard input > 0 else { return "—" }
        return String(format: "%.0f%%", Double(model.snapshot.today.tokens.cachedInput) / Double(input) * 100)
    }

    private var activity: some View {
        HStack(spacing: 0) {
            activityItem("请求", "\(model.snapshot.today.requestCount)")
            Divider().frame(height: 30)
            activityItem("会话", "\(model.snapshot.today.sessionCount)")
            Divider().frame(height: 30)
            activityItem("缓存", cacheRatio)
            Divider().frame(height: 30)
            activityItem("较近 7 天", trendText)
        }
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func activityItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var trendText: String {
        guard let change = model.snapshot.frequencyChangePercent else { return "—" }
        return String(format: "%@%.0f%%", change >= 0 ? "+" : "", change)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("14 天 Token 趋势").font(.subheadline.weight(.semibold))
                    Text("总计 \(model.compact(recentTotal)) token")
                        .font(.title3.bold().monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("日均").font(.caption2).foregroundStyle(.secondary)
                    Text("\(model.compact(recentAverage)) token")
                        .font(.caption.bold().monospacedDigit())
                }
            }

            Chart(model.snapshot.recentDays) { day in
                AreaMark(
                    x: .value("日期", day.date, unit: .day),
                    y: .value("Token", day.tokens.total)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.32), .blue.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("日期", day.date, unit: .day),
                    y: .value("Token", day.tokens.total)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                if day.tokens.total > 0 {
                    PointMark(
                        x: .value("日期", day.date, unit: .day),
                        y: .value("Token", day.tokens.total)
                    )
                    .foregroundStyle(day.date == model.snapshot.today.date ? .orange : .blue)
                    .symbolSize(day.date == model.snapshot.today.date ? 55 : 22)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    if let tokens = value.as(Int64.self) {
                        AxisValueLabel { Text(model.compact(tokens)) }
                    }
                }
            }
            .frame(height: 120)

            HStack(spacing: 4) {
                ForEach(Array(model.snapshot.recentDays.suffix(7))) { day in
                    VStack(spacing: 3) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(model.compact(day.tokens.total))
                            .font(.caption2.bold().monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        day.date == model.snapshot.today.date ? Color.orange.opacity(0.13) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                }
            }
        }
        .padding(12)
        .background(.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }

    private var recentTotal: Int64 {
        model.snapshot.recentDays.reduce(0) { $0 + $1.tokens.total }
    }

    private var recentAverage: Int64 {
        guard !model.snapshot.recentDays.isEmpty else { return 0 }
        return recentTotal / Int64(model.snapshot.recentDays.count)
    }

    @ViewBuilder
    private var rateLimit: some View {
        if let rate = model.snapshot.latestRateLimit {
            HStack(alignment: .top, spacing: 14) {
                QuotaRing(remainingPercent: max(0, 100 - rate.usedPercent))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.officialPlan?.displayName ?? planDisplayName(rate.planType))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Link("OpenAI 官网", destination: OfficialPricingService.sourceURL)
                            .font(.caption)
                    }
                    Text(rate.windowMinutes == 10_080 ? "每周使用限额" : "账户额度窗口：\(windowDescription(rate.windowMinutes))")
                        .font(.caption)
                    if let estimate = model.snapshot.estimatedQuota {
                        Text("预计剩余 ≈ \(model.compact(estimate.estimatedRemainingTokens)) token")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.blue)
                        Text("预计总量 ≈ \(model.compact(estimate.estimatedTotalTokens)) · 本窗口已记录 \(model.compact(estimate.observedTokens))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let range = model.officialPlan?.solLocalMessages {
                        Text("GPT-5.6 Sol：约 \(range) 条本地消息 / 5 小时")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = model.officialPlanError {
                        Text(error).font(.caption2).foregroundStyle(.orange)
                    } else if let checked = model.officialPlan?.checkedAt {
                        Text("官网同步：\(checked.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let reset = rate.resetsAt {
                        Text("重置：\(reset.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if model.snapshot.estimatedQuota != nil {
                        Text("按本机窗口 token ÷ 已用比例反推；比例取整及模型、缓存权重会造成误差。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func planDisplayName(_ raw: String?) -> String {
        OfficialPricingService.fallback(planType: raw).displayName
    }

    private func windowDescription(_ minutes: Int) -> String {
        if minutes % 10_080 == 0 { return "\(minutes / 10_080) 周" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) 天" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }

    private var footer: some View {
        VStack(spacing: 9) {
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Toggle("开机启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).controlSize(.small)
                Spacer()
                Button("打开日志目录") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"))
                }
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
        }
    }
}

private struct TokenTotalRing: View {
    let title: String
    let used: Int64
    let color: Color
    let compact: (Int64) -> String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), style: StrokeStyle(lineWidth: 11))
                Circle()
                    .trim(from: 0.08, to: 0.92)
                    .stroke(
                        AngularGradient(colors: [color.opacity(0.55), color], center: .center),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Image(systemName: title == "今天" ? "sun.max.fill" : "calendar")
                        .font(.caption.bold())
                        .foregroundStyle(color)
                    Text(compact(used))
                        .font(.title3.bold().monospacedDigit())
                }
            }
            .frame(width: 92, height: 92)
            Text(title).font(.subheadline.weight(.semibold))
            Text("精确 token 累计")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct QuotaRing: View {
    let remainingPercent: Double

    var body: some View {
        ZStack {
            Circle().stroke(.blue.opacity(0.13), lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(max(remainingPercent / 100, 0), 1))
                .stroke(.green.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(String(format: "%.0f%%", remainingPercent))
                    .font(.headline.bold().monospacedDigit())
                Text("剩余额度").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 78, height: 78)
    }
}

struct OfficialPlanInfo: Sendable {
    let rawPlanType: String?
    let displayName: String
    let solLocalMessages: String?
    let checkedAt: Date
}

private enum OfficialPricingService {
    static let sourceURL = URL(string: "https://learn.chatgpt.com/docs/pricing")!
    private static let markdownURL = URL(string: "https://learn.chatgpt.com/docs/pricing.md")!

    static func fetch(planType: String?) async throws -> OfficialPlanInfo {
        var request = URLRequest(url: markdownURL)
        request.timeoutInterval = 12
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8), text.contains("GPT-5.6 Sol") else {
            throw URLError(.badServerResponse)
        }

        let mapping = planMapping(planType)
        let cells = solTableCells(in: text)
        let range = mapping.tableColumn.flatMap { column in
            column < cells.count ? cells[column] : nil
        }

        return OfficialPlanInfo(rawPlanType: planType, displayName: mapping.displayName, solLocalMessages: range, checkedAt: Date())
    }

    static func fallback(planType: String?) -> OfficialPlanInfo {
        let mapping = planMapping(planType)
        let fallbackRanges = [1: "10–100", 2: "50–500", 3: "200–2,000", 4: "10–100"]
        let range = mapping.tableColumn.flatMap { fallbackRanges[$0] }
        return OfficialPlanInfo(rawPlanType: planType, displayName: mapping.displayName, solLocalMessages: range, checkedAt: Date())
    }

    private static func planMapping(_ raw: String?) -> (displayName: String, tableColumn: Int?) {
        switch raw?.lowercased() {
        case "plus": return ("ChatGPT Plus", 1)
        case "prolite", "pro_5x", "pro5x": return ("ChatGPT Pro 5x", 2)
        case "pro", "pro_20x", "pro20x": return ("ChatGPT Pro 20x", 3)
        case "business", "team": return ("ChatGPT Business", 4)
        case "enterprise": return ("ChatGPT Enterprise", nil)
        case "edu": return ("ChatGPT Edu", nil)
        case "free": return ("ChatGPT Free", nil)
        case "go": return ("ChatGPT Go", nil)
        case .some(let raw): return ("ChatGPT \(raw)", nil)
        case nil: return ("套餐识别中", nil)
        }
    }

    private static func solTableCells(in text: String) -> [String] {
        guard let modelRange = text.range(of: "<td>GPT-5.6 Sol</td>"),
              let rowEnd = text.range(of: "</tr>", range: modelRange.lowerBound..<text.endIndex) else {
            return []
        }
        let row = String(text[modelRange.lowerBound..<rowEnd.upperBound])
        let expression = try? NSRegularExpression(pattern: #"<td[^>]*>\s*([^<\n]+?)\s*</td>"#)
        let nsRange = NSRange(row.startIndex..<row.endIndex, in: row)
        return expression?.matches(in: row, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: row) else { return nil }
            return String(row[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? []
    }
}
