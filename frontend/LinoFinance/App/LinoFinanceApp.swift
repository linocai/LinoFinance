import SwiftUI

@main
struct LinoFinanceApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
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
        }
    }
}
