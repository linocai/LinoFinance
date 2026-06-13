import SwiftUI

// LinoFinance v2 — app entry (P2).
//
// macOS root is now the REAL app shell: MacGlassScene (floating sidebar + bloom +
// glass) with the Overview dashboard as the .overview destination and the 记一笔
// button swapping the content area to AddEntryPage (right-side full page, R1 ·去模
//态 — no longer a sheet). Other sidebar destinations show their real screens.
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
        .commands {
            CommandMenu("视图") {
                Button("记一笔") { model.isAddEntryPresented = true }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                ForEach(Array(SidebarDestination.allCases.enumerated()), id: \.element) { index, dest in
                    Button(dest.title) { model.selection = dest }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            #if DEBUG
            CommandMenu("调试") {
                Button("DesignSystem 预览") { showShowcase = true }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            #endif
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

    var body: some View {
        // Nav selection + add-entry presentation live on the model so the menu
        // commands (⌘1–8 / ⌘N) can drive them.
        MacGlassScene(selection: $model.selection, onAddEntry: { model.isAddEntryPresented = true }) {
            content
        }
        // Tapping any sidebar nav row while the 记一笔 page is up leaves the page
        // and shows the chosen destination (the page is no longer a modal).
        .onChange(of: model.selection) { _, _ in
            model.isAddEntryPresented = false
        }
    }

    // 记一笔 is now a RIGHT-SIDE PAGE (R1 ·去模态): the sidebar stays visible and
    // the content area swaps to AddEntryPage. The old `.sheet` is gone.
    @ViewBuilder
    private var content: some View {
        if model.isAddEntryPresented {
            AddEntryPage(
                model: model,
                onClose: { model.isAddEntryPresented = false },
                onSubmitted: { Task { await model.refreshAll() } }
            )
        } else {
            destinationContent
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch model.selection {
        case .overview:      OverviewView(model: model)
        case .accounts:      AccountsScreen(model: model)          // P3 (D2) — also opens 对账
        case .cashFlow:      CashFlowScreen(model: model)          // P3 (D4)
        case .ledger:        LedgerScreen(model: model)            // P3 (D5)
        case .reimbursements: ReimbursementsScreen(model: model)   // P4 (D6)
        case .cycles:        CyclesScreen(model: model)            // P4 (D7)
        case .reports:       ReportsScreen(model: model)           // P4 (D8)
        case .settings:      SettingsScreen(model: model)              // P5 (D10)
        }
    }
}
#else
private struct IOSAppShell: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // Px: the core 5 screens are wired (总览 / 账户 / 现金流 / 报表 + 记一笔 via
        // the raised center button as a full-screen sheet). 「更多」(top-trailing)
        // reaches the secondary features (流水 real, others placeholder).
        IOSTabScaffold(
            onAddEntry: { model.isAddEntryPresented = true },
            overview: { OverviewIOSView(model: model) },
            accounts: { AccountsIOSView(model: model) },
            cashFlow: { CashFlowIOSView(model: model) },
            reports: { ReportsIOSView(model: model) },
            more: { MoreIOSView(model: model) }
        )
        .sheet(isPresented: $model.isAddEntryPresented) {
            AddEntryIOSSheet(model: model) {
                Task { await model.refreshAll() }
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
