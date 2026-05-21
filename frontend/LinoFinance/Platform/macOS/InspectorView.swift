#if os(macOS)
import SwiftUI

struct InspectorView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        ScrollView {
            SelectionDetailView(selection: environment.inspectorSelection, environment: environment)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FinanceTokens.Surface.deepGlass)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(FinanceTokens.Stroke.hairline)
                .frame(width: 0.5)
        }
    }
}
#endif
