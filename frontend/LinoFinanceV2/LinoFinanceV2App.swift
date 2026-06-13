import SwiftUI

// LinoFinance v2 — empty multiplatform shell (P0 scaffolding only).
//
// P0 scope: prove the new target builds, the shared Core layer compiles into it,
// and that auth + API are reachable. No DesignSystem, no real screens — those are P1+.
// macOS: floating empty shell. iOS: TabView empty shell.

@main
struct LinoFinanceV2App: App {
    @StateObject private var probe = APIReachabilityProbe()

    var body: some Scene {
        WindowGroup {
            RootShell()
                .environmentObject(probe)
                .task { await probe.run() }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}

/// Minimal platform-split shell. macOS shows a single floating placeholder card;
/// iOS shows a TabView placeholder. Real navigation (floating glass sidebar /
/// iOS TabBar with the "记一笔" button) lands in P1/Px.
private struct RootShell: View {
    var body: some View {
        #if os(macOS)
        MacShell()
        #else
        iOSShell()
        #endif
    }
}

#if os(macOS)
private struct MacShell: View {
    var body: some View {
        ZStack {
            Color(.windowBackgroundColor).ignoresSafeArea()
            ProbePanel()
                .frame(maxWidth: 420)
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
#else
private struct iOSShell: View {
    var body: some View {
        TabView {
            ProbePanel()
                .padding()
                .tabItem { Label("总览", systemImage: "chart.pie") }
        }
    }
}
#endif

/// P0 connectivity readout — confirms the shared Core layer (SecureTokenStore +
/// LinoAPIClient) compiles and that auth + API are reachable from the new target.
private struct ProbePanel: View {
    @EnvironmentObject private var probe: APIReachabilityProbe

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LinoFinance v2")
                .font(.system(size: 27, weight: .semibold))
            Text("P0 工程脚手架空壳")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Divider()
            Label(probe.baseURLDescription, systemImage: "network")
                .font(.system(size: 13).monospacedDigit())
            Label(probe.tokenDescription, systemImage: "key")
                .font(.system(size: 13))
            Label(probe.statusDescription, systemImage: probe.statusSymbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(probe.statusColor)
        }
    }
}

/// Drives one read-only call against the backend to prove networking + auth.
/// Tries the authenticated `GET /dashboard/summary`; if that fails, falls back
/// to the unauthenticated `GET /health` so the panel still reports reachability.
@MainActor
final class APIReachabilityProbe: ObservableObject {
    enum State { case idle, running, ok(String), failed(String) }

    @Published private(set) var state: State = .idle

    private let baseURL: URL
    private let token: String?

    init() {
        self.baseURL = APIReachabilityProbe.resolveBaseURL()
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
            // Fall back to the unauthenticated health endpoint so we can still
            // distinguish "network down" from "auth missing/expired".
            do {
                let health = try await client.health()
                state = .failed("鉴权调用失败，但 /health=\(health.status) 可达：\(error.localizedDescription)")
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
        // Mirror the outcome to stderr so the P0 reachability probe can be
        // verified from a headless launch (no GUI inspection needed).
        FileHandle.standardError.write(Data("[LinoFinanceV2.P0Probe] \(statusDescription)\n".utf8))
    }

    /// Same resolution chain as v1 (env → UserDefaults → Info.plist → prod fallback),
    /// kept local so the v2 shell does not pull in v1's AppEnvironment.
    private static func resolveBaseURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let value = env["LINOFINANCE_API_BASE_URL"], let url = URL(string: value) {
            return url
        }
        if let value = UserDefaults.standard.string(forKey: "linofinance.apiBaseURL"),
           let url = URL(string: value) {
            return url
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "LinoFinanceAPIBaseURL") as? String,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "https://lf.linotsai.top/api/v1")!
    }
}
