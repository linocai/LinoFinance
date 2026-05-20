import SwiftUI

@main
struct LinoFinanceApp: App {
    @State private var environment = AppEnvironment()
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @AppStorage("linofinance.showMenuBarExtra") private var showMenuBarExtra = true
#endif

    var body: some Scene {
#if os(macOS)
        WindowGroup("LinoF", id: "main") {
            MacRootView(environment: environment)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建记录") {
                    environment.beginNewEntry()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("新建现金流") {
                    environment.beginNewCashFlow()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("LinoF") {
                Button("总览") {
                    environment.selectedModule = .dashboard
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("账户") {
                    environment.selectedModule = .accounts
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("记账") {
                    environment.selectedModule = .entries
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("现金流") {
                    environment.selectedModule = .cashFlow
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("报销") {
                    environment.selectedModule = .reimbursements
                }
                .keyboardShortcut("5", modifiers: .command)

                Button("信用") {
                    environment.selectedModule = .credit
                }
                .keyboardShortcut("6", modifiers: .command)

                Button("分析") {
                    environment.selectedModule = .reports
                }
                .keyboardShortcut("7", modifiers: .command)

                Divider()

                Button("搜索") {
                    environment.isSearchFocused = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("AI 工作台") {
                    environment.beginAI()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
            CommandMenu("窗口") {
                Button("打开 Command Palette") {
                    openWindow(id: "command")
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("分析独立窗口") {
                    openWindow(id: "module", value: FinanceModule.reports)
                }
                Button("AI 独立窗口") {
                    openWindow(id: "module", value: FinanceModule.ai)
                }
                Button("信用独立窗口") {
                    openWindow(id: "module", value: FinanceModule.credit)
                }
            }
        }

        WindowGroup("模块", id: "module", for: FinanceModule.self) { module in
            MacModuleWindow(environment: environment, module: module.wrappedValue ?? .dashboard)
        }
        .windowStyle(.titleBar)

        Window("Command Palette", id: "command") {
            CommandPalette(environment: environment)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("LinoF", systemImage: "yensign.circle.fill", isInserted: $showMenuBarExtra) {
            MenuBarPopover(environment: environment, showMenuBarExtra: $showMenuBarExtra)
        }
#else
        WindowGroup {
            iOSRootView(environment: environment)
        }
#endif
    }
}

#if os(macOS)
private struct MacModuleWindow: View {
    @Bindable var environment: AppEnvironment
    let module: FinanceModule

    var body: some View {
        FinanceModuleContentView(environment: environment, module: module)
            .padding(FinanceSpacing.page)
            .frame(minWidth: 760, minHeight: 560)
            .background(FinanceTokens.Surface.base)
            .navigationTitle(module.title)
            .task {
                await environment.refreshPrimaryData()
            }
            .preferredColorScheme(environment.appearance.colorScheme)
            .tint(FinanceTokens.Brand.primary)
    }
}
#endif
