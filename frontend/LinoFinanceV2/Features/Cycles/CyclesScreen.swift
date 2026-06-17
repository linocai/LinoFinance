import SwiftUI

#if os(macOS)

// CyclesScreen — D7 周期 (macOS · glass · 订阅 + 分期 + 信用账单周期).
//
// A segmented switcher chooses one of three sections; each renders glass cards
// bound to its real DTO with inline row actions (plan §D7):
//   • 订阅 SubscriptionRuleDTO   → 暂停/恢复 · 生成下一期 · 取消
//   • 分期 InstallmentPlanDTO     → 进度 (已还 N/共 M) · 提前结清 · 标记已结清 · 取消
//   • 信用账单周期 CreditStatementCycleDTO → 只读列表 + 新建（无 update/close）
struct CyclesScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var cyclesModel: CyclesModel

    enum Section: String, CaseIterable, Identifiable {
        case subscriptions, installments, statements
        var id: String { rawValue }
        var title: String {
            switch self {
            case .subscriptions: "订阅"
            case .installments: "分期"
            case .statements: "信用账单周期"
            }
        }
    }

    @State private var section: Section = .subscriptions
    @State private var showingNewSubscription = false
    @State private var showingNewInstallment = false
    @State private var showingNewStatementCycle = false
    @State private var editingCycle: CreditStatementCycleDTO?
    @State private var actionError: String?

    init(model: AppModel) {
        self.model = model
        _cyclesModel = StateObject(wrappedValue: CyclesModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            SegmentedPill(options: Section.allCases, selection: $section) { $0.title }
                .frame(maxWidth: 420)

            switch cyclesModel.state {
            case .idle, .loading:
                loadingState
            case .failed(let message):
                failedState(message)
            case .loaded:
                switch section {
                case .subscriptions: subscriptionsSection
                case .installments: installmentsSection
                case .statements: statementsSection
                }
            }
            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
            }
        }
        .task {
            if cyclesModel.subscriptions.isEmpty && cyclesModel.installments.isEmpty {
                await cyclesModel.load()
            }
            if model.accounts.isEmpty { await model.loadAccounts() }
            if model.categories.isEmpty { await model.loadCategories() }
        }
        .sheet(isPresented: $showingNewSubscription) {
            NewSubscriptionSheet(model: model, cyclesModel: cyclesModel)
        }
        .sheet(isPresented: $showingNewInstallment) {
            NewInstallmentSheet(model: model, cyclesModel: cyclesModel)
        }
        .sheet(isPresented: $showingNewStatementCycle) {
            NewStatementCycleSheet(model: model, cyclesModel: cyclesModel)
        }
        .sheet(item: $editingCycle) { cycle in
            EditStatementCycleSheet(cyclesModel: cyclesModel, cycle: cycle) {
                Task { await model.refreshAll() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("周期")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("订阅、分期与信用卡账单周期")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            SubtleToolbarButton(title: addButtonTitle) {
                switch section {
                case .subscriptions: showingNewSubscription = true
                case .installments: showingNewInstallment = true
                case .statements: showingNewStatementCycle = true
                }
            }
        }
    }

    private var addButtonTitle: String {
        switch section {
        case .subscriptions: "新建订阅"
        case .installments: "新建分期"
        case .statements: "新建账单周期"
        }
    }

    // MARK: - Subscriptions

    @ViewBuilder
    private var subscriptionsSection: some View {
        if cyclesModel.subscriptions.isEmpty {
            emptyCard("还没有订阅", "为流媒体、会员等周期性扣费创建订阅规则，自动生成现金流。")
        } else {
            VStack(spacing: 12) {
                ForEach(cyclesModel.subscriptions) { rule in
                    subscriptionCard(rule)
                }
            }
        }
    }

    private func subscriptionCard(_ rule: SubscriptionRuleDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(rule.title)
                        .font(Theme.Font.subtitle(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    StatusBadge(text: rule.status.financeStatusTitle, tone: subscriptionTone(rule.status))
                    Spacer()
                    AmountText(value: rule.amount, currency: rule.currency, font: Theme.Font.cardNumber(), color: Theme.Color.textPrimary)
                }
                HStack(spacing: 14) {
                    metaChip("周期", rule.billingInterval.financeStatusTitle)
                    if let next = rule.nextChargeDate {
                        metaChip("下次扣费", FinanceFormatter.shortDate(next))
                    }
                    metaChip("已生成", "\(rule.generatedCashFlowCount) 期")
                }
                Divider().overlay(Theme.Color.divider)
                HStack(spacing: 8) {
                    if rule.status == "active" {
                        TintedActionChip(title: "暂停", tone: .neutral) { run { try await cyclesModel.pauseSubscription(rule.id) } }
                    } else if rule.status == "paused" {
                        TintedActionChip(title: "恢复", tone: .positive) { run { try await cyclesModel.resumeSubscription(rule.id) } }
                    }
                    if rule.status == "active" {
                        TintedActionChip(title: "生成下一期", tone: .action) { run { try await cyclesModel.generateNextSubscription(rule.id) } }
                    }
                    if rule.status != "cancelled" && rule.status != "canceled" {
                        TintedActionChip(title: "取消", tone: .destructive) { run { try await cyclesModel.cancelSubscription(rule.id) } }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func subscriptionTone(_ status: String) -> StatusBadge.Tone {
        switch status {
        case "active": return .positive
        case "paused": return .warning
        case "cancelled", "canceled": return .negative
        default: return .neutral
        }
    }

    // MARK: - Installments

    @ViewBuilder
    private var installmentsSection: some View {
        if cyclesModel.installments.isEmpty {
            emptyCard("还没有分期", "把一笔信用卡大额消费拆成多期，跟踪每期金额与剩余进度。")
        } else {
            VStack(spacing: 12) {
                ForEach(cyclesModel.installments) { plan in
                    installmentCard(plan)
                }
            }
        }
    }

    private func installmentCard(_ plan: InstallmentPlanDTO) -> some View {
        // 已还 N = settled period count (v2.3.0 P3 fix). 之前误用 generatedCashFlowCount
        // (= 一次性生成的总期数 ≈ M)，进度恒满。
        let paid = cyclesModel.settledInstallmentCount(plan.id)
        let total = plan.numberOfPayments
        let progress = total > 0 ? Double(paid) / Double(total) : 0
        let remainingCount = max(total - paid, 0)
        let remainingAmount = DecimalValue(plan.paymentAmount.value * Decimal(remainingCount))
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("分期")
                        .font(Theme.Font.subtitle(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    StatusBadge(text: plan.status.financeStatusTitle, tone: installmentTone(plan.status))
                    Spacer()
                    AmountText(value: plan.totalAmount, currency: plan.currency, font: Theme.Font.cardNumber(), color: Theme.Color.textPrimary)
                }
                // Progress (已还 N/共 M)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("已还 \(paid)/共 \(total) 期")
                            .font(Theme.Font.caption(.medium).monospacedDigit())
                            .foregroundStyle(Theme.Color.textSecondary)
                        Spacer()
                        Text("每期 \(FinanceFormatter.money(plan.paymentAmount, currency: plan.currency))")
                            .font(Theme.Font.caption().monospacedDigit())
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    ProgressView(value: progress)
                        .tint(Theme.Color.brandEnd)
                }
                HStack(spacing: 14) {
                    metaChip("剩余", "\(remainingCount) 期 · \(FinanceFormatter.money(remainingAmount, currency: plan.currency))")
                    metaChip("起始", FinanceFormatter.shortDate(plan.startDate))
                }
                Divider().overlay(Theme.Color.divider)
                HStack(spacing: 8) {
                    if plan.status == "active" {
                        TintedActionChip(title: "提前结清", tone: .action) { run { try await cyclesModel.markInstallmentEarlyPaidOff(plan.id) } }
                        TintedActionChip(title: "标记已结清", tone: .positive) { run { try await cyclesModel.markInstallmentPaidOff(plan.id) } }
                        TintedActionChip(title: "取消", tone: .destructive) { run { try await cyclesModel.cancelInstallment(plan.id) } }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func installmentTone(_ status: String) -> StatusBadge.Tone {
        switch status {
        case "paid": return .positive
        case "active": return .pending
        case "cancelled", "canceled": return .negative
        default: return .neutral
        }
    }

    // MARK: - Statement cycles (read-only + create)

    @ViewBuilder
    private var statementsSection: some View {
        if cyclesModel.statementCycles.isEmpty {
            emptyCard("还没有账单周期", "为信用卡账户登记账单周期，跟踪出账金额、最低还款与剩余。")
        } else {
            VStack(spacing: 12) {
                ForEach(cyclesModel.statementCycles) { cycle in
                    statementCycleCard(cycle)
                }
            }
        }
    }

    private func statementCycleCard(_ cycle: CreditStatementCycleDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("账单 \(FinanceFormatter.shortDate(cycle.statementDate))")
                        .font(Theme.Font.subtitle(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    StatusBadge(text: cycle.status.financeStatusTitle, tone: statementTone(cycle.status))
                    Spacer()
                    AmountText(value: cycle.statementAmount, currency: cycle.currency, font: Theme.Font.cardNumber(), color: Theme.Color.textPrimary)
                }
                HStack(spacing: 14) {
                    metaChip("周期", "\(FinanceFormatter.shortDate(cycle.cycleStartDate)) – \(FinanceFormatter.shortDate(cycle.cycleEndDate))")
                    metaChip("还款日", FinanceFormatter.shortDate(cycle.dueDate))
                }
                HStack(spacing: 14) {
                    metaChip("最低还款", FinanceFormatter.money(cycle.minimumPayment, currency: cycle.currency))
                    metaChip("已还", FinanceFormatter.money(cycle.paidAmount, currency: cycle.currency))
                    metaChip("剩余", FinanceFormatter.money(cycle.remainingAmount, currency: cycle.currency))
                }
                // 纠错动作 (v2.3.0 P2 · D2). voided 周期锁定 (改源已无意义).
                if cycle.status != "voided" {
                    Divider().overlay(Theme.Color.divider)
                    HStack(spacing: 8) {
                        TintedActionChip(title: "编辑", tone: .neutral) { editingCycle = cycle }
                        if cycle.remainingAmount.value > 0 {
                            TintedActionChip(title: "标记已还", tone: .positive) {
                                run { try await cyclesModel.markStatementCyclePaid(cycle.id); await model.refreshAll() }
                            }
                        }
                        TintedActionChip(title: "作废", tone: .destructive) {
                            run { try await cyclesModel.voidStatementCycle(cycle.id); await model.refreshAll() }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func statementTone(_ status: String) -> StatusBadge.Tone {
        switch status {
        case "paid", "closed": return .positive
        case "open": return .pending
        case "statement_generated", "partially_paid": return .warning
        case "overdue": return .negative
        default: return .neutral
        }
    }

    // MARK: - Shared bits

    private func metaChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.Font.badge(.semibold))
                .foregroundStyle(Theme.Color.textTertiary)
            Text(value)
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    // Chips fire actions directly — no native二次确认 (data is recoverable, R3).
    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                actionError = nil
                try await work()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func emptyCard(_ title: String, _ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "arrow.triangle.2.circlepath")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    private var loadingState: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在加载周期数据…")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("周期数据加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                    Task { await cyclesModel.load() }
                }
            }
        }
    }
}

#endif
