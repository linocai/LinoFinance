import SwiftUI

#if os(macOS)

// ReconciliationScreen — v2.2.0 对账「一致性/冲突检测器」(macOS, sheet).
//
// 推倒重做（删旧「系统余额 vs 当前余额」那套——两个恒等内部数相减、永远「无需调整」、
// 还掩盖信用欠款 −1400 真 bug）。新理念（用户原话）：对账 =「快捷找到哪些账户有冲突 →
// 我定夺哪个对 → 一键纠错」。
//
// 结构：
//   顶部冲突横幅（X 个账户有问题 / N 条孤儿，全平时绿色「一切对得上」）
//   ├─ 孤儿区（R4，跨对象，红标，给「去处理」跳转）
//   └─ 逐账户区（有冲突置顶红标）：
//        • 信用账户 → R1 三数拆解卡（本期待还 / 其他期未还 / 合计），漂移时「重算此账户」
//          + R2 账单↔还款现金流冲突逐条「去处理」跳转
//        • 余额/投资账户 → R3「录真实余额」inline 表单，一键以真实为准记调整对平
//
// 纠错三路：R1 internalRecompute（recompute 接口）/ R3 externalActual（adjustments 接口）/
// R2·R4 jumpRecord（前端导航到现金流 / 周期 / 报销 section）。
struct ReconciliationScreen: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var reconModel: ReconciliationModel

    @State private var globalError: String?

    init(model: AppModel) {
        self.model = model
        _reconModel = StateObject(wrappedValue: ReconciliationModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch reconModel.state {
                    case .idle, .loading:
                        loadingState
                    case .failed(let message):
                        failedState(message)
                    case .loaded:
                        summaryBanner
                        if let globalError {
                            Label(globalError, systemImage: "exclamationmark.triangle.fill")
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Color.expense)
                        }
                        if !reconModel.orphans.isEmpty {
                            orphansSection
                        }
                        ForEach(reconModel.sortedAccounts) { account in
                            AccountConflictCard(
                                account: account,
                                reconModel: reconModel,
                                onJump: jump(to:),
                                onError: { globalError = $0 }
                            )
                        }
                        if reconModel.accounts.isEmpty && reconModel.orphans.isEmpty {
                            emptyState
                        }
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 640, height: 740)
        .background {
            BloomBackground(animated: false).opacity(0.9)
        }
        .task {
            if reconModel.snapshot == nil { await reconModel.load() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("对账")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("找出对不上的账户 · 你定夺真相 · 一键纠错")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            SubtleToolbarButton(title: "刷新", systemImage: "arrow.clockwise") {
                Task { await reconModel.load() }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: - Summary banner

    private var summaryBanner: some View {
        let accountConflicts = reconModel.conflictAccountCount
        let orphanConflicts = reconModel.orphanConflictCount
        let clean = !reconModel.hasConflicts
        return GlassCard {
            HStack(spacing: 12) {
                Image(systemName: clean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(clean ? Theme.Color.income : Theme.fixed(0xE08A1F))
                VStack(alignment: .leading, spacing: 2) {
                    Text(clean ? "一切对得上" : "发现需要核对的冲突")
                        .font(Theme.Font.subtitle(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text(clean
                         ? "所有账户与账单 / 现金流 / 真实余额一致。"
                         : conflictSummaryText(accountConflicts, orphanConflicts))
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
            }
        }
    }

    private func conflictSummaryText(_ accounts: Int, _ orphans: Int) -> String {
        var parts: [String] = []
        if accounts > 0 { parts.append("\(accounts) 个账户有问题") }
        if orphans > 0 { parts.append("\(orphans) 条记录孤儿") }
        return parts.isEmpty ? "见下方拆解。" : parts.joined(separator: " · ")
    }

    // MARK: - Orphans (R4)

    private var orphansSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(Theme.Color.expense)
                    Text("跨对象孤儿")
                        .font(Theme.Font.subtitle(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    StatusBadge(text: "\(reconModel.orphans.count)", tone: .negative)
                    Spacer()
                }
                Text("这些记录缺少应有的关联，需补/改对应记录。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
                ForEach(reconModel.orphans) { conflict in
                    ConflictRow(conflict: conflict, onJump: jump(to:))
                    if conflict.id != reconModel.orphans.last?.id {
                        Divider().overlay(Theme.Color.divider)
                    }
                }
            }
        }
    }

    // MARK: - Navigation (R2/R4 jump)

    /// Jump to the offending record. No per-item deep-link exists in v2 yet, so we
    /// navigate to the owning section and dismiss the sheet; the conflict row已清楚
    /// 标出「哪条记录、什么问题」让用户在目标 section 找到它。
    private func jump(to pointer: ReconciliationPointerDTO) {
        switch pointer.type {
        case "cash_flow_item":
            model.selection = .cashFlow
        case "credit_statement_cycle":
            model.selection = .cycles
        case "reimbursement_claim":
            model.selection = .reimbursements
        case "account":
            model.selection = .accounts
        default:
            return
        }
        dismiss()
    }

    // MARK: - States

    private var loadingState: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在核对账户一致性…")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("对账加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                    Task { await reconModel.load() }
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            Text("没有可对账的账户。")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }
}

// MARK: - Per-account conflict card

private struct AccountConflictCard: View {
    let account: ReconciliationCheckAccountDTO
    @ObservedObject var reconModel: ReconciliationModel
    let onJump: (ReconciliationPointerDTO) -> Void
    let onError: (String) -> Void

    @State private var isRecomputing = false
    @State private var recomputeMessage: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                if account.accountType == .credit {
                    creditBody
                } else {
                    balanceBody
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(account.accountName)
                .font(Theme.Font.subtitle(.semibold))
                .foregroundStyle(Theme.Color.textPrimary)
            StatusBadge(text: account.accountType.title, tone: .neutral)
            if account.hasConflicts {
                StatusBadge(text: "需核对", tone: .warning)
            } else {
                StatusBadge(text: "已对平", tone: .positive)
            }
            Spacer()
        }
    }

    // MARK: Credit — R1 three-number breakdown + recompute + R2 jumps

    @ViewBuilder
    private var creditBody: some View {
        if let breakdown = account.breakdown {
            CreditBreakdownCard(breakdown: breakdown, currency: account.currency)
        }
        // R1 漂移（fix=internalRecompute）→ recompute 按钮。
        if let drift = account.conflicts.first(where: {
            $0.code == "credit_three_way" && $0.fix == .internalRecompute
        }) {
            recomputeBlock(drift)
        }
        // R2 账单↔还款现金流冲突逐条「去处理」。
        ForEach(account.conflicts.filter { $0.code == "statement_cashflow" }) { conflict in
            ConflictRow(conflict: conflict, onJump: onJump)
        }
    }

    @ViewBuilder
    private func recomputeBlock(_ drift: ReconciliationConflictDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(drift.title, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Font.body(.medium))
                .foregroundStyle(Theme.fixed(0xE08A1F))
            if let detail = drift.detail {
                Text(detail)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            if let recomputeMessage {
                Label(recomputeMessage, systemImage: "checkmark.circle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.income)
            }
            HStack {
                TintedActionChip(
                    title: isRecomputing ? "重算中…" : "重算此账户",
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: .action
                ) {
                    Task { await recompute() }
                }
                .disabled(isRecomputing)
                .opacity(isRecomputing ? 0.5 : 1)
                Text("以账单为准（合计 = Σ未还账单）重算欠款")
                    .font(Theme.Font.badge())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        .padding(12)
        .background(
            Theme.fixed(0xE08A1F).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    @MainActor
    private func recompute() async {
        isRecomputing = true
        recomputeMessage = nil
        defer { isRecomputing = false }
        do {
            let result = try await reconModel.recompute(accountID: account.accountId)
            recomputeMessage = "已重算：欠款 \(FinanceFormatter.money(result.recomputedLiability, currency: account.currency))"
                + "（调整 \(FinanceFormatter.money(result.delta, currency: account.currency))）"
        } catch {
            onError(error.localizedDescription)
        }
    }

    // MARK: Balance / investment — R3 record-real-balance

    @ViewBuilder
    private var balanceBody: some View {
        if let r3 = account.conflicts.first(where: { $0.code == "balance_external" }) {
            BalanceExternalForm(
                account: account,
                conflict: r3,
                reconModel: reconModel,
                onError: onError
            )
        } else {
            Text("账户余额与上次录入的真实余额一致。")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }
}

// MARK: - Credit R1 three-number breakdown card

private struct CreditBreakdownCard: View {
    let breakdown: ReconciliationBreakdownDTO
    let currency: CurrencyCode

    /// 本期待还 = 合计 − 其他期；信息由 detail 已给，这里把「合计 vs 账户存的欠款」拆开。
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("信用欠款拆解")
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            HStack(spacing: 0) {
                numberCell(
                    "未还账单合计",
                    breakdown.openStatementsTotal,
                    color: Theme.Color.textPrimary
                )
                cellDivider
                numberCell(
                    "未出账消费",
                    breakdown.unbilledCharges,
                    color: Theme.Color.textSecondary
                )
                cellDivider
                numberCell(
                    "账户记录欠款",
                    breakdown.storedLiability,
                    color: storedColor
                )
            }
        }
        .padding(12)
        .background(
            Theme.Color.glassFill,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var storedColor: Color {
        breakdown.storedLiability == breakdown.openStatementsTotal
            ? Theme.Color.income
            : Theme.Color.expense
    }

    private func numberCell(_ label: String, _ value: DecimalValue, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Theme.Font.badge())
                .foregroundStyle(Theme.Color.textTertiary)
                .multilineTextAlignment(.center)
            AmountText(
                value: value,
                currency: currency,
                font: Theme.Font.subtitle(.semibold),
                color: color
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Theme.Color.divider)
            .frame(width: 0.5, height: 34)
    }
}

// MARK: - R3 record-real-balance inline form

private struct BalanceExternalForm: View {
    let account: ReconciliationCheckAccountDTO
    let conflict: ReconciliationConflictDTO
    @ObservedObject var reconModel: ReconciliationModel
    let onError: (String) -> Void

    @State private var actualText = ""
    @State private var isSubmitting = false
    @State private var successMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 现状对比（系统 vs 上次真实）。
            if let detail = conflict.detail {
                Text(detail)
                    .font(Theme.Font.caption())
                    .foregroundStyle(conflict.isConflict ? Theme.Color.expense : Theme.Color.textSecondary)
            }
            HStack(spacing: 10) {
                Text("录真实余额")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                TextField("0.00", text: $actualText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Font.cardNumber().monospacedDigit())
                    .frame(maxWidth: 160)
                Text(account.currency.rawValue)
                    .font(Theme.Font.body(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            if let parsed = parsedActual, let stored = conflict.storedBalance {
                let delta = DecimalValue(parsed.value - stored.value)
                HStack(spacing: 6) {
                    Text("将记调整")
                        .font(Theme.Font.badge())
                        .foregroundStyle(Theme.Color.textTertiary)
                    AmountText(
                        value: delta,
                        currency: account.currency,
                        showsPositiveSign: true,
                        font: Theme.Font.caption(.medium),
                        color: delta.value == 0 ? Theme.Color.textTertiary
                            : (delta.value < 0 ? Theme.Color.expense : Theme.Color.income)
                    )
                    Text("对平")
                        .font(Theme.Font.badge())
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            if let successMessage {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.income)
            }
            TintedActionChip(
                title: isSubmitting ? "对平中…" : "以真实为准对平",
                systemImage: "equal.circle",
                tone: .action
            ) {
                Task { await submit() }
            }
            .disabled(isSubmitting || parsedActual == nil)
            .opacity((isSubmitting || parsedActual == nil) ? 0.5 : 1)
        }
    }

    private var parsedActual: DecimalValue? {
        guard let decimal = parseDecimalAmount(actualText) else { return nil }
        return DecimalValue(decimal)
    }

    @MainActor
    private func submit() async {
        guard let actual = parsedActual else { return }
        isSubmitting = true
        successMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await reconModel.submitAdjustment(
                accountId: account.accountId,
                actualAmount: actual,
                reason: "对账：录真实余额",
                note: nil
            )
            successMessage = "已对平，账户余额已更新。"
            actualText = ""
        } catch {
            onError(error.localizedDescription)
        }
    }
}

// MARK: - Generic conflict row (R2 / R4 jump_record)

private struct ConflictRow: View {
    let conflict: ReconciliationConflictDTO
    let onJump: (ReconciliationPointerDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: conflict.isConflict ? "exclamationmark.circle.fill" : "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(conflict.isConflict ? Theme.Color.expense : Theme.Color.textTertiary)
                Text(conflict.title)
                    .font(Theme.Font.body(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer(minLength: 8)
                if let delta = conflict.delta, delta.value != 0 {
                    AmountText(
                        value: delta,
                        currency: .cny,
                        showsPositiveSign: true,
                        showsSymbol: false,
                        font: Theme.Font.caption(.medium),
                        color: Theme.Color.expense
                    )
                }
            }
            if let detail = conflict.detail {
                Text(detail)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            if conflict.fix == .jumpRecord, let pointer = conflict.offending.first {
                TintedActionChip(title: "去处理", systemImage: "arrow.up.right", tone: .action) {
                    onJump(pointer)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#endif
