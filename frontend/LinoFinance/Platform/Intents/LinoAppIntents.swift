import AppIntents
import Foundation

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
            let accounts = try await repository.accounts().balanceAccounts
            let categories = try await repository.categories()
                .filter { $0.type == direction.categoryType && $0.isActive }

            let account = match(accountName, in: accounts)
            let category = match(categoryName, in: categories)
            var missing: [String] = []
            if account == nil { missing.append("账户") }
            if category == nil { missing.append("分类") }

            let decimal = Decimal(amount)
            let decimalValue = DecimalValue(decimal)
            let status: EntryStatus = missing.isEmpty ? .confirmed : .draft
            let note = missing.isEmpty
                ? "由 Siri/Shortcuts 创建。"
                : "由 Siri/Shortcuts 创建；缺少\(missing.joined(separator: "、"))，已保存为草稿。"

            let request = EntryCreateRequest(
                title: cleanTitle,
                date: Date(),
                status: status,
                note: note,
                createdBy: "app_intent",
                categoryLines: category.map {
                    [
                        EntryCategoryLineCreateRequest(
                            categoryId: $0.id,
                            direction: direction.categoryDirection,
                            amount: decimalValue,
                            currency: currency,
                            exchangeRateId: nil,
                            convertedCnyAmount: currency == .cny ? decimalValue : nil
                        )
                    ]
                } ?? [],
                accountMovements: account.map {
                    [
                        AccountMovementCreateRequest(
                            accountId: $0.id,
                            statementCycleId: nil,
                            movementType: direction.movementType,
                            amount: decimalValue,
                            currency: currency,
                            exchangeRateId: nil,
                            convertedCnyAmount: currency == .cny ? decimalValue : nil
                        )
                    ]
                } ?? []
            )

            let entry = try await repository.createEntry(request)
            if status == .confirmed {
                return "已记录\(direction.title)：\(cleanTitle)，\(FinanceFormatter.money(decimalValue, currency: currency))。"
            }
            return "已保存草稿：\(cleanTitle)。缺少\(missing.joined(separator: "、"))，打开 LinoFinance 后补齐即可。记录 ID：\(entry.id)。"
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
        let token = AppEnvironment.defaultAPIToken()
        guard token != nil else {
            throw IntentFinanceError.missingToken
        }
        return FinanceRepository(
            apiClient: LinoAPIClient(
                baseURL: AppEnvironment.defaultAPIBaseURL(),
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
        // Build the month window with the local calendar: the resulting Dates
        // are formatted as plain calendar days via `linoAPIDate` (local tz), so
        // a UTC calendar here would shift the month start/end by one day in any
        // non-UTC offset (audit §3.4 — negative offsets land a day early).
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
