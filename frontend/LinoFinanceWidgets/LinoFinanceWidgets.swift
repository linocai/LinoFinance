import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit
#endif

private let appGroupID = "group.com.lino.linofinance"
private let snapshotKey = "linofinance.widget.snapshot"

struct WidgetSnapshot: Codable, Equatable {
    struct CreditDue: Codable, Equatable {
        let accountName: String
        let dueDate: Date
        let amount: String
    }

    let netWorth: String
    let balance: String
    let creditLiability: String
    let thirtyDayNet: String
    let trend: [Double]
    let nextCreditDue: CreditDue?
    let pendingAIPlanCount: Int
    let updatedAt: Date

    static let placeholder = WidgetSnapshot(
        netWorth: "¥0",
        balance: "¥0",
        creditLiability: "¥0",
        thirtyDayNet: "¥0",
        trend: [0, 2, 1, 3, 2, 4, 3],
        nextCreditDue: nil,
        pendingAIPlanCount: 0,
        updatedAt: Date()
    )
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: readSnapshot() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = readSnapshot() ?? .placeholder
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [SnapshotEntry(date: Date(), snapshot: snapshot)], policy: .after(next)))
    }

    private func readSnapshot() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

struct NetWorthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NetWorthWidget", provider: SnapshotProvider()) { entry in
            NetWorthWidgetView(entry: entry)
        }
        .configurationDisplayName("LinoF 净资产")
        .description("查看净资产和 30 天趋势。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CreditDueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CreditDueWidget", provider: SnapshotProvider()) { entry in
            CreditDueWidgetView(entry: entry)
        }
        .configurationDisplayName("LinoF 还款")
        .description("查看下一笔信用还款。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

struct AIPlansWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIPlansWidget", provider: SnapshotProvider()) { entry in
            AIPlansWidgetView(entry: entry)
        }
        .configurationDisplayName("LinoF AI")
        .description("查看待确认 AI 计划数量。")
        .supportedFamilies([.systemSmall])
    }
}

struct NetWorthWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("净资产", systemImage: "chart.pie.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.snapshot.netWorth)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.72)
            MiniSparkline(values: entry.snapshot.trend)
                .frame(height: family == .systemSmall ? 34 : 48)
            if family == .systemMedium {
                HStack {
                    Metric("余额", entry.snapshot.balance)
                    Metric("30天", entry.snapshot.thirtyDayNet)
                    Metric("信用", entry.snapshot.creditLiability)
                }
            }
            Spacer(minLength: 0)
            Text(entry.snapshot.updatedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.background, for: .widget)
    }
}

struct CreditDueWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.snapshot.nextCreditDue.map { "\($0.accountName) \($0.amount)" } ?? "无待还款")
        case .accessoryCircular:
            Gauge(value: daysUntilDue, in: 0...30) {
                Image(systemName: "creditcard")
            } currentValueLabel: {
                Text("\(Int(daysUntilDue))")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("下次还款")
                Text(entry.snapshot.nextCreditDue?.amount ?? "无待还款")
                    .font(.headline)
                Text(entry.snapshot.nextCreditDue.map { $0.dueDate.formatted(date: .abbreviated, time: .omitted) } ?? "")
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Label("下次还款", systemImage: "creditcard.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let due = entry.snapshot.nextCreditDue {
                    Text(due.accountName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(due.amount)
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text(due.dueDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("无待还款")
                        .font(.headline)
                }
                Spacer(minLength: 0)
            }
            .containerBackground(.background, for: .widget)
        }
    }

    private var daysUntilDue: Double {
        guard let due = entry.snapshot.nextCreditDue else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: due.dueDate).day ?? 0
        return Double(max(0, min(30, days)))
    }
}

struct AIPlansWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI 待确认", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(entry.snapshot.pendingAIPlanCount)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text(entry.snapshot.pendingAIPlanCount == 0 ? "全部处理完" : "需要确认")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .containerBackground(.background, for: .widget)
    }
}

#if canImport(ActivityKit)
struct LinoCreditDueAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let dueDate: Date
        let remainingAmount: String
        let statusText: String
    }

    let cycleID: String
    let accountName: String
}

struct LinoAIPlanAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let statusText: String
        let actionCount: Int
    }

    let planID: String
    let sourceText: String
}

struct LinoCreditDueLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LinoCreditDueAttributes.self) { context in
            LiveActivityCard(
                title: context.attributes.accountName,
                subtitle: context.state.statusText,
                value: context.state.remainingAmount,
                systemImage: "creditcard.fill"
            )
            .activityBackgroundTint(.black.opacity(0.72))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.accountName, systemImage: "creditcard.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.remainingAmount)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.statusText)
                }
            } compactLeading: {
                Image(systemName: "creditcard.fill")
            } compactTrailing: {
                Text(context.state.dueDate, style: .timer)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "creditcard.fill")
            }
        }
    }
}

struct LinoAIPlanLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LinoAIPlanAttributes.self) { context in
            LiveActivityCard(
                title: "AI 计划",
                subtitle: context.attributes.sourceText,
                value: "\(context.state.actionCount) 个动作",
                systemImage: "sparkles"
            )
            .activityBackgroundTint(.black.opacity(0.72))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("AI", systemImage: "sparkles")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.actionCount)")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.sourceText)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                Text("\(context.state.actionCount)")
            } minimal: {
                Image(systemName: "sparkles")
            }
        }
    }
}

struct LiveActivityCard: View {
    let title: String
    let subtitle: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .lineLimit(2)
            }
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .padding()
    }
}
#endif

struct Metric: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MiniSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let points = normalizedPoints(in: geometry.size)
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else {
            return [
                CGPoint(x: 0, y: size.height / 2),
                CGPoint(x: size.width, y: size.height / 2),
            ]
        }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let range = max(maximum - minimum, 0.0001)
        return values.enumerated().map { index, value in
            let x = size.width * Double(index) / Double(max(values.count - 1, 1))
            let y = size.height - ((value - minimum) / range * size.height)
            return CGPoint(x: x, y: y)
        }
    }
}

@main
struct LinoFinanceWidgets: WidgetBundle {
    var body: some Widget {
        NetWorthWidget()
        CreditDueWidget()
        AIPlansWidget()
#if canImport(ActivityKit)
        LinoCreditDueLiveActivityWidget()
        LinoAIPlanLiveActivityWidget()
#endif
    }
}
