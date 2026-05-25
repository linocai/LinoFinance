#if os(macOS)
import SwiftUI
import AppKit

/// macOS 快速记账窗口 —— ⌘K 唤起。
/// 三 tab：AI（自然语言）/ 表单（标题/金额/账户/分类）/ 粘贴（剪贴板）。
/// 与 iOS QuickEntrySheet 共用 `QuickEntryIntent` + `QuickEntryError` + 业务路径。
struct MacQuickEntryView: View {
    @Bindable var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    // Form is the most common path; AI mode lives behind the segmented
    // switcher when needed. Defaulting to .form also means @FocusState
    // can plant the caret on 标题 the moment the window opens.
    @State private var mode: Mode = .form
    @State private var sourceText = ""
    @State private var pastedText = ""
    @State private var title = ""
    @State private var amount = ""
    @State private var intent: QuickEntryIntent = .expense
    @State private var accountID: String?
    @State private var categoryID: String?
    @State private var date = Date()
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @FocusState private var titleFieldFocused: Bool

    enum Mode: String, CaseIterable, Identifiable {
        case ai, form, paste
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ai: "AI"
            case .form: "表单"
            case .paste: "粘贴"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(FinanceTokens.Stroke.hairline)
            content
                .padding(20)
            Divider().background(FinanceTokens.Stroke.hairline)
            footer
        }
        .frame(minWidth: 560, minHeight: 440)
        .background(CanvasBackground())
        .task {
            // Pull the app forward; the call site in MenuBarPopover /
            // MacRootView already does this, but doing it again from
            // inside the window is cheap and handles the case where
            // the user re-focused some other app between click and
            // window appear.
            NSApp.activate(ignoringOtherApps: true)
            // Plant the caret on 标题 so the user can start typing
            // immediately — this is the actual fix for "字打不进去".
            titleFieldFocused = true
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
        }
        .onChange(of: mode) { _, newMode in
            // Re-focus 标题 every time the user pops back into the
            // form tab. AI / paste tabs use TextEditor so they don't
            // need the @FocusState bridge.
            if newMode == .form {
                titleFieldFocused = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AccountIconTile(systemImage: "wand.and.stars", tint: FinanceTokens.Brand.primary, size: 32, radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("快速记账")
                    .font(FinanceTypography.headline)
                    .foregroundStyle(FinanceTokens.Text.primary)
                Text("自然语言 / 表单 / 粘贴")
                    .font(FinanceTypography.caption)
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }
            Spacer()
            SegmentedSwitcher(options: Mode.allCases, selection: $mode) { $0.title }
                .frame(maxWidth: 240)
        }
        .padding(20)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .ai: aiSection
        case .form: formSection
        case .paste: pasteSection
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自然语言")
                .font(FinanceTypography.sectionKicker)
                .kickerTracking()
                .foregroundStyle(FinanceTokens.Text.secondary)
            ZStack(alignment: .topLeading) {
                if sourceText.isEmpty {
                    Text("例如：午餐 58 元，招商信用卡支付，餐饮分类")
                        .font(.system(size: 14))
                        .foregroundStyle(FinanceTokens.Text.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $sourceText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .frame(minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: FinanceTokens.Radius.md, style: .continuous)
                    .fill(FinanceTokens.Surface.glass)
                    .overlay {
                        RoundedRectangle(cornerRadius: FinanceTokens.Radius.md, style: .continuous)
                            .stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
                    }
            )
            Text("提交后会创建 AI 计划，自动跳转到 AI 工作台审阅。")
                .font(FinanceTypography.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
        }
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("方向", selection: $intent) {
                ForEach(QuickEntryIntent.allCases) { intent in
                    Text(intent.title).tag(intent)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                TextField("标题", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFieldFocused)
                TextField("金额", text: $amount)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
            }

            DatePicker("日期", selection: $date, displayedComponents: .date)
                .datePickerStyle(.field)

            HStack(spacing: 10) {
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
            }

            Text("字段完整时直接确认；缺账户或分类时保存为草稿。")
                .font(FinanceTypography.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
        }
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("剪贴板")
                    .font(FinanceTypography.sectionKicker)
                    .kickerTracking()
                    .foregroundStyle(FinanceTokens.Text.secondary)
                Spacer()
                Button {
                    pastedText = NSPasteboard.general.string(forType: .string) ?? ""
                } label: {
                    Label("读取剪贴板", systemImage: "doc.on.clipboard")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
            ZStack(alignment: .topLeading) {
                if pastedText.isEmpty {
                    Text("把账单 / 收据 / 截图 OCR 后的文本粘进来，AI 会拆成结构化记账。")
                        .font(.system(size: 14))
                        .foregroundStyle(FinanceTokens.Text.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $pastedText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .frame(minHeight: 170)
            .background(
                RoundedRectangle(cornerRadius: FinanceTokens.Radius.md, style: .continuous)
                    .fill(FinanceTokens.Surface.glass)
                    .overlay {
                        RoundedRectangle(cornerRadius: FinanceTokens.Radius.md, style: .continuous)
                            .stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
                    }
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(FinanceTypography.caption)
                    .foregroundStyle(FinanceTokens.State.warning)
                    .lineLimit(2)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("提交 ⏎")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

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
            switch mode {
            case .ai: try await submitAI(text: sourceText)
            case .paste: try await submitAI(text: pastedText)
            case .form: try await submitForm()
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
        guard !trimmed.isEmpty else { throw QuickEntryError.emptyText }
        let plan = try await environment.aiViewModel.createPlan(sourceText: trimmed)
        environment.selectedModule = .ai
        environment.inspectorSelection = .aiPlan(plan)
    }

    @MainActor
    private func submitForm() async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw QuickEntryError.missingTitle }
        guard let decimal = Decimal(string: amount), decimal > 0 else { throw QuickEntryError.invalidAmount }

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
