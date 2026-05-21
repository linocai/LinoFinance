import SwiftUI
import Charts

/// 现金流图卡 —— 对齐 HTML `.chart-card` 第一张：标题 + segmented + 12 桶堆叠柱 + 12 点折线。
/// 模式（mode）影响图形：
///   - `.stacked`: 进账 / 出账 / 净额折线全部叠
///   - `.net`: 仅净额折线 + 0 基线
///   - `.cumulative`: 净额累计折线
struct CashflowChartCard: View {
    let buckets: [Bucket]
    @Binding var mode: Mode
    var title: String = "现金流 · 未来 90 天"
    var subtitle: String = "含工资 · 订阅 · 信用卡还款 · 报销到账"

    struct Bucket: Identifiable, Equatable {
        let id: String
        let label: String
        let inflow: Double
        let outflow: Double
        let net: Double
    }

    enum Mode: String, CaseIterable, Identifiable {
        case stacked, net
        var id: String { rawValue }
        var title: String {
            switch self {
            case .stacked: "堆叠"
            case .net: "净额"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(FinanceTypography.headline)
                        .foregroundStyle(FinanceTokens.Text.primary)
                    Text(subtitle)
                        .font(FinanceTypography.caption)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                }
                Spacer()
                SegmentedSwitcher(options: Mode.allCases, selection: $mode) { $0.title }
                    .frame(maxWidth: 220)
            }

            chart
                .frame(height: 200)

            HStack(spacing: 18) {
                Legend(color: FinanceTokens.State.income, label: "进账")
                Legend(color: FinanceTokens.State.expense, label: "出账")
                Legend(color: FinanceTokens.Brand.primary, label: "净额", shape: .circle)
                Spacer()
                Text("下周 → \(bucketsRange)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(FinanceTokens.Text.tertiary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(strength: .strong, elevation: .elevated)
    }

    @ViewBuilder
    private var chart: some View {
        if buckets.isEmpty {
            ContentUnavailableView("暂无现金流", systemImage: "chart.bar")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            Chart {
                switch mode {
                case .stacked:
                    ForEach(buckets) { b in
                        BarMark(
                            x: .value("时段", b.label),
                            y: .value("进账", b.inflow)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [FinanceTokens.State.income.opacity(0.85), FinanceTokens.State.income.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(3)

                        BarMark(
                            x: .value("时段", b.label),
                            y: .value("出账", -b.outflow)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [FinanceTokens.State.expense.opacity(0.15), FinanceTokens.State.expense.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(3)
                    }
                    netLineAndPoints
                case .net:
                    netLineAndPoints
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(FinanceTokens.Text.tertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                        .foregroundStyle(FinanceTokens.Stroke.soft)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(FinanceTokens.Text.tertiary)
                }
            }
        }
    }

    @ChartContentBuilder
    private var netLineAndPoints: some ChartContent {
        ForEach(buckets) { b in
            LineMark(
                x: .value("时段", b.label),
                y: .value("净额", b.net)
            )
            .foregroundStyle(FinanceTokens.Brand.primary)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2))

            PointMark(
                x: .value("时段", b.label),
                y: .value("净额", b.net)
            )
            .foregroundStyle(FinanceTokens.Brand.primary)
            .symbolSize(36)
        }
    }

    private var bucketsRange: String {
        guard let first = buckets.first?.label, let last = buckets.last?.label else { return "—" }
        return "\(first) → \(last)"
    }
}

private struct Legend: View {
    let color: Color
    let label: String
    enum Shape { case bar, circle }
    var shape: Shape = .bar

    var body: some View {
        HStack(spacing: 6) {
            Group {
                switch shape {
                case .bar:
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: 10, height: 6)
                case .circle:
                    Circle().fill(color).frame(width: 7, height: 7)
                }
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(FinanceTokens.Text.secondary)
        }
    }
}
