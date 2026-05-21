# LinoFinance v1.1 升级施工计划

版本：v1.1.0
计划日期：2026-05-20
基线版本：v1（生产部署于 `https://lf.linotsai.top/api/v1`，2026-05-16 起稳定运行）
适用平台：iOS 18+（推荐 iOS 26）/ iPadOS 18+ / macOS 15 Sequoia+（推荐 macOS 26）/ watchOS 11+（可选）
配套文档：[plan.md](plan.md)、[LinoFinance前端设计方向.md](LinoFinance前端设计方向.md)、[.planning/STATE.md](.planning/STATE.md)、[v1.1前端升级预览.html](v1.1前端升级预览.html)

> 本计划面向施工人员（后端 + iOS/macOS 客户端 + 部署），所有改动都要可回滚、有审计、能跑通既有 56 + 12 个测试。

---

## 0. v1 现状速记（施工前必读）

| 域 | 现状 |
|---|---|
| 后端 | FastAPI 0.115 + SQLAlchemy 2.0 + Alembic + PostgreSQL 16；16 个 route 模块；中间件顺序为 `RequestContext → Auth → RateLimit → CORS`；生产强制 `LINOFINANCE_API_AUTH_TOKEN`；最新 Alembic 版本 `202605160005` |
| 后端模型 | `Account` / `Category` / `CurrencyRate` / `FinancialEntry` / `EntryCategoryLine` / `AccountMovement` / `CreditStatementCycle` / `CashFlowItem` / `ReimbursementClaim` / `InstallmentPlan` / `SubscriptionRule` / `AIPlan` / `AIAction` / `AIActionExecution` / `NotificationRule` / `AuditLog` |
| AI 协议 | 已支持 `CreateEntry / CreateCashFlowItem / MarkReimbursable / CreateInstallmentPlan / RecordCreditRepayment / GenerateNotificationRule / VoidEntry / SetCashFlowStatus / UpdateReimbursementStatus`；阈值 `auto_confirm_limit_cny = 1000`；高风险走 `EXECUTE_HIGH_RISK` |
| Provider | OpenAI 兼容；生产用 `deepseek-v4-flash`，连接已通 |
| 客户端代码 | SwiftPM `frontend/Sources/*`（共享 DTO / API Client / 占位 View）+ Xcode `frontend/LinoFinance/*`（真正的 SwiftUI 业务页面）。**业务 UI 主要在 Xcode target 里**，SwiftPM 现在只承担「shared lib + 编译型测试」；新工作除 DTO/Model 外尽量加在 Xcode target |
| macOS | Sidebar + Content + Inspector 三栏，模块 10 个全部接真 API |
| iOS | TabView（总览 / 记账 / 现金流 / 信用 / 更多），强制 `.preferredColorScheme(.light)`；无 Widget、无 Live Activity、无 App Intents |
| 部署 | `hz` 服务器 systemd `linofinance-api`，nginx + Let's Encrypt（到期 2026-08-14） |
| 仍欠 | ⌘K / Menu Bar Extra / Widget / Live Activity / Shortcuts / 真实推送 / 附件 / 离线草稿同步 / 隐私模糊 / Apple Charts / 账户对账 / AI 月报 |

---

## 1. v1.1 目标总览

### 1.1 价值主张

> v1 解决了「能不能记」。v1.1 解决「记得快、看得清、AI 真有用、系统真集成」。

### 1.2 必交付（Must）

1. **视觉系统刷新到 Liquid Glass**，并补齐 Light / Dark / High Contrast 三套语义令牌。
2. **macOS：⌘K 命令面板 + Menu Bar Extra + 多窗口 + Apple Charts 报表**。
3. **iOS：浮动 Tab Bar + 中央 FAB 一句话记账 + Dynamic Island/Live Activity + Lock Screen 小组件 + 主屏 Widget**。
4. **App Intents + Siri + Spotlight**（至少「新建支出」「查询本月支出」「下一笔信用卡还款」三个 Intent）。
5. **隐私模糊（Privacy Blur）+ Face ID / Touch ID 解锁**。
6. **离线草稿队列 + 冲突解决** —— SwiftData 本地存草稿、回放、失败重试、版本号冲突提示。
7. **AI 月度财务故事**（后端聚合 + 模型生成；前端可编辑、改语气、导出 PDF）。
8. **账户对账（Account Reconciliation）** —— 应有余额 vs 实有余额；一键 `AccountAdjustment`。
9. **附件模型（Attachment）+ 报销凭证预览**。
10. **后端配套**：搜索接口、附件接口、AI 月报接口、APNs 推送接口、对账接口、`/health` 增加 Sentry/uptime 指标。

### 1.3 不做（明确 Out of Scope）

- 自动汇率 API、银行自动抓取、CloudKit 同步、多用户协作账本、JSON / SQLite / PDF 备份（除 AI 月报 PDF 外）、投资交易、预算模块、Apple Watch app（仅做 complication 数据源）。

### 1.4 验收口径

- 所有 `pytest` / `swift test` / `xcodebuild` 现有用例继续通过。
- 任何新数据模型有 Alembic 迁移、回滚脚本、`docs/api-contract.md` 增补、至少 1 个 happy path 测试 + 1 个失败路径测试。
- 任何前端 UI 改动都通过：iOS 26 + iOS 18.4 双 SDK 编译，macOS 26 + macOS 15 双 SDK 编译，`swift test` 通过。
- AI 月报、对账、对接外部服务的接口必须支持 token 失效、provider 5xx、超时三种错误码路径。
- 关键交付都写一个手动 smoke 步骤入到 `.planning/STATE.md`。

---

## 2. 整体里程碑

| Phase | 名称 | 工期估算 | 阻塞关系 |
|---|---|---|---|
| **P1** | 设计令牌 + DesignSystem 重构 | 3 天 | 无（最先做） |
| **P2** | 后端基础：搜索 / 对账 / 月报 / 附件 / 推送骨架 | 5 天 | 与 P1 并行 |
| **P3** | macOS：⌘K + Menu Bar Extra + Apple Charts + 多窗口 + Inspector 升级 | 6 天 | P1 完成 |
| **P4** | iOS：浮动 Tab Bar + Hero + Dynamic Island + Lock Screen Widget + 主屏 Widget | 6 天 | P1 完成 |
| **P5** | App Intents + Siri + Spotlight | 3 天 | P2 完成 |
| **P6** | 隐私模糊 + Face ID + 后台保护 | 1.5 天 | P1 完成 |
| **P7** | 离线草稿队列 + 冲突解决 | 4 天 | P2 完成 |
| **P8** | AI 月报（前后端） | 4 天 | P2 完成 |
| **P9** | 账户对账 UI + 一键 `AccountAdjustment` | 2 天 | P2 完成 |
| **P10** | 附件模型 + 报销凭证预览 | 3 天 | P2 完成 |
| **P11** | 推送：APNs + 后端规则触发器 | 3 天 | P2 + P4 完成 |
| **P12** | 端到端回归、文档、部署、Tag `v1.1.0` | 2 天 | 全部完成 |

> 单人施工：累计 ~42.5 天。可并行：P3/P4/P5 同时，P6/P7 同时；预计 4–5 周完工。

---

## 3. Phase 1：设计令牌 + DesignSystem 重构

### 3.1 目标

把 v1 的 `FinanceColor` / `FinanceSpacing` / `FinanceComponents` 升级为 **语义令牌系统**，并新增 Liquid Glass 修饰符，使 Light / Dark / High Contrast 一次实装。

### 3.2 后端

无改动。

### 3.3 前端文件清单

新增：

- `frontend/LinoFinance/DesignSystem/Tokens/FinanceTokens.swift`（完全重写）
- `frontend/LinoFinance/DesignSystem/Tokens/FinanceTypography.swift`
- `frontend/LinoFinance/DesignSystem/Materials/Glass.swift`（自适应 `.regularMaterial` / `.thinMaterial` / `.ultraThinMaterial` + custom shadow）
- `frontend/LinoFinance/DesignSystem/Components/HeroNumber.swift`
- `frontend/LinoFinance/DesignSystem/Components/Sparkline.swift`
- `frontend/LinoFinance/DesignSystem/Components/PrivacyAmount.swift`（包裹 `MoneyText`，根据 `AppEnvironment.privacyMaskEnabled` 模糊）

修改：

- `frontend/LinoFinance/DesignSystem/Components/FinanceComponents.swift`：`KPIStat` 改 Hero 风格，`FinancePanel` 切到 Glass，`StatusTag` 与 `EmptyState` 走新字号。
- `frontend/LinoFinance/Platform/iOS/iOSRootView.swift`：移除 `.preferredColorScheme(.light)`，改为 Settings 控制。
- `frontend/LinoFinance/Features/Settings/SettingsView.swift`：新增 `appearance: system|light|dark`、`useHeroNumbers`、`privacyMaskEnabled`。
- 全部 Feature 使用 `FinanceTokens.Color.*` / `FinanceTokens.Surface.*`，移除直接的 `Color(.secondarySystemGroupedBackground)`。

### 3.4 设计令牌（Swift 接口）

```swift
enum FinanceTokens {
    enum Surface {
        static var base: Color           // 主背景
        static var raised: Color         // 卡片
        static var glass: ShapeStyle     // .regularMaterial（自适应）
        static var glassStrong: ShapeStyle
        static var deep: Color           // Sidebar / Inspector
    }
    enum Text { static var primary, secondary, tertiary: Color }
    enum Stroke { static var hairline, soft: Color }
    enum Brand { static var primary, deep, soft: Color }
    enum Currency { static var cny, usd: Color }
    enum State { static var income, expense, credit, warning, ai, pending: Color }
    enum Radius { static let sm: CGFloat = 10, md: CGFloat = 14, lg: CGFloat = 22, xl: CGFloat = 30 }
}

enum FinanceTypography {
    static var heroNumber: Font   // 38pt bold mono tnum
    static var titleXL: Font      // 30pt
    static var headline: Font     // 17pt
    static var bodyMono: Font     // 14pt mono tnum
    static var caption: Font      // 11.5pt
}
```

### 3.5 验收

- `swift test` 通过。
- macOS / iOS Debug build 通过。
- iOS Settings 切 Dark Mode 后所有页面无白底闪烁、无硬编码色。
- 截屏 4 张存到 `.planning/screenshots/v1.1-p1-*.png`：iOS Light、iOS Dark、macOS Light、macOS Dark。

---

## 4. Phase 2：后端基础接口

### 4.1 目标

为后续 P3–P11 提供 API 基线，**不动 v1 现有路由的行为**，全部走新前缀。

### 4.2 数据模型迁移

新增 Alembic 迁移 `202605200001_attachment_and_adjustment.py`：

1. `attachments`
    - `id: str(UUID)` PK
    - `owner_type: str(32)`（`entry_category_line` / `reimbursement_claim` / `ai_action`）
    - `owner_id: str(UUID)`
    - `filename: str(200)`
    - `content_type: str(100)`
    - `size_bytes: int`
    - `storage_key: str(300)`（云端对象存储 key；当前阶段写入服务器本地路径 `/opt/linofinance/storage/...`，预留 S3 兼容字段）
    - `checksum_sha256: str(64)`
    - `uploaded_by: str(32)`
    - 时间戳 + 删除标记
2. `account_adjustments`
    - `id`、`account_id`、`reason: str(120)`、`delta_amount: Decimal(18,2)`、`currency: str(3)`、`balance_before / balance_after: Decimal(18,2)`、`source: str(32)`（`reconciliation` / `manual`）、`note: text`、`created_by: str(32)`
3. `ai_memos`
    - `id`、`period_start: date`、`period_end: date`、`summary: text`（Markdown）、`stats_json: jsonb`（聚合指标 snapshot）、`prompt_token / completion_token: int`、`generator: str(80)`、`status: str(32)`（`draft / published / archived`）
4. `push_devices`
    - `id`、`device_id`、`platform: str(16)`（`ios` / `macos`）、`apns_token: str(64)`、`app_version`、`installed_at`、`last_seen_at`、`enabled: bool`

> 所有迁移必须给出 `downgrade()` 完整还原；`storage_key` 中不写绝对路径，全部走 `LINOFINANCE_STORAGE_ROOT` 环境变量解析。

### 4.3 新路由

挂载位置：`backend/app/api/routes/`。

| Route | 方法 + 路径 | 用途 |
|---|---|---|
| `search.py` | `GET /search?q=&limit=20&types=` | ⌘K 全局搜索。返回 `accounts / entries / cash_flow_items / reimbursement_claims / ai_plans / notification_rules` 命中并标注相关度 |
| `attachments.py` | `POST /attachments`（multipart） / `GET /attachments/{id}` / `DELETE /attachments/{id}` | 报销凭证、AI 动作附件 |
| `reconciliation.py` | `GET /reconciliation/accounts` / `POST /reconciliation/adjustments` | 列「应有 vs 实有」表；提交一个 `account_adjustments` 记录并产生 AuditLog |
| `ai_memos.py` | `GET /ai/memos?period=` / `POST /ai/memos/generate` / `PATCH /ai/memos/{id}` / `DELETE /ai/memos/{id}` | 生成 / 列表 / 编辑 / 删除月度财务故事 |
| `push.py` | `POST /push/devices`（注册 APNs token） / `DELETE /push/devices/{id}` | 设备注册与卸载 |

> 所有新接口与 v1 一样走 `APIAuthMiddleware`；`/search` 在 token 缺失时 401，公开 `/health` 路径不变。

### 4.4 服务层

新增：

- `app/services/search.py`：先做 PostgreSQL `ILIKE` 简单实现；预留 `pg_trgm` 索引（Alembic 同迁移）。
- `app/services/attachments.py`：本地 FS 存储 + SHA-256 + 大小限制 10 MB / 文件、25 MB / 报销单。
- `app/services/reconciliation.py`：扫描 `account_movements` + `credit_statement_cycles` + `account_adjustments` 算 expected，与 `accounts.current_balance / current_liability` 对比；阈值 `RECONCILIATION_THRESHOLD = Decimal("0.01")`。
- `app/services/ai_memo.py`：聚合 `report` 服务现有指标，组装 prompt 给 `ai_provider.py`，落库返回。Prompt 模板放 `app/services/prompts/ai_memo_zh.md`。
- `app/services/push.py`：现阶段不直接发推送，只管设备登记与查询；APNs 实际发送在 P11 加。

### 4.5 配置

新增到 `app/core/config.py`：

```python
storage_root: str = ".local/storage"
attachment_max_bytes: int = 25 * 1024 * 1024
search_result_limit: int = 50
ai_memo_max_tokens: int = 2000
apns_topic: Optional[str] = None
apns_key_id: Optional[str] = None
apns_team_id: Optional[str] = None
apns_key_path: Optional[str] = None
```

### 4.6 测试

每个新路由至少 2 个测试：

- `tests/api/test_search.py`：账户/记录命中、token 缺失 401。
- `tests/api/test_attachments.py`：上传 + 下载 + 大小越界 413。
- `tests/api/test_reconciliation.py`：构造 movement 与 balance 漂移，列表与 adjustment 提交、再列零差。
- `tests/api/test_ai_memos.py`：生成 mock provider 月报、PATCH 编辑、删除。
- `tests/api/test_push_devices.py`：注册、重复 token 幂等、删除。

### 4.7 验收

- `pytest`、`ruff check`、`alembic upgrade head --sql` 全部通过。
- `docs/api-contract.md` 增补 5 个章节。
- 生产部署前 `production_migrate.py` dry-run 通过。

---

## 5. Phase 3：macOS 升级

### 5.1 目标

让 macOS 站稳「财务控制台」的定位：键盘优先、密度高、报表一屏看完。

### 5.2 ⌘K 命令面板

文件：`frontend/LinoFinance/Platform/macOS/CommandPalette.swift`。

- 用 `Window` + `.commands` 注册 `⌘K`（macOS 14+ `WindowGroup(id:)`）；iPad 也复用此组件，绑定到外接键盘。
- 模型：`CommandPaletteItem { id, category, title, subtitle, shortcut, action }`。
- 数据源：
    - **页面跳转**：所有 `FinanceModule` 用 `⌘1..⌘9` 直跳。
    - **AI 动作**：`"新建 餐饮 88 招商"` 直接调用 `aiViewModel.createPlan(sourceText:)`；返回的 plan 走「自动确认候选」流程。
    - **后端搜索**：≥2 字符且 200 ms 防抖后调 `GET /search`。
    - **最近**：`UserDefaults` 存 20 条最近命中。
- 键盘：↑↓ 切换、↩ 执行、⇧↩ 用作「保存为草稿」、`esc` 关闭。
- Liquid Glass：`.regularMaterial` + 大圆角 18、模糊 40、饱和 180%。

### 5.3 Menu Bar Extra

文件：`frontend/LinoFinance/Platform/macOS/MenuBarExtra.swift`。

- 在 `LinoFinanceApp.swift` 加 `MenuBarExtra("LinoFinance", systemImage: "yensign.circle.fill") { MenuBarPopover() }`。
- 显示：净资产、今日新增、下次还款、AI 待确认；按钮：快速记账、同步、⌘K。
- 同一个 `AppEnvironment`；用 `Defaults` 持久化「最近一次显示金额」。
- 点击 Hide 时记住偏好；隐私模糊由 `AppEnvironment.privacyMaskEnabled` 决定。

### 5.4 多窗口（Multi-Window）

- 把 `LinoFinanceApp.scene` 拆为：
    - 主窗口 `WindowGroup`：保留原 Sidebar+Content+Inspector。
    - `WindowGroup(id: "module", for: FinanceModule.self)`：模块独立窗口（Reports / AI / Credit），右键 Sidebar → 「在新窗口中打开」。
    - `Window(id: "command", "Command Palette")` ：⌘K 唤起。
- 状态共享：所有窗口共享 `AppEnvironment`（已 `@Bindable`）。
- 触发：`SwiftUI.openWindow(id:value:)`，菜单 `Window → New Reports Window`。

### 5.5 Apple Charts 报表

- 新增依赖 `import Charts`（系统库，不引第三方）。
- 替换 `Features/Reports/ReportsView.swift` 中所有 `ThinBar` 为：
    - **现金流压力**：`Chart` 堆叠 BarMark（进账+出账）+ LineMark（净额）+ AnnotationMark（账单还款日 / 工资日 / AI 关注点）。
    - **分类支出**：SectorMark（环形）+ side legend；交互悬停高亮。
    - **信用负债**：BarMark + RuleMark（信用额度上限）。
    - **报销视角**：BarMark + 视角切换（segmented）。
- 全部图表支持 `chartXSelection` / `chartYSelection`，给出 tooltip。

### 5.6 Inspector 升级

文件：`Features/Shared/SelectionDetailView.swift`。

- 顶部主信息卡（金额 Hero + 状态）。
- 加 `AI 建议` 卡（调用 `GET /ai/plans?related_to={selection_id}`，无则隐藏）。
- 加 `审计 · 最近 3 条`（调用 `GET /audit-logs?owner_type=&owner_id=&limit=3`）。
- 加 `相关附件`（P10）。

### 5.7 验收

- macOS Debug build 通过。
- ⌘K 在三类输入下都能命中：纯页面、自然语言、远端搜索。
- Menu Bar Extra 长开 1 小时内存增长 < 50 MB。
- 多窗口下关闭主窗口不会让子窗口 crash。
- Reports 全部图表能跑通空数据 → 1 条数据 → 多条数据三档。

---

## 6. Phase 4：iOS 升级

### 6.1 目标

让 iOS 的两秒记账体验真正成立。

### 6.2 浮动 Tab Bar + 中央 FAB

文件：`frontend/LinoFinance/Platform/iOS/iOSRootView.swift`。

- 用 `TabView { ... }.tabViewStyle(.tabBarOnly)`（iOS 18 起 `.tabBarOnly`）；如需更强自定义，自己实装一个 `FloatingTabBar` 覆盖在 `ZStack` 上层。
- 中央位置不放 Tab，而是放 `FAB`：
    - Tap → 展示 `QuickEntrySheet`（AI / 表单 / 粘贴 三 tab）。
    - Long Press → Menu：新建收入 / 新建支出 / 新建信用消费 / 新建报销。
- 隐藏系统 Tab Bar，全部走 `safeAreaInset(edge: .bottom)`。

### 6.3 Hero 总览

修改 `Features/Dashboard/DashboardView.swift`：

- 顶部 `HeroNumber(amount: summary.netWorthCny, currency: .cny)` + 30 天 Sparkline（用 P1 的 `Sparkline` 组件，数据源 `report.cashFlow.dailyNetCny`，需要后端新增 30 天日级窗口；后端在 `services/report.py` 加 `daily_net_window(days=30)` 函数与对应字段返回）。
- 三栏副指标：余额、信用负债、30 天净额。
- AI 月报卡（来自 P8）。
- 今日 / 待办 / 异常 三块用 `glass-card` 包裹。

### 6.4 Dynamic Island + Live Activity

新增 `frontend/LinoFinance/Platform/iOS/LiveActivities/`：

- `LinoCreditDueAttributes.swift`：`ContentState { remainingDays, amountCNY, accountName, dueDate }`，`StaticAttributes { cycleId }`。
- `LinoCreditDueLiveActivity.swift`：用 `ActivityKit` 注册；提供 compact / minimal / expanded 三种布局。
- 触发：用户在「信用」模块为一笔账单点「设置提醒 Live Activity」；后端 P11 推送 `update` / `end`。
- `LinoAIPlanAttributes`：AI 计划生成 / 待确认 / 已执行的窗口。

### 6.5 主屏 Widget + 锁屏 Widget + StandBy

新增 Widget Extension target `LinoFinanceWidgets`：

- 三个 Widget：
    - `NetWorthWidget`（systemSmall / Medium）：净资产 + Sparkline + ▲/▼。
    - `CreditDueWidget`（systemSmall / Medium / accessoryInline / accessoryRectangular / accessoryCircular）：下次还款。
    - `AIPlansWidget`（systemSmall）：AI 待确认数。
- 数据通道：用 App Group `group.com.lino.linofinance` + UserDefaults 共享 `WidgetSnapshot`（每次主 App refresh 时写一次）。
- StandBy：选 systemMedium，配深色背景。
- Apple Watch complication：复用 `WidgetExtension`（iOS 18 起原生支持），不另外开 target。

### 6.6 设置项

`Features/Settings/SettingsView.swift` 增「Widget & 通知」分区：

- 启用 Widget 自动更新（默认 30 min）。
- 默认 Live Activity 提醒提前天数（默认 5）。
- 启用 Dynamic Island AI 计划提示。

### 6.7 验收

- iOS Simulator + iOS device build 通过（仍需提醒装 iOS Simulator runtime，见 `.planning/STATE.md` Remaining 第 1 条）。
- Widget 在锁屏 / 主屏 / StandBy 三处显示数据 < 2s 后台刷新。
- Live Activity 5 天倒计时可见，到期自动 `end`。
- 切到深色模式所有页面正常。

---

## 7. Phase 5：App Intents + Siri + Spotlight

### 7.1 目标

把记账、查询、还款做成系统级动作。

### 7.2 新增 Intents

文件：`frontend/LinoFinance/Platform/Intents/`。

| Intent | 描述 | 参数 |
|---|---|---|
| `RecordExpenseIntent` | 记一笔支出 | `title: String`、`amount: Double`、`currency: CurrencyCode`、`accountName: String?`、`categoryName: String?` |
| `RecordIncomeIntent` | 记一笔收入 | 同上 |
| `QueryMonthlySpendIntent` | 查询本月支出 | `month: Int?` |
| `NextCreditDueIntent` | 下笔信用卡还款 | 无 |
| `ConfirmAIPlanIntent` | 确认指定 AI 计划 | `planId: String` |

### 7.3 Shortcuts AppShortcutsProvider

```swift
struct LinoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordExpenseIntent(), phrases: [
            "用 \(.applicationName) 记一笔 \(\.$amount) 元",
            "记一笔 \(\.$amount) 元 \(\.$categoryName) 到 \(\.$accountName)",
        ], shortTitle: "记账", systemImageName: "plus.circle.fill")
        // ...
    }
}
```

### 7.4 Spotlight

- 用 `CoreSpotlight` 把账户 + 记录 + 报销 + AI 计划做成 `CSSearchableItem`；每次 refresh 时维护索引。
- 索引项必须包含 `displayName`、`contentDescription`、`thumbnailData`（账户图标）、`relatedUniqueIdentifier`。
- Token 失效时清空索引。

### 7.5 验收

- 「嘿 Siri，用 LinoFinance 记一笔 35 块咖啡」可走完整路径生成记录。
- Spotlight 输入「Logitech」能命中那笔信用消费。
- App Intents 在 Shortcuts.app 出现并可拖拽组合。

---

## 8. Phase 6：隐私模糊 + Face ID

### 8.1 目标

App 后台、长时间无操作或显式启用「隐私模式」时金额自动模糊。

### 8.2 实装

- `AppEnvironment` 新增 `@Published var privacyMaskEnabled: Bool = false`；持久化到 `UserDefaults`。
- `PrivacyAmount` 修饰符（P1 已建占位）：包裹 `MoneyText`，启用时 `.blur(radius: 8)` + 长按显示 + LocalAuthentication 解锁。
- `LinoFinanceApp.scene` 监听 `ScenePhase` `.background` / `.inactive`，自动启用 mask；恢复 `active` 时若开启了 Face ID 锁，先弹 `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`。
- macOS：监听 `NSApplication.willResignActiveNotification`；同上策略。
- Menu Bar Extra：默认所有金额走 mask 模式，hover 显示。

### 8.3 设置

`SettingsView` 加：

- 启用隐私模糊：开 / 关。
- 解锁方式：Face ID / Touch ID / 密码 / 永不锁。
- 进入后台自动模糊：开 / 关（默认开）。
- 长时间无操作自动模糊：5 / 15 / 30 / 永不 分钟（默认 15）。

### 8.4 验收

- 后台 → 前台流程稳定，无金额闪现。
- macOS 切到其他 App 后再切回，Hero 数字保持模糊到解锁。

---

## 9. Phase 7：离线草稿队列

### 9.1 目标

无网络也能记账，恢复网络时按顺序回放，冲突给用户选。

### 9.2 数据

- 不再「客户端是临时」的口号上加更多，而是用 **SwiftData 仅做本地草稿镜像**。
- 新增 `frontend/LinoFinance/Core/Sync/`：
    - `DraftEntry.swift`（SwiftData `@Model`）
    - `SyncQueue.swift`：保存草稿、状态枚举（`pending / inflight / synced / conflict / failed`）。
    - `SyncWorker.swift`：网络可达时按 FIFO 调用 `LinoAPIClient.createEntry`；收到 200 后写入 `serverId`，更新状态为 `synced`。
    - 失败：5xx 指数退避（30 s → 5 min）；4xx 直接标 `failed` 并把错误塞 `lastError`。
    - 冲突：服务端返回 `409 / 412` 时进入 `conflict`，弹「保留本地 / 接受远端 / 合并」。

### 9.3 后端配合

- `POST /entries` 增加可选 `client_draft_id: str | None`，落库到 `financial_entries.client_draft_id`（新加列，迁移 `202605200002_client_draft_id.py`）。
- 服务端发现同 `client_draft_id` 已存在，直接返回 409 + 现有 entry id，幂等。

### 9.4 UI

- 新增「同步队列」入口（iOS 在「更多」、macOS 在 Sidebar 底部）。
- 列表显示状态与重试按钮。
- 创建草稿时如果网络不可达，直接 toast「已存入本地草稿，恢复网络后自动同步」。

### 9.5 验收

- 飞行模式下创建 3 笔记录，关掉飞行模式后 30 s 内全部 `synced`。
- 故意把同 `client_draft_id` 走两次，只产生一笔实际入账。

---

## 10. Phase 8：AI 月度财务故事

### 10.1 目标

每月生成一段可编辑、可改语气、可导出 PDF 的「财务故事」。

### 10.2 后端

- `POST /ai/memos/generate { period_start, period_end }` →
    1. 从 `services/report.py` 聚合：收支、Top 5 分类、订阅、信用负债、报销视角、异常 (z-score) 大额。
    2. 构造 Markdown system prompt + 上一月用户编辑过的 memo（如果有）作为 few-shot。
    3. 调 `ai_provider.completion(...)`；写入 `ai_memos`。
    4. 同时把 stats_json 完整存档。
- `PATCH /ai/memos/{id}`：仅允许 status / summary（可 user-edit）。

### 10.3 前端

- 新模块入口 `FinanceModule.aiMemo`（macOS Sidebar 进 AI 子集，iOS 在「更多」）。
- 卡片：上月、本月（草稿）、自定义区间。
- 编辑：富文本（用 `TextEditor` + Markdown 预览切换），「让 AI 改语气」按钮调 `POST /ai/memos/generate?tone=warm|terse|playful|professional`。
- 导出 PDF：macOS 用 `NSPrintOperation`；iOS 用 `UIPrintInteractionController` + `PDFKit` 渲染。

### 10.4 验收

- 同一区间二次调用 generate 不会写第二条，按 `period_start+period_end` 唯一。
- 编辑后保留时间戳；导出 PDF 文件名 `LinoFinance-月报-2026-05.pdf`。

---

## 11. Phase 9：账户对账 UI

### 11.1 后端已在 P2 完成，本阶段做 UI。

### 11.2 UI

- macOS：`Features/Accounts/ReconciliationView.swift`，Sidebar 多一个 `账户 → 对账` 子项。
- iOS：在「账户」详情下加「对账」入口。
- 表格列：账户、应有、实有、差额、币种、最近变动、Action。
- 提交 Adjustment 表单：金额、原因（下拉：手续费 / 利息 / 汇率漂移 / 系统差 / 其他）、备注；提交后 toast「已提交并写入审计日志」。

### 11.3 验收

- 提交一次后差额回到 0、审计日志里有 `account_adjustment.create`。
- 对账列表支持「全部 / 仅有差额」过滤。

---

## 12. Phase 10：附件 + 报销凭证预览

### 12.1 UI

- 新建报销 / 已确认报销详情新增附件区：上传 / 预览（图片 / PDF）/ 删除。
- iOS：`PhotosPicker` + `Transferable`；macOS：`fileImporter` + 拖入。
- 预览：图片用 `Image`；PDF 用 `PDFKit.PDFView`（macOS / iOS 都有）。

### 12.2 验收

- 上传 5 MB 图片正常；上传 30 MB 文件被拒。
- 删除附件后再次列表无该项；后台保留 30 天 soft-delete（`is_deleted = true`），逾期清理由 P11 定时任务做。

---

## 13. Phase 11：APNs 推送

### 13.1 目标

把「下次还款」「报销批准」「AI 高风险计划等待确认」做成系统通知。

### 13.2 后端

- 新增 `app/services/push_dispatch.py`：
    - 用 `aioapns` 或 `httpx` + JWT 直发 APNs（避免引入重型框架）。
    - 触发点：
        - 信用卡账单生成（`statement_generated` 状态写入时）。
        - 还款日 T-5 / T-3 / T-1 / T-0：调度任务（用 `apscheduler` 内嵌或简单 systemd timer）。
        - 报销批准 / 到账状态切换。
        - AI 高风险 plan `requires_confirmation` 出现。
    - 全部经过用户「通知规则」过滤；未匹配的不发。
- `POST /push/devices` 在 P2 已注册。

### 13.3 设置

- `/etc/linofinance/api.env` 增加 `LINOFINANCE_APNS_TOPIC` / `LINOFINANCE_APNS_KEY_ID` / `LINOFINANCE_APNS_TEAM_ID` / `LINOFINANCE_APNS_KEY_PATH`。
- 部署：把 `.p8` 私钥放 `/etc/linofinance/apns.p8`，`root:linofinance` `0640`。

### 13.4 验收

- 在 sandbox 环境对一台真机发出 1 条「还款 T-3 提醒」，可点击直跳到账单详情。
- 在 prod 环境用 dry-run 模式（`LINOFINANCE_APNS_DRY_RUN=true`）确认 payload 正确。

---

## 14. Phase 12：回归 + 发布

### 14.1 自动化验证

```bash
# 后端
cd backend && .venv/bin/ruff check .
cd backend && .venv/bin/pytest -q
cd backend && .venv/bin/alembic upgrade head --sql
python3 -m compileall backend/app backend/scripts backend/tests

# 前端
cd frontend && swift test
xcodebuild -project frontend/LinoFinance.xcodeproj \
  -scheme LinoFinance -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath frontend/.derivedData build
xcodebuild -project frontend/LinoFinance.xcodeproj \
  -scheme 'LinoFinance iOS' -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone Air' \
  -derivedDataPath frontend/.derivedData-ios build
```

### 14.2 手动 smoke（写入 `.planning/STATE.md`）

1. macOS：⌘K → 「新建 餐饮 88 招商」→ 立即出现在记录列表。
2. macOS：Menu Bar Extra 显示净资产；点「快速记账」走通。
3. macOS：Reports 切到「现金流」「分类」「信用」「报销」「订阅」均能渲染 Chart 与 Tooltip。
4. macOS：选中一笔信用账单后 Inspector 显示「AI 建议」「最近审计 3 条」。
5. iOS：底部浮动 Tab Bar + FAB 一句话记账走通。
6. iOS：Dynamic Island 启用「工商 3375 还款」Live Activity，倒计时正常。
7. iOS：锁屏 Widget、主屏 Widget、StandBy Widget 全部出现。
8. iOS：Siri 「记一笔 35 块咖啡」记录入账。
9. iOS / macOS：隐私模糊后台 → 前台 Face ID 解锁；金额无闪现。
10. iOS：飞行模式下 3 笔草稿全部成功回放、其中一笔 409 走「冲突解决」。
11. AI 月报：本月生成 + 编辑 + 导出 PDF + 切语气重生。
12. 账户对账：人为修改 `accounts.current_balance` 制造差额 → 列表显示 → 提交 `AccountAdjustment` → 差额归零。
13. 附件：上传 PDF + 图片 + 删除全走通。
14. APNs：sandbox 真机收到「还款 T-3」推送，点击进入账单。

### 14.3 发布步骤

1. 合并到 `main`，打 Tag `v1.1.0`。
2. `backend/scripts/backup_postgres.py --label pre-v1.1`。
3. `make backend-prod-migrate`（先 dry-run，再正式）。
4. `systemctl restart linofinance-api`。
5. 验证 `curl https://lf.linotsai.top/api/v1/health` 包含 `version: 1.1.0`。
6. 把更新版 `.app` 放回 `/Users/linotsai/Applications/LinoF.app`。
7. iOS 用 TestFlight 推到自己设备（依赖签名 team 已在 v1 配置完成）。
8. 在 `.planning/STATE.md` 写入 `## v1.1 Release` 段落，记录 commit、Alembic head、生产 backup 路径、APNs 配置时间。

### 14.4 回滚预案

- 数据库：每个 Phase 的 Alembic 都准备 `downgrade()`；生产 backup 在 `/opt/linofinance/backups/`，回滚先 `alembic downgrade -1` 再 `pg_restore`。
- 服务端：保留上个 release 目录 `releases/<previous>`，回滚 `ln -snf .../<previous> /opt/linofinance/app/current && systemctl restart linofinance-api`。
- 客户端：保留 `v1.0.x` 的 `.app` 与 `.ipa`，必要时直接替换。

---

## 15. 风险与对策

| 风险 | 触发条件 | 对策 |
|---|---|---|
| iOS 26 / macOS 26 API 在 18 / 15 上不可用 | 用了仅 26 的 `@available(*, iOS 26.0)` API | 全部 26-only API 走 `if #available(iOS 26, *)` 软降级；保留 18 路径 |
| Liquid Glass 在低亮度 / 高对比度下对比度不足 | 自定义颜色叠在 `.regularMaterial` 上 | 文本永远用 `.primary/.secondary` 系统色，禁止硬编码白/黑文字；高对比度模式下加 stroke 描边 |
| AI 月报 prompt 漏掉关键指标导致幻觉 | provider 临时切换或字段缺失 | `stats_json` 作为唯一事实来源喂模型；prompt 显式声明「只使用以下数字，禁止编造」；生成后做 numeric 校验，发现幻觉自动重试 1 次再降级为模板 |
| 离线草稿与 v1 既有 SQLite 路径冲突 | iOS / macOS 同时启用 | 新建独立 `LinoDraftStore.sqlite`，与 v1 调试数据库隔离 |
| APNs 沙箱证书与正式证书混用 | `.env` 错配 | 加 `LINOFINANCE_APNS_USE_SANDBOX: bool` 开关；启动时把开关写入 `/health`，便于排查 |
| Widget 数据刷新被系统压低频率 | 用户关闭后台刷新 | 在 App 主进程每次进入前台都 `WidgetCenter.shared.reloadAllTimelines()`；不依赖系统调度的最低延迟 |
| ⌘K 远端搜索拉慢主线程 | 频繁敲键盘 | 200 ms 防抖 + `Task.cancel()`；超过 500 ms 显示 spinner |
| 多窗口同时编辑导致状态丢失 | 在两个窗口同时改同一记录 | 走和离线草稿一样的 ETag / `updated_at` 校验；后端写时校验 |

---

## 16. 文件改动总览（速查）

### 16.1 新增（按 Phase 标注）

```
backend/app/api/routes/search.py                            # P2
backend/app/api/routes/attachments.py                       # P2
backend/app/api/routes/reconciliation.py                    # P2
backend/app/api/routes/ai_memos.py                          # P2
backend/app/api/routes/push.py                              # P2
backend/app/services/search.py                              # P2
backend/app/services/attachments.py                         # P2
backend/app/services/reconciliation.py                      # P2
backend/app/services/ai_memo.py                             # P2
backend/app/services/push.py                                # P2
backend/app/services/push_dispatch.py                       # P11
backend/app/services/prompts/ai_memo_zh.md                  # P2
backend/app/models/attachment.py                            # P2
backend/app/models/account_adjustment.py                    # P2
backend/app/models/ai_memo.py                               # P2
backend/app/models/push_device.py                           # P2
backend/app/schemas/{attachment,reconciliation,ai_memo,push,search}.py  # P2
backend/alembic/versions/202605200001_attachment_and_adjustment.py     # P2
backend/alembic/versions/202605200002_client_draft_id.py               # P7
backend/tests/api/test_{search,attachments,reconciliation,ai_memos,push_devices,client_draft}.py  # P2/P7

frontend/LinoFinance/DesignSystem/Tokens/FinanceTokens.swift           # P1 (rewrite)
frontend/LinoFinance/DesignSystem/Tokens/FinanceTypography.swift       # P1
frontend/LinoFinance/DesignSystem/Materials/Glass.swift                # P1
frontend/LinoFinance/DesignSystem/Components/HeroNumber.swift          # P1
frontend/LinoFinance/DesignSystem/Components/Sparkline.swift           # P1
frontend/LinoFinance/DesignSystem/Components/PrivacyAmount.swift       # P1/P6

frontend/LinoFinance/Platform/macOS/CommandPalette.swift               # P3
frontend/LinoFinance/Platform/macOS/MenuBarExtra.swift                 # P3
frontend/LinoFinance/Features/Accounts/ReconciliationView.swift        # P9
frontend/LinoFinance/Features/AIMemo/AIMemoView.swift                  # P8
frontend/LinoFinance/Features/Sync/SyncQueueView.swift                 # P7

frontend/LinoFinance/Platform/Intents/RecordExpenseIntent.swift        # P5
frontend/LinoFinance/Platform/Intents/RecordIncomeIntent.swift         # P5
frontend/LinoFinance/Platform/Intents/QueryMonthlySpendIntent.swift    # P5
frontend/LinoFinance/Platform/Intents/NextCreditDueIntent.swift        # P5
frontend/LinoFinance/Platform/Intents/ConfirmAIPlanIntent.swift        # P5
frontend/LinoFinance/Platform/Intents/LinoShortcuts.swift              # P5

frontend/LinoFinance/Platform/iOS/LiveActivities/LinoCreditDueAttributes.swift     # P4
frontend/LinoFinance/Platform/iOS/LiveActivities/LinoCreditDueLiveActivity.swift   # P4
frontend/LinoFinance/Platform/iOS/LiveActivities/LinoAIPlanAttributes.swift        # P4

frontend/LinoFinanceWidgets/...                                        # P4 (Widget Extension)
frontend/LinoFinance/Core/Sync/{DraftEntry,SyncQueue,SyncWorker}.swift # P7
frontend/LinoFinance/Core/Spotlight/SpotlightIndexer.swift             # P5
```

### 16.2 修改（不完全列举）

```
backend/app/api/router.py                # 注册新路由
backend/app/main.py                      # 注入 storage/apns 配置校验
backend/app/services/report.py           # 增加 daily_net_window
backend/app/services/ai_provider.py      # 抽出 completion(...) 通用入口（月报与 plan 共用）
backend/app/core/config.py               # 新字段
docs/api-contract.md                     # 新接口文档
docs/deployment.md                       # storage 目录、APNs key 部署

frontend/LinoFinance/App/LinoFinanceApp.swift     # MenuBarExtra, 新 Scene, 多窗口
frontend/LinoFinance/Platform/iOS/iOSRootView.swift # 浮动 Tab Bar、Dark Mode 解禁
frontend/LinoFinance/Platform/macOS/MacRootView.swift # 加 ⌘K、命令注册
frontend/LinoFinance/Features/Dashboard/DashboardView.swift # Hero + Sparkline
frontend/LinoFinance/Features/Reports/ReportsView.swift     # Apple Charts
frontend/LinoFinance/Features/Reimbursements/ReimbursementsView.swift # 附件
frontend/LinoFinance/Features/Settings/SettingsView.swift   # appearance / privacy / widget
frontend/LinoFinance/Core/Models/APIDTOs.swift              # 新增 Attachment / Adjustment / AIMemo / SearchHit DTO
frontend/LinoFinance/Core/Services/LinoAPIClient.swift      # 新增 multipart upload / search / memo / reconciliation 调用
```

---

## 17. 与 v1 兼容性承诺

1. 所有 v1 路由保持原有 path 与 body 不变；本计划仅 **新增** 接口与字段。
2. `entries`、`accounts`、`cash_flow_items`、`reimbursement_claims` 表只加列（`client_draft_id`），不动既有列；加列必须 `nullable=True` + 默认空。
3. v1 客户端（已部署到生产）即使不升级，仍能继续工作；v1.1 客户端遇到 v1 后端时所有「新功能开关」自动降级（用 `/health` 返回的 `features: { widget, memo, reconcile, search, attachments, push }` 决定）。
4. `/health` 增加 `version` 与 `features` 字段，客户端按此决定 UI 显示。

---

## 18. 任务排程建议

> 单人节奏。多人可让 P3 + P4 并行；P8 + P11 在 P2 完成后并行。

| 周 | 周一 | 周二 | 周三 | 周四 | 周五 |
|---|---|---|---|---|---|
| W1 | P1 令牌系统 | P1 组件 | P1 收尾 + 截图 | P2 模型迁移 + 搜索 | P2 对账 + 月报骨架 |
| W2 | P2 附件 + 推送骨架 | P3 ⌘K | P3 Menu Bar Extra | P3 多窗口 + Charts | P3 Inspector + 收尾 |
| W3 | P4 浮动 Tab + Hero | P4 Live Activity | P4 Widget Extension | P4 收尾 + 设备测试 | P5 App Intents |
| W4 | P5 Spotlight | P6 隐私模糊 | P7 SyncWorker | P7 冲突解决 + UI | P8 AI 月报后端 |
| W5 | P8 月报前端 + PDF | P9 对账 UI | P10 附件 | P11 APNs | P12 回归 + 发布 |

---

## 19. 完工定义（Definition of Done）

- 所有里程碑验收项打钩。
- 生产 `https://lf.linotsai.top/api/v1/health` 返回 `version: "1.1.0"` 且 `features.*` 全为 `true`。
- macOS 与 iOS 客户端 build 号 ≥ `1.1.0`。
- `.planning/STATE.md` 写完整 v1.1 段落。
- 至少 3 张 v1.1 截图存 `.planning/screenshots/`：iOS Dashboard、macOS Reports（Apple Charts）、Menu Bar Extra。
- 一份 `pg_dump` 生产备份 + 一份 Alembic 回滚演练记录。
