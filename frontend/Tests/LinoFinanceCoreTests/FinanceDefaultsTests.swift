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
}
