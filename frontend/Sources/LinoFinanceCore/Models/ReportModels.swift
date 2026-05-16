import Foundation

public enum ReimbursementReportView: String, Codable, Equatable, Sendable {
    case preReimbursement = "pre_reimbursement"
    case expectedNet = "expected_net"
    case approvedNet = "approved_net"
    case receivedNet = "received_net"
    case personalNet = "personal_net"
}

public struct ReportCurrencySummary: Codable, Equatable, Sendable {
    public let currency: CurrencyCode
    public let amount: Decimal
    public let convertedCNYAmount: Decimal

    public init(currency: CurrencyCode, amount: Decimal, convertedCNYAmount: Decimal) {
        self.currency = currency
        self.amount = amount
        self.convertedCNYAmount = convertedCNYAmount
    }
}

public struct MonthlyOverviewReport: Codable, Equatable, Sendable {
    public let dateFrom: Date
    public let dateTo: Date
    public let incomeCNY: Decimal
    public let expenseCNY: Decimal
    public let netIncomeCNY: Decimal
    public let personalNetExpenseCNY: Decimal
    public let futureNetCNY: Decimal
    public let creditLiabilityCNY: Decimal

    public init(
        dateFrom: Date,
        dateTo: Date,
        incomeCNY: Decimal,
        expenseCNY: Decimal,
        netIncomeCNY: Decimal,
        personalNetExpenseCNY: Decimal,
        futureNetCNY: Decimal,
        creditLiabilityCNY: Decimal
    ) {
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.incomeCNY = incomeCNY
        self.expenseCNY = expenseCNY
        self.netIncomeCNY = netIncomeCNY
        self.personalNetExpenseCNY = personalNetExpenseCNY
        self.futureNetCNY = futureNetCNY
        self.creditLiabilityCNY = creditLiabilityCNY
    }
}

public struct CategoryExpenseRow: Codable, Equatable, Sendable {
    public let categoryID: String
    public let categoryName: String
    public let expenseCNY: Decimal
    public let currencies: [ReportCurrencySummary]

    public init(
        categoryID: String,
        categoryName: String,
        expenseCNY: Decimal,
        currencies: [ReportCurrencySummary]
    ) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.expenseCNY = expenseCNY
        self.currencies = currencies
    }
}

public struct CashFlowPressureWindow: Codable, Equatable, Sendable {
    public let days: Int
    public let dateFrom: Date
    public let dateTo: Date
    public let expectedInflowCNY: Decimal
    public let expectedOutflowCNY: Decimal
    public let netCNY: Decimal
    public let itemCount: Int

    public init(
        days: Int,
        dateFrom: Date,
        dateTo: Date,
        expectedInflowCNY: Decimal,
        expectedOutflowCNY: Decimal,
        netCNY: Decimal,
        itemCount: Int
    ) {
        self.days = days
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.expectedInflowCNY = expectedInflowCNY
        self.expectedOutflowCNY = expectedOutflowCNY
        self.netCNY = netCNY
        self.itemCount = itemCount
    }
}

public struct ReimbursementReport: Codable, Equatable, Sendable {
    public let view: ReimbursementReportView
    public let grossReimbursableExpenseCNY: Decimal
    public let expectedOffsetCNY: Decimal
    public let approvedOffsetCNY: Decimal
    public let receivedOffsetCNY: Decimal
    public let selectedNetExpenseCNY: Decimal

    public init(
        view: ReimbursementReportView,
        grossReimbursableExpenseCNY: Decimal,
        expectedOffsetCNY: Decimal,
        approvedOffsetCNY: Decimal,
        receivedOffsetCNY: Decimal,
        selectedNetExpenseCNY: Decimal
    ) {
        self.view = view
        self.grossReimbursableExpenseCNY = grossReimbursableExpenseCNY
        self.expectedOffsetCNY = expectedOffsetCNY
        self.approvedOffsetCNY = approvedOffsetCNY
        self.receivedOffsetCNY = receivedOffsetCNY
        self.selectedNetExpenseCNY = selectedNetExpenseCNY
    }
}

public struct SubscriptionReport: Codable, Equatable, Sendable {
    public let asOf: Date
    public let activeSubscriptionCount: Int
    public let monthlyTotalCNY: Decimal
    public let annualTotalCNY: Decimal
    public let upcoming30DaysCNY: Decimal

    public init(
        asOf: Date,
        activeSubscriptionCount: Int,
        monthlyTotalCNY: Decimal,
        annualTotalCNY: Decimal,
        upcoming30DaysCNY: Decimal
    ) {
        self.asOf = asOf
        self.activeSubscriptionCount = activeSubscriptionCount
        self.monthlyTotalCNY = monthlyTotalCNY
        self.annualTotalCNY = annualTotalCNY
        self.upcoming30DaysCNY = upcoming30DaysCNY
    }
}

public struct ExportDataset: Codable, Equatable, Sendable {
    public let name: String
    public let filename: String

    public init(name: String, filename: String) {
        self.name = name
        self.filename = filename
    }
}
