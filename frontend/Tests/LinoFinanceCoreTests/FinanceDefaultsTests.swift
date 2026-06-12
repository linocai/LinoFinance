import XCTest
@testable import LinoFinanceCore

final class FinanceDefaultsTests: XCTestCase {
    func testConfirmedDefaults() {
        XCTAssertEqual(FinanceDefaults.initialUSDCNYRate, Decimal(string: "6.8")!)
        XCTAssertEqual(FinanceDefaults.aiAutoConfirmLimitCNY, Decimal(1000))
        XCTAssertEqual(FinanceDefaults.baseCurrency, .cny)
        XCTAssertEqual(FinanceDefaults.v1ExportFormat, "csv")
    }

    func testMoneyAmountFormattingKeepsOriginalAndConvertedAmounts() {
        let money = MoneyAmount(
            amountMinor: 12_345,
            currency: .usd,
            convertedCNYMinor: 83_946,
            exchangeRate: FinanceDefaults.initialUSDCNYRate
        )

        XCTAssertEqual(money.formattedOriginal, "$123.45")
        XCTAssertEqual(money.formattedConvertedCNY, "about ¥839.46")
    }

    func testCreditStatementStatusUsesApiRawValues() {
        XCTAssertEqual(CreditStatementStatus.statementGenerated.rawValue, "statement_generated")
        XCTAssertEqual(CreditStatementStatus.partiallyPaid.rawValue, "partially_paid")
    }

    func testCashFlowEnumsUseApiRawValues() {
        XCTAssertEqual(CashFlowType.creditRepayment.rawValue, "credit_repayment")
        XCTAssertEqual(CashFlowType.oneTime.rawValue, "one_time")
        XCTAssertEqual(CashFlowStatus.settled.rawValue, "settled")
    }

    func testReimbursementStatusUsesApiRawValues() {
        XCTAssertEqual(ReimbursementStatus.invoicePending.rawValue, "invoice_pending")
        XCTAssertEqual(ReimbursementStatus.waitingReceived.rawValue, "waiting_received")
        XCTAssertEqual(ReimbursementStatus.partialReceived.rawValue, "partial_received")
    }

    func testInstallmentStatusUsesApiRawValues() {
        XCTAssertEqual(InstallmentPlanStatus.paidOff.rawValue, "paid_off")
        XCTAssertEqual(InstallmentPlanStatus.earlyPaidOff.rawValue, "early_paid_off")
        XCTAssertEqual(InstallmentPlanStatus.cancelled.rawValue, "cancelled")
    }

    func testSubscriptionEnumsUseApiRawValues() {
        XCTAssertEqual(SubscriptionBillingInterval.monthly.rawValue, "monthly")
        XCTAssertEqual(SubscriptionRuleStatus.paused.rawValue, "paused")
        XCTAssertEqual(SubscriptionRuleStatus.cancelled.rawValue, "cancelled")
    }

    func testAIEnumsUseApiRawValues() {
        XCTAssertEqual(AIPlanStatus.autoConfirmCandidate.rawValue, "auto_confirm_candidate")
        XCTAssertEqual(AIPlanStatus.requiresConfirmation.rawValue, "requires_confirmation")
        XCTAssertEqual(AIActionType.createCashFlowItem.rawValue, "CreateCashFlowItem")
        XCTAssertEqual(AIActionType.generateNotificationRule.rawValue, "GenerateNotificationRule")
        XCTAssertEqual(AIActionType.setCashFlowStatus.rawValue, "SetCashFlowStatus")
        XCTAssertEqual(AIActionType.updateReimbursementStatus.rawValue, "UpdateReimbursementStatus")
        XCTAssertEqual(AIActionStatus.rolledBack.rawValue, "rolled_back")
    }

    func testNotificationEnumsUseApiRawValues() {
        XCTAssertEqual(NotificationRuleType.creditRepayment.rawValue, "credit_repayment")
        XCTAssertEqual(NotificationRuleType.cashFlow.rawValue, "cash_flow")
        XCTAssertEqual(NotificationChannel.inApp.rawValue, "in_app")
    }

    func testJSONValueRoundTripsNestedPayloads() throws {
        let payload: [String: JSONValue] = [
            "amount": .number(88),
            "currency": .string("CNY"),
            "metadata": .object(["auto": .bool(true)]),
        ]

        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: encoded)

        XCTAssertEqual(decoded, payload)
    }

    func testReportEnumsUseApiRawValues() {
        XCTAssertEqual(ReimbursementReportView.preReimbursement.rawValue, "pre_reimbursement")
        XCTAssertEqual(ReimbursementReportView.expectedNet.rawValue, "expected_net")
        XCTAssertEqual(ReimbursementReportView.personalNet.rawValue, "personal_net")
    }

    func testExportDatasetKeepsCsvFilename() {
        let dataset = ExportDataset(name: "entries", filename: "entries.csv")

        XCTAssertEqual(dataset.filename, "entries.csv")
    }

    func testIntentRecordResolverReportsIncompleteWhenLinksAreMissing() {
        // 草稿移除（v1.4.0 P5）：缺字段不再产 draft，而是标 incomplete，
        // 由调用方返回失败文案、不建单。
        let resolution = IntentRecordResolver.resolve(
            accountName: "招商",
            categoryName: "咖啡",
            accounts: [IntentNamedCandidate(id: "a1", name: "招商银行")],
            categories: []
        )

        XCTAssertEqual(resolution.status, .incomplete)
        XCTAssertEqual(resolution.accountID, "a1")
        XCTAssertNil(resolution.categoryID)
        XCTAssertEqual(resolution.missingFields, ["category"])
    }

    func testIntentRecordResolverConfirmsWhenAccountAndCategoryMatch() {
        let resolution = IntentRecordResolver.resolve(
            accountName: "工资卡",
            categoryName: "餐饮",
            accounts: [IntentNamedCandidate(id: "a1", name: "工资卡")],
            categories: [IntentNamedCandidate(id: "c1", name: "日常餐饮")]
        )

        XCTAssertEqual(resolution.status, .confirmed)
        XCTAssertEqual(resolution.accountID, "a1")
        XCTAssertEqual(resolution.categoryID, "c1")
        XCTAssertTrue(resolution.missingFields.isEmpty)
    }

    func testMonthWindowResolverUsesCurrentYearAndWholeMonth() throws {
        let now = DateFormatter.linoCoreTestDate.date(from: "2026-05-20")!
        let window = try XCTUnwrap(MonthWindowResolver.window(month: 2, now: now))

        XCTAssertEqual(DateFormatter.linoCoreTestDate.string(from: window.start), "2026-02-01")
        XCTAssertEqual(DateFormatter.linoCoreTestDate.string(from: window.end), "2026-02-28")
    }

    func testSpotlightTargetRoundTrips() throws {
        let target = SpotlightTargetID(type: "entry", id: "abc-123")
        let parsed = try XCTUnwrap(SpotlightTargetID.parse(target.uniqueIdentifier))

        XCTAssertEqual(parsed, target)
        XCTAssertNil(SpotlightTargetID.parse("entry.abc-123"))
    }
}

private extension DateFormatter {
    static let linoCoreTestDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // MonthWindowResolver now resolves in the device-local timezone
        // (audit §3.4 fix); construct and render the test dates in the same
        // local zone so the whole-month boundary assertions stay consistent.
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
