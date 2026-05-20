import SwiftUI

struct PrivacyActivityMonitor: ViewModifier {
    let environment: AppEnvironment

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    environment.recordUserActivity()
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).onChanged { _ in
                    environment.recordUserActivity()
                }
            )
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    await MainActor.run {
                        environment.enforceIdlePrivacyLock()
                    }
                }
            }
    }
}

extension View {
    func privacyActivityMonitor(environment: AppEnvironment) -> some View {
        modifier(PrivacyActivityMonitor(environment: environment))
    }
}
