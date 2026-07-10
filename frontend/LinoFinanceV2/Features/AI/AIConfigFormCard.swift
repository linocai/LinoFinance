import SwiftUI

// AIConfigFormCard — v3.0.0 P4 ② AI 配置表单内容 (macOS Settings + iOS
// SettingsIOSView 共用, D0: 运行时配置改 app 内填写落库、不再靠服务端 env).
//
// base_url / model 文本 + api_key SecureField + 保存 / 清除密钥。Key 安全: 表单
// SecureField 从不回填真实 key (`GET /ai/config` 只回掩码尾4位) — 「打开表单直接
// 保存」绝不清空已存的 key (`AIConfigModel.save` 的 field-presence 语义: 空
// SecureField → 不带 api_key 字段，服务端保留原值)；显式清空走独立的两段式
// 「清除密钥」chip，避免误触。
struct AIConfigFormCard: View {
    @ObservedObject var configModel: AIConfigModel

    @State private var baseUrlText = ""
    @State private var modelText = ""
    @State private var apiKeyText = ""
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow
            switch configModel.state {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("加载中…").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
            case .loaded:
                form
            }
        }
        .onAppear(perform: seed)
        .onChange(of: configModel.config) { _, _ in seed() }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            StatusBadge(
                text: configModel.isFullyConfigured ? "已配置" : "未配置",
                tone: configModel.isFullyConfigured ? .positive : .warning
            )
            if let hint = configModel.config?.apiKeyHint {
                Text("密钥 \(hint)")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Base URL") {
                TextField("如：https://api.openai.com/v1", text: $baseUrlText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            field("Model") {
                TextField("如：gpt-4o-mini", text: $modelText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            field("API Key") {
                SecureField(keyPlaceholder, text: $apiKeyText)
                    .textFieldStyle(.roundedBorder)
            }
            if let error = configModel.actionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
                    .lineLimit(3)
            }
            actions
        }
    }

    private var keyPlaceholder: String {
        (configModel.config?.apiKeyConfigured ?? false) ? "留空 = 不改动已保存的密钥" : "输入 API Key"
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if configModel.config?.apiKeyConfigured == true {
                if confirmingClear {
                    TintedActionChip(title: "确认清除密钥？", tone: .destructive) {
                        Task {
                            await configModel.clearApiKey()
                            confirmingClear = false
                        }
                    }
                    TintedActionChip(title: "算了", tone: .neutral) { confirmingClear = false }
                } else {
                    TintedActionChip(title: "清除密钥", tone: .destructive) { confirmingClear = true }
                }
            }
            Spacer(minLength: 8)
            PrimaryDarkButton("保存", isLoading: configModel.isSaving) {
                Task {
                    let ok = await configModel.save(baseUrl: baseUrlText, model: modelText, newApiKey: apiKeyText)
                    if ok { apiKeyText = "" }
                }
            }
            .disabled(configModel.isSaving)
            .opacity(configModel.isSaving ? 0.6 : 1)
        }
    }

    private func seed() {
        baseUrlText = configModel.config?.baseUrl ?? ""
        modelText = configModel.config?.model ?? ""
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            content()
        }
    }
}
