# LinoFinance · PROJECT_PLAN

> 本项目**唯一权威计划文件**。上半部 = 生效 Plan，下半部 = 变更日志。
> 工作流见全局 `~/.claude/CLAUDE.md` 三段式：@planner 规划 → @builder 施工 → @reviewer 审查。
> 工程性经验 / 坑见项目根 [CLAUDE.md](CLAUDE.md)。各历史版本的**完整 plan 全文**存 [archive/](archive/)，本文件只留摘要。

---

# ▌上半部 · 生效 Plan

## 1. 项目概述

LinoFinance 是个人**双币种（CNY / USD）记账与现金流控制中心**。三端：FastAPI 后端 + SwiftUI 的 iOS / macOS 客户端。**云端数据库是唯一权威数据源**，客户端是**纯在线**客户端——每次读写都直连云端 API，没有本地缓存、离线草稿队列或重试队列。离线能力在第 6 节 backlog（v1.3.0 文档归真，离线草稿队列从未交付，见下半部 v1.1.0 偏离注记）。

## 2. 架构 & 技术选型（定死，施工阶段不再选型）

| 层 | 选型 |
|---|---|
| 后端 | FastAPI 0.115 + SQLAlchemy 2.0 + Alembic + PostgreSQL 16 |
| 后端测试 / lint | `backend/.venv/bin/pytest`（当前 113 通过）/ `ruff check .` |
| 迁移 | Alembic，最新 revision `202605270001`（auth users/sessions） |
| Apple 登录验证 | `python-jose[cryptography]`（验 identity_token JWT，JWKS in-process 缓存 1h） |
| 前端 | SwiftUI 单一代码库，Xcode 工程 `frontend/LinoFinance.xcodeproj`；**业务 UI 在 Xcode target `frontend/LinoFinance/`**，SwiftPM `frontend/Sources/*` **仅作编译型护栏（`swift test`，16 通过），不被 App target 引用**（v1.3.0 P10 已清死码、收回空 target，名实归位） |
| 客户端鉴权 | `Authorization: Bearer <token>`。两条路：Apple 会话 token（`auth_sessions` 哈希匹配）或 admin 环境 token（`LINOFINANCE_API_AUTH_TOKEN`，运维旁路） |
| 导出 | V1 仅 CSV |

施工总原则（不可违背）：

1. 后端是账本真相源；金额 / 余额 / 信用负债 / 报销净额 / 报表聚合**一律以服务端计算为准**。
2. 所有金额保留原币种 + 折算 CNY + 所用汇率；前端展示原币 + CNY。
3. 正式记录必须完整、影响余额；草稿可不完整、不影响余额和正式报表。
4. 信用卡消费计入消费 + 信用负债；信用卡还款只算账户转移，不重复计入消费。
5. 可报销消费同时产生：正式支出 + 报销对象 + 未来应收现金流。
6. AI 只能通过结构化动作操作账本，所有动作分级 / 可确认 / 可回滚 / 可审计。
7. iOS 优先快速记账与一眼总览；macOS 优先表格、批量、报表、对账、管理。
8. 任何后端模型变更都要：Alembic 迁移 + 更新 `docs/api-contract.md` + happy/failure 双路径测试。

## 3. 产品决策（durable，跨版本生效）

| 决策点 | 口径 |
|---|---|
| 汇率 | V1 手动维护，不接自动汇率 API；初始 USD/CNY = `6.8`。历史记录保存当时汇率，不回写。 |
| 币种范围 | V1 仅 `CNY` / `USD`。汇率记录只能是非 CNY → CNY。 |
| 信用卡账单 | 用独立账单周期对象 `CreditStatementCycle`，不靠账单日/还款日硬算。 |
| 报销净支出 | 报表支持五视图：报销前支出 / 预计抵扣 / 已批准抵扣 / 已到账抵扣 / 个人净支出。 |
| AI 自动确认阈值 | `1000 CNY`。≤ 阈值的低风险动作可进自动确认候选，但仍须字段完整 + 可回滚 + 可审计。 |
| 数据部署 | 整个 DB 上云；客户端经域名访问后端，本地存储非主数据源。 |
| 账户类型 | `balance` / `credit` / `investment`（v1.1.6 引入，`accounts.type` 为自由 `String(32)`，无需迁移）。 |

## 4. 当前状态

**v1.2.0 已发布并部署生产（2026-05-29）。** 生产 `https://lf.linotsai.top/api/v1/health` 报 `version 1.2.0`、`auth_modes:[admin,user]`、真 APNs（非 sandbox / 非 dry-run）。代码经 PR #1 合并入 `main`，本地 tag `v1.2.0` 已打。

**v1.3.0（审计修复版）规划完成，待施工（2026-06-10）。** 基于 v1.2.0 全量审计（`REVIEW_REPORT_v1.2.0.md`，发布时归档 `archive/`），范围 = 致命 4 + 重要 15 + 文档归真，详见第 5 节。工作区有 1 处未提交的 `Formatters.swift` 时区修复（审计已确认正确），随 v1.3.0 P0 先行提交。

## 5. 当前版本 Plan · v1.3.0 审计修复版

> 发布后浓缩为下半部一条变更日志、本节回到空。
> 事实来源：v1.2.0 审计报告（现在根目录 `REVIEW_REPORT_v1.2.0.md`，P11 移入 `archive/`）；下文「审 X.Y」指报告条目编号，关键结论已内联，plan 自足可施工。
> **范围（用户已裁决，施工不再讨论）**：致命 4 项 + 重要 15 项 + 文档归真 + 个别一行级捎带。用户隔离走**单人闸门**（不做多用户 user_id 隔离）；**离线草稿队列不实现**，只做文档改口并入 backlog；其余建议级全部进第 6 节 backlog。纯缺陷修复版，无新功能。

### 5.0 设计裁决（定死，施工阶段不再选择）

| # | 分叉 | 结论 |
|---|---|---|
| D1 | 单人闸门机制 | **首用户自举 + 后来者禁用 + 可选白名单**：users 表为空时首个通过 SIWA 的 sub 建为激活用户；此后任何新 sub 一律建档 `disabled=True` 并拒发会话（留痕便于运维激活）；新增 env `LINOFINANCE_APPLE_SUB_ALLOWLIST`（逗号分隔 sub，可空），命中名单的新 sub 直接激活（解决换 Apple ID；自己的 sub 登录后从 `GET /auth/me` 的 `apple_user_id` 字段抄录）。同时修存量会话洞：`get_session_for_token` 校验 `user.disabled`。不做 admin 管理接口，激活/禁用走运维 psql（写进 deployment.md）。`is_admin` 字段本版继续不消费。 |
| D2 | 报销 settle 旁路 | **禁用通用 settle，强制 mark-received**：`linked_reimbursement_id` 非空的现金流项，后端 settle 直接 400、前端隐藏「结算」入口。不选「settle 时同步 claim」——那要在 settle 里复刻 mark-received 的 entry 生成与状态机，两套逻辑难保只生成一笔收入。 |
| D3 | 前端金额解析收口 | 统一函数 `parseDecimalAmount(_:) -> Decimal?` 放 Xcode target `frontend/LinoFinance/Core/Utilities/Formatters.swift`（SPM 库不被 App target 引用，放 SPM 无意义）：trim 空白 → 剥千分位英文逗号 → **整串正则** `^-?[0-9]+(\.[0-9]+)?$` 校验 → 通过才 `Decimal(string:)`，否则 nil。不剥币符（`"58元"`/`"¥100"` 一律拒绝报错，宁可让用户改输入也不静默吞字符）。用整串正则而非「往返格式化比对」，避免尾零 `"1.50"→"1.5"` 假阴性。 |
| D4 | daily-pnl「今日盈亏」语义 | **维持来源过滤后的 delta 累加**（现状 `source='investment_daily'` 过滤已存在），不改「末值−初值」——末值−初值会把同日穿插的转账 entry / reconciliation 修正误计入盈亏；过滤累加对同日多次快录天然等于首末差且与其它资金事件正交。本版动作：契约写明该语义 + 修日期锚（见 D6，`created_at` 是 UTC naive，当前与服务器本地 `date.today()` 比较不闭环）。 |
| D5 | 限流器淘汰策略 | **进程内有界化，不引 Redis**（backlog「持久化限流后端」仍留作可选增强）：`_InMemoryRateLimiter.hit` 内距上次清扫 ≥60s 时全量删除过期窗口；键数硬上限 10000，插入新 key 前若满则先清扫、仍满淘汰 `started_at` 最旧者。 |
| D6 | 时区口径 | **后端显式业务时区，代码侧为主**：settings 新增 `app_timezone: str = "Asia/Shanghai"`（env `LINOFINANCE_APP_TIMEZONE`），新增 `app/core/timeutils.py` 提供 `app_today()` 与 `utc_to_app_date(dt)`（py39 标准库 zoneinfo），替换全部「今天」锚与 UTC `created_at` 的取日比较；不依赖 systemd `TZ`（deployment.md 只记 env 口径）。前端已验证的 `Formatters.swift` 修复（`linoAPIDate` UTC→`.current`）P0 先行提交；`linoAPIDateTime` 保持 UTC 不动（后端 naive datetime 即 UTC，审 §3.2）。**例外**：`ai_provider.py:74` 的 `date.today()` 在 AI 冻结范围内，本版不动，挂 v1.4。 |

### 5.1 Phase 拆分

依赖顺序：P0 → P1 → P2 → P3 可并行起；P4 必须先于 P5（P5 依赖业务时区日期锚）；P6–P10 相互独立；P11 收口全部文档；P12 终验最后。

#### P0 · 施工准备（前端，10 分钟）

- 确认在 `release/v1.3.0` 分支（不存在则从最新 `main` 本地创建；工作区未提交的 `Formatters.swift` 与未跟踪的 `REVIEW_REPORT_v1.2.0.md` 会随工作区带过来，无需 stash）。
- **单独提交**工作区的 `frontend/LinoFinance/Core/Utilities/Formatters.swift` 时区修复（commit message 注明源自 v1.2.0 审计 §3 专项确认），不夹带其他文件。`REVIEW_REPORT_v1.2.0.md` 此时不提交，留给 P11 归档。
- 验收：`git log -1` 仅含该文件；xcodebuild macOS Debug 通过。

#### P1 · 鉴权单人闸门（后端）【致命 审1.1 + 审1.2】

- `app/core/config.py`：新增 `apple_sub_allowlist: str = ""`（解析为集合的 helper 随放）。
- `app/services/auth.py:80-92` `_upsert_user`：新建 user 时按 D1 决定 `disabled`（白名单命中 → False；users 表已有任意记录 → True；全空首用户 → False）；新建即 disabled 的，先 `db.commit()` 落库留痕**再**抛 `UserDisabledError`（注意：异常会触发会话回滚，仅 flush 不落库、留痕会落空；沿用现有 disabled→HTTP 映射，与 `auth.py:134` 既有拒绝路径同码）。
- `app/services/auth.py:159` `get_session_for_token`：加 `if session.user is None or session.user.disabled: return None`（user 已 selectinload，零额外查询）。
- 无迁移（users 表无新列）。同步更新 `docs/api-contract.md` 的 `/auth/apple` 段：闸门语义、disabled 错误响应、`LINOFINANCE_APPLE_SUB_ALLOWLIST`。
- 测试（happy/failure）：①空表首登录激活；②已有用户后新 sub 建档 disabled 且拒登；③白名单命中的新 sub 激活；④disabled 用户的存量有效 session 访问任意业务路由 → 401；⑤admin env token 不受影响。
- 验收：pytest 全绿、ruff 干净；本地 SQLite runner curl 复现 ②④。

#### P2 · 报销 settle 旁路封堵（全栈）【致命 审1.3】

- 后端 `app/services/cash_flow.py:104` `settle_cash_flow_item`：入口处 `item.linked_reimbursement_id is not None` → 抛 `LedgerValidationError`（400，message 指引走 mark-received）。
- 前端 `Features/CashFlow/CashFlowView.swift`：`:196` 菜单及同文件全部结算入口（详情面板 / swipe / `SettleCompletionSheet` 触发点）对 `item.linkedReimbursementId != nil`（DTO 已有，`Core/Models/APIDTOs.swift:155`）隐藏「结算」，与既有 transfer 拦截同模式。
- 契约：settle 接口补该 400 错误条目。
- 测试：①linked claim 项 settle → 400（failure）；②同一项随后 `mark-received` 正常生成唯一收入 entry、claim 终态（happy，防双计回归）；③普通项 settle 不回归。
- 验收：pytest 全绿；xcodebuild macOS 通过。

#### P3 · 前端金额解析收口（前端）【致命 审1.4】

- `Formatters.swift` 新增 `parseDecimalAmount`（按 D3 实现），替换全部 12 处 `Decimal(string:)` 金额解析与对应表单校验：`CashFlowView.swift:414/449/643`、`EntriesView.swift:769/834`、`QuickEntrySheet:205`、`MacQuickEntryView:300`、`DailyPnLSheet:31`、`DailyPnLSidebarPanel:34/91`、`AccountsView:395`、`SettingsView:502`。
- 验收：xcodebuild macOS 通过；用临时 swift 脚本对函数跑表驱动断言后删除脚本（必测：`"1,234.56"→1234.56`、`"58元"→nil`、`"1.5"→1.5`、`"-20"→-20`、`""→nil`、`"1.2.3"→nil`、`" 100 "→100`）。

#### P4 · 时区闭环（全栈）【重要 审2.17 + 审§3.4/3.5】

- 后端（按 D6）：`timeutils.py` + `app_timezone` 配置；替换锚点 `dashboard.py:20`（`date.today()`）、`dashboard.py:121`（`created_at.date()` → `utc_to_app_date`）、`report.py:142/171/327/381`、`push_dispatch.py:168`。`ai_provider.py:74` 不动（AI 冻结）。
- 前端：`LinoAppIntents.swift:381` `monthWindow` 改本地 calendar 构造（审 §3.4 负偏移时区早一天）；`Formatters.swift` 解析器链补「naive datetime + 微秒（`.SSSSSS`）UTC」兜底 formatter（审 §3.5，本地 SQLite runner 场景）。
- 测试：`utc_to_app_date` 跨日边界（UTC 16:00+ = 沪时次日）happy/failure；daily-pnl「今天」在 UTC 边界的归日用例。
- 验收：pytest 全绿；xcodebuild macOS 通过。deployment.md 的 env 增补在 P11 统一做。

#### P5 · 账本口径修正（后端）【重要 审2.2 / 审2.3 / 审2.6】（依赖 P4）

- 审2.2 报销报表跨月锚统一：`report.py:282` 与 `:461` 的 `received_in_range` 改 `original_in_range`——五视图统一锚定**原支出日期**，消除「支出 5 月、到账 6 月时 6 月报表 gross 不含原支出却扣 received」的错配与负净值；`_claim_received_date` 若失去全部调用则删除。`personal_net`（=expected_net，可报销 gross 口径）与 `monthly_overview.personal_net_expense_cny`（全量支出口径）**双口径保留、不改代码**，差异写进契约。
- 审2.3：dashboard「今日盈亏」维持过滤累加（D4），日期锚已由 P4 修正；契约写明语义（同日多次快录等于首末差、reconciliation/转账不计入）。
- 审2.6 信用周期重叠校验：`app/services/credit.py` 创建周期时校验同账户 `[cycle_start_date, cycle_end_date]` 与既有周期区间不相交，违者 400/409；消费自动归属（`ledger.py:328` 取 `cycle_start_date desc limit 1`）逻辑不动。
- 测试：①跨月报销报表前后口径用例（happy + 旧错配场景断言修复）；②重叠周期创建被拒（failure）+ 相邻不重叠周期可建（happy）。
- 验收：pytest 全绿;契约对应段落更新。

#### P6 · 主数据管理补全（后端）【重要 审2.5】

- `PATCH /accounts/{id}`：可改 `name` / `include_in_net_worth` / `status` / `display_order` / `credit_limit` / `statement_day` / `due_day` / `minimum_payment` / `notes`；**不可改** `type` / `currency` / `current_balance` / `current_liability`（余额走对账调整）。零迁移。
- `PATCH /categories/{id}`：可改 `name` / `is_active` / `display_order`；不可改 `type` / `parent_id`。
- 汇率唯一约束：Alembic 迁移给 `currency_rates` 加 `(from_currency, to_currency, date)` 唯一约束；迁移前置去重（同键多条保留 `created_at` 最新）；SQLite 走 `batch_alter_table`（本地 runner 兼容）。
- `PATCH /currency-rates/{id}`：仅 `rate` 字段，且仅当该 rate 未被任何 entry line / movement / cash flow / claim 引用时允许，被引用 → 409（守住「历史不回写」决策）。
- PATCH 语义沿用 v1.1.7 模式（`model_fields_set` 三态）。前端管理 UI 本版不做（接口先行，进 backlog）。
- 测试：三个 PATCH 各 happy/failure（含改禁改字段被拒、被引用汇率 409）；唯一约束冲突 409;迁移在含重复数据的库上可升级。
- 验收：pytest 全绿；`alembic upgrade head` SQLite/本地通过；契约新增三接口。

#### P7 · 防护与导出闭包（后端）【重要 审2.1 / 审2.4 / 审2.7】

- 审2.1：限流器按 D5 有界化（周期清扫 + 10000 键上限 + 最旧淘汰），`_rate_limit_key` 逻辑不动。
- 审2.4：`app/services/attachments.py:29` 上传/下载校验 `(owner_type, owner_id)` 对应实体真实存在，不存在 → 404；单账本语义下不做 per-user 归属。
- 审2.7：`app/services/export.py` `DATASET_MODELS` 补 `categories` / `currency_rates` / `account_adjustments` / `attachments`（元数据列，不含文件本体），使导出数据的 `category_id` / `exchange_rate_id` 引用闭包自洽。
- 测试：①限流清扫与上限淘汰单测;②不存在 owner 上传 → 404（failure）+ 真实 owner happy；③新 dataset 导出 happy + 未知 dataset failure 回归。
- 验收：pytest 全绿；契约导出 dataset 清单更新。

#### P8 · 还款提醒链路落地（后端 + 部署文件）【重要 审2.8】

- Alembic data migration：幂等 seed 一条还款提醒默认 `NotificationRule`（`channel="system"`，字段以 `push_dispatch.py:230` 起的查询条件与现有测试 fixture 为准，已存在同类规则则跳过）。
- `deploy/systemd/` 新增 `linofinance-jobs.service`（oneshot，跑 `scripts/run_scheduled_jobs.py`，env 同 api）+ `linofinance-jobs.timer`（`OnCalendar` 每日 09:00 业务时区）。
- `docs/deployment.md` 新增「定时任务」章节：timer 安装/enable 口径、不装 timer 则 T-5/3/1/0 提醒永不触发的事实声明。
- 测试：seed 迁移幂等（连升两次/库内已有规则不重复插入）；scheduled jobs 在 seed 后 dry-run 能选中规则。真推送验证留用户侧收尾。
- 验收：pytest 全绿；`alembic upgrade head` 通过。

#### P9 · 客户端缺陷批修（前端）【重要 审2.9–2.13 + 一行级捎带】

- 审2.9：`CashFlowView.swift:490` `monthlyDates` 改为每次从原始 startDate `byAdding: .month, value: i`（消灭 1/31→2/28→永久 28 的漂移）。
- 审2.10：`MacDashboardView.swift:194` 今日盈亏改用 `abs` 值格式化 + 显式拼正负号（修「负号被当币符砍掉、亏损显示成正数」）；捎带：负号字符全工程统一为 ASCII `-`（审建议级「两种负号混用」）。
- 审2.11：`AppEnvironment.swift:639` 401 判定改 `if case .badStatus(401, _)` 按状态码，废除 `"API 401"` 文案匹配。
- 审2.12：`refreshPrimaryData`（或集中错误处理）捕获 401 时——session 槽模式：清 keychain `linofinance.sessionToken` + 置 `needsSignIn=true` 回登录页；admin 槽模式：仅 banner 不清 token。消灭「必须杀 app 重启」。
- 审2.13：`CashFlowView.swift:580` / `:712` 两处账户 picker 与 `:394` NewCashFlowSheet 对齐为仅 `balance` 账户（credit 账户结算后端必拒）。
- 捎带：`MenuBarPopover:120` 版本号兜底硬编码 `"v1.1.7"` 改从 Bundle 读取。
- 验收：xcodebuild macOS Debug 通过（iOS Simulator destination 可用时一并 build）；逐项在 macOS App 手测路径写入施工记录。

#### P10 · SPM 名实归位（前端）【重要 审2.14】

- 删 SPM 侧死代码：`frontend/Sources/` 下的 `APIClient.swift`、各 `*PlaceholderView`（及仅服务于它们的测试）；pbxproj 对 SPM 库零引用，删除不影响 App target。
- `frontend/Sources/.../SystemIntegrationSupport.swift:90` 的 UTC date formatter 同步改 `.current`，消除与 Xcode 侧 Formatters 修复的现实 drift。
- 技术选型表（本文件 §2 前端行）改口在 P11 一并做。
- 验收：`swift test` 通过（数量变化如实记录）；xcodebuild macOS 通过。

#### P11 · 文档归真（文档）【重要 审2.15 / 审2.16 + 审建议级文档项】

- `docs/api-contract.md` 补 4 个版本增量并复核 P1/P2/P5/P6/P7 的顺手更新：v1.1.5（`include_cancelled` + cancel 幂等）、v1.1.6（`POST /accounts/{id}/daily-pnl`、dashboard 四卡字段）、v1.1.7（`PATCH /cash-flow-items/{id}`）、v1.2.0（`/auth/*` 五接口、health `auth_modes`/version）、v1.3.0 全部接口面变更；写明 `/auth/apple` 走公共路径不限流的现状（单独限流进 backlog）。
- `docs/deployment.md`：env 表补 APNs / SIWA / `STORAGE_ROOT` / `LINOFINANCE_APP_TIMEZONE` / `LINOFINANCE_APPLE_SUB_ALLOWLIST`；systemd 示例路径 `/srv/` → 实际 `/opt/`；smoke 章节补 user-mode 口径；disabled 用户激活/禁用 psql 操作；复核 P8 的定时任务章节。
- `README`：删除 "v1.1 has shipped" 陈旧表述;三处「离线草稿/重试队列」宣称改口为「纯在线客户端，离线能力在 backlog」。
- 本文件：§1 概述「客户端本地存储只做缓存、离线草稿和重试队列」改口；§2 前端行注明「SPM 仅编译型护栏，不被 App target 引用」；下半部 v1.1.0 变更日志条目加偏离注记（离线草稿队列实际未交付，v1.1 P7 取消）。
- `git mv REVIEW_REPORT_v1.2.0.md archive/`。
- 验收：grep 全仓不再有「离线草稿已交付」类宣称；契约与实现一致性抽查（auth / cash-flow / dashboard 三接口对照代码）。

#### P12 · 版本号 bump + 终验（全栈）

- 版本号 → 1.3.0：`backend/pyproject.toml`、`backend/app/core/config.py` `app_version`、`scripts/deploy-api.sh` `EXPECTED_VERSION`、pbxproj 12 处 `MARKETING_VERSION`（`CURRENT_PROJECT_VERSION` 递增）。
- 终验清单：pytest 全绿（应 >113）+ ruff 干净 + `alembic upgrade head`；`swift test` 通过；xcodebuild macOS Debug（iOS Simulator 可用时一并）；`scripts/deploy-api.sh --dry-run` 干净；`run_local_sqlite.py` 起本地 API 后 curl smoke：闸门拒第二用户、linked-claim settle 400、PATCH 账户生效。
- 发布收尾：本节浓缩为变更日志一条、本节清空（由 builder 在发布提交中完成）。

### 5.2 用户侧收尾（builder 在本环境做不了，用户手动）

1. 审阅施工结果后：合并 PR 入 `main`、本地打 tag `v1.3.0`、push（全部用户手动，git 纪律）。
2. live 部署：`scripts/deploy-api.sh`（先 `--dry-run`）；更新 `/etc/linofinance/api.env`：`LINOFINANCE_APP_TIMEZONE=Asia/Shanghai`（可选 `LINOFINANCE_APPLE_SUB_ALLOWLIST`）；安装并 `systemctl enable --now linofinance-jobs.timer`。
3. 生产闸门确认：psql 查 `SELECT id, apple_user_id, disabled FROM users;` 确认仅本人且激活；若表为空，**部署后尽快本人完成一次 Apple 登录占首用户位**。
4. 真机验证（单测抓不到的项）：本人 Apple 登录闭环仍正常；第二个 Apple ID 登录被拒（可选）；手动 disable 一个测试用户后其旧会话立刻 401；还款提醒真推送（等 T-N 触发或在 hz 手跑 `run_scheduled_jobs.py`）；macOS 用 `ditto` 换装 `/Applications/LinoF.app`（旧包备份 `LinoF.app.bak-<UTC>`）；iOS 真机 install（automatic signing，Team `HX73DFL88G`）。
5. v1.2.0 遗留的真机三项（§6 用户侧收尾）与上条合并执行。

## 6. Backlog / 下一步

### v1.4 候选 · AI 模块重做（bug 收集箱）

AI 模块自 v1.1.5 起持续推迟。用户反馈「AI 问题较多」但尚未给出具体清单。**这里是清单的家**——用户随时把 AI bug / 期望往下列追加，v1.4 由 @planner 据此开 Phase。施工冻结范围：`backend/app/services/ai*.py`、`backend/app/api/routes/ai.py`、`backend/app/services/prompts/*`、`frontend/.../AI*.swift`，未进入 v1.4 plan 前不动。

- （待用户填写）…
- AI 动作仍缺 `GenerateReport` / `CreateRecurringRule`（当前报表 API + 订阅 API 已覆盖阻断性工作流）。
- 〔v1.2.0 审计〕`ai_provider.py:74` 的 `date.today()` 改业务时区锚（v1.3.0 因冻结跳过）；AIMemoView 硬编码日期 2026-05-01；AI 月报 PDF 单页截断。

### 工程 Backlog · 既有项（原 STATE.md，仍为真待办）

- 报销 / 部分还款需要时，补**部分（分批）现金流结算**（含 `partial_received` 完整链路）。
- 账单周期建后若需人工对账编辑，补 `CreditStatementCycle` 的 update/close 接口（重叠校验已在 v1.3.0 P5 落地）。
- 补**账户余额重算 / 对账命令**：从 movements + 周期金额重建余额。
- 生产可观测性增强（如需）：外部错误追踪、持久化限流后端（进程内有界化已在 v1.3.0 P7 完成，Redis 仍为可选增强）、日志投递、可用性探测。

### 工程 Backlog · v1.2.0 审计建议级（未进 v1.3.0，按需排版本）

立项类：
- **离线草稿队列**（审 2.16，用户裁决本版不实现）：客户端缓存 + 草稿 + 重试队列，需后端 `client_draft_id` 幂等支持，独立开版本。
- **entry 编辑接口**（契约文档自列 "Planned next"）：正式记录目前只能 void 重建。
- 主数据管理前端 UI（v1.3.0 P6 只补了 PATCH 接口）。
- push 设备用户归属（单账本语义下成立，若将来走多用户随隔离一并做）。

后端：
- 中间件每请求两次 commit 写放大（last_seen 超 N 分钟才更新）；死代码 `subscription.advance_next_charge_date`；CSV 导出全表入内存无上限；`GET /entries` 无分页 + N+1；PATCH 现金流未保护系统联动项（会被源对象 sync 覆盖）；`_sync_reimbursement_cash_flow` 不重算 converted；dev shortcut 空 aud 兜底；`/auth/apple` 公共路径单独限流。

前端：
- AccountType 严格枚举遇未知值整列表 decode 失败（补 unknown fallback）；「本月」范围 off-by-one（MacDashboardView:83）；inspector 选中项值快照编辑后不更新；legacy UserDefaults 明文 token 通道未关闭；撤销本机会话后 logout 产生 401 噪音；`refreshPrimaryData` 串行 12 请求且首错即断；MenuBarExtra / 快速记账窗口未走登录门；markReceived 武断取第一个账户/收入分类；cancelled 现金流前端无开关可见；widget 跨 target 手抄类型双份；EntryDetail 头部跨币种直加标成 CNY；本地累加净资产与服务端口径并存、缺汇率时 1:1 fallback（AccountsView:197/236 等，违反施工总原则 1 的残留）。

口径：
- `AccountAdjustment` / `CreditStatementCycle` 缺「折算 CNY + 汇率」三元组（施工总原则 2 残留）；未来现金流报表「建项时汇率 vs 实时折算」口径混用写明即可。

### 用户侧收尾（v1.2.0 遗留，与 v1.3.0 §5.2 收尾合并执行）

- iOS 真机签名 install（automatic signing，Team ID `HX73DFL88G`，验证 portal capability/profile）。
- 真机 Apple ID 完整登录闭环。
- 真机收 APNs 推送（含 hz 上 push smoke）。

---

# ▌下半部 · 变更日志

> 每条 = 一句话摘要 + 关键决策/偏离 + 全文指针。完整 Phase 计划与实施记录在 archive/ 对应文件。

## v1.2.0 — 2026-05-29 · 双端登录现代化 + iOS Push 回归

主题：Sign in with Apple 作主登录 + 恢复被 v1.1.0 剥掉的 iOS 推送 entitlements。
- 后端：新建 `users` + `auth_sessions` 两表（alembic `202605270001`，自 `202605200001` 来首个迁移）；5 个 `/auth/*` 接口（apple / me / logout / sessions / sessions/{id}）；中间件支持会话 token + admin 环境 token 两条路；admin 旁路保留给 ops。
- 前端：客户端 Keychain 从单槽 `linofinance.apiToken` 升级为双槽 `linofinance.sessionToken` / `linofinance.adminToken`，含一次性迁移把老 token 搬进 admin 槽；iOS + macOS 登录门（`SignInWithAppleView`）+ Settings 设备列表；老 token 粘贴退到「高级设置/管理员 Token」折叠区。iOS entitlements 回归 `aps-environment=production` + App Groups + SIWA，widget 共享 App Group。
- 关键决策/偏离：①方案 A（Sign in with Apple）优于 token+QR / 用户名密码；②`python-jose` 3.5 的 `jwt.decode` 只收单字符串 audience，改为 `verify_aud:False` + 手动比对 `aud in expected_audiences`；③新增 `LINOFINANCE_APPLE_DEV_SHORTCUT`（仅非生产可跳过 JWKS，生产启动期硬拒）；④`auth_sessions` 不复用 `IDTimestampMixin`（列名是 `issued_at`/`last_seen_at`）；⑤P4 沿用 v1.1.7 P2 判断，auth DTO 放 Xcode target 不镜像 SPM，跳过 SPM 编码测试。
- pytest 88→113，swift test 16。全文：`archive/v1.2_plan.md`。

## v1.1.7 — 2026-05-24 · 现金流操作模型重写

主题：每条非终态现金流可编辑；「结算」从两步（确认→结算）收成单一动作，自动补缺失字段。
- 后端单接口：`PATCH /cash-flow-items/{id}`，仅 `expected`/`confirmed` 可改，`settled`/`cancelled` 锁定；非 CNY 须带 `exchange_rate_id`。零迁移。
- 前端：菜单去掉「确认发生」，「结算」齐字段直接走、缺字段弹 `SettleCompletionSheet`（前端 PATCH + settle 两调，服务端语义不变）；macOS 详情面板 + iOS swipe actions 加「编辑」。
- 偏离：`Nullable<T>` + `CashFlowItemUpdateRequest` 放 Xcode target 不镜像 SPM，跳过 SPM 测试（真实 PATCH curl smoke 校验 `account_id:null` 真输出 JSON null）。pytest 82→88，swift test 16。全文：`archive/v1.1.7_fix_plan.md`。

## v1.1.6 — 2026-05-24 · Dashboard 四卡改版 + 投资账户

主题：引入第三账户类型 `investment` + 重排 Dashboard KPI + 每日盈亏快录。
- 后端：`accounts.type` 复用自由 String 无迁移；生产把 funds/stock 账户 backfill 为 `investment`（先 read-only 审计 UUID 再单事务 UPDATE + audit_logs）；重写 `GET /dashboard/summary` 为分币种可支配/投资/今日盈亏/30 天现金流净额，净资产含投资；新增 `POST /accounts/{id}/daily-pnl`（提交新余额，服务端算 delta，写 `account_adjustments` + `audit_logs`）。
- 前端：四卡（未来一月可支配 / 投资账户 / 净资产 / 未来 30 天现金流）；账户列表三分组（余额/投资/信用）；macOS 侧栏内嵌每日盈亏快录，iOS 行内 `+` 弹 sheet。
- 偏离：`.app` 实际装到 `/Applications/LinoF.app`（非历史误写的 `/Users/linotsai/Applications/`），按「装哪替哪」原则收尾。全文：`archive/v1.1.6_fix_plan.md`。

## v1.1.5 — 2026-05-23 · 现金流取消语义 + 前端缺陷批修

主题：低风险 patch，修现金流「取消」幂等 + 10 项前端缺陷 + 产出部署脚本。
- 后端唯一接口面变更：`GET /cash-flow-items` 默认隐藏 `cancelled`，加 `include_cancelled` 参数；`POST /cash-flow-items/{id}/cancel` 对已取消改幂等 200。携入已并入 main 的 AI parser bias 提交 `d6f4107`。
- 副产物：`scripts/deploy-api.sh`（`--dry-run` 须干净，live 部署用户手动）。AI 模块按指示跳过。
- 偏离：实际函数名 `listCashFlowItems`（plan 写 `cashFlowItems`）；默认隐藏后 2 条订阅测试补 `?include_cancelled=true`。pytest 69→72，swift test 16。全文：`archive/v1.1.5_fix_plan.md`。

## v1.1.0 — 2026-05-20 · 平台集成与体验升级

主题：「记得快、看得清、AI 真有用、系统真集成」。
- Liquid Glass 设计 token；macOS MenuBarExtra + Apple Charts + 多窗口；iOS 浮动 Tab + Dynamic Island/Live Activity + widgets；App Intents/Siri/Spotlight；隐私模糊 + Face/Touch ID；AI 月报（语气 + 幂等）；账户对账 + 审计日志；附件（P10）；APNs 推送基础（P11）。
- **偏离注记（v1.3.0 P11 文档归真补记）**：当时计划列含「离线草稿队列」，实际**从未交付**——v1.1 P7 已取消该项，客户端始终是纯在线模型。README / PROJECT_PLAN §1 等多处一度沿袭旧宣称，v1.3.0 P11 统一改口、把「离线草稿队列」移入第 6 节 backlog（审 2.16）。
- alembic 推进到 `202605200001`（attachment + adjustment）。pytest 56→69，swift test 12→16。完整计划：`archive/plan_v1.1.md`、设计方向 `archive/LinoFinance前端设计方向.md`。

## v1.0.0 — 2026-05-16 · 首版上云

主题：完整账本后端 + macOS 客户端 + 首次生产部署。
- 后端 Phase 1–8：账户/分类/汇率/分录、信用账单周期、现金流、报销、分期/订阅、AI 计划+通知、报表+CSV 导出、生产硬化（token 鉴权/限流/请求 ID/结构化日志/备份恢复脚本/systemd+nginx runbook）。alembic `202605160001`→`202605160005`。
- 首次部署 `hz`：域名 `https://lf.linotsai.top/api/v1`，systemd `linofinance-api`，PostgreSQL 16，Let's Encrypt（到期 2026-08-14）。上云前审计与阻断修复见 `archive/PRECLOUD_AUDIT.md`。
- 完整计划：`archive/plan.md`（综合 `archive/LinoFinance前置计划.md`）。早期一次性环境错误（pip editable / setuptools discovery 等）见 `archive/ERRORS.md`。
