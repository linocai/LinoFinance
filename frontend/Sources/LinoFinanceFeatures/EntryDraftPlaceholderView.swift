import LinoFinanceDesignSystem
import SwiftUI

public struct EntryDraftPlaceholderView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Entry Draft")
                .font(.headline)
            StatusTag("draft", style: .draft)
            Text("Draft entries never affect account balances or official reports.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

