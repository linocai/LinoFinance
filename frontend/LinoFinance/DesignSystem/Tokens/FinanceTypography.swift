import SwiftUI

enum FinanceTypography {
    static var heroNumber: Font { .system(size: 38, weight: .bold, design: .rounded).monospacedDigit() }
    static var titleXL: Font { .system(size: 28, weight: .semibold, design: .rounded) }
    static var headline: Font { .system(.headline, design: .rounded).weight(.semibold) }
    static var bodyMono: Font { .body.monospacedDigit() }
    static var caption: Font { .caption.weight(.medium) }
}
