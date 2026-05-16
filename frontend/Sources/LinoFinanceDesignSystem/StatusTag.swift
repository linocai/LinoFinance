import SwiftUI

public enum FinanceStatusStyle {
    case draft
    case confirmed
    case expected
    case settled
    case warning
}

public struct StatusTag: View {
    public let title: String
    public let style: FinanceStatusStyle

    public init(_ title: String, style: FinanceStatusStyle) {
        self.title = title
        self.style = style
    }

    public var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch style {
        case .draft:
            return .secondary
        case .confirmed, .settled:
            return .green
        case .expected:
            return .blue
        case .warning:
            return .orange
        }
    }

    private var background: Color {
        foreground.opacity(0.12)
    }
}

