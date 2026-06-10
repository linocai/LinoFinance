# LinoFinance 审查报告 · v1.2.0

> @reviewer 一次性交付物(2026-06-10)。审查对象:`release/v1.2.0`(commit `4e8acb2` + 工作区 1 处未提交修改)。
> 方法:三路并行独立审计(后端代码 / 前端代码 / 项目与产品逻辑),主审查员对致命项逐一复核。
> 处理完毕后建议将本文件移入 `archive/`,结论按条目吸收进 PROJECT_PLAN.md 的 backlog,不留第二份长期计划类文件。

---

## 0. 总体评估

| 维度 | 结论 |
|---|---|
| 基线验证 | pytest **113 通过**、ruff 干净、alembic 链完整(head `202605270001`);swift test **16 通过**、macOS App target `xcodebuild` **BUILD SUCCEEDED** |
| 对照生效 plan 的完成度 | 约 **95%**——v1.2.0 承诺的登录 + push 回归基本兑现,核心账本逻辑(草稿/确认/作废、信用周期、报销三联动、AI 动作分级)质量扎实 |
| 对照项目自述能力的完成度 | 约 **85%**——「离线草稿队列」从未实现却被三处文档宣称;`docs/api-contract.md` 自 v1.1.0 起停更,违反施工总原则第 8 条 |
| 最大风险 | **致命 4 项**:多用户无隔离 + 开放注册;disabled 用户旧会话仍有效;报销现金流可被通用 settle 绕过造成收入双计;前端金额解析按前缀截断静默错记 |
| 问题总量 | 致命 4 / 重要 15 / 建议 20+(下文逐条) |

工作区那处未提交的 [Formatters.swift](frontend/LinoFinance/Core/Utilities/Formatters.swift) 时区修改(UTC → `.current`)经专项审查**是正确且自洽的**,且已发布的 v1.2.0 客户端仍带「UTC+8 下选 6/2 存成 6/1」的 bug——**建议尽快提交并随 patch 版发布**(详见 §3.3)。

---

## 1. 致命问题(必须裁决/修复)

### 1.1 账本完全无用户隔离,且对任意 Apple ID 开放注册

- **证据**:全部账本模型(`accounts` / `financial_entries` / `cash_flow_items` / `reimbursement_claims` / `credit_statement_cycles` / `installment_plans` / `subscription_rules` / `push_devices` / `audit_logs`)均无 `user_id` 列,grep 仅 `auth_session` / `user` 命中;除 `/auth/*` 外**没有任何路由**读取 `request.state.auth`(全表无过滤查询,如 `app/api/routes/accounts.py:23`、`app/services/ledger.py` `list_entries`)。同时 `app/services/auth.py:80-92` 对任何通过 JWKS 验证的新 Apple `sub` 自动建 user(`disabled=False`)并立即发 365 天会话;`is_admin` 字段定义后从未被检查,`mode="user"` 与 `mode="admin"` 授权完全等同(`app/core/middleware.py:96-107`)。
- **与 plan 矛盾**:`archive/v1.2_plan.md:123` 自述 "First Apple sub we see becomes the only user",代码**并未实现该闸门**。
- **影响**:任何拿到 app 构建的人用自己的 Apple ID 登录,即获得整本账完整读写(看余额流水、建账作废、改余额)。攻击面受 SIWA audience 限制(需真 app 发起),单人自用实害有限,但当前状态两头不靠:**能多人登录、数据不隔离**。
- **建议(需用户裁决)**:(a) 维持单人设计 → 加 Apple `sub` 白名单或「首个 user 之后新建一律 `disabled=True`」,成本最低;(b) 走多用户 → 需要整套 `user_id` 归属 + 查询过滤,工作量大,应开版本。无论选哪条,口径都应写进 PROJECT_PLAN。

### 1.2 用户被 disabled 后,已签发会话仍可全程访问

- **证据**:`app/services/auth.py:159` `get_session_for_token` 只判 `revoked_at` / `expires_at`,不检查 `session.user.disabled`;登录入口虽拒绝 disabled 用户(`auth.py:134`),但存量会话(默认 365 天,`config.py:44`)照常放行。
- **影响**:禁用用户无法即时切断访问,必须手动撤销其全部会话——这恰是修复 1.1 方案 (a) 的依赖项:若靠 `disabled=True` 挡新用户,这个洞会让该闸门形同虚设。
- **修复**:`get_session_for_token` 加 `if session.user is None or session.user.disabled: return None`(user 已 selectinload,零额外查询)。

### 1.3 报销现金流可被通用 settle 绕过,导致收入双计(已复核确认)

- **证据**:`app/services/cash_flow.py` `settle_cash_flow_item` 只联动 `linked_subscription_rule_id`,**不处理 `linked_reimbursement_id`**;前端 [CashFlowView.swift:196](frontend/LinoFinance/Features/CashFlow/CashFlowView.swift:196) 仅拦 transfer 方向,报销应收项照常显示「结算」。
- **复现路径**:报销 inflow 现金流被通用 settle → 现金流 settled + 生成第一笔收入 entry,但 claim 仍停在非终态;之后再走 `mark-received`(`app/services/reimbursement.py:208`,`_ensure_not_final` 不拦)→ 生成**第二笔**收入 entry。余额与收入双计,报销报表 `received_net` 还一直不动。
- **修复**:settle 时同步 claim 为 received,或对 `linked_reimbursement_id` 非空的项禁用通用 settle、强制走 mark-received(前后端都拦)。

### 1.4 前端金额解析按前缀截断,静默错记(已实测)

- **证据**:`Decimal(string: "1,234.56")` 返回 **1**(逗号截断)、`"58元"` 返回 58,而表单校验 `Decimal(string:) != nil` 照样通过。波及全部金额输入:[CashFlowView.swift:414](frontend/LinoFinance/Features/CashFlow/CashFlowView.swift:414)/449/643、[EntriesView.swift:769](frontend/LinoFinance/Features/Entries/EntriesView.swift:769)/834、QuickEntrySheet:205、MacQuickEntryView:300、DailyPnLSheet:31、DailyPnLSidebarPanel:34/91、AccountsView:395、SettingsView:502。
- **影响**:macOS 自由文本金额框粘贴「1,234.56」会被静默记成 ¥1——记账 app 最坏的错误类别:无报错、数据错。
- **修复**:收口一个统一金额解析函数:剥离分组分隔符/币符后解析,并「解析结果再格式化回去整串比对」,拒绝部分匹配。

---

## 2. 重要问题

### 后端

| # | 问题 | 证据 | 影响与建议 |
|---|---|---|---|
| 2.1 | 限流器内存字典无限增长、无淘汰 | `app/core/middleware.py:116`,过期窗口只覆盖不删除;生产 `trusted_proxy_headers` 下可伪造 `X-Forwarded-For` 制造无限 key | 长跑进程内存泄漏 + 内存型 DoS。定期清理过期 key 或有界 LRU(backlog「持久化限流后端」可归并此项) |
| 2.2 | 报销报表口径不一致 | `app/services/report.py:280,291-294`:`approved_net` 把 `reimbursable`(未批准)的支出也算入净值偏高;`received_net` 在 received 与原支出跨月时错配;`monthly_overview.personal_net_expense_cny`(:76,全量支出口径)与 `reimbursement_report.personal_net`(:294,仅可报销 gross 口径)两个「个人净支出」语义不同 | 报表跨期/部分状态下误导(不影响账本余额)。统一口径或在契约文档写明差异 |
| 2.3 | daily-pnl 同日多次提交按全部 delta 累加 | `app/services/dashboard.py:104` | 同日重复快录、或穿插 reconciliation 调整时「今日盈亏」偏差。明确语义或改为「末值 − 初值」 |
| 2.4 | 附件无归属与存在性校验 | `app/services/attachments.py:29`:`owner_id` 任意字符串不验存在,下载也不校验归属 | 任何登录者可上传/下载任意附件。至少校验 owner 实体存在;隔离方案定了后加归属校验 |
| 2.5 | 主数据(账户/分类/汇率)无 update/delete | `routes/accounts.py` / `categories.py` / `currency_rates.py` 仅 GET/POST;`currency_rates` 无 `(from,to,date)` 唯一约束,同日多条时 `_resolve_rate`(`ledger.py:382`)取哪条未定义 | 账单日/credit_limit 建错改不了、汇率录错只能将错就错、分类 `is_active` 无接口可翻。补 PATCH + 汇率唯一约束 |
| 2.6 | 信用周期无重叠校验 | `app/services/credit.py` `_validate_cycle_payload` 只校验单周期内部;`ledger.py:328` 自动归属取 `cycle_start_date desc limit 1` | 手滑建重叠周期后消费归属悄悄串账,叠加周期不可改不可关(backlog 已列 update/close,但**重叠校验未被覆盖**)。创建时校验同账户区间不重叠 |
| 2.7 | CSV 导出不构成自洽账本 | `app/services/export.py:26-41` 共 14 个 dataset,缺 `categories` / `currency_rates` / `account_adjustments` / 附件元数据 | 导出数据引用 `category_id` / `exchange_rate_id` 却导不出这两表,无法解读重建;「用户能否完整导出账本」当前答案是否(只能靠运维 pg_dump)。补全引用闭包内的表 |
| 2.8 | 还款提醒推送链路三个无文档前提 | T-5/3/1/0 提醒只在手动跑 `scripts/run_scheduled_jobs.py` 时发出,`deploy/` 无 timer/cron、`docs/deployment.md` 不提 scheduled jobs;且要求用户手动建过 `channel=system` 的 NotificationRule(无默认 seed)+ 至少一台 enabled device | 「信用卡还款提醒」核心场景生产上**大概率从未触发过**,用户以为会被提醒而错过还款。deployment.md 补 cron/timer 口径 + seed 默认规则(或前端引导创建) |

### 前端

| # | 问题 | 证据 | 影响与建议 |
|---|---|---|---|
| 2.9 | 工资月度重复日期漂移 | [CashFlowView.swift:490](frontend/LinoFinance/Features/CashFlow/CashFlowView.swift:490) `monthlyDates` 用「上一结果 +1 月」迭代:1/31 → 2/28 → **3/28**(永久钳到 28 日) | 发薪日 ≥29 的用户从 3 月起所有工资现金流日期错误。改为每次从原始 startDate `byAdding: .month, value: i` |
| 2.10 | 投资卡「今日盈亏」负数显示损坏 | [MacDashboardView.swift:194](frontend/LinoFinance/Features/Dashboard/MacDashboardView.swift:194):`dropFirst(symbol.count)` 砍掉的是负号而非币符,实测渲染成 `今日 ¥ ¥123.45`(负号丢失 + 币符重复) | 亏损天显示成正数。用 `abs` 格式化并显式拼正负号 |
| 2.11 | 401 检测靠 localizedDescription 字符串匹配 | [AppEnvironment.swift:639](frontend/LinoFinance/App/AppEnvironment.swift:639) 匹配 `"API 401"` 文案 | 401 响应体为空/非 JSON(nginx、代理)时文案不匹配 → 过期 token 永不清理。改为 `if case .badStatus(401, _)` 按状态码判断 |
| 2.12 | 运行中会话过期无重登录路径 | `loadCurrentUser()` 仅在根视图 `.task`(启动)与改 baseURL 时执行;运行中过期后 `needsSignIn` 因 keychain 仍有 token 恒为 false | 用户只能反复看 401 banner,**必须杀 app 重启**才能回登录页。在 `refreshPrimaryData` 捕获 401 时触发清 session + rebuild |
| 2.13 | 现金流编辑/补全可选 credit 账户但结算必失败 | [CashFlowView.swift:580](frontend/LinoFinance/Features/CashFlow/CashFlowView.swift:580)、:712 两处 picker 只按币种过滤;`runSettle`(:242)固定发 balance movement,后端 `ledger.py:362` 拒绝 credit 账户 | 编辑时被允许选、结算时收到晦涩 400。与 NewCashFlowSheet(:394)对齐为仅 balance 账户 |
| 2.14 | SPM「共享库」实际零共享,16 个测试不覆盖任何上线代码 | pbxproj 无任何对 LinoFinanceCore/DesignSystem/Features 的引用;`MoneyText` / `APIClient` / 各 Model 两边各一份,本次时区修复只改了 Xcode 侧、SPM `SystemIntegrationSupport.swift:90` 仍是 UTC(已现实 drift) | 不违反「业务类型不镜像 SPM」铁律,但「共享库」名实不符、`swift test` 的护栏作用≈0,应在 plan 如实标注,并删 SPM 侧已死的 `APIClient.swift`、`*PlaceholderView` |

### 文档与口径

| # | 问题 | 证据 | 影响与建议 |
|---|---|---|---|
| 2.15 | `docs/api-contract.md` 停更于 v1.1.0,违反施工总原则第 8 条 | `git log -- docs/api-contract.md` 最后一次改动 `f8859de Release v1.1.0`;缺 `/auth/*` 五接口、`PATCH /cash-flow-items/{id}`、`/accounts/{id}/daily-pnl`、`include_cancelled`、dashboard 四卡新字段;health 示例仍写 `version 1.1.0` | 契约文档已不可信。补记 v1.1.5→v1.2.0 四个版本的接口增量 |
| 2.16 | 「离线草稿队列」从未实现,但三处文档宣称已交付 | v1.1 P7 实际取消(`archive/STATE.md:318`),全工程无任何 Sync/DraftQueue/SwiftData 代码、后端无 `client_draft_id`;但 PROJECT_PLAN.md:13(项目概述)、:118(v1.1.0 变更日志)、README 三处仍宣称 | 断网时完全无法记账(无缓存无重试,ErrorBanner 的「重试」只是手动刷新),且 plan 与现实脱节误导后续规划。**要么实现、要么三处文档改口 + 列入 backlog** |
| 2.17 | 时区口径不闭环;时区修复未随 v1.2.0 发布 | 前端修复仍是未提交状态(git status M);后端 anchor 全用服务器本地 `date.today()`(`dashboard.py:20`、`report.py:142` 等),部署文档未固定服务器 TZ | 已发布客户端在北京时间 0–8 点记账日期错一天;「今日盈亏」、30 天窗口、T-N 提醒的「今天」取决于服务器时区。**提交 Formatters 修复并发 patch 版**;deployment.md 固定 `TZ=Asia/Shanghai` 或后端显式时区 |

---

## 3. 专项结论:未提交的 Formatters.swift 时区修改

**结论:正确、自洽,建议提交。**

1. 对称性成立:`linoAPIDate` 同时承担 encoder、query 参数格式化、decoder 第一优先解析器三处职责,共用同一 formatter,改 `.current` 后编码/解码闭环一致(实测 round-trip 相等)。
2. decoder 安全:`yyyy-MM-dd` formatter 对 datetime 字符串一律返回 nil(要求整串匹配),不会误吞时间戳;`linoAPIDateTime` 保持 UTC 是**正确的**(后端 naive datetime 即 UTC),不要顺手改。
3. 顺带修好三类既有 bug(UTC+8 下):DatePicker 选 6/2 存成 6/1;AI 月报「本月」被编码成上月末日;信用消费 entry_date 早一天触发后端「不在账单周期内」假阳性。
4. 遗留不对称(低危,UTC+8 不触发):`LinoAppIntents.swift:381` `monthWindow` 仍用 UTC calendar 构造再经本地 formatter 输出,负偏移时区会早一天,建议统一本地 calendar;DST 时区零点不存在时 `date(from:)` 可能 nil(Asia/Shanghai 无 DST)。
5. 独立发现:四个解析器都无法解析「naive datetime + 微秒」——生产 Postgres 列 tz-aware 不触发,仅本地 SQLite runner 有风险,可补一个带 `.SSSSSS` 的 UTC formatter 兜底。

---

## 4. 施工总原则 8 条核验

| # | 原则 | 结论 | 关键证据 |
|---|---|---|---|
| 1 | 金额计算一律服务端 | **部分成立** | 余额/报表/dashboard 确在服务端;但 [AccountsView.swift:197](frontend/LinoFinance/Features/Accounts/AccountsView.swift:197) 本地累加信用负债/净资产(与服务端净资产两套口径并存),且缺汇率时 **fallback 按 1:1 把 USD 当 CNY**(:236);MacDashboardView:386、MenuBarPopover:107 同类 |
| 2 | 原币 + 折算 CNY + 汇率三元组 | **部分成立** | entry lines / movements / cash flow / claims 四处齐全;例外:`AccountAdjustment`(含每日盈亏)只有原币 delta 无 CNY 无 rate;`CreditStatementCycle` 无 CNY 列 |
| 3 | 草稿不影响余额 | **成立** | `ledger.py:60` 仅 confirmed 走 movements;报表只查 confirmed |
| 4 | 信用还款不重复计消费 | **成立** | `credit_repayment` 归 TRANSFER 类型,消费报表只聚合 expense 分类行;void 可回滚周期金额 |
| 5 | 可报销三联动 | **成立(但有旁路)** | confirm 自动建 claim + inflow,void 自动 abandon + cancel;旁路即致命问题 1.3 |
| 6 | AI 动作分级/可确认/可回滚/可审计 | **成立** | 三级风险 + 高危强确认、rollback 接口、审计快照;auto_confirm 仍需客户端显式 execute,无无人值守 |
| 7 | iOS 快录优先 / macOS 管理优先 | **成立** | QuickEntrySheet / FloatingTabBar / Live Activity vs MenuBarPopover / Inspector / 批量表格 |
| 8 | 模型变更三件套(迁移+契约+双测试) | **不成立** | 迁移、测试有;契约文档 4 个版本未更新(见 2.15) |

## 5. 产品决策表核验

| 决策 | 结论 |
|---|---|
| 汇率手动维护、初始 6.8、历史不回写 | ✅ 成立(`constants.py:3`、initial migration seed、历史存 `exchange_rate_id`) |
| 仅 CNY/USD、非 CNY→CNY | ✅ 成立(`normalize_currency`、`routes/currency_rates.py:38` 强制 to==CNY) |
| `CreditStatementCycle` 独立对象 | ✅ 成立(但无 update/close、无重叠校验,见 2.6) |
| 报销五视图 | ✅ 成立(`report.py:47-51`;口径问题见 2.2) |
| AI 自动确认阈值 1000 CNY | ✅ 成立(`config.py:37`、`ai.py:486`) |
| DB 上云、客户端本地缓存/草稿/重试队列 | ⚠️ **半成立**:上云成立;客户端没有任何缓存/草稿/重试实现(见 2.16) |
| 账户三类型 | ✅ 成立(schema regex 校验 + 双端三分组) |

## 6. 契约差异表(api-contract.md vs 后端 vs 前端)

| 接口/口径 | 后端 | 前端 | 契约文档 | 定性 |
|---|---|---|---|---|
| `/auth/*` 五接口(v1.2) | 有 | 有 | **缺失** | 实现未入文档 |
| `PATCH /cash-flow-items/{id}`(v1.1.7) | 有 | 有 | **缺失** | 同上 |
| `POST /accounts/{id}/daily-pnl`(v1.1.6) | 有 | 有 | **缺失** | 同上 |
| `include_cancelled` + cancel 幂等(v1.1.5) | 有 | 有 | **缺失**(文档仍写旧语义) | 同上 |
| `/health` `auth_modes` / version | 有 | 有 | 示例停在 1.1.0 | 文档陈旧 |
| `GET /dashboard/summary` 四卡字段 | 有 | 有 | 仍标「待扩展」 | 文档陈旧 |
| 文档有但未实现 | — | — | **无** | 无差异 |
| 前端调了但后端没有 | — | **无** | — | 无差异 |
| `/auth/apple` 不限流 | public path 跳过限流 | — | 未写明 | 口径缺失(建议单独限流) |

## 7. Backlog 校验

PROJECT_PLAN 第 6 节既有 backlog **全部属实**(部分结算、周期 update/close、余额重算命令、可观测性、AI 两个缺失动作均确实未实现,无 plan 与代码脱节)。

**本次审计新发现、未被 backlog 覆盖,建议补入**:

1. 用户隔离/注册闸门裁决(致命 1.1)+ disabled 会话失效(1.2)
2. 报销 settle 旁路封堵(1.3)
3. 前端金额解析收口(1.4)
4. 离线草稿队列:实现或文档改口(2.16)
5. api-contract.md 补 4 个版本增量(2.15)
6. 时区闭环:提交 Formatters 修复 + 发 patch + 服务器 TZ 固定(2.17)
7. 定时任务部署口径 + 默认通知规则 seed(2.8)
8. 主数据 PATCH + 汇率唯一约束(2.5);信用周期重叠校验(2.6)
9. CSV 导出表闭包(2.7)
10. entry 编辑接口(契约文档自己列为 "Planned next",目前正式记录只能 void 重建,backlog 没接住)

## 8. 建议级改进(汇总)

**后端**:中间件每请求两次 commit 的写放大(`middleware.py:209`,可改为 last_seen 超 N 分钟才更新);死代码 `subscription.advance_next_charge_date` 无调用;CSV 导出全表入内存无上限;`GET /entries` 无分页 + N+1(`ledger.py:73`);PATCH 现金流未保护系统联动项(改了会被源对象 sync 静默覆盖);`_sync_reimbursement_cash_flow` 不重算 converted(边界);dev shortcut 空 aud 兜底。

**前端**:AccountType 严格枚举遇未知值会让整个账户列表 decode 失败(建议 unknown fallback);「本月」范围 off-by-one(MacDashboardView:83 用下月 1 日作含端点的 date_to);inspector 选中项为值快照、编辑后不更新;legacy UserDefaults 明文 token 通道未关闭(且与 keychain 身份态不一致);撤销本机会话后再调 logout 必产生 401 噪音;`refreshPrimaryData` 串行 12 请求且首错即断(MenuBarPopover 每次打开全量跑);MenuBarExtra 与快速记账窗口未走登录门;版本号兜底硬编码 "v1.1.7"(MenuBarPopover:120)、AIMemoView 硬编码 2026-05-01;共享 NumberFormatter 可变状态 + 两种负号字符混用;markReceived 武断取第一个账户/收入分类;cancelled 现金流前端完全不可见(后端 v1.1.5 特意加的参数无开关);widget 跨 target 手抄类型双份;EntryDetail 头部跨币种直加标成 CNY;AI 月报 PDF 单页截断。

**逻辑/文档**:未来现金流报表用建项时汇率 vs dashboard 实时折算的口径混用(写明即可);`docs/deployment.md` 系统性陈旧(缺 APNs/SIWA/STORAGE_ROOT env、smoke 仍纯 admin 口径、systemd 示例路径 `/srv/` vs 实际 `/opt/`);README 仍写 "v1.1 has shipped";push 设备无用户归属(单账本语义下成立,修隔离时一并处理)。

## 9. 值得肯定的设计

- **鉴权收口干净**:中间件任何异常一律干净 401 不泄 500;admin token `hmac.compare_digest` 防时序;注销/撤销在路由自己的 DB session 落库(CLAUDE.md 反复强调的游离对象坑处理正确且有测试);Apple JWT 验证扎实(audience 手动比对、kid 失配 bust 缓存重取、生产硬拒 dev shortcut)。
- **账本核心严谨**:统一 `quantize_money` ROUND_HALF_UP + 尾零裁剪;信用消费同记负债与周期、还款只算转移;void 可反向回滚 movement 与周期金额;SQLite/Postgres 分叉守卫到位;推送失败不阻断财务主流程且有 audit_log 去重。
- **前端契约工程**:`DecimalValue` 字符串编解码,金额全程不经 Double;`Nullable<T>` 三态 PATCH 语义与后端 `model_fields_set` 严格对齐并有 curl smoke 记录;`30d→30D` 的 CodingKeys 坑位注释是教科书级文档;写操作后的链式刷新纪律好;Keychain 双槽 + 一次性迁移含防重入标记。

## 10. 修复优先级建议

1. **立即(patch 版)**:1.2 disabled 会话失效(一行)+ 1.1 的注册闸门(白名单/首用户后 disabled)→ 1.3 报销 settle 旁路 → 1.4 金额解析收口 → 提交 Formatters 时区修复,四项打包一个 v1.2.1。
2. **短期**:2.9–2.13 前端缺陷批修 + 2.15/2.16/2.17 文档归真 + 2.8 定时任务口径。
3. **下一个功能版本**:2.5/2.6/2.7(主数据管理、周期校验、导出闭包)与既有 backlog 合并规划;用户隔离若走多用户方案则单独开版本。
