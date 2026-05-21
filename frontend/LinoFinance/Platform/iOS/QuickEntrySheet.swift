#if os(iOS)
import SwiftUI
import UIKit

struct QuickEntrySheet: View {
    @Bindable var environment: AppEnvironment
    let initialIntent: QuickEntryIntent
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = "ai"
    @State private var sourceText = ""
    @State private var pastedText = ""
    @State private var title = ""
    @State private var amount = ""
    @State private var intent: QuickEntryIntent
    @State private var accountID: String?
    @State private var categoryID: String?
    @State private var date = Date()
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    init(environment: AppEnvironment, initialIntent: QuickEntryIntent = .expense) {
        self.environment = environment
        self.initialIntent = initialIntent
        _intent = State(initialValue: initialIntent)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("快速记账", selection: $selectedTab) {
                    Text("AI").tag("ai")
                    Text("表单").tag("form")
                    Text("粘贴").tag("paste")
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top], 16)

                Form {
                    switch selectedTab {
                    case "form":
                        formSection
                    case "paste":
                        pasteSection
                    default:
                        aiSection
                    }

                    if let errorMessage {
                        Section {
                            ErrorBanner(message: errorMessage)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(FinanceTokens.Surface.base)
            }
            .navigationTitle("两秒记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    submitButton
                }
            }
            .task {
                try? await environment.accountsViewModel.refresh()
                try? await environment.entriesViewModel.refresh()
            }
        }
    }

    private var aiSection: some View {
        Section {
            TextEditor(text: $sourceText)
                .frame(minHeight: 160)
                .overlay(alignment: .topLeading) {
                    if sourceText.isEmpty {
                        Text("例如：午餐 58 元，招商信用卡支付，餐饮分类")
                            .foregroundStyle(FinanceTokens.Text.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                }
        } header: {
            Text("自然语言")
        }
    }

    private var pasteSection: some View {
        Section {
            Button {
                pastedText = UIPasteboard.general.string ?? ""
            } label: {
                Label("读取剪贴板", systemImage: "doc.on.clipboard")
            }
            TextEditor(text: $pastedText)
                .frame(minHeight: 150)
        } header: {
            Text("粘贴文本")
        }
    }

    private var formSection: some View {
        Group {
            Section {
                TextField("标题", text: $title)
                TextField("金额", text: $amount)
                    .keyboardType(.decimalPad)
                Picker("方向", selection: $intent) {
                    ForEach(QuickEntryIntent.allCases) { intent in
                        Text(intent.title).tag(intent)
                    }
                }
                .pickerStyle(.segmented)
                DatePicker("日期", selection: $date, displayedComponents: .date)
            }

            Section {
                Picker("账户", selection: $accountID) {
                    Text("未选择").tag(Optional<String>.none)
                    ForEach(selectableAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                Picker("分类", selection: $categoryID) {
                    Text("未选择").tag(Optional<String>.none)
                    ForEach(selectableCategories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
            } footer: {
                Text("字段完整时直接确认；缺账户或分类时保存为草稿。")
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            if isSubmitting {
                ProgressView()
            } else {
                Text("完成")
            }
        }
        .disabled(isSubmitting)
    }

    private var selectableAccounts: [AccountDTO] {
        switch intent {
        case .creditCharge:
            environment.accountsViewModel.accounts.creditAccounts
        case .expense, .income:
            environment.accountsViewModel.accounts.balanceAccounts
        }
    }

    private var selectableCategories: [CategoryDTO] {
        environment.entriesViewModel.categories
            .filter { $0.isActive && $0.type.rawValue == intent.categoryDirection.rawValue }
            .sorted { $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            switch selectedTab {
            case "form":
                try await submitForm()
            case "paste":
                try await submitAI(text: pastedText)
            default:
                try await submitAI(text: sourceText)
            }
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submitAI(text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QuickEntryError.emptyText
        }
        let plan = try await environment.aiViewModel.createPlan(sourceText: trimmed)
        if environment.dynamicIslandAIEnabled {
            LiveActivityManager.shared.startAIPlan(plan: plan)
        }
        environment.selectedModule = .ai
        environment.inspectorSelection = .aiPlan(plan)
    }

    @MainActor
    private func submitForm() async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw QuickEntryError.missingTitle }
        guard let decimal = Decimal(string: amount), decimal > 0 else {
            throw QuickEntryError.invalidAmount
        }

        let hasRequiredLinks = accountID != nil && categoryID != nil
        let status: EntryStatus = hasRequiredLinks ? .confirmed : .draft
        var categoryLines: [EntryCategoryLineCreateRequest] = []
        if let categoryID {
            categoryLines.append(
                EntryCategoryLineCreateRequest(
                    categoryId: categoryID,
                    direction: intent.categoryDirection,
                    amount: DecimalValue(decimal),
                    currency: .cny,
                    exchangeRateId: nil,
                    convertedCnyAmount: nil
                )
            )
        }

        var movements: [AccountMovementCreateRequest] = []
        if let accountID {
            movements.append(
                AccountMovementCreateRequest(
                    accountId: accountID,
                    statementCycleId: nil,
                    movementType: intent.movementType,
                    amount: DecimalValue(decimal),
                    currency: .cny,
                    exchangeRateId: nil,
                    convertedCnyAmount: nil
                )
            )
        }

        let request = EntryCreateRequest(
            title: cleanTitle,
            date: date,
            status: status,
            categoryLines: categoryLines,
            accountMovements: movements
        )
        let repository = FinanceRepository(apiClient: environment.apiClient)
        let entry = try await repository.createEntry(request)
        try await environment.entriesViewModel.refresh()
        try? await environment.dashboardViewModel.refresh()
        environment.selectedModule = .entries
        environment.inspectorSelection = .entry(entry)
    }
}

#endif
