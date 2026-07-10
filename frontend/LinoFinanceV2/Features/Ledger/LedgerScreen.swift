import SwiftUI

#if os(macOS)

// LedgerScreen — D5 流水 (macOS, liquid glass). Row design matches the comp:
// a FLAT list (one glass card, hairline rows — no day-group headers / daily
// summary), each row = colored category tile + title + inline badges
// (可报销 / 转账 / 已作废) + 分类·账户 subtitle, with the date + signed amount +
// 删除 chip on the right.
//
// Five filters: 全部 / 支出 / 收入 / 转账 / 已作废 (voided hidden by default). Top
// search runs GET /search with a local title/note fallback. 删除 = void (直接作废,
// 无原生二次确认; 可在「已作废」过滤中找回). No draft, no confirm flow.
//
// Contract: `init(model: AppModel)`; owns its own @StateObject LedgerModel.

struct LedgerScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var ledgerModel: LedgerModel

    @State private var filter: LedgerFilter = .all
    @State private var searchText = ""

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
            SegmentedPill(options: LedgerFilter.allCases, selection: $filter) { $0.title }
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
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
            }
            .padding(12)
            .glassPanel(cornerRadius: Theme.Radius.button, tint: Theme.Color.expense)
        }
    }

    // MARK: - Content (flat list, one glass card)

    @ViewBuilder
    private var content: some View {
        let rows = sortedEntries
        if ledgerModel.entries.isEmpty {
            emptyState(title: "还没有记录", message: "用「记一笔」添加第一条记账，这里就会显示流水。")
        } else if rows.isEmpty {
            emptyState(title: "当前过滤下没有记录", message: "换一个过滤条件或清空搜索。")
        } else {
            GlassCard(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(Theme.Color.divider).padding(.horizontal, 12) }
                        // 编辑 only for non-voided entries whose shape the 记一笔
                        // form can represent (v3.0.0 P5). Structurally-linked
                        // entries still reach the form but the backend rejects the
                        // PATCH with a clear 400 (surfaced in actionBanner).
                        let onEdit: (() -> Void)? = (entry.status != .voided && AddEntryPrefill(entry: entry) != nil)
                            ? { model.editingEntry = entry }
                            : nil
                        let onDelete: (() -> Void)? = entry.status == .voided
                            ? nil
                            : { Task { await ledgerModel.voidEntry(entry.id) } }
                        EntryRow(
                            entry: entry,
                            kind: ledgerModel.kind(of: entry),
                            category: ledgerModel.category(entry.categoryLines.first?.categoryId ?? ""),
                            account: ledgerModel.account(entry.accountMovements.first?.accountId),
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                    }
                }
            }
        }
    }

    // MARK: - Filtering (flat, sorted by date desc)

    private var sortedEntries: [EntryDTO] {
        filteredEntries.sorted { $0.date > $1.date }
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
                SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                    Task { await ledgerModel.load() }
                }
            }
        }
    }
}

// MARK: - Entry row (comp-matched: colored tile + badges + date + amount + chip)

private struct EntryRow: View {
    let entry: EntryDTO
    let kind: LedgerKind
    let category: CategoryDTO?
    let account: AccountDTO?
    /// nil → no edit entry point (voided / shape the 记一笔 form can't represent).
    let onEdit: (() -> Void)?
    /// nil → no delete (voided rows can't be re-deleted).
    let onDelete: (() -> Void)?

    private var primaryLine: EntryCategoryLineDTO? { entry.categoryLines.first }
    private var isVoided: Bool { entry.status == .voided }
    private var isReimbursable: Bool { entry.categoryLines.contains { $0.reimbursableFlag } }

    var body: some View {
        HStack(spacing: 13) {
            // Colored category tile (solid rounded square, comp style).
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tileColor)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(isVoided ? Theme.Color.textSecondary : Theme.Color.textPrimary)
                        .lineLimit(1)
                    if kind == .transfer { StatusBadge(text: "转账", tone: .neutral) }
                    if isReimbursable { StatusBadge(text: "可报销", tone: .brand) }
                    if isVoided { StatusBadge(text: "已作废", tone: .negative) }
                }
                Text(subtitle)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(dateLabel)
                .font(Theme.Font.caption().monospacedDigit())
                .foregroundStyle(Theme.Color.textTertiary)

            if let amountValue {
                AmountText(
                    value: amountValue,
                    currency: amountCurrency,
                    showsPositiveSign: kind == .income,
                    font: Theme.Font.subtitle(.semibold),
                    color: amountTint
                )
                .frame(minWidth: 96, alignment: .trailing)
            }

            if let onEdit {
                // 编辑 = void+recreate（v3.0.0 P5）：预填记一笔表单、提交后原记录作废、生成新记录。
                TintedActionChip(title: "编辑", tone: .action, action: onEdit)
                    .help("编辑后原记录作废、生成一条新记录")
            }

            if let onDelete {
                // 直接作废，无原生二次确认（数据可在「已作废」过滤中找回）。
                TintedActionChip(title: "删除", tone: .neutral, action: onDelete)
                    .help("作废后可在「已作废」过滤中找回")
            }
        }
        .opacity(isVoided ? 0.62 : 1)
    }

    private func signedAmount(_ line: EntryCategoryLineDTO) -> DecimalValue {
        kind == .expense ? DecimalValue(-line.amount.value) : line.amount
    }

    /// Amount to show: the category line (signed) for expense/income; the movement
    /// amount (unsigned, neutral) for transfers, which carry no category line.
    private var amountValue: DecimalValue? {
        if let line = primaryLine { return signedAmount(line) }
        if let mv = entry.accountMovements.first { return mv.amount }
        return nil
    }

    private var amountCurrency: CurrencyCode {
        primaryLine?.currency ?? entry.accountMovements.first?.currency ?? .cny
    }

    /// 分类 · 账户 (comp order).
    private var subtitle: String {
        let categoryPart = category?.name ?? (kind == .transfer ? "转账" : "未分类")
        let accountPart = account.map { " · \($0.name)" } ?? ""
        return "\(categoryPart)\(accountPart)"
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(entry.date) { return "今天" }
        if cal.isDateInYesterday(entry.date) { return "昨天" }
        return Self.md.string(from: entry.date)
    }

    /// Solid tile color: voided→gray, transfer→indigo, income→green, expense→a
    /// stable per-category palette pick (so each category keeps one color).
    private var tileColor: Color {
        if isVoided { return Theme.fixed(0x9A9AA0) }
        switch kind {
        case .income: return Theme.fixed(0x34C759)
        case .transfer: return Theme.fixed(0x5B8DEF)
        case .expense:
            let key = category?.name ?? entry.title
            return Self.expensePalette[Self.stableIndex(key, Self.expensePalette.count)]
        }
    }

    private var amountTint: Color {
        if isVoided { return Theme.Color.textTertiary }
        switch kind {
        case .income: return Theme.Color.income
        case .expense: return Theme.Color.expense
        case .transfer: return Theme.Color.textSecondary
        }
    }

    // Soft-vivid expense palette (comp vibe: orange / blue / violet / pink / teal / amber).
    private static let expensePalette: [Color] = [
        Theme.fixed(0xFF8A4C), Theme.fixed(0x4C9AFF), Theme.fixed(0x9B7BFF),
        Theme.fixed(0xFF6F91), Theme.fixed(0x2BB7A6), Theme.fixed(0xF0B429),
    ]

    /// Deterministic (process-stable) hash → palette index. Swift's String.hashValue
    /// is per-run randomized, so use a fixed djb2 instead.
    private static func stableIndex(_ s: String, _ count: Int) -> Int {
        var h = 5381
        for b in s.utf8 { h = (h &* 33 &+ Int(b)) & 0x7fffffff }
        return count > 0 ? h % count : 0
    }

    private static let md: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d"
        return f
    }()
}

#endif
