import LinoFinanceDesignSystem
import SwiftUI

public struct NotificationRulePlaceholderView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notification Rule")
                .font(.headline)
            Text("Credit repayment reminder")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                StatusTag("active", style: .confirmed)
                StatusTag("in app", style: .expected)
            }
        }
        .padding()
    }
}
