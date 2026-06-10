import SwiftUI

struct SettingsView: View {
    @Bindable var environment: AppEnvironment
    @State private var apiBaseURL = ""
    @State private var usdRate = "6.8"
    @State private var errorMessage: String?
    @State private var configMessage: String?

    var body: some View {
        #if os(iOS)
        iOSContent
        #else
        macOSContent
        #endif
    }

#if os(iOS)
    private var iOSContent: some View {
        Form {
            Section {
                HStack {
                    Text("API 连接")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task {
                            do { try await environment.settingsViewModel.refresh() }
                            catch { environment.lastErrorMessage = error.localizedDescription }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("刷新连接状态")
                }
                DetailLine(title: "地址", value: environment.apiClient.baseURL.absoluteString)
                DetailLine(title: "Token", value: environment.apiClient.authToken == nil ? "未配置" : "已配置")
                DetailLine(title: "状态", value: environment.settingsViewModel.health?.status ?? "未知")
                DetailLine(title: "环境", value: environment.settingsViewModel.health?.environment ?? "未知")
                if let health = environment.settingsViewModel.health {
                    DetailLine(title: "鉴权", value: health.authRequired == true ? "已启用" : "未启用")
                    DetailLine(title: "限流", value: health.rateLimitEnabled == true ? "已启用" : "未启用")
                    DetailLine(title: "APNs", value: apnsStatus(health))
                }
                if let message = environment.lastErrorMessage {
                    ErrorBanner(message: message)
                }
            } header: {
                settingsHeader(title: "设置", subtitle: "API 连接、AI 配置、汇率和运行状态")
            }

            Section("连接配置") {
                TextField("API 地址", text: $apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                Button {
                    Task { await saveAPIConfiguration() }
                } label: {
                    Label("保存并重连", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if let configMessage {
                    Text(configMessage)
                        .font(.caption)
                        .foregroundStyle(FinanceTokens.State.income)
                }
            }

            Section("账号") {
                if environment.isAdminSession {
                    Text("你正在使用管理员 Token 直连")
                        .font(.subheadline.weight(.semibold))
                    Button(role: .destructive) {
                        Task { await environment.exitAdminMode() }
                    } label: {
                        Label("退出管理员模式", systemImage: "key.slash")
                            .frame(maxWidth: .infinity)
                    }
                } else if let user = environment.authUser {
                    DetailLine(title: "名称", value: user.displayName ?? "未提供")
                    DetailLine(title: "邮箱", value: user.email ?? "未提供")
                    DetailLine(title: "Apple ID", value: user.appleUserId)
                    Button(role: .destructive) {
                        Task { await environment.logout() }
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if environment.authUser != nil {
                Section("已登录设备") {
                    AuthSessionsSection(environment: environment)
                }
            }

            Section {
                DisclosureGroup("高级设置 / 管理员 Token") {
                    AdminTokenEntryView(environment: environment)
                }
            }

            Section("外观与隐私") {
                Picker("外观", selection: $environment.appearance) {
                    ForEach(FinanceAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                Toggle("使用大数字样式", isOn: $environment.useHeroNumbers)
                Toggle("启用隐私模糊", isOn: $environment.privacyMaskEnabled)
                Picker("解锁方式", selection: $environment.privacyUnlockMethod) {
                    ForEach(PrivacyUnlockMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                Toggle("进入后台自动模糊", isOn: $environment.privacyAutoMaskOnBackground)
                Picker("长时间无操作自动模糊", selection: $environment.privacyIdleLockInterval) {
                    ForEach(PrivacyIdleLockInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                Button {
                    environment.lockPrivacy()
                } label: {
                    Label("立即隐藏金额", systemImage: "eye.slash.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!environment.privacyMaskEnabled)
            }

            Section("Widget & 通知") {
                Toggle("Widget 自动更新", isOn: $environment.widgetAutoUpdateEnabled)
                Stepper(value: $environment.widgetRefreshMinutes, in: 5...120, step: 5) {
                    DetailLine(title: "刷新间隔", value: "\(environment.widgetRefreshMinutes) 分钟")
                }
                Stepper(value: $environment.liveActivityReminderDays, in: 1...30) {
                    DetailLine(title: "Live Activity 提前", value: "\(environment.liveActivityReminderDays) 天")
                }
                Toggle("Dynamic Island AI 计划提示", isOn: $environment.dynamicIslandAIEnabled)
                Toggle("系统推送", isOn: $environment.systemPushEnabled)
                Button {
                    Task { await requestPushRegistration() }
                } label: {
                    Label("授权并注册本机", systemImage: "bell.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!environment.systemPushEnabled || environment.pushNotificationViewModel.isRegistering)
                if let device = environment.pushNotificationViewModel.lastRegisteredDevice {
                    DetailLine(title: "最近注册", value: FinanceFormatter.mediumDate(device.lastSeenAt))
                } else if let status = environment.pushNotificationViewModel.statusMessage {
                    DetailLine(title: "注册状态", value: status)
                }
                if let message = environment.pushNotificationViewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }

            Section("AI 配置") {
                if let config = environment.settingsViewModel.aiConfig {
                    DetailLine(title: "Provider", value: config.provider)
                    DetailLine(title: "模型", value: config.model ?? "未配置")
                    DetailLine(title: "端点", value: config.baseUrlConfigured ? "已配置" : "未配置")
                    DetailLine(title: "API Key", value: config.apiKeyConfigured ? "已配置" : "未配置")
                    DetailLine(title: "自动确认阈值", value: FinanceFormatter.money(config.autoConfirmLimitCny))
                } else {
                    Text("尚未读取 AI 配置")
                        .foregroundStyle(FinanceTokens.Text.secondary)
                }
            }

            Section("手动汇率") {
                TextField("USD/CNY", text: $usdRate)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                Button {
                    Task { await createRate() }
                } label: {
                    Label("写入今日汇率", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                ForEach(environment.settingsViewModel.rates.prefix(8)) { rate in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(rate.fromCurrency.rawValue)/\(rate.toCurrency.rawValue)")
                                .font(.headline.monospaced())
                            Spacer()
                            Text(FinanceFormatter.shortDate(rate.date))
                                .font(.caption)
                                .foregroundStyle(FinanceTokens.Text.secondary)
                        }
                        Text(NSDecimalNumber(decimal: rate.rate.value).stringValue)
                            .font(.body.monospacedDigit())
                    }
                }
            }

            if let message = errorMessage ?? environment.settingsViewModel.errorMessage {
                Section {
                    ErrorBanner(message: message)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(FinanceTokens.Surface.base)
        .moduleFrame()
        .task {
            syncDrafts()
            try? await environment.settingsViewModel.refresh()
            await environment.refreshSessions()
        }
    }

    private func settingsHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(FinanceTokens.Text.secondary)
                .textCase(nil)
        }
        .padding(.top, 8)
    }
#endif

    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "设置", subtitle: "API 连接、AI 配置、汇率和运行状态")

                FinancePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("API 连接")
                            .font(.headline)
                        DetailLine(title: "地址", value: environment.apiClient.baseURL.absoluteString)
                        DetailLine(title: "Token", value: environment.apiClient.authToken == nil ? "未配置" : "已配置")
                        DetailLine(title: "状态", value: environment.settingsViewModel.health?.status ?? "未知")
                        DetailLine(title: "环境", value: environment.settingsViewModel.health?.environment ?? "未知")
                        if let health = environment.settingsViewModel.health {
                            DetailLine(title: "鉴权", value: health.authRequired == true ? "已启用" : "未启用")
                            DetailLine(title: "限流", value: health.rateLimitEnabled == true ? "已启用" : "未启用")
                            DetailLine(title: "APNs", value: apnsStatus(health))
                        }
                        if let message = environment.lastErrorMessage {
                            ErrorBanner(message: message)
                        }
                    }
                }

                FinancePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("连接配置")
                            .font(.headline)
                        TextField("API 地址", text: $apiBaseURL)
                            .autocorrectionDisabled()
                        HStack {
                            Button("保存并重连") {
                                Task { await saveAPIConfiguration() }
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }
                        if let configMessage {
                            Text(configMessage)
                                .font(.caption)
                                .foregroundStyle(FinanceTokens.State.income)
                        }
                    }
                }

                FinancePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("账号")
                            .font(.headline)
                        if environment.isAdminSession {
                            Text("你正在使用管理员 Token 直连")
                                .font(.subheadline.weight(.semibold))
                            Button("退出管理员模式", role: .destructive) {
                                Task { await environment.exitAdminMode() }
                            }
                        } else if let user = environment.authUser {
                            DetailLine(title: "名称", value: user.displayName ?? "未提供")
                            DetailLine(title: "邮箱", value: user.email ?? "未提供")
                            DetailLine(title: "Apple ID", value: user.appleUserId)
                            Button("退出登录", role: .destructive) {
                                Task { await environment.logout() }
                            }
                        } else {
                            Text("未登录")
                                .foregroundStyle(FinanceTokens.Text.secondary)
                        }
                    }
                }

                if environment.authUser != nil {
                    FinancePanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("已登录设备")
                                .font(.headline)
                            AuthSessionsSection(environment: environment)
                        }
                    }
                }

                FinancePanel {
                    DisclosureGroup("高级设置 / 管理员 Token") {
                        AdminTokenEntryView(environment: environment)
                    }
                }

                FinancePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("外观与隐私")
                            .font(FinanceTypography.headline)
                        Picker("外观", selection: $environment.appearance) {
                            ForEach(FinanceAppearance.allCases) { appearance in
                                Text(appearance.title).tag(appearance)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("使用大数字样式", isOn: $environment.useHeroNumbers)
                        Toggle("启用隐私模糊", isOn: $environment.privacyMaskEnabled)
                        Picker("解锁方式", selection: $environment.privacyUnlockMethod) {
                            ForEach(PrivacyUnlockMethod.allCases) { method in
                                Text(method.title).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("进入后台自动模糊", isOn: $environment.privacyAutoMaskOnBackground)
                        Picker("长时间无操作自动模糊", selection: $environment.privacyIdleLockInterval) {
                            ForEach(PrivacyIdleLockInterval.allCases) { interval in
                                Text(interval.title).tag(interval)
                            }
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Button {
                                environment.lockPrivacy()
                            } label: {
                                Label("立即隐藏金额", systemImage: "eye.slash.fill")
                            }
                            .disabled(!environment.privacyMaskEnabled)

                            Button {
                                Task { await environment.authenticatePrivacyIfNeeded() }
                            } label: {
                                Label("解锁金额", systemImage: "lock.open.fill")
                            }
                            .disabled(!environment.privacyMaskEnabled || !environment.isPrivacyLocked)
                        }
                    }
                }

                FinancePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Widget & 通知")
                            .font(FinanceTypography.headline)
                        Toggle("Widget 自动更新", isOn: $environment.widgetAutoUpdateEnabled)
                        Stepper(value: $environment.widgetRefreshMinutes, in: 5...120, step: 5) {
                            DetailLine(title: "刷新间隔", value: "\(environment.widgetRefreshMinutes) 分钟")
                        }
                        Stepper(value: $environment.liveActivityReminderDays, in: 1...30) {
                            DetailLine(title: "Live Activity 提前", value: "\(environment.liveActivityReminderDays) 天")
                        }
                        Toggle("Dynamic Island AI 计划提示", isOn: $environment.dynamicIslandAIEnabled)
                        Toggle("系统推送", isOn: $environment.systemPushEnabled)
#if os(iOS)
                        Button {
                            Task { await requestPushRegistration() }
                        } label: {
                            Label("授权并注册本机", systemImage: "bell.badge")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!environment.systemPushEnabled || environment.pushNotificationViewModel.isRegistering)
#else
                        Text("macOS 本轮保留后端兼容，不主动注册 APNs。")
                            .font(FinanceTypography.caption)
                            .foregroundStyle(FinanceTokens.Text.secondary)
#endif
                        if let device = environment.pushNotificationViewModel.lastRegisteredDevice {
                            DetailLine(title: "最近注册", value: FinanceFormatter.mediumDate(device.lastSeenAt))
                        } else if let status = environment.pushNotificationViewModel.statusMessage {
                            DetailLine(title: "注册状态", value: status)
                        }
                        if let message = environment.pushNotificationViewModel.errorMessage {
                            ErrorBanner(message: message)
                        }
#if os(macOS)
                        Text("菜单栏入口已固定显示。")
                            .font(FinanceTypography.caption)
                            .foregroundStyle(FinanceTokens.Text.secondary)
#endif
                    }
                }

                FinancePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI 配置")
                            .font(FinanceTypography.headline)
                        if let config = environment.settingsViewModel.aiConfig {
                            DetailLine(title: "Provider", value: config.provider)
                            DetailLine(title: "模型", value: config.model ?? "未配置")
                            DetailLine(title: "端点", value: config.baseUrlConfigured ? "已配置" : "未配置")
                            DetailLine(title: "API Key", value: config.apiKeyConfigured ? "已配置" : "未配置")
                            DetailLine(title: "自动确认阈值", value: FinanceFormatter.money(config.autoConfirmLimitCny))
                        } else {
                            Text("尚未读取 AI 配置")
                                .foregroundStyle(FinanceTokens.Text.secondary)
                        }
                    }
                }

                FinancePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("手动汇率")
                            .font(.headline)
                        HStack {
                            TextField("USD/CNY", text: $usdRate)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            Button("写入今日汇率") {
                                Task { await createRate() }
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }
                        ForEach(environment.settingsViewModel.rates.prefix(8)) { rate in
                            HStack {
                                Text("\(rate.fromCurrency.rawValue)/\(rate.toCurrency.rawValue)")
                                    .font(.headline.monospaced())
                                Spacer()
                                Text(NSDecimalNumber(decimal: rate.rate.value).stringValue)
                                    .font(.body.monospacedDigit())
                                Text(FinanceFormatter.shortDate(rate.date))
                                    .foregroundStyle(FinanceTokens.Text.secondary)
                            }
                        }
                    }
                }

                if let message = errorMessage ?? environment.settingsViewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(FinanceTokens.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .moduleFrame()
        .task {
            syncDrafts()
            try? await environment.settingsViewModel.refresh()
            await environment.refreshSessions()
        }
    }

    private func syncDrafts() {
        apiBaseURL = environment.apiClient.baseURL.absoluteString
    }

    private func saveAPIConfiguration() async {
        let trimmedURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), !trimmedURL.isEmpty else {
            errorMessage = "请输入合法 API 地址"
            return
        }
        await environment.updateBaseURL(url)
        configMessage = "连接配置已保存"
        errorMessage = nil
    }

    private func requestPushRegistration() async {
#if os(iOS)
        do {
            environment.pushNotificationViewModel.markWaitingForToken()
            try await PushNotificationManager.shared.requestAuthorizationAndRegister()
            errorMessage = nil
        } catch {
            environment.pushNotificationViewModel.markFailure(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
#else
        configMessage = "macOS 本轮不注册 APNs"
#endif
    }

    private func apnsStatus(_ health: AppHealthDTO) -> String {
        let mode = health.apnsUseSandbox == true ? "sandbox" : "production"
        return health.apnsDryRun == true ? "\(mode) · dry-run" : mode
    }

    private func createRate() async {
        guard let decimal = parseDecimalAmount(usdRate) else {
            errorMessage = "请输入合法汇率"
            return
        }
        do {
            try await environment.settingsViewModel.createRate(
                CurrencyRateCreateRequest(fromCurrency: .usd, rate: DecimalValue(decimal), date: Date(), note: "macOS 手动录入")
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
