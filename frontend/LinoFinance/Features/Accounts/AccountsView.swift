import SwiftUI

struct AccountsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "账户", subtitle: "余额账户和信用账户统一管理")
            HStack {
                Button {
                    environment.beginNewAccount()
                } label: {
                    Label("新建账户", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
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
                List(selection: Binding(
                    get: {
                        if case .account(let account) = environment.inspectorSelection {
                            return account.id
                        }
                        return nil
                    },
                    set: { id in
                        guard let id, let account = environment.accountsViewModel.accounts.first(where: { $0.id == id }) else { return }
                        environment.inspectorSelection = .account(account)
                    }
                )) {
                    Section("余额账户") {
                        ForEach(environment.accountsViewModel.accounts.balanceAccounts) { account in
                            AccountRow(account: account)
                                .tag(account.id)
                        }
                    }
                    Section("信用账户") {
                        ForEach(environment.accountsViewModel.accounts.creditAccounts) { account in
                            AccountRow(account: account)
                                .tag(account.id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
        .moduleFrame()
        .task {
            try? await environment.accountsViewModel.refresh()
        }
    }
}

private struct AccountRow: View {
    let account: AccountDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.type == .credit ? "creditcard.fill" : "wallet.pass.fill")
                .foregroundStyle(account.type == .credit ? FinanceColor.credit : FinanceColor.brand)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    StatusTag(title: account.type.title, style: account.type == .credit ? .warning : .confirmed)
                    Text(account.currency.rawValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            MoneyText(
                amount: account.type == .credit ? account.currentLiability : account.currentBalance,
                currency: account.currency,
                convertedCNY: account.currency == .cny ? nil : (account.type == .credit ? account.currentLiability : account.currentBalance),
                prominence: .headline
            )
        }
        .padding(.vertical, 6)
    }
}

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
                    ForEach(AccountType.allCases, id: \.self) { type in
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
                    .foregroundStyle(.orange)
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
            currentBalance: accountType == .balance ? DecimalValue(amount) : DecimalValue(0),
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
