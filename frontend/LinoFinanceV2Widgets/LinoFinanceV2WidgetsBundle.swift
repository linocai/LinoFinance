import SwiftUI
import WidgetKit

// LinoFinance v2 widget extension — Py ④ Widget (decision gate E).
//
// Replaces the P0 placeholder with the three v1 widgets (net worth / credit due /
// AI plans), reading the SAME `WidgetSnapshot` shape from the shared App Group
// `group.com.lino.linofinance.v2` that the v2 app writes after each refresh.
// Appearance is reworked toward the v2 liquid-glass tone: the widget render
// environment does not support the app's full `.glassEffect`, so we approximate
// with a soft indigo→violet gradient `containerBackground` (decision E only asks
// for an appearance rework, not pixel-level glass).
//
// App Group id + snapshot key are duplicated here verbatim from
// `V2WidgetSharing` — the widget target compiles separately from the app, so it
// cannot link the app-side constant; the plan sanctions this copy.

private let appGroupID = "group.com.lino.linofinance.v2"
private let snapshotKey = "linofinance.widget.snapshot"

// MARK: - Snapshot (verbatim shape copy of V2WidgetSnapshot)

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

// MARK: - Liquid-glass container background (v2 tone)

private extension View {
    /// Soft indigo→violet glass wash for the widget container — the v2 accent
    /// approximated for the widget render environment.
    func v2GlassContainer() -> some View {
        containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(.sRGB, red: 0x5B / 255, green: 0x8D / 255, blue: 0xEF / 255, opacity: 0.16),
                    Color(.sRGB, red: 0x8A / 255, green: 0x6D / 255, blue: 0xF0 / 255, opacity: 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(.background)
        }
    }
}

// MARK: - Widgets

struct NetWorthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NetWorthWidget", provider: SnapshotProvider()) { entry in
            NetWorthWidgetView(entry: entry)
        }
        .configurationDisplayName("LinoF 净资产")
        .description("查看净资产和余额概览。")
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
        // Lock-screen accessory families are iOS-only; the v2 widget target also
        // builds for macOS, so they're gated out there.
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular, .accessoryCircular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
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

// MARK: - Views

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
                .lineLimit(1)
            if family == .systemMedium {
                HStack {
                    Metric("余额", entry.snapshot.balance)
                    Metric("30天", entry.snapshot.thirtyDayNet)
                    Metric("信用", entry.snapshot.creditLiability)
                }
            } else {
                Metric("余额", entry.snapshot.balance)
            }
            Spacer(minLength: 0)
            Text(entry.snapshot.updatedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .v2GlassContainer()
    }
}

struct CreditDueWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        #if os(iOS)
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
        #endif
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
            .v2GlassContainer()
        }
    }

    #if os(iOS)
    private var daysUntilDue: Double {
        guard let due = entry.snapshot.nextCreditDue else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: due.dueDate).day ?? 0
        return Double(max(0, min(30, days)))
    }
    #endif
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
        .v2GlassContainer()
    }
}

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

// MARK: - Bundle

@main
struct LinoFinanceV2WidgetsBundle: WidgetBundle {
    var body: some Widget {
        NetWorthWidget()
        CreditDueWidget()
        AIPlansWidget()
    }
}
