import SwiftUI

struct SettingsView: View {
    @Bindable var environment: AppEnvironment
    @State private var usdRate = "6.8"
    @State private var errorMessage: String?

    var body: some View {
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
                        }
                        if let message = environment.lastErrorMessage {
                            ErrorBanner(message: message)
                        }
                    }
                }

                FinancePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI 配置")
                            .font(.headline)
                        if let config = environment.settingsViewModel.aiConfig {
                            DetailLine(title: "Provider", value: config.provider)
                            DetailLine(title: "模型", value: config.model ?? "未配置")
                            DetailLine(title: "端点", value: config.baseUrlConfigured ? "已配置" : "未配置")
                            DetailLine(title: "API Key", value: config.apiKeyConfigured ? "已配置" : "未配置")
                            DetailLine(title: "自动确认阈值", value: FinanceFormatter.money(config.autoConfirmLimitCny))
                        } else {
                            Text("尚未读取 AI 配置")
                                .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let message = errorMessage ?? environment.settingsViewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .moduleFrame()
        .task {
            try? await environment.settingsViewModel.refresh()
        }
    }

    private func createRate() async {
        guard let decimal = Decimal(string: usdRate) else {
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
