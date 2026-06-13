import SwiftUI

#if os(macOS)

// DailyPnLSheet — D2 投资账户「记当日盈亏」(glass modal, P3).
//
// The user enters the account's CURRENT balance for the day; the backend
// (`POST /accounts/{id}/daily-pnl`) computes the delta (today's P&L) and moves
// the balance. Mirrors the v1 `DailyPnLSheet` semantics: input = new balance,
// preview shows the implied delta.

struct DailyPnLSheet: View {
    @ObservedObject var model: AccountsModel
    let account: AccountDTO
    @Environment(\.dismiss) private var dismiss

    var onRecorded: () -> Void

    @State private var newBalanceText = ""
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var parsedNewBalance: Decimal? {
        let trimmed = newBalanceText.trimmingCharacters(in: .whitespaces)
        return Decimal(string: trimmed)
    }

    private var delta: Decimal? {
        guard let new = parsedNewBalance else { return nil }
        return new - account.currentBalance.value
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    currentBalanceCard
                    field("当前余额") {
                        TextField(plainBalance, text: $newBalanceText)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.Font.cardNumber().monospacedDigit())
                    }
                    deltaPreview
                    field("备注") {
                        TextField("例如：盘后调整", text: $note)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(22)
            }
            Divider().overlay(Theme.Color.divider)
            footer
        }
        .frame(width: 460, height: 460)
        .background { BloomBackground(animated: false).opacity(0.9) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("记当日盈亏")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(account.name)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var currentBalanceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("系统记录余额")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                AmountText(
                    value: account.currentBalance,
                    currency: account.currency,
                    font: Theme.Font.cardNumber(),
                    color: Theme.Color.textPrimary
                )
            }
        }
    }

    @ViewBuilder
    private var deltaPreview: some View {
        if let delta {
            HStack(spacing: 8) {
                Text("今日盈亏")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer(minLength: 8)
                AmountText(
                    value: DecimalValue(delta),
                    currency: account.currency,
                    showsPositiveSign: true,
                    font: Theme.Font.subtitle(.semibold),
                    color: delta < 0 ? Theme.Color.expense : Theme.Color.income
                )
            }
            .padding(12)
            .glassPanel(cornerRadius: Theme.Radius.button)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                PrimaryDarkButton("记录", fullWidth: true, isLoading: isSubmitting) {
                    Task { await submit() }
                }
                .disabled(isSubmitting || parsedNewBalance == nil)
                .opacity((isSubmitting || parsedNewBalance == nil) ? 0.5 : 1)
                .keyboardShortcut(.defaultAction)

                SubtleTextButton("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var plainBalance: String {
        NSDecimalNumber(decimal: account.currentBalance.value).stringValue
    }

    @MainActor
    private func submit() async {
        guard let new = parsedNewBalance else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await model.recordDailyPnL(
                accountID: account.id,
                request: DailyPnLCreateRequest(
                    newBalance: DecimalValue(new),
                    asOfDate: nil,
                    note: trimmedNote.isEmpty ? nil : trimmedNote
                )
            )
            errorMessage = nil
            onRecorded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            content()
        }
    }
}

#endif
