import SwiftUI

#if os(iOS)

// MoreIOSView — 「更多」入口 (iOS · 决策门 B 核心 5 屏先行).
//
// The core 5 screens (总览 / 账户 / 记一笔 / 现金流 / 报表) live in the bottom
// TabBar. The remaining features reach via 「更多」: 流水 (read-only list) and 对账
// (v2.2.0 简版：只读冲突清单 + 信用三数拆解 + 重算) are real screens; the rest
// (报销 / 周期 / 设置) are reachable placeholders marked 「iOS 版后续」.

struct MoreIOSView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                BloomBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        GlassCard {
                            VStack(spacing: 0) {
                                NavigationLink {
                                    LedgerIOSView(model: model)
                                } label: {
                                    moreRow(title: "流水", subtitle: "全部记账记录", systemImage: "list.bullet.rectangle", ready: true)
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Theme.Color.divider)
                                placeholderRow(title: "报销", systemImage: "arrow.uturn.left.circle")
                                Divider().overlay(Theme.Color.divider)
                                placeholderRow(title: "周期", systemImage: "arrow.triangle.2.circlepath")
                                Divider().overlay(Theme.Color.divider)
                                NavigationLink {
                                    ReconciliationIOSView(model: model)
                                } label: {
                                    moreRow(title: "对账", subtitle: "找出对不上的账户 · 信用欠款拆解", systemImage: "checklist", ready: true)
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Theme.Color.divider)
                                placeholderRow(title: "设置", systemImage: "gearshape")
                            }
                        }
                        Text("iOS 版先做核心 5 屏，其余功能稍后补齐。")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 110)
                }
            }
            .navigationTitle("更多")
        }
    }

    private func moreRow(title: String, subtitle: String, systemImage: String, ready: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Color.brandEnd)
                .frame(width: 30, height: 30)
                .background(Theme.Color.brandEnd.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(subtitle)
                    .font(Theme.Font.badge())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .contentShape(Rectangle())
        .frame(minHeight: 44)
        .padding(.vertical, 6)
    }

    private func placeholderRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(width: 30, height: 30)
                .background(Theme.Color.textSecondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(Theme.Font.body(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer(minLength: 8)
            StatusBadge(text: "iOS 版后续", tone: .neutral)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 6)
    }
}

// MARK: - LedgerIOSView — 流水 basic list (LedgerModel, read-only)

private struct LedgerIOSView: View {
    @ObservedObject var model: AppModel
    @StateObject private var ledgerModel: LedgerModel

    init(model: AppModel) {
        self.model = model
        _ledgerModel = StateObject(wrappedValue: LedgerModel(apiClient: model.apiClient))
    }

    var body: some View {
        ZStack {
            BloomBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch ledgerModel.state {
                    case .idle, .loading where ledgerModel.entries.isEmpty:
                        loadingState
                    case .failed(let message):
                        failedState(message)
                    default:
                        content
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("流水")
        .navigationBarTitleDisplayMode(.inline)
        .task { if ledgerModel.entries.isEmpty { await ledgerModel.load() } }
    }

    @ViewBuilder
    private var content: some View {
        let visible = ledgerModel.entries.filter { $0.status == .confirmed }
        if visible.isEmpty {
            GlassCard {
                Text("还没有记录")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
            }
        } else {
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(Theme.Color.divider) }
                        row(entry)
                            .padding(.vertical, 11)
                    }
                }
            }
        }
    }

    private func row(_ entry: EntryDTO) -> some View {
        let kind = ledgerModel.kind(of: entry)
        let firstLine = entry.categoryLines.first
        let amountValue = firstLine?.amount ?? entry.accountMovements.first?.amount ?? DecimalValue(0)
        let cur = firstLine?.currency ?? entry.accountMovements.first?.currency ?? .cny
        return HStack(spacing: 11) {
            Image(systemName: symbol(kind))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color(kind))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Text(Self.dateText(entry.date))
                    .font(Theme.Font.badge())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer(minLength: 8)
            AmountText(
                value: signed(amountValue, kind: kind),
                currency: cur,
                showsPositiveSign: kind == .income,
                font: Theme.Font.subtitle(.semibold),
                color: color(kind)
            )
        }
    }

    private func signed(_ value: DecimalValue, kind: LedgerKind) -> DecimalValue {
        kind == .expense ? DecimalValue(-value.value) : value
    }

    private func symbol(_ kind: LedgerKind) -> String {
        switch kind {
        case .income: "arrow.down.circle.fill"
        case .expense: "arrow.up.circle.fill"
        case .transfer: "arrow.left.arrow.right.circle.fill"
        }
    }

    private func color(_ kind: LedgerKind) -> Color {
        switch kind {
        case .income: Theme.Color.income
        case .expense: Theme.Color.expense
        case .transfer: Theme.Color.textSecondary
        }
    }

    private var loadingState: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在加载流水…")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("流水加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                    Task { await ledgerModel.load() }
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日"
        return f
    }()

    private static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }
}

#endif
