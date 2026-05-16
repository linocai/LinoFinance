import Foundation

public enum FinanceDefaults {
    public static let initialUSDCNYRate = Decimal(string: "6.8")!
    public static let aiAutoConfirmLimitCNY = Decimal(1000)
    public static let baseCurrency = CurrencyCode.cny
    public static let v1ExportFormat = "csv"
}

