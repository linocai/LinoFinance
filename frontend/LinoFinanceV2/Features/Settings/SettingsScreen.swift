import SwiftUI

#if os(macOS)

// SettingsScreen — D10 设置 (macOS · liquid glass · 2-column card grid).
//
// Comp source: lf_settings_hi.png — a two-column masonry of glass cards.
//   左列: 分类管理 (彩点列表 + 新增 + 编辑) / 登录与设备 (账户 + 会话列表 + 撤销) / 数据导出
//   右列: 汇率 (大数 7.18 + 历史条 + 更新) / 通知规则 (开关列表) / AI 助手 (自然语言输入) / 审计日志
//
// One SettingsModel (@StateObject on model.apiClient) loads all seven sections in
// parallel; each section degrades to its own loading/empty/failed card without
// blanking the rest. AppModel is not mutated. Apple 登录按钮 / 推送设备注册 are
// deferred to Py (entitlements) — see the 登录与设备 section. AI is a thin
// "connect + confirm + rollback" shell, not a deep business surface (plan §D10.7).
//
// Contract: `init(model: AppModel)`; wired into the router's `.settings` case.
struct SettingsScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var settings: SettingsModel

    @State private var showingNewCategory = false
    @State private var editingCategory: CategoryDTO?
    @State private var showingNewRate = false
    @State private var editingRate: CurrencyRateDTO?
    @State private var showingNewRule = false

    init(model: AppModel) {
        self.model = model
        _settings = StateObject(wrappedValue: SettingsModel(apiClient: model.apiClient))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actionBanner
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        CategoriesCard(
                            settings: settings,
                            onNew: { showingNewCategory = true },
                            onEdit: { editingCategory = $0 }
                        )
                        AuthCard(settings: settings, model: model)
                        ExportCard(settings: settings)
                    }
                    VStack(spacing: 18) {
                        RatesCard(
                            settings: settings,
                            onNew: { showingNewRate = true },
                            onEdit: { editingRate = $0 }
                        )
                        NotificationsCard(settings: settings, onNew: { showingNewRule = true })
                        AIAssistantCard(settings: settings)
                        AuditLogCard(settings: settings)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .task {
            // Only the first appearance triggers the parallel load; re-selecting the
            // tab keeps the cached slices.
            if settings.categoriesState == .idle { await settings.loadAll() }
        }
        .sheet(isPresented: $showingNewCategory) { NewCategorySheet(settings: settings) }
        .sheet(item: $editingCategory) { EditCategorySheet(settings: settings, category: $0) }
        .sheet(isPresented: $showingNewRate) { NewCurrencyRateSheet(settings: settings) }
        .sheet(item: $editingRate) { EditCurrencyRateSheet(settings: settings, rate: $0) }
        .sheet(isPresented: $showingNewRule) { NewNotificationRuleSheet(settings: settings) }
    }

    // MARK: - Header + banner

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设置")
                .font(Theme.Font.pageTitle())
                .foregroundStyle(Theme.Color.textPrimary)
            Text("分类、汇率、通知、导出、登录与 AI 助手")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    @ViewBuilder
    private var actionBanner: some View {
        if let message = settings.actionError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer(minLength: 8)
                Button { settings.actionError = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }
            .padding(12)
            .glassPanel(cornerRadius: Theme.Radius.button, tint: Theme.Color.expense)
        }
    }
}

// MARK: - Section card shell (glass card with a titled header + optional action)

private struct SettingsCard<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassCard(tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 7) {
                        if let systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                        Text(title)
                            .font(Theme.Font.subtitle(.semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                    Spacer()
                    if let actionTitle, let action {
                        Button(action: action) {
                            Text(actionTitle)
                                .font(Theme.Font.caption(.semibold))
                                .foregroundStyle(Theme.Color.link)
                        }
                        .buttonStyle(.plain)
                    }
                }
                content()
            }
        }
    }
}

// MARK: - Small reusable section states

private struct SectionLoading: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("加载中…").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SectionFailed: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.expense)
                .lineLimit(3)
            SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise", action: retry)
        }
    }
}

private struct SectionEmpty: View {
    let message: String
    var body: some View {
        Text(message)
            .font(Theme.Font.caption())
            .foregroundStyle(Theme.Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 1. 分类管理

private struct CategoriesCard: View {
    @ObservedObject var settings: SettingsModel
    let onNew: () -> Void
    let onEdit: (CategoryDTO) -> Void

    var body: some View {
        SettingsCard(title: "分类管理", systemImage: "tag", actionTitle: "+ 新增", action: onNew) {
            switch settings.categoriesState {
            case .idle, .loading:
                SectionLoading()
            case .failed(let m):
                SectionFailed(message: m) { Task { await settings.loadCategories() } }
            case .loaded:
                if settings.categories.isEmpty {
                    SectionEmpty(message: "还没有分类。点「+ 新增」创建第一个。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedCategories.enumerated()), id: \.element.id) { index, cat in
                            if index > 0 { Divider().overlay(Theme.Color.divider) }
                            CategoryRow(category: cat) { onEdit(cat) }
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private var sortedCategories: [CategoryDTO] {
        settings.categories.sorted {
            if $0.type != $1.type { return typeRank($0.type) < typeRank($1.type) }
            return $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder
        }
    }

    private func typeRank(_ t: CategoryType) -> Int {
        switch t {
        case .expense: 0
        case .income: 1
        case .transfer: 2
        case .system: 3
        }
    }
}

private struct CategoryRow: View {
    let category: CategoryDTO
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
            Text(category.name)
                .font(Theme.Font.body(.medium))
                .foregroundStyle(category.isActive ? Theme.Color.textPrimary : Theme.Color.textTertiary)
                .lineLimit(1)
            StatusBadge(text: category.type.title, tone: typeTone)
            if !category.isActive {
                StatusBadge(text: "已停用", tone: .negative)
            }
            Spacer(minLength: 8)
            TintedActionChip(title: "编辑", tone: .neutral, action: onEdit)
        }
    }

    private var typeTone: StatusBadge.Tone {
        switch category.type {
        case .income: .positive
        case .transfer: .brand
        case .expense: .neutral
        case .system: .warning
        }
    }

    // Income→green, transfer→indigo, expense→stable per-name palette pick (same
    // idiom as LedgerScreen's EntryRow tile color).
    private var dotColor: Color {
        if !category.isActive { return Theme.fixed(0x9A9AA0) }
        switch category.type {
        case .income: return Theme.fixed(0x34C759)
        case .transfer: return Theme.fixed(0x5B6CF0)
        case .system: return Theme.fixed(0x9A9AA0)
        case .expense:
            return Self.expensePalette[Self.stableIndex(category.name, Self.expensePalette.count)]
        }
    }

    private static let expensePalette: [Color] = [
        Theme.fixed(0xFF8A4C), Theme.fixed(0x4C9AFF), Theme.fixed(0x9B7BFF),
        Theme.fixed(0xFF6F91), Theme.fixed(0x2BB7A6), Theme.fixed(0xF0B429),
    ]

    private static func stableIndex(_ s: String, _ count: Int) -> Int {
        var h = 5381
        for b in s.utf8 { h = (h &* 33 &+ Int(b)) & 0x7fffffff }
        return count > 0 ? h % count : 0
    }
}

// MARK: - 2. 汇率

private struct RatesCard: View {
    @ObservedObject var settings: SettingsModel
    let onNew: () -> Void
    let onEdit: (CurrencyRateDTO) -> Void

    var body: some View {
        SettingsCard(title: "汇率", systemImage: "arrow.left.arrow.right", actionTitle: "更新", action: onNew) {
            switch settings.ratesState {
            case .idle, .loading:
                SectionLoading()
            case .failed(let m):
                SectionFailed(message: m) { Task { await settings.loadRates() } }
            case .loaded:
                if settings.rates.isEmpty {
                    SectionEmpty(message: "还没有汇率。点「更新」录入 USD→CNY。")
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        headline
                        Divider().overlay(Theme.Color.divider)
                        ForEach(Array(settings.historicalRates.prefix(6))) { rate in
                            RateRow(rate: rate) { onEdit(rate) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var headline: some View {
        if let usd = settings.latestUSDRate {
            VStack(alignment: .leading, spacing: 4) {
                Text(rateString(usd.rate.value))
                    .font(Theme.Font.bigNumber(.bold).monospacedDigit())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("USD → CNY · \(FinanceFormatter.mediumDate(usd.date))")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        } else {
            Text("暂无 USD→CNY 汇率")
                .font(Theme.Font.subtitle())
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private func rateString(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 4
        return f.string(from: n) ?? "\(d)"
    }
}

private struct RateRow: View {
    let rate: CurrencyRateDTO
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rate.fromCurrency.rawValue) → \(rate.toCurrency.rawValue)")
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            Text(FinanceFormatter.shortDate(rate.date))
                .font(Theme.Font.caption().monospacedDigit())
                .foregroundStyle(Theme.Color.textTertiary)
            Spacer(minLength: 8)
            Text(rateString(rate.rate.value))
                .font(Theme.Font.body(.semibold).monospacedDigit())
                .foregroundStyle(Theme.Color.textPrimary)
            TintedActionChip(title: "编辑", tone: .neutral, action: onEdit)
        }
    }

    private func rateString(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 4
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "\(d)"
    }
}

// MARK: - 3. 通知规则

private struct NotificationsCard: View {
    @ObservedObject var settings: SettingsModel
    let onNew: () -> Void

    var body: some View {
        SettingsCard(title: "通知规则", systemImage: "bell", actionTitle: "+ 新增", action: onNew) {
            switch settings.notificationsState {
            case .idle, .loading:
                SectionLoading()
            case .failed(let m):
                SectionFailed(message: m) { Task { await settings.loadNotifications() } }
            case .loaded:
                if settings.notificationRules.isEmpty {
                    SectionEmpty(message: "还没有通知规则。点「+ 新增」创建到期提醒。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.notificationRules.enumerated()), id: \.element.id) { index, rule in
                            if index > 0 { Divider().overlay(Theme.Color.divider) }
                            NotificationRow(
                                rule: rule,
                                onToggle: { Task { await settings.toggleRule(rule) } },
                                onCancel: { Task { await settings.cancelRule(rule.id) } }
                            )
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }
}

private struct NotificationRow: View {
    let rule: NotificationRuleDTO
    let onToggle: () -> Void
    let onCancel: () -> Void

    private var isActive: Bool { rule.status == "active" }
    private var isCancelled: Bool { rule.status == "cancelled" || rule.status == "canceled" }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title)
                    .font(Theme.Font.body(.medium))
                    .foregroundStyle(isCancelled ? Theme.Color.textTertiary : Theme.Color.textPrimary)
                    .lineLimit(1)
                Text(rule.ruleType.financeStatusTitle)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer(minLength: 8)
            if isCancelled {
                StatusBadge(text: "已取消", tone: .negative)
            } else {
                TintedActionChip(title: "取消", tone: .destructive, action: onCancel)
                // .switch toggle drives pause/resume (active ⇄ paused). OS26 system
                // control, kept per R0 (native switch is the agreed exception).
                Toggle("", isOn: Binding(get: { isActive }, set: { _ in onToggle() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - 4. 数据导出

private struct ExportCard: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        SettingsCard(title: "数据导出", systemImage: "square.and.arrow.up") {
            switch settings.exportsState {
            case .idle, .loading:
                SectionLoading()
            case .failed(let m):
                SectionFailed(message: m) { Task { await settings.loadExports() } }
            case .loaded:
                if settings.exportDatasets.isEmpty {
                    SectionEmpty(message: "暂无可导出的数据集。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.exportDatasets.enumerated()), id: \.element.id) { index, dataset in
                            if index > 0 { Divider().overlay(Theme.Color.divider) }
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(datasetTitle(dataset.name))
                                        .font(Theme.Font.body(.medium))
                                        .foregroundStyle(Theme.Color.textPrimary)
                                    Text(dataset.filename)
                                        .font(Theme.Font.caption())
                                        .foregroundStyle(Theme.Color.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                if settings.exportingDataset == dataset.name {
                                    ProgressView().controlSize(.small)
                                } else {
                                    TintedActionChip(title: "导出 CSV", tone: .action) {
                                        Task { await settings.exportCSV(dataset) }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private func datasetTitle(_ name: String) -> String {
        switch name {
        case "entries": "记账明细"
        case "accounts": "账户"
        case "cash_flow_items": "现金流"
        case "reimbursement_claims": "报销"
        case "categories": "分类"
        case "currency_rates": "汇率"
        default: name
        }
    }
}

// MARK: - 5. 登录与设备

private struct AuthCard: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var model: AppModel
    @State private var showingAdminEntry = false
    @State private var adminToken = ""

    var body: some View {
        SettingsCard(title: "登录与设备", systemImage: "person.crop.circle") {
            switch settings.authState {
            case .idle, .loading:
                SectionLoading()
            case .failed(let m):
                SectionFailed(message: m) { Task { await settings.loadAuth() } }
            case .loaded:
                VStack(alignment: .leading, spacing: 14) {
                    accountHeader
                    if settings.isLoggedIn {
                        if !settings.sessions.isEmpty {
                            Divider().overlay(Theme.Color.divider)
                            VStack(spacing: 0) {
                                ForEach(Array(settings.sessions.enumerated()), id: \.element.id) { index, session in
                                    if index > 0 { Divider().overlay(Theme.Color.divider) }
                                    SessionRow(session: session) {
                                        Task { await settings.revoke(session.id) }
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        HStack {
                            Spacer()
                            TintedActionChip(title: "退出登录", tone: .destructive) {
                                Task { await settings.logout() }
                            }
                        }
                    } else {
                        // Py ② — real Sign in with Apple button (login persists to
                        // the session keychain slot + rebuilds clients via AppModel)
                        // plus the admin-token bypass, kept in parallel.
                        Divider().overlay(Theme.Color.divider)
                        SignInWithAppleView(model: model) {
                            Task { await settings.loadAuth() }
                        }
                        DisclosureGroup(isExpanded: $showingAdminEntry) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("仅在使用 LINOFINANCE_API_AUTH_TOKEN 直连后端时填写。")
                                    .font(Theme.Font.caption())
                                    .foregroundStyle(Theme.Color.textTertiary)
                                SecureField("Admin Token", text: $adminToken)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                HStack {
                                    Spacer()
                                    TintedActionChip(title: "保存", tone: .neutral) {
                                        let token = adminToken
                                        adminToken = ""
                                        Task {
                                            try? await model.saveAdminToken(token)
                                            await settings.loadAuth()
                                        }
                                    }
                                    .disabled(adminToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Text("高级设置 / 管理员 Token")
                                .font(Theme.Font.caption(.medium))
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var accountHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: settings.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.questionmark")
                .font(.system(size: 30))
                .foregroundStyle(settings.isLoggedIn ? Theme.Color.link : Theme.Color.textTertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.accountTitle)
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(settings.accountSubtitle)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
    }
}

private struct SessionRow: View {
    let session: AuthSessionDTO
    let onRevoke: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: deviceIcon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.deviceLabel)
                        .font(Theme.Font.body(.medium))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    if session.isCurrent { StatusBadge(text: "当前", tone: .positive) }
                }
                Text("\(platformTitle) · 活跃 \(FinanceFormatter.shortDate(session.lastSeenAt))")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer(minLength: 8)
            if !session.isCurrent {
                TintedActionChip(title: "撤销", tone: .destructive, action: onRevoke)
            }
        }
    }

    private var platformTitle: String {
        switch session.platform.lowercased() {
        case "ios": "iOS"
        case "macos": "macOS"
        default: session.platform
        }
    }

    private var deviceIcon: String {
        switch session.platform.lowercased() {
        case "ios": "iphone"
        case "macos": "laptopcomputer"
        default: "desktopcomputer"
        }
    }
}

// MARK: - 6. 审计日志 (只读)

private struct AuditLogCard: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        SettingsCard(title: "审计日志", systemImage: "list.bullet.rectangle") {
            switch settings.auditState {
            case .idle, .loading:
                SectionLoading()
            case .failed(let m):
                SectionFailed(message: m) { Task { await settings.loadAuditLogs() } }
            case .loaded:
                if settings.auditLogs.isEmpty {
                    SectionEmpty(message: "暂无审计记录。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.auditLogs.prefix(20).enumerated()), id: \.element.id) { index, log in
                            if index > 0 { Divider().overlay(Theme.Color.divider) }
                            AuditRow(log: log)
                                .padding(.vertical, 7)
                        }
                    }
                }
            }
        }
    }
}

private struct AuditRow: View {
    let log: AuditLogDTO

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.actionType.financeStatusTitle)
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Text("\(log.targetType) · \(log.actor)")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
    }
}

// MARK: - 7. AI 助手 (薄壳: 创建计划 → 批准/驳回/执行/回滚 · 备忘生成/归档)

private struct AIAssistantCard: View {
    @ObservedObject var settings: SettingsModel
    @State private var sourceText = ""
    @State private var submitting = false

    var body: some View {
        SettingsCard(title: "AI 助手", systemImage: "sparkles", tint: Theme.Color.brandEnd) {
            switch settings.aiState {
            case .idle, .loading:
                SectionLoading()
            case .failed(let m):
                SectionFailed(message: m) { Task { await settings.loadAI() } }
            case .loaded:
                VStack(alignment: .leading, spacing: 14) {
                    configRow
                    inputCard
                    if !settings.aiPlans.isEmpty {
                        Divider().overlay(Theme.Color.divider)
                        Text("计划")
                            .font(Theme.Font.caption(.semibold))
                            .foregroundStyle(Theme.Color.textSecondary)
                        ForEach(Array(settings.aiPlans.prefix(5))) { plan in
                            AIPlanRow(plan: plan, settings: settings)
                        }
                    }
                    memosSection
                }
            }
        }
    }

    @ViewBuilder
    private var configRow: some View {
        if let config = settings.aiConfig {
            HStack(spacing: 8) {
                StatusBadge(
                    text: config.apiKeyConfigured ? "已配置 \(config.provider)" : "未配置密钥",
                    tone: config.apiKeyConfigured ? .positive : .warning
                )
                if let m = config.model, !m.isEmpty {
                    Text(m).font(Theme.Font.caption()).foregroundStyle(Theme.Color.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 自然语言输入框 — 玻璃面板内的多行输入 (comp 的 AI 输入卡).
            TextEditor(text: $sourceText)
                .font(Theme.Font.body())
                .scrollContentBackground(.hidden)
                .frame(height: 64)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassPanel(cornerRadius: Theme.Radius.button)
                .overlay(alignment: .topLeading) {
                    if sourceText.isEmpty {
                        Text("用自然语言描述，例如：把上周三星巴克 38 元记成餐饮支出")
                            .font(Theme.Font.body())
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Spacer()
                PrimaryDarkButton("解析", isLoading: submitting) {
                    Task {
                        submitting = true
                        let ok = await settings.createPlan(sourceText: sourceText)
                        if ok { sourceText = "" }
                        submitting = false
                    }
                }
                .disabled(submitting || sourceText.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity((submitting || sourceText.trimmingCharacters(in: .whitespaces).isEmpty) ? 0.5 : 1)
            }
        }
    }

    @ViewBuilder
    private var memosSection: some View {
        Divider().overlay(Theme.Color.divider)
        HStack {
            Text("月度备忘")
                .font(Theme.Font.caption(.semibold))
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            TintedActionChip(title: "生成", tone: .brand) { Task { await settings.generateMemo() } }
        }
        if settings.aiMemos.isEmpty {
            Text("还没有月度备忘。点「生成」创建上一个月的总结。")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textTertiary)
        } else {
            ForEach(Array(settings.aiMemos.prefix(3))) { memo in
                AIMemoRow(memo: memo) { Task { await settings.archiveMemo(memo.id) } }
            }
        }
    }
}

private struct AIPlanRow: View {
    let plan: AIPlanDTO
    @ObservedObject var settings: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(plan.sourceText)
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 6)
                StatusBadge(text: plan.status.financeStatusTitle, tone: statusTone)
            }
            HStack(spacing: 8) {
                StatusBadge(text: plan.riskLevel.financeStatusTitle, tone: riskTone)
                Spacer(minLength: 0)
                actions
            }
        }
        .padding(10)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    @ViewBuilder
    private var actions: some View {
        switch plan.status {
        case "pending", "requires_confirmation", "auto_confirm_candidate":
            TintedActionChip(title: "批准", tone: .positive) { Task { await settings.approvePlan(plan.id) } }
            TintedActionChip(title: "驳回", tone: .destructive) { Task { await settings.rejectPlan(plan.id) } }
        case "approved":
            TintedActionChip(title: "执行", tone: .action) { Task { await settings.executePlan(plan.id) } }
            TintedActionChip(title: "驳回", tone: .destructive) { Task { await settings.rejectPlan(plan.id) } }
        case "executed":
            // 执行后可对每个 action 回滚 (薄链路: 只暴露第一个可回滚 action).
            if let action = plan.actions.first(where: { $0.status == "executed" }) {
                TintedActionChip(title: "回滚", tone: .neutral) { Task { await settings.rollbackAction(action.id) } }
            }
        default:
            EmptyView()
        }
    }

    private var statusTone: StatusBadge.Tone {
        switch plan.status {
        case "executed": .positive
        case "approved": .pending
        case "rejected", "failed": .negative
        case "rolled_back": .neutral
        default: .warning
        }
    }

    private var riskTone: StatusBadge.Tone {
        switch plan.riskLevel {
        case "high": .negative
        case "medium": .warning
        default: .neutral
        }
    }
}

private struct AIMemoRow: View {
    let memo: AIMemoDTO
    let onArchive: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(FinanceFormatter.shortDate(memo.periodStart)) – \(FinanceFormatter.shortDate(memo.periodEnd))")
                    .font(Theme.Font.caption(.medium).monospacedDigit())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(memo.summary)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                StatusBadge(text: memo.status.financeStatusTitle, tone: memo.status == "archived" ? .neutral : .pending)
                if memo.status != "archived" {
                    TintedActionChip(title: "归档", tone: .neutral, action: onArchive)
                }
            }
        }
        .padding(10)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }
}

#endif
