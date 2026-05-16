import SwiftUI

struct NotificationsView: View {
    @Bindable var environment: AppEnvironment
    @State private var confirmation: ConfirmAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "通知", subtitle: "还款、现金流、报销、订阅和异常规则")
            HStack {
                Button {
                    environment.isShowingNewNotificationSheet = true
                } label: {
                    Label("新建通知规则", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }

            if environment.notificationsViewModel.rules.isEmpty {
                EmptyState(
                    title: "还没有通知规则",
                    message: "创建还款、现金流或订阅提醒，后续可接系统通知。",
                    systemImage: "bell.badge",
                    actionTitle: "新建规则",
                    action: { environment.isShowingNewNotificationSheet = true }
                )
            } else {
                List(environment.notificationsViewModel.rules, selection: Binding(
                    get: {
                        if case .notification(let rule) = environment.inspectorSelection {
                            return rule.id
                        }
                        return nil
                    },
                    set: { id in
                        guard let id, let rule = environment.notificationsViewModel.rules.first(where: { $0.id == id }) else { return }
                        environment.inspectorSelection = .notification(rule)
                    }
                )) { rule in
                    NotificationRuleRow(rule: rule)
                        .tag(rule.id)
                        .contextMenu {
                            if rule.status == "active" {
                                Button("暂停") { confirm(rule, "pause") }
                            } else if rule.status == "paused" {
                                Button("恢复") { confirm(rule, "resume") }
                            }
                            Button("取消", role: .destructive) { confirm(rule, "cancel") }
                        }
                }
                .listStyle(.inset)
            }

            if let message = environment.notificationsViewModel.errorMessage {
                ErrorBanner(message: message)
            }
        }
        .padding(24)
        .moduleFrame()
        .task {
            try? await environment.notificationsViewModel.refresh()
        }
        .alert(confirmation?.title ?? "确认操作", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), presenting: confirmation) { item in
            Button(item.confirmTitle, role: item.role) {
                item.action()
                confirmation = nil
            }
            Button("取消", role: .cancel) { confirmation = nil }
        } message: { item in
            Text(item.message)
        }
    }

    private func confirm(_ rule: NotificationRuleDTO, _ operation: String) {
        let title = operation == "pause" ? "暂停通知规则？" : operation == "resume" ? "恢复通知规则？" : "取消通知规则？"
        confirmation = ConfirmAction(title: title, message: "规则状态会同步到 API。", confirmTitle: title.replacingOccurrences(of: "？", with: ""), role: operation == "cancel" ? .destructive : nil) {
            Task { await perform(rule, operation) }
        }
    }

    private func perform(_ rule: NotificationRuleDTO, _ operation: String) async {
        do {
            switch operation {
            case "pause":
                try await environment.notificationsViewModel.pause(rule.id)
            case "resume":
                try await environment.notificationsViewModel.resume(rule.id)
            default:
                try await environment.notificationsViewModel.cancel(rule.id)
            }
        } catch {
            environment.notificationsViewModel.errorMessage = error.localizedDescription
            environment.lastErrorMessage = error.localizedDescription
        }
    }
}

private struct NotificationRuleRow: View {
    let rule: NotificationRuleDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(rule.status == "active" ? FinanceColor.brand : FinanceColor.pending)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.title)
                    .font(.headline)
                Text("\(rule.ruleType.financeStatusTitle) · \(rule.channel.financeStatusTitle) · \(rule.nextTriggerDate.map(FinanceFormatter.mediumDate) ?? "未排期")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusTag(status: rule.status)
        }
        .padding(.vertical, 6)
    }
}

struct NewNotificationRuleSheet: View {
    @Bindable var environment: AppEnvironment
    @State private var title = ""
    @State private var ruleType = "cash_flow"
    @State private var channel = "in_app"
    @State private var nextDate = Date()
    @State private var daysBefore = "3"
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建通知规则")
                .font(.title2.weight(.semibold))
            Form {
                TextField("标题", text: $title)
                Picker("类型", selection: $ruleType) {
                    ForEach(["credit_repayment", "cash_flow", "reimbursement", "subscription", "anomaly"], id: \.self) {
                        Text($0.financeStatusTitle).tag($0)
                    }
                }
                Picker("渠道", selection: $channel) {
                    ForEach(["in_app", "system", "email"], id: \.self) {
                        Text($0.financeStatusTitle).tag($0)
                    }
                }
                DatePicker("下次触发", selection: $nextDate, displayedComponents: .date)
                TextField("提前天数", text: $daysBefore)
                TextField("备注", text: $note)
            }
            if let errorMessage { ErrorBanner(message: errorMessage) }
            HStack {
                Spacer()
                Button("取消") { environment.isShowingNewNotificationSheet = false }
                Button("创建") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
    }

    private func submit() async {
        let triggerPayload: [String: JSONValueDTO] = [
            "days_before": .number(Double(daysBefore) ?? 3)
        ]
        let request = NotificationRuleCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            ruleType: ruleType,
            channel: channel,
            triggerPayload: triggerPayload,
            nextTriggerDate: nextDate,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        do {
            try await environment.notificationsViewModel.create(request)
            environment.isShowingNewNotificationSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
