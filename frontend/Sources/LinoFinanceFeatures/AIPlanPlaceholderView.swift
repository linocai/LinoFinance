import LinoFinanceDesignSystem
import SwiftUI

public struct AIPlanPlaceholderView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Plan")
                .font(.headline)
            Text("CreateEntry")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                StatusTag("low risk", style: .confirmed)
                StatusTag("auto candidate", style: .expected)
            }
        }
        .padding()
    }
}
