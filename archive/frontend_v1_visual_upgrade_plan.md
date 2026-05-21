# LinoFinance Frontend v1 Visual Upgrade Plan

版本：v1.1.x 前端视觉修复计划  
计划日期：2026-05-20  
权威视觉稿：[`v1.1前端升级预览.html`](v1.1前端升级预览.html)  
适用平台：macOS 15+ / iOS 18+  

> 本计划只解决「SwiftUI 前端与 HTML 高保真预览差距过大」的问题。目标不是继续堆新业务能力，而是让 macOS 和 iOS 的真实 app 达到 HTML 预览稿的视觉、层级、交互密度和完成度。

---

## 0. 当前问题判断

### 0.1 macOS

当前 macOS 已经有 P3/P8/P9/P10/P11 的功能骨架，例如 `CommandPalette`、`MenuBarExtra`、多窗口、Charts、AI 月报、对账、附件等。但真实 UI 仍主要依赖：

- 系统 `NavigationSplitView`
- 系统 `List`
- 系统 `.toolbar`
- 通用 `FinancePanel`
- 共享桌面/移动业务页面

这导致它看起来像一个普通系统工具 app，而不是 HTML 中的「Liquid Glass 财务控制台」。

主要缺口：

- 没有自定义 macOS titlebar / toolbar 视觉。
- Sidebar 仍是系统 List，不是 HTML 的 branded sidebar。
- Content 背景没有 HTML 的 canvas 渐变和 layered surface。
- Dashboard 仍是普通 KPI grid，不是 HTML 的控制台首页。
- Inspector 还没有完整做到 Hero 信息卡 + 审计 + AI 建议 + 附件的视觉统一。
- Command Palette 功能有了，但外观仍偏系统窗口，不是 HTML 的 glass overlay。

### 0.2 iOS

当前 iOS 做了产品结构升级：

- 隐藏系统 TabBar，加入自定义 `FloatingTabBar`。
- 有中央 FAB。
- 有 `QuickEntrySheet` 的 AI / 表单 / 粘贴三段式。
- Dashboard 顶部有 HeroNumber + Sparkline。

但 iOS 仍不是 HTML 里的效果：

- Floating TabBar 只是基础胶囊，没有 active glass highlight、层级和动效。
- Quick Entry 仍是原生 `Form`，视觉和 HTML 的 glass sheet 不一致。
- Dashboard 顶部升级了，但下方卡片仍是旧 `FinancePanel`。
- More、列表、详情、设置等页面大量复用桌面式共享页面。
- 整体缺少统一的 iOS page chrome、卡片节奏、空态、按钮、行样式和 motion。

---

## 1. 总目标

### 1.1 一句话目标

把当前 SwiftUI app 从「功能完整但默认系统控件感强」升级为「真实接近 HTML 预览稿的 Liquid Glass 财务产品」。

### 1.2 视觉目标

必须对齐 HTML 中这些关键视觉信号：

- `--bg-canvas`：全局背景不是纯色，而是轻微层次化 canvas。
- `--surface-raised` / `--surface-glass` / `--surface-glass-strong`：卡片、工具栏、tabbar、popover 有明确 surface 分层。
- `--shadow-soft` / `--shadow-elevated` / `--shadow-floating`：不同高度的组件有不同阴影。
- Hero 数字使用大字号、monospaced digit、隐私模糊兼容。
- macOS 是「三栏控制台」，不是系统默认三栏。
- iOS 是「一眼看净资产，两秒记一笔」，不是一组系统表单。

### 1.3 不做

- 不新增后端业务能力。
- 不改 DTO wire shape。
- 不重写业务逻辑。
- 不重新规划 P7 离线草稿。
- 不做 TestFlight。
- 不为了视觉重构删除现有 P3-P11 功能。

---

## 2. 设计系统重修

### 2.1 文件范围

重点文件：

- `frontend/LinoFinance/DesignSystem/Tokens/FinanceTokens.swift`
- `frontend/LinoFinance/DesignSystem/Tokens/FinanceTypography.swift`
- `frontend/LinoFinance/DesignSystem/Materials/Glass.swift`
- `frontend/LinoFinance/DesignSystem/Components/FinanceComponents.swift`
- 新增 `frontend/LinoFinance/DesignSystem/Components/LiquidComponents.swift`

### 2.2 Token 补齐

将 HTML CSS token 完整映射到 SwiftUI：

- `Canvas`
  - `base`
  - `deep`
  - `gradient`
- `Surface`
  - `raised`
  - `glass`
  - `glassStrong`
  - `deep`
  - `overlay`
- `Stroke`
  - `hairline`
  - `soft`
  - `selected`
- `Shadow`
  - `soft`
  - `elevated`
  - `floating`
- `Brand`
  - `primary`
  - `deep`
  - `soft`
- `State`
  - `income`
  - `expense`
  - `credit`
  - `warning`
  - `ai`
  - `pending`
- `Radius`
  - `sm = 10`
  - `md = 14`
  - `lg = 22`
  - `xl = 30`
  - `pill = 999`

### 2.3 基础组件

新增或重写：

- `LiquidPageBackground`
- `LiquidCard`
- `LiquidToolbar`
- `LiquidSegmentedControl`
- `LiquidIconButton`
- `LiquidIconPill`
- `LiquidMetricCard`
- `LiquidSectionHeader`
- `LiquidListRow`
- `LiquidEmptyState`
- `LiquidStatusTag`
- `LiquidSearchField`
- `LiquidPopoverSurface`

验收要求：

- 不再靠散落的 `.background(FinanceTokens.Surface.raised)` 手写每个页面。
- 所有页面 surface 层级来自统一组件。
- Light / Dark 都能保持对比度。
- `swift test` 与 macOS/iOS build 必须通过。

---

## 3. macOS Visual Parity

### 3.1 目标

macOS 要对齐 HTML 的「三栏控制台 + 内嵌标题栏 + 高密度报表 + Inspector」。

### 3.2 新 macOS 外壳

重点替换：

- `frontend/LinoFinance/Platform/macOS/MacRootView.swift`

新增：

- `frontend/LinoFinance/Platform/macOS/MacChromeView.swift`
- `frontend/LinoFinance/Platform/macOS/MacSidebarView.swift`
- `frontend/LinoFinance/Platform/macOS/MacTitleToolbar.swift`
- `frontend/LinoFinance/Platform/macOS/MacInspectorChrome.swift`

施工内容：

- 保留 `NavigationSplitView` 的状态语义，但视觉上改成自定义三栏 chrome。
- Sidebar 使用自定义 `VStack/ScrollView`，不用裸 `List`。
- Sidebar 分组对齐 HTML：
  - 主控台
  - 分析 · AI
  - 系统
- Sidebar item：
  - 图标 16pt
  - active item 使用 brand gradient
  - badge 使用 glass pill
- 底部 API footer 做成 glass card。
- 顶部 toolbar 内嵌：
  - 窗口标题
  - 新建
  - AI
  - 币种
  - 时间范围
  - 搜索 / Command Palette
  - 刷新
- 内容区背景使用 `LiquidPageBackground`。
- Inspector 背景使用 `Surface.deep`，卡片用 `LiquidCard`。

### 3.3 macOS Dashboard

重点文件：

- `frontend/LinoFinance/Features/Dashboard/DashboardView.swift`

新增：

- `MacDashboardHero`
- `MacKPIGrid`
- `MacDashboardChartCard`
- `MacDashboardInsightCard`

施工内容：

- macOS 不再走普通 `SummaryGrid`。
- 顶部使用 HTML 中的 content head：
  - 标题「总览」
  - subtitle 包含 API 状态 / 日期
  - 时间范围 segmented control
- KPI 卡片对齐 HTML：
  - 4 列布局
  - icon pill
  - value 大号 mono
  - label
  - trend line
  - subtle radial highlight
- 主内容区域：
  - 现金流趋势 chart card
  - 分类支出 card
  - AI 月报 / 待确认 card
  - 报销与信用摘要 card

### 3.4 macOS Reports

重点文件：

- `frontend/LinoFinance/Features/Reports/ReportsView.swift`

施工内容：

- 保留 Apple Charts，但包在 `LiquidChartCard` 中。
- 图表标题、legend、tooltip 和空态统一。
- segmented report picker 改为 `LiquidSegmentedControl`。
- Charts 空数据、单条、多条数据都要漂亮。

### 3.5 macOS Command Palette

重点文件：

- `frontend/LinoFinance/Platform/macOS/CommandPalette.swift`

施工内容：

- 外层改成 HTML 的 centered glass overlay。
- 搜索框使用 `LiquidSearchField`。
- 行样式使用 `LiquidListRow`，保留键盘操作。
- 快捷键提示使用 kbd chip。

### 3.6 macOS Inspector

重点文件：

- `frontend/LinoFinance/Features/Shared/SelectionDetailView.swift`
- `frontend/LinoFinance/Platform/macOS/InspectorView.swift`

施工内容：

- 顶部 Hero 信息卡：
  - icon pill
  - 标题
  - 主金额
  - 状态 tag
  - subtitle
- 分区：
  - 关键字段
  - 审计 · 最近 3 条
  - AI 建议
  - 附件
- 所有 detail row 使用统一 spacing、hairline、mono value。

### 3.7 macOS 验收

截图必须生成：

- `.planning/screenshots/frontend-v1-macos-dashboard-light.png`
- `.planning/screenshots/frontend-v1-macos-dashboard-dark.png`
- `.planning/screenshots/frontend-v1-macos-reports-light.png`
- `.planning/screenshots/frontend-v1-macos-command-palette.png`
- `.planning/screenshots/frontend-v1-macos-inspector.png`

手动验收：

- 主窗口第一屏必须明显像 HTML 的 macOS preview。
- Sidebar active item 是蓝色 gradient。
- 顶部 toolbar 是内嵌 glass，而不是系统默认工具栏观感。
- Dashboard KPI 卡片与 HTML 的卡片层级一致。
- Command Palette 打开时是 floating glass overlay。
- Reports 不再像普通表单页。

---

## 4. iOS Visual Parity

### 4.1 目标

iOS 要对齐 HTML 的「Hero Dashboard + Floating Liquid Glass TabBar + 中央 FAB + 两秒记账」。

### 4.2 iOS Root Chrome

重点文件：

- `frontend/LinoFinance/Platform/iOS/iOSRootView.swift`
- `frontend/LinoFinance/Platform/iOS/FloatingTabBar.swift`

新增：

- `frontend/LinoFinance/Platform/iOS/iOSPageChrome.swift`
- `frontend/LinoFinance/Platform/iOS/iOSMoreHubView.swift`

施工内容：

- 所有 tab 页面使用统一 `iOSPageChrome`。
- 背景使用 `LiquidPageBackground`，不再只是纯 `Surface.base`。
- Floating TabBar 对齐 HTML：
  - capsule glass strong
  - active tab 有 soft highlight
  - FAB 嵌入中间且视觉上浮
  - tab icon/title spacing 固定
  - 避免遮挡底部内容
- 长按 FAB 的菜单保持：
  - 新建收入
  - 新建支出
  - 新建信用消费
  - 新建报销

### 4.3 iOS Dashboard

重点文件：

- `frontend/LinoFinance/Features/Dashboard/DashboardView.swift`

施工内容：

- Hero card 对齐 HTML：
  - 净资产 eyebrow
  - HeroNumber
  - 隐藏金额按钮
  - 30 天 Sparkline
  - 余额 / 信用负债 / 30 天净额 三个 mini metric
- 今日 / 待办 / 异常使用 glass-card，不是普通小格子。
- AI 月报卡加入首页下方，视觉上有 AI soft gradient。
- 列表型 dashboard card 改成移动端卡片节奏。

### 4.4 Quick Entry Sheet

重点文件：

- `frontend/LinoFinance/Platform/iOS/QuickEntrySheet.swift`

施工内容：

- 从原生 `Form` 改成自定义 glass sheet。
- 顶部：
  - drag handle
  - 标题「两秒记账」
  - segmented control：AI / 表单 / 粘贴
- AI tab：
  - 大文本输入卡
  - 示例 chip
  - primary action button
- 表单 tab：
  - amount first
  - title / account / category / date
  - direction segmented
  - 缺字段时显示 draft explanation
- 粘贴 tab：
  - 读取剪贴板按钮
  - text preview
  - 走同一 AI flow
- 错误态用 inline glass banner。

### 4.5 iOS More Hub

当前更多页是导航列表，需要升级为卡片 hub。

施工内容：

- 入口分组：
  - 账户与对账
  - 报销与附件
  - 分析与 AI
  - 通知与设置
- 每个入口是 `LiquidListRow` / card row：
  - icon pill
  - title
  - subtitle
  - optional badge
- 不使用裸系统 `List`。

### 4.6 iOS 业务列表

优先改造：

- Accounts
- Entries
- CashFlow
- Credit
- Reimbursements
- AI
- Notifications
- Settings

统一要求：

- 不直接裸用 `List` 作为主视觉。
- row 使用 `LiquidListRow`。
- 金额靠右但允许换行。
- status tag 固定高度，不撑爆。
- action menu 用图标按钮。
- 空态使用 `LiquidEmptyState`。

### 4.7 iOS 详情 Sheet

重点文件：

- `frontend/LinoFinance/Features/Shared/SelectionDetailView.swift`

施工内容：

- 详情 sheet 顶部使用 Hero card。
- 关键字段改成移动端 grouped card。
- 附件预览、AI 建议、审计记录保持同一视觉语言。

### 4.8 iOS Settings

重点文件：

- `frontend/LinoFinance/Features/Settings/SettingsView.swift`

施工内容：

- 保留 iOS 原生 Form 的可用性，但外层视觉升级：
  - grouped glass sections
  - token 化 header
  - token/API 状态卡
  - Widget & 通知卡
  - 隐私卡
- API URL 长文本完整换行和复制。

### 4.9 iOS 验收

截图必须生成：

- `.planning/screenshots/frontend-v1-ios-dashboard-light.png`
- `.planning/screenshots/frontend-v1-ios-dashboard-dark.png`
- `.planning/screenshots/frontend-v1-ios-quick-entry-ai.png`
- `.planning/screenshots/frontend-v1-ios-quick-entry-form.png`
- `.planning/screenshots/frontend-v1-ios-more-hub.png`
- `.planning/screenshots/frontend-v1-ios-settings.png`

手动验收：

- 第一眼必须像 HTML 的 iOS preview，而不是系统 Form app。
- Floating TabBar 不遮挡内容。
- FAB 打开 Quick Entry 顺滑。
- Dashboard Hero 数字、Sparkline、AI 卡都在首屏内。
- iPhone 小屏无横向溢出。

---

## 5. 全局迁移规则

### 5.1 禁止继续扩大系统默认 UI

除非有明确平台理由，否则不要新增：

- 主页面裸 `List`
- 主页面裸 `Form`
- 散落 `.background(Color...)`
- 散落 `.regularMaterial`
- 页面内自造一套局部 card 样式

允许：

- 设置页局部使用 Form，但要包在视觉统一外壳内。
- picker、date picker、file importer 继续用系统控件。

### 5.2 保留功能，替换外观

视觉升级不得破坏：

- API 请求
- view model 状态
- selection / inspector
- Quick Entry 创建逻辑
- Push routing
- Spotlight routing
- Privacy lock
- Widget snapshot 写入

### 5.3 兼容性

- macOS 15+ 必须编译。
- iOS 18+ 必须编译。
- 若使用 macOS/iOS 26 特性，必须 `if #available` 降级。
- Dark Mode 必须全页面可读。

---

## 6. 施工顺序

### P0：建立视觉基线

1. 打开 HTML 预览，截取 macOS/iOS 关键区域。
2. 运行当前 app，截取同区域。
3. 放入 `.planning/screenshots/baseline-*`。
4. 列出最大 10 个视觉差距。

### P1：DesignSystem 补齐

1. 补齐 token。
2. 新增 Liquid 基础组件。
3. 替换 `FinancePanel` 内核，但不大面积改页面。
4. 编译验证。

### P2：macOS 外壳

1. 重做 `MacRootView` chrome。
2. 自定义 Sidebar。
3. 自定义顶部 toolbar。
4. Inspector shell token 化。
5. 截图验收。

### P3：macOS 首页与核心页

1. Dashboard 对齐 HTML。
2. Reports chart cards 对齐。
3. Command Palette 对齐。
4. Inspector detail cards 对齐。

### P4：iOS 外壳

1. 重做 `FloatingTabBar`。
2. 新增 `iOSPageChrome`。
3. 重做 More Hub。
4. 调整 safe area 和底部 inset。

### P5：iOS 首页和 Quick Entry

1. Dashboard Hero 对齐。
2. Dashboard cards 对齐。
3. Quick Entry 从 Form 改为 custom glass sheet。
4. 截图验收。

### P6：业务页面扫尾

1. Accounts / Entries / CashFlow / Credit。
2. Reimbursements / Attachments。
3. AI / AI Memo。
4. Notifications / Settings。

### P7：深色模式、动效和最终 QA

1. Light/Dark screenshots。
2. 小屏截图。
3. macOS 窄窗口截图。
4. Swift test + xcodebuild。
5. 替换本机 macOS app。

---

## 7. Test Plan

### 7.1 自动化

```bash
cd frontend && swift test
```

```bash
xcodebuild -project frontend/LinoFinance.xcodeproj \
  -scheme LinoFinance \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath frontend/.derivedData build
```

```bash
xcodebuild -project frontend/LinoFinance.xcodeproj \
  -scheme 'LinoFinance iOS' \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone Air,OS=26.4.1' \
  -derivedDataPath frontend/.derivedData-ios build
```

### 7.2 视觉验收

必须保存截图：

- macOS Dashboard light/dark
- macOS Reports
- macOS Command Palette
- macOS Inspector
- iOS Dashboard light/dark
- iOS Quick Entry AI/Form
- iOS More Hub
- iOS Settings

### 7.3 手动 smoke

macOS：

- 切换模块。
- 打开 Command Palette，执行模块跳转、远端搜索、自然语言 AI plan。
- Menu Bar Extra 显示净资产并能刷新。
- Reports 每个 tab 不崩、不溢出。
- Inspector 选择账户、记录、报销、AI plan 都有统一 Hero。

iOS：

- 首屏 token 配置。
- Dashboard 首屏完整。
- FAB 打开 Quick Entry。
- AI / 表单 / 粘贴三条路径可创建 draft 或 confirmed entry。
- More Hub 能进入所有模块。
- 设置页 API URL / Token / 隐私 / 推送可操作。

---

## 8. Definition of Done

本计划完成的标准：

- macOS 第一屏和 HTML macOS preview 在布局、层级、颜色、卡片、toolbar、sidebar 上明显一致。
- iOS 第一屏和 HTML iOS preview 在 Hero、TabBar、FAB、卡片节奏上明显一致。
- 不再给人“只是系统 List/Form 套壳”的感觉。
- Light/Dark 都可用。
- `swift test`、macOS build、iOS simulator build 通过。
- `.planning/STATE.md` 记录实际截图路径、构建命令和剩余差距。

