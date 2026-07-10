import Foundation
import SwiftUI

// AIConfigModel — v3.0.0 P4 ② AI 配置表单 view-model (macOS + iOS 共用, D0).
//
// Kept separate from `AIAssistantModel` (the plan/proposal review-and-execute
// flow) — this one only owns the three-field config (base_url / api_key /
// model) CRUD, so the Settings form on both platforms can share one small,
// focused model instead of dragging in the whole plan surface. `AIAssistantModel`
// independently reads `GET /ai/config` itself for its own (read-only) "未配置"
// banner — two cheap GETs, not a shared instance — see its doc comment.
@MainActor
final class AIConfigModel: ObservableObject {

    enum State: Equatable {
        case idle, loading, loaded, failed(String)
    }

    @Published private(set) var config: AIConfigDTO?
    @Published private(set) var state: State = .idle
    @Published var actionError: String?
    @Published private(set) var isSaving = false

    private let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    /// base_url + api_key + model 三者都有才算真正可用 — 与后端
    /// `ResolvedAIConfig.is_configured` 同一口径 (仅 base_url+api_key 齐但缺
    /// model 时 provider 请求仍会失败).
    var isFullyConfigured: Bool {
        guard let config else { return false }
        return config.baseUrlConfigured && config.apiKeyConfigured
            && !(config.model ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    func load() async {
        state = .loading
        do {
            config = try await apiClient.aiConfig()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// 保存 base_url / model (总是整段重发 — 清空字段 = 清空该项，后端把显式空串
    /// 当 null 处理，语义与「留空不填」这两者是不同意图: 见 `newApiKey` 参数) +
    /// 可选新 api_key (空 = 不改动原 key — SecureField 从不回填真实值，留空绝不能
    /// 被当成「清空」；显式清空走 `clearApiKey()`).
    @discardableResult
    func save(baseUrl: String, model: String, newApiKey: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            actionError = nil
            let trimmedKey = newApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let request = AIConfigUpdateRequest(
                baseUrl: baseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey: trimmedKey.isEmpty ? nil : .value(trimmedKey),
                model: model.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            config = try await apiClient.updateAIConfig(request)
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    /// 显式清空已保存的 key — 独立动作，绝不会被「打开表单直接保存」误触发。
    @discardableResult
    func clearApiKey() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            actionError = nil
            config = try await apiClient.updateAIConfig(AIConfigUpdateRequest(apiKey: .null))
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }
}
