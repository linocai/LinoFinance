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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }
}
#endif
