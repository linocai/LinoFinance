import SwiftUI

#if os(iOS)

// ReconciliationIOSView — 对账简版 (iOS · 决策门 D3 = macOS + iOS 简版).
//
// 简版只读冲突清单 + R1 信用三数拆解 + 「重算此账户」按钮（消灭 −1400 困惑）。复杂的
// R2/R4 跳转、R3 录真实余额对平后置到 macOS——iOS 上以引导文案「去 macOS 处理」标出。
// 一眼看出哪个账户有冲突即达成 iOS 简版目标。

// MARK: - iOS view-model

@MainActor
private final class ReconciliationIOSModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var snapshot: ReconciliationCheckResponseDTO?
    @Published private(set) var state: LoadState = .idle

    private let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    var accounts: [ReconciliationCheckAccountDTO] { snapshot?.accounts ?? [] }
    var orphans: [ReconciliationConflictDTO] { snapshot?.orphans ?? [] }
    var hasConflicts: Bool { snapshot?.hasConflicts ?? false }

    var sortedAccounts: [ReconciliationCheckAccountDTO] {
        accounts.sorted { lhs, rhs in
            if lhs.hasConflicts != rhs.hasConflicts { return lhs.hasConflicts }
            return lhs.accountName < rhs.accountName
        }
    }

    var conflictAccountCount: Int { accounts.filter(\.hasConflicts).count }
    var orphanConflictCount: Int { orphans.filter(\.isConflict).count }

    func load() async {
        state = .loading
        do {
            snapshot = try await apiClient.reconciliationCheck()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func recompute(accountID: String) async throws -> CreditRecomputeResponseDTO {
        let result = try await apiClient.recomputeCreditLiability(accountID: accountID)
        await load()
        return result
    }
}

// MARK: - Screen

struct ReconciliationIOSView: View {
    @ObservedObject var model: AppModel
    @StateObject private var reconModel: ReconciliationIOSModel

    @State private var errorMessage: String?

    init(model: AppModel) {
        self.model = model
        _reconModel = StateObject(wrappedValue: ReconciliationIOSModel(apiClient: model.apiClient))
    }

    var body: some View {
        ZStack {
            BloomBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch reconModel.state {
                    case .idle, .loading where reconModel.snapshot == nil:
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
        .navigationTitle("对账")
        .navigationBarTitleDisplayMode(.inline)
        .task { if reconModel.snapshot == nil { await reconModel.load() } }
    }

    @ViewBuilder
    private var content: some View {
        summaryBanner
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.expense)
                .padding(.horizontal, 4)
        }
        ForEach(reconModel.sortedAccounts) { account in
            accountCard(account)
        }
        if !reconModel.orphans.isEmpty {
            orphansCard
        }
        if reconModel.accounts.isEmpty && reconModel.orphans.isEmpty {
            GlassCard {
                Text("没有可对账的账户。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        Text("录真实余额对平、跳转改记录等复杂纠错请在 macOS 上完成。")
            .font(Theme.Font.caption())
            .foregroundStyle(Theme.Color.textTertiary)
            .padding(.horizontal, 4)
    }

    // MARK: - Summary

    private var summaryBanner: some View {
        let clean = !reconModel.hasConflicts
        return GlassCard {
            HStack(spacing: 12) {
                Image(systemName: clean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(clean ? Theme.Color.income : Theme.fixed(0xE08A1F))
                VStack(alignment: .leading, spacing: 2) {
                    Text(clean ? "一切对得上" : "发现需要核对的冲突")
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text(clean ? "所有账户一致。" : summaryText)
                        .font(Theme.Font.badge())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var summaryText: String {
        var parts: [String] = []
        if reconModel.conflictAccountCount > 0 { parts.append("\(reconModel.conflictAccountCount) 个账户有问题") }
        if reconModel.orphanConflictCount > 0 { parts.append("\(reconModel.orphanConflictCount) 条记录孤儿") }
        return parts.isEmpty ? "见下方拆解。" : parts.joined(separator: " · ")
    }

    // MARK: - Account card

    private func accountCard(_ account: ReconciliationCheckAccountDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(account.accountName)
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    StatusBadge(text: account.accountType.title, tone: .neutral)
                    if account.hasConflicts {
                        StatusBadge(text: "需核对", tone: .warning)
                    } else {
                        StatusBadge(text: "已对平", tone: .positive)
                    }
                    Spacer()
                }
                if account.accountType == .credit, let breakdown = account.breakdown {
                    creditBreakdown(breakdown, currency: account.currency)
                    if let drift = account.conflicts.first(where: {
                        $0.code == "credit_three_way" && $0.fix == .internalRecompute
                    }) {
                        recomputeBlock(account: account, drift: drift)
                    }
                    ForEach(account.conflicts.filter { $0.code == "statement_cashflow" }) { conflict in
                        conflictNote(conflict)
                    }
                } else {
                    // R3 余额账户：iOS 简版只展示状态，对平留 macOS。
                    ForEach(account.conflicts.filter { $0.code == "balance_external" }) { conflict in
                        conflictNote(conflict)
                    }
                }
            }
        }
    }

    private func creditBreakdown(_ breakdown: ReconciliationBreakdownDTO, currency: CurrencyCode) -> some View {
        VStack(spacing: 8) {
            numberRow("未还账单合计", breakdown.openStatementsTotal, currency: currency, color: Theme.Color.textPrimary)
            Divider().overlay(Theme.Color.divider)
            numberRow("未出账消费", breakdown.unbilledCharges, currency: currency, color: Theme.Color.textSecondary)
            Divider().overlay(Theme.Color.divider)
            numberRow(
                "账户记录欠款",
                breakdown.storedLiability,
                currency: currency,
                color: breakdown.storedLiability == breakdown.openStatementsTotal
                    ? Theme.Color.income : Theme.Color.expense
            )
        }
        .padding(12)
        .background(Theme.Color.glassFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func numberRow(_ label: String, _ value: DecimalValue, currency: CurrencyCode, color: Color) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            AmountText(value: value, currency: currency, font: Theme.Font.body(.semibold), color: color)
        }
    }

    @ViewBuilder
    private func recomputeBlock(account: ReconciliationCheckAccountDTO, drift: ReconciliationConflictDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let detail = drift.detail {
                Text(detail)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.fixed(0xE08A1F))
            }
            TintedActionChip(
                title: recomputingID == account.accountId ? "重算中…" : "重算此账户",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .action
            ) {
                Task { await recompute(account) }
            }
            .disabled(recomputingID != nil)
            .opacity(recomputingID != nil ? 0.5 : 1)
        }
        .padding(12)
        .background(Theme.fixed(0xE08A1F).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func conflictNote(_ conflict: ReconciliationConflictDTO) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: conflict.isConflict ? "exclamationmark.circle.fill" : "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(conflict.isConflict ? Theme.Color.expense : Theme.Color.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.title)
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                if let detail = conflict.detail {
                    Text(detail)
                        .font(Theme.Font.badge())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            Spacer(minLength: 4)
        }
    }

    // MARK: - Orphans

    private var orphansCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(Theme.Color.expense)
                    Text("跨对象孤儿")
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    StatusBadge(text: "\(reconModel.orphans.count)", tone: .negative)
                    Spacer()
                }
                ForEach(reconModel.orphans) { conflict in
                    conflictNote(conflict)
                    if conflict.id != reconModel.orphans.last?.id {
                        Divider().overlay(Theme.Color.divider)
                    }
                }
                Text("缺关联的记录请在 macOS 上补/改。")
                    .font(Theme.Font.badge())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    // MARK: - Recompute

    @State private var recomputingID: String?

    @MainActor
    private func recompute(_ account: ReconciliationCheckAccountDTO) async {
        recomputingID = account.accountId
        errorMessage = nil
        defer { recomputingID = nil }
        do {
            _ = try await reconModel.recompute(accountID: account.accountId)
            await model.refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
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
}

#endif
