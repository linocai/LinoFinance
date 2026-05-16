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
}
