import SwiftUI

#if os(macOS)

// LedgerScreen — D5 流水 (macOS, liquid glass). Replaces the P2 stub.
//
// Lists entries grouped by day. Five filters: 全部 / 支出 / 收入 / 转账 / 已作废
// (voided hidden by default; the first four show only non-voided). Top search
// box runs `GET /search` (entries) and also falls back to a local title/note
// match. Each day header shows a 支出/收入 小汇总 (CNY 折算, only confirmed).
// 作废 action文案 = 删除; the confirm弹窗写明可在「已作废」找回. No draft, no
// confirm flow (v1.4.0 口径).
//
// Contract: `init(model: AppModel)`; owns its own @StateObject LedgerModel.

struct LedgerScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var ledgerModel: LedgerModel

    @State private var filter: LedgerFilter = .all
    @State private var searchText = ""
    @State private var deleteTarget: EntryDTO?

    init(model: AppModel) {
        self.model = model
        _ledgerModel = StateObject(wrappedValue: LedgerModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            controls
            actionBanner

            switch ledgerModel.state {
            case .idle, .loading where ledgerModel.entries.isEmpty:
                loadingState
            case .failed(let message):
                failedState(message)
            default:
                content
            }
        }
        .task { if ledgerModel.entries.isEmpty { await ledgerModel.load() } }
        .alert("删除记录？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), presenting: deleteTarget) { entry in
            Button("删除", role: .destructive) {
                Task { await ledgerModel.voidEntry(entry.id) }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text("删除会回滚这条记录对余额、账单和报销的影响，可在「已作废」过滤中找回。")
        }
    }

    // MARK: - Header + controls

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("流水")
                .font(Theme.Font.pageTitle())
                .foregroundStyle(Theme.Color.textPrimary)
            Text("单笔记录、分类拆分和账户流水")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("", selection: $filter) {
                ForEach(LedgerFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.textTertiary)
                TextField("搜索标题、备注", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                    .onSubmit { Task { await ledgerModel.runSearch(searchText) } }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        Task { await ledgerModel.runSearch("") }
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassPanel(cornerRadius: Theme.Radius.button)
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty { Task { await ledgerModel.runSearch("") } }
        }
    }

    @ViewBuilder
    private var actionBanner: some View {
        if let message = ledgerModel.actionError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer(minLength: 8)
                Button { ledgerModel.actionError = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
            .padding(12)
            .glassPanel(cornerRadius: Theme.Radius.button, tint: Theme.Color.expense)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let groups = groupedEntries
        if ledgerModel.entries.isEmpty {
            emptyState(title: "还没有记录", message: "用「记一笔」添加第一条记账，这里就会显示流水。")
        } else if groups.isEmpty {
            emptyState(title: "当前过滤下没有记录", message: "换一个过滤条件或清空搜索。")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups) { group in
                    dayCard(group)
                }
            }
        }
    }

    private func dayCard(_ group: DayGroup) -> some View {
        let totals = ledgerModel.dailyTotals(group.entries)
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(group.title)
                        .font(Theme.Font.subtitle(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    if totals.expense > 0 || totals.income > 0 {
                        HStack(spacing: 10) {
                            if totals.expense > 0 {
                                Text("支出 \(cny(totals.expense))")
                                    .foregroundStyle(Theme.Color.expense)
                            }
                            if totals.income > 0 {
                                Text("收入 \(cny(totals.income))")
                                    .foregroundStyle(Theme.Color.income)
                            }
                        }
                        .font(Theme.Font.badge(.semibold).monospacedDigit())
                    }
                    Text("\(group.entries.count) 条")
                        .font(Theme.Font.badge().monospacedDigit())
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(Theme.Color.divider) }
                        EntryRow(
                            entry: entry,
                            kind: ledgerModel.kind(of: entry),
                            category: ledgerModel.category(entry.categoryLines.first?.categoryId ?? ""),
                            account: ledgerModel.account(entry.accountMovements.first?.accountId),
                            onDelete: entry.status == .voided ? nil : { deleteTarget = entry }
                        )
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func cny(_ value: Decimal) -> String {
        "¥" + (Self.groupingFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)")
    }

    // MARK: - Grouping + filtering

    private struct DayGroup: Identifiable {
        let id: TimeInterval
        let title: String
        let entries: [EntryDTO]
    }

    private var filteredEntries: [EntryDTO] {
        var base: [EntryDTO]
        switch filter {
        case .voided:
            base = ledgerModel.entries.filter { $0.status == .voided }
        case .all:
            base = ledgerModel.entries.filter { $0.status != .voided }
        case .expense:
            base = ledgerModel.entries.filter { $0.status != .voided && ledgerModel.kind(of: $0) == .expense }
        case .income:
            base = ledgerModel.entries.filter { $0.status != .voided && ledgerModel.kind(of: $0) == .income }
        case .transfer:
            base = ledgerModel.entries.filter { $0.status != .voided && ledgerModel.kind(of: $0) == .transfer }
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter { entry in
            if let hits = ledgerModel.searchHitIds, hits.contains(entry.id) { return true }
            return entry.title.localizedCaseInsensitiveContains(trimmed)
                || (entry.note?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private var groupedEntries: [DayGroup] {
        let calendar = Calendar.current
        let dict = Dictionary(grouping: filteredEntries) { calendar.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { day in
            DayGroup(
                id: day.timeIntervalSince1970,
                title: dayLabel(day),
                entries: (dict[day] ?? []).sorted { $0.date > $1.date }
            )
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今日" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        return Self.dayFormatter.string(from: day)
    }

    // MARK: - States

    private func emptyState(title: String, message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
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
                Button("重试") { Task { await ledgerModel.load() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Formatters

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 EEEE"
        return f
    }()

    private static let groupingFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Entry row

private struct EntryRow: View {
    let entry: EntryDTO
    let kind: LedgerKind
    let category: CategoryDTO?
    let account: AccountDTO?
    /// nil → no delete (voided rows can't be re-deleted).
    let onDelete: (() -> Void)?

    private var primaryLine: EntryCategoryLineDTO? { entry.categoryLines.first }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconSymbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: 28, height: 28)
                .background(iconTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(Theme.Font.body(.medium))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    if entry.status == .voided {
                        StatusBadge(text: "已作废", tone: .negative)
                    }
                }
                Text(subtitle)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let primaryLine {
                AmountText(
                    value: signedAmount(primaryLine),
                    currency: primaryLine.currency,
                    showsPositiveSign: kind == .income,
                    font: Theme.Font.subtitle(.semibold),
                    color: amountTint
                )
            }

            if let onDelete {
                Menu {
                    Button("删除", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .opacity(entry.status == .voided ? 0.6 : 1)
        .contextMenu {
            if let onDelete { Button("删除", role: .destructive) { onDelete() } }
        }
    }

    private func signedAmount(_ line: EntryCategoryLineDTO) -> DecimalValue {
        kind == .expense ? DecimalValue(-line.amount.value) : line.amount
    }

    private var subtitle: String {
        let accountPart = account.map { "\($0.name) · " } ?? ""
        let categoryPart = category?.name ?? (kind == .transfer ? "转账" : "未分类")
        return "\(accountPart)\(categoryPart)"
    }

    private var iconSymbol: String {
        if entry.status == .voided { return "xmark.circle" }
        switch kind {
        case .income: return "arrow.down.left.circle"
        case .expense: return "arrow.up.right.circle"
        case .transfer: return "arrow.left.arrow.right.circle"
        }
    }

    private var iconTint: Color {
        if entry.status == .voided { return Theme.Color.textTertiary }
        switch kind {
        case .income: return Theme.Color.income
        case .expense: return Theme.Color.expense
        case .transfer: return Theme.Color.link
        }
    }

    private var amountTint: Color {
        if entry.status == .voided { return Theme.Color.textTertiary }
        switch kind {
        case .income: return Theme.Color.income
        case .expense: return Theme.Color.expense
        case .transfer: return Theme.Color.textSecondary
        }
    }
}

#endif
