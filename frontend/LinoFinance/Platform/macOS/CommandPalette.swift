#if os(macOS)
import SwiftUI

struct CommandPalette: View {
    @Bindable var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var items: [CommandPaletteItem] = []
    @State private var selectedID: CommandPaletteItem.ID?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let repository: FinanceRepository

    init(environment: AppEnvironment) {
        self.environment = environment
        self.repository = FinanceRepository(apiClient: environment.apiClient)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            Divider()

            List(selection: $selectedID) {
                ForEach(items) { item in
                    CommandPaletteRow(item: item)
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedID = item.id
                        }
                        .onSubmit {
                            Task { await executeSelected() }
                        }
                }
            }
            .listStyle(.plain)
            .overlay {
                if items.isEmpty && !isLoading {
                    EmptyState(
                        title: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "输入命令或搜索" : "没有命中",
                        message: "可以跳转模块、搜索后端数据，或直接创建 AI 计划。",
                        systemImage: "command"
                    )
                    .padding()
                }
            }

            Divider()

            footer
        }
        .frame(width: 680, height: 560)
        .background(FinanceTokens.Surface.base)
        .task(id: query) {
            await reloadItems()
        }
        .onAppear {
            items = localItems(for: "")
            selectedID = items.first?.id
        }
        .onSubmit {
            Task { await executeSelected() }
        }
        .onMoveCommand { direction in
            moveSelection(direction)
        }
        .onExitCommand {
            dismiss()
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "command")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FinanceTokens.Brand.primary)
            TextField("搜索模块、记录，或输入自然语言创建 AI 计划", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(FinanceTokens.State.warning)
            } else {
                Label("↑↓ 选择 · Return 执行 · Shift Return 保存草稿 · Esc 关闭", systemImage: "keyboard")
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }
            Spacer()
            Button("保存草稿") {
                saveDraft()
            }
            .keyboardShortcut(.return, modifiers: [.shift])
            Button("执行") {
                Task { await executeSelected() }
            }
            .keyboardShortcut(.return, modifiers: [])
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @MainActor
    private func reloadItems() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var nextItems = localItems(for: trimmed)
        guard !trimmed.isEmpty else {
            items = nextItems
            selectedID = items.first?.id
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            try await Task.sleep(for: .milliseconds(180))
            let response = try await repository.search(query: trimmed, limit: 20)
            nextItems.append(contentsOf: response.items.map(CommandPaletteItem.remote))
            items = deduplicated(nextItems)
            selectedID = items.first?.id
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            items = nextItems
            selectedID = items.first?.id
            errorMessage = error.localizedDescription
        }
    }

    private func localItems(for query: String) -> [CommandPaletteItem] {
        let modules = FinanceModule.allCases
            .filter { module in
                query.isEmpty ||
                module.title.localizedCaseInsensitiveContains(query) ||
                module.rawValue.localizedCaseInsensitiveContains(query)
            }
            .map(CommandPaletteItem.module)

        var output = modules
        if !query.isEmpty {
            output.append(.aiPlanDraft(query))
        }
        output.append(contentsOf: recentDrafts().map(CommandPaletteItem.recentDraft))
        return output
    }

    private func deduplicated(_ items: [CommandPaletteItem]) -> [CommandPaletteItem] {
        var seen = Set<CommandPaletteItem.ID>()
        return items.filter { item in
            guard !seen.contains(item.id) else { return false }
            seen.insert(item.id)
            return true
        }
    }

    @MainActor
    private func executeSelected() async {
        guard let selected = items.first(where: { $0.id == selectedID }) ?? items.first else { return }
        do {
            switch selected.kind {
            case .module(let module):
                environment.selectedModule = module
                environment.inspectorSelection = .module(module)
                await environment.refreshCurrentModule()
                dismiss()
            case .remote(let hit):
                await select(hit)
                dismiss()
            case .aiPlanDraft(let text), .recentDraft(let text):
                let plan = try await environment.aiViewModel.createPlan(sourceText: text)
                rememberDraft(text)
                environment.selectedModule = .ai
                environment.inspectorSelection = .aiPlan(plan)
                dismiss()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func select(_ hit: SearchHitDTO) async {
        switch hit.type {
        case "account":
            environment.selectedModule = .accounts
            if let account = environment.accountsViewModel.accounts.first(where: { $0.id == hit.id }) {
                environment.inspectorSelection = .account(account)
            }
        case "entry":
            environment.selectedModule = .entries
            if let entry = environment.entriesViewModel.entries.first(where: { $0.id == hit.id }) {
                environment.inspectorSelection = .entry(entry)
            }
        case "cash_flow_item":
            environment.selectedModule = .cashFlow
            if let item = environment.cashFlowViewModel.items.first(where: { $0.id == hit.id }) {
                environment.inspectorSelection = .cashFlow(item)
            }
        case "reimbursement_claim":
            environment.selectedModule = .reimbursements
            if let claim = environment.reimbursementsViewModel.claims.first(where: { $0.id == hit.id }) {
                environment.inspectorSelection = .reimbursement(claim)
            }
        case "ai_plan":
            environment.selectedModule = .ai
            if let plan = environment.aiViewModel.plans.first(where: { $0.id == hit.id }) {
                environment.inspectorSelection = .aiPlan(plan)
            }
        case "notification_rule":
            environment.selectedModule = .notifications
            if let rule = environment.notificationsViewModel.rules.first(where: { $0.id == hit.id }) {
                environment.inspectorSelection = .notification(rule)
            }
        default:
            break
        }
        await environment.refreshCurrentModule()
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !items.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max(0, currentIndex - 1)
        case .down:
            nextIndex = min(items.count - 1, currentIndex + 1)
        default:
            return
        }
        selectedID = items[nextIndex].id
    }

    private func saveDraft() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rememberDraft(trimmed)
        errorMessage = "已保存到最近草稿"
    }

    private func recentDrafts() -> [String] {
        UserDefaults.standard.stringArray(forKey: "linofinance.commandPalette.recents") ?? []
    }

    private func rememberDraft(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var drafts = recentDrafts().filter { $0 != trimmed }
        drafts.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(drafts.prefix(20)), forKey: "linofinance.commandPalette.recents")
    }
}

private struct CommandPaletteItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case module(FinanceModule)
        case aiPlanDraft(String)
        case remote(SearchHitDTO)
        case recentDraft(String)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .module(let module): "module-\(module.rawValue)"
        case .aiPlanDraft(let text): "ai-draft-\(text)"
        case .remote(let hit): "remote-\(hit.type)-\(hit.id)"
        case .recentDraft(let text): "recent-\(text)"
        }
    }

    var category: String {
        switch kind {
        case .module: "模块"
        case .aiPlanDraft: "AI"
        case .remote(let hit): hit.type.financeStatusTitle
        case .recentDraft: "最近"
        }
    }

    var title: String {
        switch kind {
        case .module(let module): module.title
        case .aiPlanDraft: "创建 AI 计划"
        case .remote(let hit): hit.title
        case .recentDraft(let text): text
        }
    }

    var subtitle: String {
        switch kind {
        case .module(let module): "跳转到 \(module.title)"
        case .aiPlanDraft(let text): text
        case .remote(let hit): hit.subtitle ?? hit.target
        case .recentDraft: "从最近草稿重新创建 AI 计划"
        }
    }

    var symbolName: String {
        switch kind {
        case .module(let module): module.symbolName
        case .aiPlanDraft: "sparkles"
        case .remote(let hit):
            switch hit.type {
            case "account": "wallet.pass.fill"
            case "entry": "square.and.pencil"
            case "cash_flow_item": "arrow.left.arrow.right.circle.fill"
            case "reimbursement_claim": "arrow.uturn.left.circle.fill"
            case "ai_plan": "sparkles"
            case "notification_rule": "bell.badge.fill"
            default: "magnifyingglass"
            }
        case .recentDraft: "clock.arrow.circlepath"
        }
    }

    static func module(_ module: FinanceModule) -> CommandPaletteItem {
        CommandPaletteItem(kind: .module(module))
    }

    static func remote(_ hit: SearchHitDTO) -> CommandPaletteItem {
        CommandPaletteItem(kind: .remote(hit))
    }

    static func aiPlanDraft(_ text: String) -> CommandPaletteItem {
        CommandPaletteItem(kind: .aiPlanDraft(text))
    }

    static func recentDraft(_ text: String) -> CommandPaletteItem {
        CommandPaletteItem(kind: .recentDraft(text))
    }
}

private struct CommandPaletteRow: View {
    let item: CommandPaletteItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbolName)
                .font(.headline)
                .foregroundStyle(FinanceTokens.Brand.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(FinanceTokens.Brand.soft))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                        .font(FinanceTypography.headline)
                        .foregroundStyle(FinanceTokens.Text.primary)
                    Spacer()
                    Text(item.category)
                        .font(FinanceTypography.caption)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                }
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(FinanceTokens.Text.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }
}
#endif
