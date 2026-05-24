import SwiftUI

/// 账户页 —— 用 Dashboard 卡片语言（HTML B + C 节 DNA）重设计。
/// 自上而下：SectionHeader + AccountsHeroCard + 余额账户 SectionCard + 信用账户 SectionCard。
/// NewAccountSheet 表单部分保留不动。
struct AccountsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    kicker: "Accounts",
                    title: "账户",
                    description: "余额账户和信用账户统一管理"
                ) {
                    HStack(spacing: 8) {
                        Button {
                            environment.beginReconciliation()
                        } label: {
                            Label("对账", systemImage: FinanceModule.reconciliation.symbolName)
                        }
                        Button {
                            environment.beginNewAccount()
                        } label: {
                            Label("新建账户", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if environment.accountsViewModel.accounts.isEmpty {
                    EmptyState(
                        title: "还没有账户",
                        message: "创建一个余额账户后，就可以开始记账。",
                        systemImage: "wallet.pass",
                        actionTitle: "新建账户",
                        action: environment.beginNewAccount
                    )
                } else {
                    AccountsHeroCard(
                        netWorthCny: environment.dashboardViewModel.summary?.netWorthCny ?? totalNetCny(),
                        cnyBalance: totalBalance(currency: .cny),
                        usdBalance: totalBalance(currency: .usd),
                        creditLiabilityCny: environment.dashboardViewModel.summary?.creditLiabilityTotalCny ?? totalCreditLiabilityCny(),
                        investmentTotalCny: environment.dashboardViewModel.summary?.investmentTotalCny ?? totalInvestmentCny()
                    )

                    sectionCard(title: "余额账户", count: environment.accountsViewModel.accounts.balanceAccounts.count) {
                        ForEach(Array(environment.accountsViewModel.accounts.balanceAccounts.enumerated()), id: \.element.id) { index, account in
                            if index > 0 {
                                Divider().background(FinanceTokens.Stroke.soft)
                            }
                            balanceAccountRow(account)
                                .onTapGesture { environment.inspectorSelection = .account(account) }
                        }
                    }

                    if !environment.accountsViewModel.accounts.investmentAccounts.isEmpty {
                        sectionCard(title: "投资账户", count: environment.accountsViewModel.accounts.investmentAccounts.count) {
                            ForEach(Array(environment.accountsViewModel.accounts.investmentAccounts.enumerated()), id: \.element.id) { index, account in
                                if index > 0 {
                                    Divider().background(FinanceTokens.Stroke.soft)
                                }
                                investmentAccountRow(account)
                                    .onTapGesture { environment.inspectorSelection = .account(account) }
                            }
                        }
                    }

                    sectionCard(title: "信用账户", count: environment.accountsViewModel.accounts.creditAccounts.count) {
                        ForEach(Array(environment.accountsViewModel.accounts.creditAccounts.enumerated()), id: \.element.id) { index, account in
                            if index > 0 {
                                Divider().background(FinanceTokens.Stroke.soft)
                            }
                            creditAccountRow(account)
                                .onTapGesture { environment.inspectorSelection = .account(account) }
                        }
                    }
                }
            }
            .padding(.horizontal, accountsPagePadding)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .moduleFrame()
        .task {
            try? await environment.accountsViewModel.refresh()
            try? await environment.settingsViewModel.refresh()
        }
    }

    private var accountsPagePadding: CGFloat {
#if os(iOS)
        16
#else
        28
#endif
    }

    // MARK: - Section card

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(title)
                    .font(FinanceTypography.headline)
                    .foregroundStyle(FinanceTokens.Text.primary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(FinanceTokens.Text.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(FinanceTokens.Surface.glass))
                    .overlay { Capsule().stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5) }
            }
            VStack(spacing: 0) {
                content()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(strength: .strong, elevation: .soft)
    }

    // MARK: - Rows

    private func balanceAccountRow(_ account: AccountDTO) -> some View {
        let convertedCNY = convertedCNY(for: account)
        let primary = FinanceFormatter.money(account.currentBalance, currency: account.currency)
        let secondary = convertedCNY.map { "约 \(FinanceFormatter.money($0, currency: .cny, approximate: true))" }
        return AccountListRow(
            systemImage: balanceIcon(for: account.currency),
            iconTint: balanceTint(for: account.currency),
            title: "\(account.name) · \(account.currency.rawValue)",
            subtitle: "余额账户 · " + (account.notes ?? account.status.financeStatusTitle),
            amountPrimary: primary,
            amountSecondary: secondary,
            amountTint: FinanceTokens.State.income
        )
    }

    private func investmentAccountRow(_ account: AccountDTO) -> some View {
        let convertedCNY = convertedCNY(for: account)
        let primary = FinanceFormatter.money(account.currentBalance, currency: account.currency)
        let secondary = convertedCNY.map { "约 \(FinanceFormatter.money($0, currency: .cny, approximate: true))" }
        let subtitle = "投资账户 · " + (account.notes ?? account.status.financeStatusTitle)
        return AccountListRow(
            systemImage: "chart.line.uptrend.xyaxis.circle",
            iconTint: FinanceTokens.Brand.primary,
            title: "\(account.name) · \(account.currency.rawValue)",
            subtitle: subtitle,
            amountPrimary: primary,
            amountSecondary: secondary,
            amountTint: FinanceTokens.Brand.primary,
            trailing: {
#if os(iOS)
                Button {
                    environment.presentDailyPnLSheet(for: account.id)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(FinanceTokens.Brand.primary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
#else
                EmptyView()
#endif
            }
        )
    }

    private func creditAccountRow(_ account: AccountDTO) -> some View {
        let primary = "-" + FinanceFormatter.money(account.currentLiability, currency: account.currency)
        let limitText = account.creditLimit.map { "额度 \(FinanceFormatter.money($0, currency: account.currency))" }
        let statement = account.statementDay.map { "账单日 \($0)" } ?? ""
        let due = account.dueDay.map { "还款日 \($0)" } ?? ""
        let parts = [statement, due, limitText].compactMap { $0?.isEmpty == false ? $0 : nil }
        let subtitle = parts.isEmpty ? "信用账户 · \(account.currency.rawValue)" : parts.joined(separator: " · ")
        return AccountListRow(
            systemImage: "creditcard",
            iconTint: FinanceTokens.State.credit,
            title: "\(account.name) · \(account.currency.rawValue)",
            subtitle: subtitle,
            amountPrimary: primary,
            amountSecondary: account.minimumPayment.map { "最低 \(FinanceFormatter.money($0, currency: account.currency))" },
            amountTint: FinanceTokens.State.credit
        )
    }

    // MARK: - Aggregation helpers

    private func totalBalance(currency: CurrencyCode) -> DecimalValue {
        let sum = environment.accountsViewModel.accounts
            .balanceAccounts
            .filter { $0.currency == currency }
            .map { $0.currentBalance.value }
            .reduce(Decimal(0), +)
        return DecimalValue(sum)
    }

    private func totalCreditLiabilityCny() -> DecimalValue {
        let sum = environment.accountsViewModel.accounts
            .creditAccounts
            .map { convertedToCny($0.currentLiability, from: $0.currency) }
            .reduce(Decimal(0), +)
        return DecimalValue(sum)
    }

    private func totalInvestmentCny() -> DecimalValue {
        let sum = environment.accountsViewModel.accounts
            .investmentAccounts
            .map { convertedToCny($0.currentBalance, from: $0.currency) }
            .reduce(Decimal(0), +)
        return DecimalValue(sum)
    }

    private func totalNetCny() -> DecimalValue {
        let balance = environment.accountsViewModel.accounts
            .balanceAccounts
            .map { convertedToCny($0.currentBalance, from: $0.currency) }
            .reduce(Decimal(0), +)
        return DecimalValue(balance + totalInvestmentCny().value - totalCreditLiabilityCny().value)
    }

    private func convertedToCny(_ amount: DecimalValue, from currency: CurrencyCode) -> Decimal {
        if currency == .cny { return amount.value }
        if let rate = environment.settingsViewModel.rates.first(where: {
            $0.fromCurrency == currency && $0.toCurrency == .cny
        }) {
            return amount.value * rate.rate.value
        }
        return amount.value
    }

    private func convertedCNY(for account: AccountDTO) -> DecimalValue? {
        guard account.currency != .cny else { return nil }
        guard let rate = environment.settingsViewModel.rates.first(where: {
            $0.fromCurrency == account.currency && $0.toCurrency == .cny
        }) else {
            return nil
        }
        let amount = account.type == .credit ? account.currentLiability : account.currentBalance
        return DecimalValue(amount.value * rate.rate.value)
    }

    private func balanceIcon(for currency: CurrencyCode) -> String {
        switch currency {
        case .usd: return "dollarsign.circle"
        case .cny: return "yensign.circle"
        }
    }

    private func balanceTint(for currency: CurrencyCode) -> Color {
        switch currency {
        case .usd: return FinanceTokens.Currency.usd
        case .cny: return FinanceTokens.Currency.cny
        }
    }
}

// MARK: - Hero card

private struct AccountsHeroCard: View {
    let netWorthCny: DecimalValue
    let cnyBalance: DecimalValue
    let usdBalance: DecimalValue
    let creditLiabilityCny: DecimalValue
    let investmentTotalCny: DecimalValue

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("总资产")
                        .font(FinanceTypography.sectionKicker)
                        .kickerTracking()
                        .foregroundStyle(FinanceTokens.Text.secondary)
                    PrivacyAmount(
                        value: FinanceFormatter.money(netWorthCny),
                        font: FinanceTypography.statValue,
                        tint: FinanceTokens.Text.primary
                    )
                }
                Spacer(minLength: 12)
                AccountIconTile(systemImage: "wallet.bifold", tint: FinanceTokens.Brand.primary, size: 36)
            }

            LazyVGrid(columns: heroColumns, spacing: 10) {
                MetricChip(
                    title: "CNY 合计",
                    value: FinanceFormatter.money(cnyBalance, currency: .cny),
                    tint: FinanceTokens.Currency.cny
                )
                MetricChip(
                    title: "USD 合计",
                    value: FinanceFormatter.money(usdBalance, currency: .usd),
                    tint: FinanceTokens.Currency.usd
                )
                MetricChip(
                    title: "投资合计",
                    value: FinanceFormatter.money(investmentTotalCny, currency: .cny),
                    tint: FinanceTokens.Brand.primary
                )
                MetricChip(
                    title: "信用负债",
                    value: FinanceFormatter.money(creditLiabilityCny, currency: .cny),
                    tint: FinanceTokens.State.credit
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(
            strength: .strong,
            accent: AnyShapeStyle(FinanceTokens.Halo.brandCorner),
            elevation: .elevated
        )
    }

    private var heroColumns: [GridItem] {
#if os(iOS)
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
#else
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
#endif
    }
}

// MARK: - NewAccountSheet (unchanged)

struct NewAccountSheet: View {
    @Bindable var environment: AppEnvironment
    @State private var name = ""
    @State private var accountType: AccountType = .balance
    @State private var currency: CurrencyCode = .cny
    @State private var openingAmount = ""
    @State private var creditLimit = ""
    @State private var statementDay = ""
    @State private var dueDay = ""
    @State private var minimumPayment = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建账户")
                .font(.title2.weight(.semibold))
            Form {
                TextField("账户名称", text: $name)
                Picker("类型", selection: $accountType) {
                    ForEach([AccountType.balance, .investment, .credit], id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }
                Picker("币种", selection: $currency) {
                    ForEach(CurrencyCode.allCases, id: \.self) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                TextField(accountType == .credit ? "当前负债" : "当前余额", text: $openingAmount)
                if accountType == .credit {
                    TextField("信用额度", text: $creditLimit)
                    TextField("账单日（1-31）", text: $statementDay)
                    TextField("还款日（1-31）", text: $dueDay)
                    TextField("最低还款", text: $minimumPayment)
                }
                TextField("备注", text: $notes)
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(FinanceTokens.State.warning)
                    .font(.caption)
            }
            HStack {
                Spacer()
                Button("取消") {
                    environment.isShowingNewAccountSheet = false
                }
                Button("创建") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
    }

    private func submit() async {
        let amount = Decimal(string: openingAmount.isEmpty ? "0" : openingAmount) ?? 0
        let request = AccountCreateRequest(
            name: name,
            type: accountType,
            currency: currency,
            currentBalance: accountType == .credit ? DecimalValue(0) : DecimalValue(amount),
            currentLiability: accountType == .credit ? DecimalValue(amount) : DecimalValue(0),
            creditLimit: Decimal(string: creditLimit).map(DecimalValue.init),
            statementDay: Int(statementDay),
            dueDay: Int(dueDay),
            minimumPayment: Decimal(string: minimumPayment).map(DecimalValue.init),
            notes: notes.isEmpty ? nil : notes
        )
        do {
            try await environment.accountsViewModel.createAccount(request)
            try await environment.dashboardViewModel.refresh()
            environment.isShowingNewAccountSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
