import SwiftUI

#if os(macOS)

// SettingsCreateSheets — D10 create / edit modals (分类 / 汇率 / 通知规则).
//
// Same glass scaffold idiom as CycleCreateSheets: a glass sheet whose fields are
// glass-wrapped, dropdowns use GlassMenuPicker, footer = PrimaryDarkButton submit
// + SubtleTextButton cancel with .disabled().opacity() gating and a visible error.
// Reuses the module-private labeledField / glassDateField free functions declared
// in CycleCreateSheets.swift.
//
// Immutable fields are surfaced read-only (灰显) rather than hidden, so the user
// sees what can't change:
//   • 分类编辑 — type / parent 不可改 (read-only chips); only name / 启用 / 顺序.
//   • 汇率编辑 — from/to/date 不可改 (read-only); only rate. 被引用 → 409 ⇒ 可见错误.

// MARK: - Shared scaffold (settings flavor — submit label is caller-chosen)

struct SettingsSheetScaffold<Content: View>: View {
    let title: String
    let icon: String
    let subtitle: String
    var submitTitle: String = "创建"
    let isSubmitting: Bool
    let canSubmit: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSubmit: () async -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Font.pageTitle()).foregroundStyle(Theme.Color.textPrimary)
                    Text(subtitle).font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content() }
                    .padding(22)
            }
            Divider().overlay(Theme.Color.divider)
            HStack(spacing: 12) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.expense)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                SubtleTextButton("取消", action: onCancel).keyboardShortcut(.cancelAction)
                PrimaryDarkButton(submitTitle, isLoading: isSubmitting) {
                    Task { await onSubmit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || !canSubmit)
                .opacity((isSubmitting || !canSubmit) ? 0.5 : 1)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 520)
        .background { BloomBackground(animated: false).opacity(0.9) }
    }
}

/// Read-only field row — a glass field that displays an immutable value (灰显).
@ViewBuilder
private func readOnlyField(_ label: String, _ value: String) -> some View {
    labeledField(label) {
        Text(value)
            .font(Theme.Font.body())
            .foregroundStyle(Theme.Color.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: Theme.Radius.button)
    }
}

// MARK: - 新建分类

struct NewCategorySheet: View {
    @ObservedObject var settings: SettingsModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: CategoryType = .expense
    @State private var parentId: String?
    @State private var isActive = true
    @State private var displayOrder = 0
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let creatableTypes: [CategoryType] = [.expense, .income, .transfer]

    var body: some View {
        SettingsSheetScaffold(
            title: "新增分类",
            icon: "tag",
            subtitle: "记账与流水使用的分类",
            isSubmitting: isSubmitting,
            canSubmit: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            errorMessage: errorMessage,
            onCancel: { dismiss() },
            onSubmit: { await submit() }
        ) {
            labeledField("名称") {
                TextField("如：餐饮", text: $name).textFieldStyle(.roundedBorder)
            }
            labeledField("类型") {
                GlassMenuPicker(label: type.title) {
                    ForEach(creatableTypes, id: \.self) { t in
                        Button(t.title) { type = t }
                    }
                }
            }
            labeledField("上级分类（可选）") {
                GlassMenuPicker(
                    label: parentCandidates.first { $0.id == parentId }?.name ?? "无（顶级）",
                    isPlaceholder: parentId == nil
                ) {
                    Button("无（顶级）") { parentId = nil }
                    ForEach(parentCandidates) { cat in
                        Button(cat.name) { parentId = cat.id }
                    }
                }
            }
            labeledField("显示顺序") {
                Stepper(value: $displayOrder, in: 0...999) {
                    Text("\(displayOrder)")
                        .font(Theme.Font.body().monospacedDigit())
                        .foregroundStyle(Theme.Color.textPrimary)
                }
            }
            labeledField("状态") {
                Toggle("启用", isOn: $isActive).toggleStyle(.switch)
            }
        }
    }

    /// Same-type, active categories make sensible parents.
    private var parentCandidates: [CategoryDTO] {
        settings.categories.filter { $0.type == type && $0.isActive }
    }

    private func submit() async {
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        let request = CategoryCreateRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            parentId: parentId,
            isActive: isActive,
            displayOrder: displayOrder
        )
        do {
            _ = try await settings.apiClient.createCategory(request)
            await settings.reloadCategories()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 编辑分类 (type / parent 不可改 — 灰显; 仅 name / 启用 / 顺序)

struct EditCategorySheet: View {
    @ObservedObject var settings: SettingsModel
    let category: CategoryDTO
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isActive: Bool
    @State private var displayOrder: Int
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(settings: SettingsModel, category: CategoryDTO) {
        self.settings = settings
        self.category = category
        _name = State(initialValue: category.name)
        _isActive = State(initialValue: category.isActive)
        _displayOrder = State(initialValue: category.displayOrder)
    }

    var body: some View {
        SettingsSheetScaffold(
            title: "编辑分类",
            icon: "tag",
            subtitle: "类型与上级分类不可修改",
            submitTitle: "保存",
            isSubmitting: isSubmitting,
            canSubmit: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            errorMessage: errorMessage,
            onCancel: { dismiss() },
            onSubmit: { await submit() }
        ) {
            labeledField("名称") {
                TextField("分类名称", text: $name).textFieldStyle(.roundedBorder)
            }
            readOnlyField("类型（不可改）", category.type.title)
            labeledField("显示顺序") {
                Stepper(value: $displayOrder, in: 0...999) {
                    Text("\(displayOrder)")
                        .font(Theme.Font.body().monospacedDigit())
                        .foregroundStyle(Theme.Color.textPrimary)
                }
            }
            labeledField("状态") {
                Toggle("启用", isOn: $isActive).toggleStyle(.switch)
            }
        }
    }

    private func submit() async {
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        let request = CategoryUpdateRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            isActive: isActive,
            displayOrder: displayOrder
        )
        do {
            _ = try await settings.apiClient.updateCategory(category.id, request: request)
            await settings.reloadCategories()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 新建汇率

struct NewCurrencyRateSheet: View {
    @ObservedObject var settings: SettingsModel
    @Environment(\.dismiss) private var dismiss

    @State private var fromCurrency: CurrencyCode = .usd
    @State private var rateText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        SettingsSheetScaffold(
            title: "更新汇率",
            icon: "arrow.left.arrow.right",
            subtitle: "目标币种固定为 CNY",
            isSubmitting: isSubmitting,
            canSubmit: (parsedRate ?? 0) > 0,
            errorMessage: errorMessage,
            onCancel: { dismiss() },
            onSubmit: { await submit() }
        ) {
            labeledField("源币种") {
                GlassMenuPicker(label: "\(fromCurrency.symbol) \(fromCurrency.rawValue)") {
                    ForEach(CurrencyCode.allCases.filter { $0 != .cny }, id: \.self) { code in
                        Button("\(code.symbol) \(code.rawValue)") { fromCurrency = code }
                    }
                }
            }
            labeledField("汇率（\(fromCurrency.rawValue) → CNY）") {
                TextField("如：7.18", text: $rateText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Font.cardNumber().monospacedDigit())
            }
            labeledField("日期") {
                glassDateField($date)
            }
            labeledField("备注（可选）") {
                TextField("补充说明", text: $note).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var parsedRate: Decimal? { parseDecimalAmount(rateText) }

    private func submit() async {
        guard let rate = parsedRate else { return }
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        let request = CurrencyRateCreateRequest(
            fromCurrency: fromCurrency,
            toCurrency: .cny,
            rate: DecimalValue(rate),
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        do {
            _ = try await settings.apiClient.createCurrencyRate(request)
            await settings.reloadRates()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 编辑汇率 (from/to/date 不可改 — 灰显; 仅 rate; 被引用 → 409 可见错误)

struct EditCurrencyRateSheet: View {
    @ObservedObject var settings: SettingsModel
    let rate: CurrencyRateDTO
    @Environment(\.dismiss) private var dismiss

    @State private var rateText: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(settings: SettingsModel, rate: CurrencyRateDTO) {
        self.settings = settings
        self.rate = rate
        _rateText = State(initialValue: "\(rate.rate.value)")
    }

    var body: some View {
        SettingsSheetScaffold(
            title: "编辑汇率",
            icon: "arrow.left.arrow.right",
            subtitle: "币种与日期不可修改",
            submitTitle: "保存",
            isSubmitting: isSubmitting,
            canSubmit: (parsedRate ?? 0) > 0,
            errorMessage: errorMessage,
            onCancel: { dismiss() },
            onSubmit: { await submit() }
        ) {
            readOnlyField("币种（不可改）", "\(rate.fromCurrency.rawValue) → \(rate.toCurrency.rawValue)")
            readOnlyField("日期（不可改）", FinanceFormatter.mediumDate(rate.date))
            labeledField("汇率") {
                TextField("汇率", text: $rateText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Font.cardNumber().monospacedDigit())
            }
        }
    }

    private var parsedRate: Decimal? { parseDecimalAmount(rateText) }

    private func submit() async {
        guard let value = parsedRate else { return }
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await settings.updateRate(rate.id, to: value)
            dismiss()
        } catch let APIError.badStatus(409, _) {
            // 被引用的汇率不可改 — 给出明确可见的错误文案 (plan §D10.2).
            errorMessage = "该汇率已被引用，无法修改"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 新建通知规则

struct NewNotificationRuleSheet: View {
    @ObservedObject var settings: SettingsModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var ruleType = "cash_flow"
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let ruleTypes = ["cash_flow", "subscription", "credit_repayment", "anomaly"]

    var body: some View {
        SettingsSheetScaffold(
            title: "新增通知规则",
            icon: "bell",
            subtitle: "到期提醒与异常提示",
            isSubmitting: isSubmitting,
            canSubmit: !title.trimmingCharacters(in: .whitespaces).isEmpty,
            errorMessage: errorMessage,
            onCancel: { dismiss() },
            onSubmit: { await submit() }
        ) {
            labeledField("标题") {
                TextField("如：账单到期提醒", text: $title).textFieldStyle(.roundedBorder)
            }
            labeledField("类型") {
                GlassMenuPicker(label: ruleType.financeStatusTitle) {
                    ForEach(ruleTypes, id: \.self) { rt in
                        Button(rt.financeStatusTitle) { ruleType = rt }
                    }
                }
            }
            labeledField("备注（可选）") {
                TextField("补充说明", text: $note).textFieldStyle(.roundedBorder)
            }
        }
    }

    private func submit() async {
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        let request = NotificationRuleCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            ruleType: ruleType,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        do {
            _ = try await settings.apiClient.createNotificationRule(request)
            await settings.reloadNotifications()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#endif
