import SwiftUI

#if os(iOS)

// SettingsIOSView — v3.0.0 P4 ② iOS 设置 (目前只做 AI 配置).
//
// iOS 版设置尚未做分类/汇率/通知/导出/登录管理等 macOS Settings 七节全集 —那些留
// macOS 处理 (决策门 B 既有安排，MoreIOSView 其余行仍标「iOS 版后续」)。这里只补
// P4 明确要求的 AI 配置表单 (D0)，让 iOS 端也能填 base_url / model / api_key，不
// 必切到 Mac 才能连上 AI 供「记一笔 → AI 解析」使用。
struct SettingsIOSView: View {
    @ObservedObject var model: AppModel
    @StateObject private var configModel: AIConfigModel

    init(model: AppModel) {
        self.model = model
        _configModel = StateObject(wrappedValue: AIConfigModel(apiClient: model.apiClient))
    }

    var body: some View {
        ZStack {
            BloomBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("AI 配置", systemImage: "sparkles")
                                .font(Theme.Font.subtitle(.semibold))
                                .foregroundStyle(Theme.Color.textPrimary)
                            Text("填好后到「记一笔」里用「AI 解析」自然语言记账。")
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Color.textTertiary)
                            AIConfigFormCard(configModel: configModel)
                        }
                    }
                    Text("分类 / 汇率 / 通知 / 导出 / 登录管理请到 macOS 端设置。")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { if configModel.config == nil { await configModel.load() } }
    }
}

#endif
