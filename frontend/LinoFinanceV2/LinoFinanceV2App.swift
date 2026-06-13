import SwiftUI

// LinoFinance v2 — app entry (P2).
//
// macOS root is now the REAL app shell: MacGlassScene (floating sidebar + bloom +
// glass) with the Overview dashboard as the .overview destination and the 记一笔
// button presenting the AddEntrySheet. Other sidebar destinations show glass
// placeholders until P3–P5.
//
// The P1 DesignSystem showcase stays reachable in DEBUG via a CommandMenu entry
// ("调试 ▸ DesignSystem 预览") so it remains a DS visual-regression surface.
//
// iOS keeps the P1 IOSTabScaffold skeleton (real iOS screens land in Px). Overview /
// AddEntry / AppModel are cross-platform-compiled; macOS-only UI is #if os(macOS)-gated.

@main
struct LinoFinanceV2App: App {
    @StateObject private var model = AppModel()
    @StateObject private var probe = APIReachabilityProbe()

    #if DEBUG && os(macOS)
    @State private var showShowcase = false
    #endif

    var body: some Scene {
        WindowGroup {
            RootShell(model: model)
                .environmentObject(probe)
                .task { await probe.run() }
                .task { await model.refreshAll() }
            #if DEBUG && os(macOS)
                .sheet(isPresented: $showShowcase) {
                    DesignSystemShowcaseView()
                        .environmentObject(probe)
                        .frame(minWidth: 1160, minHeight: 680)
                }
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        #if DEBUG && os(macOS)
        .commands {
            CommandMenu("调试") {
                Button("DesignSystem 预览") { showShowcase = true }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}

/// Root selector — real shell on both platforms (the P0 connectivity shell is gone;
/// connectivity is now reflected in the Overview's loading/error state).
private struct RootShell: View {
    @ObservedObject var model: AppModel

    var body: some View {
        #if os(macOS)
        MacAppShell(model: model)
        #else
        IOSAppShell(model: model)
        #endif
    }
}

#if os(macOS)
private struct MacAppShell: View {
    @ObservedObject var model: AppModel
    @State private var selection: SidebarDestination = .overview
    @State private var showAddEntry = false

    var body: some View {
        MacGlassScene(selection: $selection, onAddEntry: { showAddEntry = true }) {
            content
        }
        .sheet(isPresented: $showAddEntry) {
            AddEntrySheet(model: model) {
                Task { await model.refreshAll() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .overview:
            OverviewView(model: model)
        default:
            PlaceholderScreen(destination: selection)
        }
    }
}
#else
private struct IOSAppShell: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // P1 TabBar skeleton retained; real iOS screens land in Px. Overview content
        // is compiled here too so cross-platform builds stay green.
        IOSTabScaffold(
            onAddEntry: {},
            overview: { OverviewView(model: model) },
            accounts: { iOSPlaceholder("账户") },
            cashFlow: { iOSPlaceholder("现金流") },
            reports: { iOSPlaceholder("报表") }
        )
    }

    private func iOSPlaceholder(_ title: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("占位 · Px 接真实屏")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }
}
#endif

/// P0 connectivity probe — retained because the DEBUG DesignSystem showcase's
/// ProbeReadout still consumes it via the environment. Drives one read-only call
/// against the backend to confirm networking + auth.
@MainActor
final class APIReachabilityProbe: ObservableObject {
    enum State { case idle, running, ok(String), failed(String) }

    @Published private(set) var state: State = .idle

    private let baseURL: URL
    private let token: String?

    init() {
        self.baseURL = AppModel.resolveBaseURL()
        self.token = SecureTokenStore.shared.readEffectiveToken()
    }

    var baseURLDescription: String { "API: \(baseURL.absoluteString)" }

    var tokenDescription: String {
        token == nil ? "鉴权: 未找到本机 token" : "鉴权: 已读到本机 token"
    }

    var statusDescription: String {
        switch state {
        case .idle: "等待探测…"
        case .running: "探测中…"
        case .ok(let msg): "可达: \(msg)"
        case .failed(let msg): "失败: \(msg)"
        }
    }

    var statusSymbol: String {
        switch state {
        case .idle, .running: "hourglass"
        case .ok: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var statusColor: Color {
        switch state {
        case .ok: .green
        case .failed: .red
        default: .secondary
        }
    }

    func run() async {
        state = .running
        let client = LinoAPIClient(baseURL: baseURL, authToken: token)
        do {
            let summary = try await client.fetchDashboardSummary()
            state = .ok("dashboard/summary 净资产 CNY \(summary.netWorthCny.value)")
        } catch {
            do {
                let health = try await client.health()
                state = .failed("鉴权调用失败，但 /health=\(health.status) 可达：\(error.localizedDescription)")
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
