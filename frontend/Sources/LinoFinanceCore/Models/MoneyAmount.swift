import Foundation

public enum CurrencyCode: String, Codable, Equatable, Sendable {
    case cny = "CNY"
    case usd = "USD"

    public var symbol: String {
        switch self {
        case .cny:
            return "¥"
        case .usd:
            return "$"
        }
    }
}

public struct MoneyAmount: Codable, Equatable, Sendable {
    public let amountMinor: Int64
    public let currency: CurrencyCode
    public let convertedCNYMinor: Int64?
    public let exchangeRate: Decimal?

    public init(
        amountMinor: Int64,
        currency: CurrencyCode,
        convertedCNYMinor: Int64? = nil,
        exchangeRate: Decimal? = nil
    ) {
        self.amountMinor = amountMinor
        self.currency = currency
        self.convertedCNYMinor = convertedCNYMinor
        self.exchangeRate = exchangeRate
    }

    public var formattedOriginal: String {
        "\(currency.symbol)\(Self.formatMinor(amountMinor))"
    }

    public var formattedConvertedCNY: String? {
        guard let convertedCNYMinor else {
            return nil
        }
        return "about ¥\(Self.formatMinor(convertedCNYMinor))"
    }

    private static func formatMinor(_ minor: Int64) -> String {
        let sign = minor < 0 ? "-" : ""
        let absMinor = Swift.abs(minor)
        let major = absMinor / 100
        let cents = absMinor % 100
        return "\(sign)\(major).\(String(format: "%02d", cents))"
    }
}
