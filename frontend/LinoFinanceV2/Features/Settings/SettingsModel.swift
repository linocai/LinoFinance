import Foundation
import SwiftUI

#if os(macOS)

// SettingsModel — D10 设置 view-model (macOS).
//
// One model backs the whole aggregated settings page; each of the seven sections
// (分类 / 汇率 / 通知 / 数据导出 / 登录与设备 / 审计日志 / AI 助手) loads independently
// and carries its own little load state, so a slow / failing section never blanks
// the rest of the page. All calls are the already-shipped Core client methods —
// this model only wraps them and reloads its own slice on success.
//
// Architecture mirrors P3/P4 screens: the SettingsScreen owns this as a
// @StateObject (built on `model.apiClient`); AppModel is not touched.
@MainActor
final class SettingsModel: ObservableObject {

    enum SectionState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // 分类
    @Published private(set) var categories: [CategoryDTO] = []
    @Published private(set) var categoriesState: SectionState = .idle

    // 汇率
    @Published private(set) var rates: [CurrencyRateDTO] = []
    @Published private(set) var ratesState: SectionState = .idle

    // 通知规则
    @Published private(set) var notificationRules: [NotificationRuleDTO] = []
    @Published private(set) var notificationsState: SectionState = .idle

    // 数据导出
    @Published private(set) var exportDatasets: [ExportDatasetDTO] = []
    @Published private(set) var exportsState: SectionState = .idle
    @Published var exportingDataset: String?

    // 登录与设备
    @Published private(set) var me: AuthMeResponseDTO?
    @Published private(set) var sessions: [AuthSessionDTO] = []
    @Published private(set) var authState: SectionState = .idle

    // 审计日志
    @Published private(set) var auditLogs: [AuditLogDTO] = []
    @Published private(set) var auditState: SectionState = .idle

    // AI 助手
    @Published private(set) var aiConfig: AIConfigDTO?
    @Published private(set) var aiPlans: [AIPlanDTO] = []
    @Published private(set) var aiMemos: [AIMemoDTO] = []
    @Published private(set) var aiState: SectionState = .idle

    /// Single banner for inline row-action errors (撤销 / 退出 / 暂停 / AI 链路…).
    @Published var actionError: String?

    let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Parallel load (each section independent)

    func loadAll() async {
        async let c: Void = loadCategories()
        async let r: Void = loadRates()
        async let n: Void = loadNotifications()
        async let e: Void = loadExports()
        async let a: Void = loadAuth()
        async let l: Void = loadAuditLogs()
        async let i: Void = loadAI()
        _ = await (c, r, n, e, a, l, i)
    }

    func loadCategories() async {
        categoriesState = .loading
        do {
            categories = try await apiClient.listCategories()
            categoriesState = .loaded
        } catch {
            categoriesState = .failed(error.localizedDescription)
        }
    }

    func loadRates() async {
        ratesState = .loading
        do {
            rates = try await apiClient.listCurrencyRates()
            ratesState = .loaded
        } catch {
            ratesState = .failed(error.localizedDescription)
        }
    }

    func loadNotifications() async {
        notificationsState = .loading
        do {
            notificationRules = try await apiClient.listNotificationRules()
            notificationsState = .loaded
        } catch {
            notificationsState = .failed(error.localizedDescription)
        }
    }

    func loadExports() async {
        exportsState = .loading
        do {
            exportDatasets = try await apiClient.listCSVExports().datasets
            exportsState = .loaded
        } catch {
            exportsState = .failed(error.localizedDescription)
        }
    }

    func loadAuth() async {
        authState = .loading
        do {
            async let meResult = apiClient.fetchMe()
            async let sessionsResult = apiClient.listSessions()
            me = try await meResult
            // Sessions may 404/403 for an admin-token bypass — degrade gracefully.
            sessions = (try? await sessionsResult) ?? []
            authState = .loaded
        } catch {
            authState = .failed(error.localizedDescription)
        }
    }

    func loadAuditLogs() async {
        auditState = .loading
        do {
            auditLogs = try await apiClient.listAuditLogs(limit: 50)
            auditState = .loaded
        } catch {
            auditState = .failed(error.localizedDescription)
        }
    }

    func loadAI() async {
        aiState = .loading
        do {
            async let configResult = apiClient.aiConfig()
            async let plansResult = apiClient.listAIPlans()
            async let memosResult = apiClient.listAIMemos()
            aiConfig = try await configResult
            aiPlans = (try? await plansResult) ?? []
            aiMemos = (try? await memosResult)?.items ?? []
            aiState = .loaded
        } catch {
            aiState = .failed(error.localizedDescription)
        }
    }

    // MARK: - 分类 actions (create / edit via sheets; this just reloads)

    func reloadCategories() async { await loadCategories() }

    // MARK: - 汇率

    /// Latest USD→CNY rate (the comp's big number); falls back to any latest rate.
    var latestUSDRate: CurrencyRateDTO? {
        rates
            .filter { $0.fromCurrency == .usd && $0.toCurrency == .cny }
            .max { $0.date < $1.date }
    }

    /// Other rates (everything but the headline USD→CNY) — newest first.
    var historicalRates: [CurrencyRateDTO] {
        rates.sorted { $0.date > $1.date }
    }

    func updateRate(_ id: String, to rate: Decimal) async throws {
        _ = try await apiClient.updateCurrencyRate(id, request: CurrencyRateUpdateRequest(rate: DecimalValue(rate)))
        await loadRates()
    }

    func reloadRates() async { await loadRates() }

    // MARK: - 通知规则

    func toggleRule(_ rule: NotificationRuleDTO) async {
        await runReloadNotifications {
            if rule.status == "paused" {
                _ = try await self.apiClient.resumeNotificationRule(rule.id)
            } else {
                _ = try await self.apiClient.pauseNotificationRule(rule.id)
            }
        }
    }

    func cancelRule(_ id: String) async {
        await runReloadNotifications { _ = try await self.apiClient.cancelNotificationRule(id) }
    }

    func reloadNotifications() async { await loadNotifications() }

    private func runReloadNotifications(_ work: () async throws -> Void) async {
        do {
            actionError = nil
            try await work()
            await loadNotifications()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - 数据导出 (download → NSSavePanel)

    func exportCSV(_ dataset: ExportDatasetDTO) async {
        exportingDataset = dataset.name
        defer { exportingDataset = nil }
        do {
            actionError = nil
            let data = try await apiClient.downloadCSV(dataset: dataset.name)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = dataset.filename
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - 登录与设备

    var accountTitle: String {
        if let user = me?.user {
            return user.displayName ?? user.email ?? "账户 \(user.id.prefix(8))"
        }
        if me?.admin == true { return "管理员令牌" }
        return "未登录"
    }

    var accountSubtitle: String {
        if let user = me?.user {
            var parts: [String] = []
            if let email = user.email { parts.append(email) }
            if user.isAdmin { parts.append("管理员") }
            return parts.isEmpty ? "Apple 账户" : parts.joined(separator: " · ")
        }
        if me?.admin == true { return "环境令牌旁路 · 无 Apple 会话" }
        return "在 Py 阶段接入 Apple 登录"
    }

    var isLoggedIn: Bool { me?.user != nil || me?.admin == true }

    func revoke(_ id: String) async {
        do {
            actionError = nil
            try await apiClient.revokeSession(id)
            await loadAuth()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func logout() async {
        do {
            actionError = nil
            try await apiClient.logout()
            await loadAuth()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - AI 助手 (薄壳: 创建计划 / 批准·驳回·执行·回滚 / 生成·归档备忘)

    @discardableResult
    func createPlan(sourceText: String) async -> Bool {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            actionError = nil
            _ = try await apiClient.createAIPlan(AIPlanCreateRequest(sourceText: trimmed))
            await loadAI()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func approvePlan(_ id: String) async { await runReloadAI { _ = try await self.apiClient.approveAIPlan(id) } }
    func rejectPlan(_ id: String) async { await runReloadAI { _ = try await self.apiClient.rejectAIPlan(id) } }
    func executePlan(_ id: String) async { await runReloadAI { _ = try await self.apiClient.executeAIPlan(id) } }
    func rollbackAction(_ id: String) async { await runReloadAI { _ = try await self.apiClient.rollbackAIAction(id) } }

    func generateMemo() async {
        await runReloadAI {
            let end = Date()
            let start = Calendar.current.date(byAdding: .month, value: -1, to: end) ?? end
            _ = try await self.apiClient.generateAIMemo(AIMemoGenerateRequest(periodStart: start, periodEnd: end))
        }
    }

    func archiveMemo(_ id: String) async { await runReloadAI { try await self.apiClient.archiveAIMemo(id) } }

    private func runReloadAI(_ work: () async throws -> Void) async {
        do {
            actionError = nil
            try await work()
            await loadAI()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

#endif
