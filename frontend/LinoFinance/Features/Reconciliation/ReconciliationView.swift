import SwiftUI

struct ReconciliationView: View {
    @Bindable var environment: AppEnvironment
    @State private var adjustingRow: ReconciliationAccountDTO?

    private var viewModel: ReconciliationViewModel { environment.reconciliationViewModel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "账户对账", subtitle: "对比系统预期余额和当前账户余额，并用调整入账闭环")
                toolbar
                if let message = viewModel.successMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FinanceTokens.State.income)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FinanceTokens.State.income.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: FinanceTokens.Radius.sm))
                }
                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }
                summary
                if viewModel.rows.isEmpty {
                    EmptyState(title: "没有需要显示的账户", message: "切换到全部账户，或刷新后再检查。", systemImage: "checklist.checked")
                } else {
#if os(macOS)
                    ReconciliationTable(rows: viewModel.rows, adjustingRow: $adjustingRow)
#else
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.rows) { row in
                            ReconciliationCard(row: row) {
                                adjustingRow = row
                            }
                        }
                    }
#endif
                }
            }
            .padding(FinanceTokens.Spacing.page)
        }
        .moduleFrame()
        .task {
            try? await viewModel.refresh()
        }
        .sheet(item: $adjustingRow) { row in
            AdjustmentSheet(environment: environment, row: row)
        }
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Picker("筛选", selection: filterBinding) {
                    ForEach(ReconciliationFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
                Button {
                    Task {
                        do { try await viewModel.refresh() }
                        catch { environment.lastErrorMessage = error.localizedDescription }
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Picker("筛选", selection: filterBinding) {
                    ForEach(ReconciliationFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                Button {
                    Task {
                        do { try await viewModel.refresh() }
                        catch { environment.lastErrorMessage = error.localizedDescription }
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var summary: some View {
        let rows = viewModel.response?.items ?? []
        let driftCount = rows.filter(\.needsAdjustment).count
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                KPIStat(title: "账户数", value: "\(rows.count)", systemImage: "wallet.pass.fill")
                KPIStat(title: "存在差异", value: "\(driftCount)", systemImage: "exclamationmark.triangle.fill", tint: FinanceTokens.State.warning)
                KPIStat(title: "阈值", value: viewModel.response?.threshold.value.formatted(.number.precision(.fractionLength(2))) ?? "0.01", systemImage: "slider.horizontal.3")
            }
            VStack(spacing: 12) {
                KPIStat(title: "账户数", value: "\(rows.count)", systemImage: "wallet.pass.fill")
                KPIStat(title: "存在差异", value: "\(driftCount)", systemImage: "exclamationmark.triangle.fill", tint: FinanceTokens.State.warning)
                KPIStat(title: "阈值", value: viewModel.response?.threshold.value.formatted(.number.precision(.fractionLength(2))) ?? "0.01", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var filterBinding: Binding<ReconciliationFilter> {
        Binding(
            get: { viewModel.filter },
            set: { viewModel.filter = $0 }
        )
    }
}

#if os(macOS)
private struct ReconciliationTable: View {
    let rows: [ReconciliationAccountDTO]
    @Binding var adjustingRow: ReconciliationAccountDTO?

    var body: some View {
        Table(rows) {
            TableColumn("账户") { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.accountName)
                        .font(.headline)
                    Text(row.accountType.title)
                        .font(.caption)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                }
            }
            TableColumn("预期") { row in
                Text(FinanceFormatter.money(row.expectedAmount, currency: row.currency))
                    .font(.body.monospacedDigit())
            }
            TableColumn("当前") { row in
                Text(FinanceFormatter.money(row.currentAmount, currency: row.currency))
                    .font(.body.monospacedDigit())
            }
            TableColumn("差异") { row in
                Text(FinanceFormatter.signedMoney(row.deltaAmount, currency: row.currency))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(row.needsAdjustment ? FinanceTokens.State.warning : FinanceTokens.State.income)
            }
            TableColumn("币种") { row in
                Text(row.currency.rawValue)
            }
            TableColumn("状态") { row in
                StatusTag(title: row.needsAdjustment ? "需调整" : "一致", style: row.needsAdjustment ? .warning : .confirmed)
            }
            TableColumn("操作") { row in
                Button("调整") {
                    adjustingRow = row
                }
                .disabled(!row.needsAdjustment)
            }
        }
        .frame(minHeight: 420)
        .glassBackground(radius: FinanceTokens.Radius.lg)
    }
}
#endif

private struct ReconciliationCard: View {
    let row: ReconciliationAccountDTO
    let action: () -> Void

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.accountName)
                            .font(.headline)
                        HStack {
                            StatusTag(title: row.accountType.title, style: row.accountType == .credit ? .warning : .confirmed)
                            StatusTag(title: row.needsAdjustment ? "需调整" : "一致", style: row.needsAdjustment ? .warning : .confirmed)
                        }
                    }
                    Spacer()
                    Button("调整", action: action)
                        .buttonStyle(.borderedProminent)
                        .disabled(!row.needsAdjustment)
                }
                DetailLine(title: "预期余额", value: FinanceFormatter.money(row.expectedAmount, currency: row.currency))
                DetailLine(title: "当前余额", value: FinanceFormatter.money(row.currentAmount, currency: row.currency))
                DetailLine(title: "差异", value: FinanceFormatter.signedMoney(row.deltaAmount, currency: row.currency))
            }
        }
    }
}

private struct AdjustmentSheet: View {
    @Bindable var environment: AppEnvironment
    let row: ReconciliationAccountDTO
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var reason = "系统差"
    @State private var note = ""
    @State private var errorMessage: String?

    private let reasons = ["手续费", "利息", "汇率漂移", "系统差", "其他"]

    var body: some View {
        NavigationStack {
            Form {
                Section("账户") {
                    LabeledContent("账户", value: row.accountName)
                    LabeledContent("预期余额", value: FinanceFormatter.money(row.expectedAmount, currency: row.currency))
                    LabeledContent("当前余额", value: FinanceFormatter.money(row.currentAmount, currency: row.currency))
                    LabeledContent("差异", value: FinanceFormatter.signedMoney(row.deltaAmount, currency: row.currency))
                }
                Section("调整") {
                    TextField("实际金额", text: $amountText)
                    Picker("原因", selection: $reason) {
                        ForEach(reasons, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let errorMessage {
                    Section {
                        ErrorBanner(message: errorMessage)
                    }
                }
            }
            .navigationTitle("提交对账调整")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") {
                        Task { await submit() }
                    }
                    .disabled(parsedAmount == nil)
                }
            }
            .onAppear {
                amountText = NSDecimalNumber(decimal: row.currentAmount.value).stringValue
            }
        }
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func submit() async {
        guard let amount = parsedAmount else { return }
        do {
            try await environment.reconciliationViewModel.submitAdjustment(
                accountID: row.accountId,
                actualAmount: DecimalValue(amount),
                reason: reason,
                note: note
            )
            try await environment.accountsViewModel.refresh()
            try await environment.dashboardViewModel.refresh()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
