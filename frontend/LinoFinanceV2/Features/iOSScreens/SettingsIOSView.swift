import SwiftUI

#if os(iOS)
import Photos
import UIKit

// SettingsIOSView — v3.0.0 P4 ② iOS 设置 (AI 配置 + 快修三新增的照片访问).
//
// iOS 版设置尚未做分类/汇率/通知/导出/登录管理等 macOS Settings 七节全集 —那些留
// macOS 处理 (决策门 B 既有安排，MoreIOSView 其余行仍标「iOS 版后续」)。这里补了
// P4 明确要求的 AI 配置表单 (D0)，让 iOS 端也能填 base_url / model / api_key，不
// 必切到 Mac 才能连上 AI 供「记一笔 → AI 解析」使用；快修三再加一张「截图记账 ·
// 照片访问」卡 (D3 反转) — 「解析截图记账」intent 现在默认自动读取相册最新一张
// 截图 (`LatestScreenshotFetcher`)，这里是用户第一次主动授权的入口，不必等到第
// 一次触发 intent 才撞见系统权限弹窗。
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
                    GlassCard {
                        PhotoAccessCard()
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

/// PhotoAccessCard — 快修三: 「解析截图记账」现在默认自动读取相册最新一张截图
/// (`LatestScreenshotFetcher`)，需要照片访问权限。展示当前授权状态 + 按状态给
/// 一个可行动的 chip：未授权→直接弹系统授权框；受限/已拒绝→跳系统设置 (受限模
/// 式取不到最新截图，只能去设置改成「所有照片」；已拒绝的应用内 `requestAuth
/// orization` 不会再弹系统框，只能去设置)。回到前台时重新读取状态，覆盖「去设
/// 置改完权限再切回来」这条路径。
private struct PhotoAccessCard: View {
    @State private var status: PHAuthorizationStatus = LatestScreenshotFetcher.currentAuthorizationStatus()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("截图记账 · 照片访问", systemImage: "photo.on.rectangle")
                .font(Theme.Font.subtitle(.semibold))
                .foregroundStyle(Theme.Color.textPrimary)
            Text("授权后，「解析截图记账」快捷指令 / Back Tap / Siri 会自动读取相册里最近 10 分钟内的最新一张截图并在本机识别记账，不用手动传图。截图不会上传，也不会被保存或分享。")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textTertiary)
            StatusBadge(text: statusText, tone: statusTone)
            if let actionTitle {
                TintedActionChip(title: actionTitle, systemImage: "gearshape", tone: .action) {
                    Task { await handleAction() }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { status = LatestScreenshotFetcher.currentAuthorizationStatus() }
        }
    }

    private func handleAction() async {
        switch status {
        case .notDetermined:
            status = await LatestScreenshotFetcher.requestAuthorization()
        case .limited, .denied, .restricted:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            _ = await UIApplication.shared.open(url)
        default:
            break
        }
    }

    private var statusText: String {
        switch status {
        case .authorized: "已授权"
        case .limited: "受限模式（仅部分照片）"
        case .notDetermined: "未授权"
        case .denied: "已拒绝"
        case .restricted: "受限制"
        @unknown default: "未知"
        }
    }

    private var statusTone: StatusBadge.Tone {
        switch status {
        case .authorized: .positive
        case .limited: .warning
        default: .negative
        }
    }

    private var actionTitle: String? {
        switch status {
        case .notDetermined: "授权照片访问"
        case .limited: "去系统设置改为「所有照片」"
        case .denied, .restricted: "去系统设置授权"
        default: nil
        }
    }
}

#endif
