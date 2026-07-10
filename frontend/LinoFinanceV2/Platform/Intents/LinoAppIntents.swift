import AppIntents
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

// LinoAppIntents — Py ⑤ App Intents / Siri / Shortcuts (iOS + macOS).
//
// v2 reimplementation of v1's `Platform/Intents/LinoAppIntents`. The five intents
// (记支出 / 记收入 / 查本月支出 / 下笔信用还款 / 确认 AI 计划) + `LinoShortcuts` are
// unchanged in behavior; `IntentFinanceService` resolves token/baseURL via the v2
// static helpers (`AppModel.resolveBaseURL()` + `SecureTokenStore.readEffectiveToken()`)
// instead of v1's `AppEnvironment.defaultAPIToken/BaseURL`. Intents run独立 of the
// app's running state — they build their own `FinanceRepository` and hit the
// backend directly with a full double-entry `EntryCreateRequest`.
//
// Needs `INFOPLIST_KEY_NSSiriUsageDescription` on the v2 app target (added to the
// pbxproj in Py). All the request/DTO types are in shared Core.

struct RecordExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔支出"
    static var description = IntentDescription("在 LinoFinance 中创建一笔支出记录。")

    @Parameter(title: "标题")
    var title: String

    @Parameter(title: "金额")
    var amount: Double

    @Parameter(title: "币种")
    var currency: CurrencyCode

    @Parameter(title: "账户")
    var accountName: String?

    @Parameter(title: "分类")
    var categoryName: String?

    init() {
        title = ""
        amount = 0
        currency = .cny
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = IntentFinanceService()
        let message = await service.record(
            title: title,
            amount: amount,
            currency: currency,
            direction: .expense,
            accountName: accountName,
            categoryName: categoryName
        )
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct RecordIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔收入"
    static var description = IntentDescription("在 LinoFinance 中创建一笔收入记录。")

    @Parameter(title: "标题")
    var title: String

    @Parameter(title: "金额")
    var amount: Double

    @Parameter(title: "币种")
    var currency: CurrencyCode

    @Parameter(title: "账户")
    var accountName: String?

    @Parameter(title: "分类")
    var categoryName: String?

    init() {
        title = ""
        amount = 0
        currency = .cny
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = IntentFinanceService()
        let message = await service.record(
            title: title,
            amount: amount,
            currency: currency,
            direction: .income,
            accountName: accountName,
            categoryName: categoryName
        )
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct QueryMonthlySpendIntent: AppIntent {
    static var title: LocalizedStringResource = "查询本月支出"
    static var description = IntentDescription("查询指定月份或当前月份的收支概览。")

    @Parameter(title: "月份")
    var month: Int?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await IntentFinanceService().monthlySpend(month: month)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct NextCreditDueIntent: AppIntent {
    static var title: LocalizedStringResource = "下一笔信用卡还款"
    static var description = IntentDescription("查询最近一笔未结清的信用卡还款。")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await IntentFinanceService().nextCreditDue()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct ConfirmAIPlanIntent: AppIntent {
    static var title: LocalizedStringResource = "确认 AI 计划"
    static var description = IntentDescription("批准指定的 AI 计划，但不会自动执行强确认动作。")

    @Parameter(title: "AI 计划 ID")
    var planId: String

    init() {
        planId = ""
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await IntentFinanceService().confirmAIPlan(planId: planId)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// AIRecordIntent / AIParseScreenshotIntent — v3.1.0 P2 免提录入 (D1/D2/D3/D4).
//
// Both funnel into the SAME headless orchestrator, `AIIntentService.record`
// (below `IntentFinanceService`), which mirrors the existing AI pipeline
// (`POST /ai/plans` → risk-assessed proposal → auto-execute when low-risk AND
// id-complete, otherwise leave pending) but makes the accept/defer decision
// itself instead of surfacing an interactive review screen — there is no
// human in the loop for a Siri/Shortcuts invocation. See `AIIntentService`'s
// doc comment for the full decision chain.

struct AIRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "AI 记一笔"
    static var description = IntentDescription("用一句话描述一笔收支，交给 AI 自动记账。金额不大且账户/分类信息完整时会直接记账并播报结果；否则会存成待确认的提案，需要打开 LinoFinance 手动确认。")

    @Parameter(title: "内容", requestValueDialog: IntentDialog("这笔账是什么？比如「星巴克花了38元，用招商卡」。"))
    var text: String

    init() {
        text = ""
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await AIIntentService().record(sourceText: text)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct AIParseScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "解析截图记账"
    static var description = IntentDescription("从一张账单或收据截图里用系统文字识别提取内容，交给 AI 自动记账。识别完全在本机进行，不会上传截图、不会保存截图，也不会访问相册——请通过「快捷指令」把截图传入（例如「获取最新截图」）。")

    // Optional (not required): a Siri voice-only invocation has no way to
    // supply an image, so a missing value is a normal, expected case —
    // handled inside `AIIntentService.recordFromScreenshot` with a clear
    // message, not one the system should interactively prompt for (D3:
    // Shortcuts-fed only, no photo-library access).
    @Parameter(title: "截图", supportedContentTypes: [.image])
    var screenshot: IntentFile?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await AIIntentService().recordFromScreenshot(screenshot)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct LinoShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordExpenseIntent(),
            phrases: [
                "用 \(.applicationName) 记一笔支出",
                "用 \(.applicationName) 记录支出",
            ],
            shortTitle: "记支出",
            systemImageName: "minus.circle.fill"
        )

        AppShortcut(
            intent: RecordIncomeIntent(),
            phrases: [
                "用 \(.applicationName) 记一笔收入",
                "用 \(.applicationName) 记录收入",
            ],
            shortTitle: "记收入",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: QueryMonthlySpendIntent(),
            phrases: [
                "用 \(.applicationName) 查询本月支出",
                "用 \(.applicationName) 看月度支出",
            ],
            shortTitle: "月度支出",
            systemImageName: "chart.pie.fill"
        )

        AppShortcut(
            intent: NextCreditDueIntent(),
            phrases: [
                "用 \(.applicationName) 查下一笔信用卡还款",
                "用 \(.applicationName) 看信用卡还款",
            ],
            shortTitle: "信用还款",
            systemImageName: "creditcard.fill"
        )

        AppShortcut(
            intent: ConfirmAIPlanIntent(),
            phrases: [
                "用 \(.applicationName) 确认 AI 计划",
                "用 \(.applicationName) 批准 AI 计划",
            ],
            shortTitle: "确认 AI",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: AIRecordIntent(),
            phrases: [
                "用 \(.applicationName) AI 记一笔",
                "用 \(.applicationName) 智能记账",
            ],
            shortTitle: "AI 记一笔",
            systemImageName: "waveform.and.mic"
        )

        AppShortcut(
            intent: AIParseScreenshotIntent(),
            phrases: [
                "用 \(.applicationName) 解析截图记账",
                "用 \(.applicationName) 识别账单截图",
            ],
            shortTitle: "解析截图记账",
            systemImageName: "text.viewfinder"
        )
    }
}

struct IntentFinanceService {
    enum Direction {
        case expense
        case income

        var categoryType: CategoryType {
            switch self {
            case .expense: .expense
            case .income: .income
            }
        }

        var categoryDirection: CategoryDirection {
            switch self {
            case .expense: .expense
            case .income: .income
            }
        }

        var movementType: MovementType {
            switch self {
            case .expense: .balanceOut
            case .income: .balanceIn
            }
        }

        var title: String {
            switch self {
            case .expense: "支出"
            case .income: "收入"
            }
        }
    }

    func record(
        title: String,
        amount: Double,
        currency: CurrencyCode,
        direction: Direction,
        accountName: String?,
        categoryName: String?
    ) async -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return "请告诉我这笔\(direction.title)的标题。"
        }
        guard amount > 0 else {
            return "金额需要大于 0。"
        }

        do {
            let repository = try repository()
            let accounts = try await repository.accounts().filter { $0.type == .balance }
            let categories = try await repository.categories()
                .filter { $0.type == direction.categoryType && $0.isActive }

            let account = match(accountName, in: accounts)
            let category = match(categoryName, in: categories)
            var missing: [String] = []
            if account == nil { missing.append("账户") }
            if category == nil { missing.append("分类") }

            guard let account, let category else {
                return "没记成：缺少\(missing.joined(separator: "、"))。请在指令里说清，或打开 LinoFinance 手动补齐。"
            }

            let decimal = Decimal(amount)
            let decimalValue = DecimalValue(decimal)

            let request = EntryCreateRequest(
                title: cleanTitle,
                date: Date(),
                status: .confirmed,
                note: "由 Siri/Shortcuts 创建。",
                createdBy: "app_intent",
                categoryLines: [
                    EntryCategoryLineCreateRequest(
                        categoryId: category.id,
                        direction: direction.categoryDirection,
                        amount: decimalValue,
                        currency: currency,
                        exchangeRateId: nil,
                        convertedCnyAmount: currency == .cny ? decimalValue : nil
                    )
                ],
                accountMovements: [
                    AccountMovementCreateRequest(
                        accountId: account.id,
                        statementCycleId: nil,
                        movementType: direction.movementType,
                        amount: decimalValue,
                        currency: currency,
                        exchangeRateId: nil,
                        convertedCnyAmount: currency == .cny ? decimalValue : nil
                    )
                ]
            )

            _ = try await repository.createEntry(request)
            return "已记录\(direction.title)：\(cleanTitle)，\(FinanceFormatter.money(decimalValue, currency: currency))。"
        } catch IntentFinanceError.missingToken {
            return "还没有配置 LinoFinance API Token，请先在 app 设置里登录或配置 Token。"
        } catch {
            return "记录失败：\(error.localizedDescription)"
        }
    }

    func monthlySpend(month: Int?) async -> String {
        do {
            guard let window = monthWindow(month: month) else {
                return "月份需要在 1 到 12 之间。"
            }
            let report = try await repository().monthlyOverview(
                dateFrom: window.start,
                dateTo: window.end
            )
            let monthText = Calendar.current.component(.month, from: window.start)
            return "\(monthText) 月支出 \(FinanceFormatter.money(report.expenseCny))，收入 \(FinanceFormatter.money(report.incomeCny))，净额 \(FinanceFormatter.signedMoney(report.netIncomeCny))。"
        } catch IntentFinanceError.missingToken {
            return "还没有配置 LinoFinance API Token，请先在 app 设置里登录或配置 Token。"
        } catch {
            return "查询失败：\(error.localizedDescription)"
        }
    }

    func nextCreditDue() async -> String {
        do {
            let repository = try repository()
            let accounts = try await repository.accounts()
            let accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
            let cycles = try await repository.statementCycles()
            let next = cycles
                .filter { $0.remainingAmount.value > 0 && !["paid", "closed"].contains($0.status) }
                .sorted { $0.dueDate < $1.dueDate }
                .first
            guard let next else {
                return "目前没有未结清的信用卡还款。"
            }
            let accountName = accountNames[next.creditAccountId] ?? "信用账户"
            return "下一笔还款是 \(accountName)，到期日 \(FinanceFormatter.mediumDate(next.dueDate))，剩余 \(FinanceFormatter.money(next.remainingAmount, currency: next.currency))。"
        } catch IntentFinanceError.missingToken {
            return "还没有配置 LinoFinance API Token，请先在 app 设置里登录或配置 Token。"
        } catch {
            return "查询失败：\(error.localizedDescription)"
        }
    }

    func confirmAIPlan(planId: String) async -> String {
        let cleanID = planId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else {
            return "请提供 AI 计划 ID。"
        }
        do {
            let plan = try await repository().approveAIPlan(cleanID)
            return "已确认 AI 计划：\(plan.sourceText)。"
        } catch IntentFinanceError.missingToken {
            return "还没有配置 LinoFinance API Token，请先在 app 设置里登录或配置 Token。"
        } catch {
            return "确认失败：\(error.localizedDescription)"
        }
    }

    private func repository() throws -> FinanceRepository {
        guard let token = SecureTokenStore.shared.readEffectiveToken(), !token.isEmpty else {
            throw IntentFinanceError.missingToken
        }
        return FinanceRepository(
            apiClient: LinoAPIClient(
                baseURL: AppModel.resolveBaseURL(),
                authToken: token
            )
        )
    }

    private func match<T>(_ query: String?, in values: [T]) -> T? where T: NamedIntentCandidate {
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let key = normalized(query)
        return values.first { normalized($0.name) == key }
            ?? values.first { normalized($0.name).contains(key) || key.contains(normalized($0.name)) }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func monthWindow(month: Int?) -> (start: Date, end: Date)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let year = components.year else { return nil }
        let resolvedMonth = month ?? components.month ?? 1
        guard (1...12).contains(resolvedMonth),
              let start = calendar.date(from: DateComponents(year: year, month: resolvedMonth, day: 1)),
              let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) else {
            return nil
        }
        return (start, end)
    }
}

/// AIIntentService — v3.1.0 P2 headless 免提编排，被 `AIRecordIntent`（文本）与
/// `AIParseScreenshotIntent`（端上 OCR 出文本后转发）共用。
///
/// Deliberately its own self-contained struct (own `repository()`, mirrors
/// `IntentFinanceService`'s pattern immediately above) rather than reusing
/// `AIAssistantModel` — that model is `@MainActor`, holds `@Published`
/// interactive-review state (editable drafts, a high-risk strong-confirm
/// gate, history), and is designed to be driven by a human tapping through a
/// SwiftUI screen. An intent's `perform()` runs headless, off the main actor,
/// with no screen and no human to hand a decision to — it must make the
/// accept/defer call itself in one shot. The tiny bit of duplication (an
/// 8-line token/baseURL → `FinanceRepository` builder, identical to
/// `IntentFinanceService.repository()`) is the trade-off for keeping both
/// services simple, self-contained, and safe to reason about in isolation —
/// exactly the same call `IntentFinanceService` itself already made.
///
/// D1 甲 免提裁决 (PROJECT_PLAN §5.6): a plan is executed automatically ONLY
/// when BOTH hold —
///   (a) `status == "auto_confirm_candidate"` AND `autoConfirmEligible` —
///       server-computed: true only when EVERY action in the plan is a
///       `CreateEntry` with amount_cny ≤ the configured auto-confirm limit
///       (backend `_assess_action` / `_highest_risk`: any other action type,
///       or a larger amount, makes the whole plan medium/high risk — verified
///       against `backend/app/services/ai.py`, not re-derived client-side so
///       it can never drift from whatever limit is actually configured);
///   (b) every action's account_id / category_id resolves against the
///       CURRENT account/category lists — reusing `EditableAIAction.
///       validationError` (`AIProposalDraft.swift`), the exact id-completeness
///       check the interactive review screen runs before a human can hit
///       confirm. This catches both "the LLM left an id blank" and "the
///       account/category was deleted since this plan was created".
/// Anything else (medium/high risk, an id that doesn't resolve, or a plan a
/// human already touched via the app) is left as a pending proposal — never
/// force-executed headless; the reply tells the user to open the app.
///
/// No client-side retry loop (纯在线, no offline queue — durable): this
/// function calls `createAIPlan` once and, only on the auto-execute path,
/// `executeAIPlan` once. A mechanical double-fire (Siri retry / Back Tap 连点
/// / a looping Shortcut) is a SEPARATE `perform()` invocation with its own
/// call into this function — the P1 120s content-fingerprint dedup window is
/// what keeps two such invocations from ever double-executing (the second
/// `createAIPlan` returns the SAME plan id; whichever call loses the race
/// either sees the plan already `executed` up front — handled below — or its
/// own `executeAIPlan` hits the server's execute state gate and 400s). This
/// function never itself loops or retries an execute (v3.0.0 评审 重要-2 同源
/// 教训: don't hand-roll a second source of duplicate execution on top of what
/// the state gate already prevents).
///
/// v3.1.0 P3 additions (免提确认闭环 — D5/D6): the spoken `IntentDialog` reply
/// this function returns was always the ONLY feedback a Siri/Shortcuts
/// invocation gave (P2). P3 adds a second, persistent channel on top of it —
/// a local notification (`LocalNotifications`, iOS only) — for the two
/// outcomes worth revisiting later: an auto-executed entry (with a "撤销"
/// action) and a plan left pending (tapping it opens `PendingAIPlanSheetIOS`
/// via the exact same push-routing path a remote high-risk-plan push already
/// uses). Both are best-effort and silently no-op when notifications aren't
/// authorized — the spoken reply is never blocked on them.
struct AIIntentService {
    func record(sourceText: String) async -> String {
        let cleanText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return "没听清要记什么，请再说一遍，比如「星巴克花了38元，用招商卡」。"
        }
        do {
            let repository = try repository()

            // D6: 未配置 AI → 立即清晰话术，不触发 LLM 网络调用。GET ai/config 只是
            // 普通后端查询（读 ai_settings 表），真正打给所配大模型的请求在下面的
            // createAIPlan 里——配置不全时绝不会走到那一步。
            let config = try await repository.aiConfig()
            guard config.baseUrlConfigured, config.apiKeyConfigured,
                  !(config.model ?? "").trimmingCharacters(in: .whitespaces).isEmpty else {
                return "AI 还没有配置，请打开 LinoFinance 在设置里填写 Base URL / API Key / Model。"
            }

            let plan = try await repository.createAIPlan(AIPlanCreateRequest(sourceText: cleanText))

            if plan.status == "executed" {
                // P1 幂等短窗（120s）命中了一个并发触发、已经执行完的同名 plan
                // （比如 Back Tap 连点两下、Siri 重试）——不再二次 execute，直接
                // 告知已经记过（accounts/categories 留空，summarize 会优雅降级为
                // 只报标题+金额，省一次没必要的账户/分类拉取）。
                return "这一笔已经记过了，没有重复记账。\(summarize(plan, accounts: [], categories: []))"
            }
            if ["rejected", "cancelled", "failed"].contains(plan.status) {
                // P1 幂等窗内命中了一个已经终结的旧 plan（比如 120s 内刚在 app 里
                // 拒绝过同样内容）——这不是"待确认"，如实告知没有记成，别误导。
                return "这笔没有记成（已是\(plan.status.financeStatusTitle)状态），如果仍要记录，请重新说一遍，或打开 LinoFinance 手动记账。"
            }
            guard plan.status == "auto_confirm_candidate", plan.autoConfirmEligible else {
                // requires_confirmation（中/高风险）、或人工已 approve 但尚未执行
                // 的旧 plan——一律留给 app 里确认，免提通道绝不代为执行。P3: also
                // fires the "待确认" local notification (D5/D6·iOS only — no-ops
                // on macOS and when notifications aren't authorized).
                let message = "已存为待确认提案，请打开 LinoFinance 确认后入账：「\(cleanText)」。"
                await notifyPending(plan: plan, summary: message)
                return message
            }

            let accounts = try await repository.accounts()
            let categories = try await repository.categories()
            let idsResolved = plan.actions.allSatisfy { action in
                EditableAIAction(action: action).validationError(accounts: accounts, categories: categories) == nil
            }
            guard idsResolved else {
                // 低风险但账户/分类 id 缺失或已失效（§5.2①）——同样只留提案，不能
                // 强行 execute（会在 schema 校验处失败，plan 直接转终态 failed，
                // 不可再补救执行）。同上，也发「待确认」通知。
                let message = "已生成提案，但账户或分类信息不完整，请打开 LinoFinance 补充后确认：「\(cleanText)」。"
                await notifyPending(plan: plan, summary: message)
                return message
            }

            let executed = try await repository.executeAIPlan(plan.id)
            let message = summarize(executed, accounts: accounts, categories: categories)
            // P3: "已自动记账" 通知 + 可撤销 action（D5/D6·iOS only）。故意只在
            // ACTUALLY 执行成功这一处调用——上面 `status == "executed"` 的幂等
            // 回显分支不会再走到这里，避免同一笔记账在两次并发触发（Back Tap 连
            // 点/Siri 重试）下弹两条「已自动记账」通知。
            await notifyExecuted(plan: executed, summary: message)
            return message
        } catch IntentFinanceError.missingToken {
            return "还没有登录 LinoFinance，请先打开 app 登录。"
        } catch let apiError as APIError {
            if case .transport = apiError {
                return "记账服务连接失败，请稍后重试。"
            }
            return "记账失败：\(apiError.localizedDescription)"
        } catch {
            return "记账失败：\(error.localizedDescription)"
        }
    }

    /// `AIParseScreenshotIntent`'s entry — OCR the screenshot on-device (D2 甲)
    /// then hand the recognized text to the same `record(sourceText:)`
    /// pipeline. `file == nil` is the expected shape for a Siri voice-only
    /// invocation (there is no image to bind) — handled here with a clear
    /// message, not via an interactive prompt (D3: Shortcuts-fed only).
    func recordFromScreenshot(_ file: IntentFile?) async -> String {
        guard let file else {
            return "没有收到截图，请通过「快捷指令」传入一张截图再试（本功能不会读取相册）。"
        }
        do {
            let recognizedText = try ScreenshotOCR.recognizeText(in: file.data)
            return await record(sourceText: recognizedText)
        } catch {
            return error.localizedDescription
        }
    }

    /// "记了什么/多少钱/哪个账户" — P3 refined to enumerate EVERY `CreateEntry`/
    /// `RecordCreditRepayment` action in the plan, not just the first: D1's
    /// auto-execute gate allows a plan with several low-risk entries in one go
    /// (e.g. "星巴克38元，7-11买水12元"), and the original single-action
    /// version silently dropped every action after the first from the spoken
    /// reply even though all of them were recorded ("多 action 合理归纳").
    /// Reuses `EditableAIAction`'s own payload parsing (the same one the
    /// interactive review screen renders from) so this never hand-rolls a
    /// second JSON-payload reader. `accounts` empty is a valid degraded call
    /// (see the dedup-echo branch in `record` above) — the account-name
    /// lookup just comes back nil and is omitted, everything else still
    /// renders.
    private func summarize(_ plan: AIPlanDTO, accounts: [AccountDTO], categories: [CategoryDTO]) -> String {
        let entries: [String] = plan.actions.compactMap { action in
            guard action.actionType == "CreateEntry" || action.actionType == "RecordCreditRepayment",
                  case .entry(let draft, _) = EditableAIAction(action: action).kind else {
                return nil
            }
            return describeEntry(draft, accounts: accounts)
        }
        guard !entries.isEmpty else {
            return "已按「\(plan.sourceText)」完成记账。"
        }
        return "已记：" + entries.joined(separator: "；") + "。"
    }

    /// One entry's "<标题> <金额+币种>，<账户名>" fragment for `summarize`.
    private func describeEntry(_ draft: EditableEntryDraft, accounts: [AccountDTO]) -> String {
        let line = draft.categoryLines.first
        let movement = draft.accountMovements.first
        let currency = line?.currency ?? movement?.currency ?? .cny
        let amountText = (line?.amountText ?? movement?.amountText)
            .flatMap(parseDecimalAmount)
            .map { FinanceFormatter.money(DecimalValue($0), currency: currency) }
        let accountName = movement?.accountId.flatMap { id in accounts.first(where: { $0.id == id })?.name }
        var text = draft.title
        if let amountText { text += " \(amountText)" }
        if let accountName { text += "，\(accountName)" }
        return text
    }

    // MARK: - Notifications (v3.1.0 P3, D5/D6 — new scheduling only exists on
    // iOS; these two helpers no-op on macOS via the internal `#if os(iOS)` so
    // `record(sourceText:)` above stays free of platform branching)

    /// A plan was left pending — schedules a local notification whose
    /// userInfo matches `push_dispatch`'s shape exactly (`target_type`=
    /// `"ai_plan"` / `target_id`), so tapping it routes through the SAME
    /// `PushNotificationManager` → `.linoDidReceivePushTarget` →
    /// `AppModel.handlePushNotificationTarget` path a remote high-risk-plan
    /// push already uses — zero new routing surface (D5 甲). Silently no-ops
    /// when notifications aren't authorized (D6: never blocks the headless
    /// reply).
    private func notifyPending(plan: AIPlanDTO, summary: String) async {
        #if os(iOS)
        await LocalNotifications.notifyPendingProposal(summary: summary, planId: plan.id)
        #endif
    }

    /// The plan auto-executed — notifies with a "撤销" action bound to the
    /// ONE executed action's id (`rollbackAIAction`'s unit, not the plan id).
    /// Mirrors `AIPlanHistoryRow`'s own "回滚" lookup
    /// (`actions.first(where: { $0.status == "executed" })`) so both surfaces
    /// agree on which action a rollback targets.
    private func notifyExecuted(plan: AIPlanDTO, summary: String) async {
        #if os(iOS)
        guard let actionId = plan.actions.first(where: { $0.status == "executed" })?.id else { return }
        await LocalNotifications.notifyExecuted(summary: summary, actionId: actionId)
        #endif
    }

    private func repository() throws -> FinanceRepository {
        guard let token = SecureTokenStore.shared.readEffectiveToken(), !token.isEmpty else {
            throw IntentFinanceError.missingToken
        }
        return FinanceRepository(
            apiClient: LinoAPIClient(
                baseURL: AppModel.resolveBaseURL(),
                authToken: token
            )
        )
    }
}

/// On-device Vision OCR (D2 甲) — no LLM vision call, no upload, no disk
/// write, no Photos permission (the image arrives already in-process via
/// `IntentFile`, fed by a Shortcut — D3). `.accurate` + zh-Hans/en-US covers
/// the bilingual receipt/bill screenshots this feature targets. Decodes via
/// `CGImageSource` (ImageIO) rather than `UIImage`/`NSImage` so this stays
/// platform-agnostic with no `#if os(...)` split — matching this file's
/// existing style (none of the other intents branch on platform either).
private enum ScreenshotOCR {
    static func recognizeText(in data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AIIntentOCRError.message("这张截图无法读取，请换一张再试。")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw AIIntentOCRError.message("截图文字识别失败，请换一张再试。")
        }
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIIntentOCRError.message("没有从截图里识别出文字，请确认截图清晰、包含账单信息。")
        }
        return text
    }
}

private enum AIIntentOCRError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

private enum IntentFinanceError: LocalizedError {
    case missingToken

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "缺少 API Token"
        }
    }
}

private protocol NamedIntentCandidate {
    var name: String { get }
}

extension AccountDTO: NamedIntentCandidate {}
extension CategoryDTO: NamedIntentCandidate {}
