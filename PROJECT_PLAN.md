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

**v1.3.0（审计修复版）已发布并部署生产（2026-06-12）。** 生产 `https://lf.linotsai.top/api/v1/health` 报 `version 1.3.0`、status ok、environment production。基于 v1.2.0 全量审计（`archive/REVIEW_REPORT_v1.2.0.md`），范围 = 致命 4 + 重要 15 + 文档归真，12 个 Phase（P0–P12）。门禁：backend pytest **155 通过**、ruff 干净、alembic 单一 head `202606100002`；`swift test` **16 通过**；xcodebuild macOS + iOS BUILD SUCCEEDED。代码经 PR #4 合并入 `main`，tag `v1.3.0` 已打并推送；**自本版起 release 分支工作流退役，改 `main` 直提**（远端只剩 `main`，见 [CLAUDE.md](CLAUDE.md) 工作流）。部署收尾：`deploy-api.sh` live 部署（迁移前自动备份，currency_rate 唯一约束+去重 / seed 还款提醒规则两迁移已上）；macOS `/Applications/LinoF.app` 已换装 1.3.0（旧包备份 `LinoF.app.bak-<UTC>`）；`linofinance-jobs.timer` 已安装启用（每日 09:00 沪时，T-5/3/1/0 还款提醒生效）。完整 Plan + 实施记录见 `archive/v1.3.0_fix_plan.md`，摘要见下半部 v1.3.0 变更日志。

## 5. 当前版本 Plan

> v1.3.0 已发布并部署生产（2026-06-12），全文（§5.0–§5.2 完整 Plan + 实施记录）见 `archive/v1.3.0_fix_plan.md`，发布/部署详情见 §4 与下半部变更日志。本节回到占位空节，下一版 @planner 在此重新填写。

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

### 用户侧收尾（v1.3.0）— ✅ 已完成（2026-06-12）

> 全部完成，保留关键回滚信息备查：
> - git：PR #4 合并入 `main`、tag `v1.3.0` 已推；**release 分支工作流退役改 `main` 直提**（远端只剩 `main`，见 [CLAUDE.md](CLAUDE.md)）。
> - 后端：`deploy-api.sh` live 部署，生产 health `1.3.0`/ok；迁移前自动备份 `linofinance-pre-migration-20260610T073937Z.dump`；**回滚**＝在 hz 上 `ln -sfn /opt/linofinance/app/releases/20260529-032355 current && sudo systemctl restart linofinance-api`（+ 必要时按 backup 恢复 DB）。
> - 还款提醒：`linofinance-jobs.{service,timer}` 已装并 `enabled+active`（每日 09:00 沪时，T-5/3/1/0 生效）。
> - macOS：`/Applications/LinoF.app` 换装 1.3.0（旧包备份 `LinoF.app.bak-<UTC>`，ad-hoc 签名）。
> - 生产闸门 psql 确认 + 真机验证（Apple 登录闭环 / 第二 ID 拒 / disable→401 / APNs 真推送 / iOS 真机 install）由用户自行完成。

---

# ▌下半部 · 变更日志

> 每条 = 一句话摘要 + 关键决策/偏离 + 全文指针。完整 Phase 计划与实施记录在 archive/ 对应文件。

## v1.3.0 — 2026-06-12 · 审计修复版（致命 4 + 重要 15 + 文档归真）

主题：v1.2.0 全量审计的纯缺陷修复——单人闸门、报销 settle 旁路封堵、前端金额解析收口、时区闭环、账本口径修正、主数据 PATCH、限流/导出/附件防护、还款提醒链路、客户端缺陷批修、SPM 名实归位、文档归真。无新功能。**已发布并部署生产（2026-06-12）**：PR #4 合并入 `main`、tag `v1.3.0` 已推、release 分支工作流退役改 `main` 直提；live 部署（迁移前自动备份 + currency_rate 唯一约束/seed 还款规则两迁移）、macOS `/Applications/LinoF.app` 换装 1.3.0、`linofinance-jobs.timer` 启用（每日 09:00 沪时）；生产闸门 psql 确认与真机验证由用户自行完成。

- 后端：单人闸门（首用户自举 + 后来者建档 disabled 留痕拒发会话 + `LINOFINANCE_APPLE_SUB_ALLOWLIST` 白名单，并修存量会话洞 `get_session_for_token` 校验 `user.disabled`，disabled→`403`/存量会话被禁→`401`）；reimbursement-linked 现金流 settle 直接 `400`（强制走 mark-received，防双计）；业务时区 `app_timezone` + `timeutils.app_today/utc_to_app_date` 替换全部「今天」锚与 UTC `created_at` 取日；报销五视图统一锚原支出日期消除跨月负净值；信用周期重叠创建拒；`PATCH /accounts|/categories|/currency-rates`（汇率被引用→`409`，新增 `(from,to,date)` 唯一约束迁移含去重）；限流器进程内有界化（周期清扫 + 10000 键上限 + 最旧淘汰）；附件 owner 实体存在校验（不存在→`404`）；导出 dataset 补 categories/currency_rates/account_adjustments/attachments 闭包；幂等 seed 默认还款提醒 `NotificationRule` + `linofinance-jobs` systemd service/timer。
- 前端：统一 `parseDecimalAmount`（整串正则严格校验，拒「58元」类）收口全部金额解析；`monthlyDates` 消灭 1/31→28 漂移；今日盈亏 `abs`+显式正负号（修负号被当币符砍掉）；401 按状态码判定 + session 槽自动清 token 回登录页（消灭杀 app 重启）；现金流账户 picker 仅 balance；负号全工程统一 ASCII；版本号从 Bundle 读取；删 SPM 死码（`APIClient`/`*PlaceholderView`/`APIEndpoint`）、UTC formatter 改 `.current`。
- 关键决策/偏离（累积折叠）：
  ① git 起点——从 `release/v1.2.0` 的 `50e2188` 切 `release/v1.3.0`（非从 `main`，否则丢 plan/审计报告/Formatters 修复）；Formatters 时区修复已由既有 `9651c23` 完成，未重复提交；`REVIEW_REPORT` 已被 `50e2188` 跟踪。
  ② P3 补全——plan「12 处」枚举不完整，据 D3 收口意图补全 CreditView/AccountsView/ReconciliationView 共 10 处同类用户输入金额解析点（致命 1.4 同类隐患）。
  ③ P6 禁改字段——用 Pydantic `extra="forbid"` 走 **422**（而非自定义 400）：被传即拒、更早失败不污染 DB。
  ④ P10——额外删 `APIEndpoint.swift`；移除清空后变空的 `LinoFinanceFeatures` SPM target + product（否则 `swift test` 起不来）；`FinanceDefaultsTests` formatter 对齐 `.current`，测试数不变 16。
  ⑤ P4/P5 无迁移（纯逻辑 + 配置）；P5 `test_reimbursement_reports...` 重写并改名 `..._anchor_all_views_on_original_expense_date`。
  ⑥ P12 pbxproj 实际处数——grep 确认 `MARKETING_VERSION` 6 处 + `CURRENT_PROJECT_VERSION` 6 处（plan/CLAUDE.md「12 处」为两字段合计；按既有约定两者同步 bump 到 1.3.0）。
  ⑦ P12 alembic 门禁——full-chain `<base>→head` 在 SQLite 上止于**既有 v1.0.0** 迁移 `202605160004`（`op.create_foreign_key`，SQLite ALTER 不支持，非 v1.3.0 引入）；本仓本地 schema 真实路径是 `create_all`（`conftest.py`/`run_local_sqlite.py`），v1.3.0 两迁移经 create_all baseline + stamp 验证可升级到 head。
  ⑧ 离线草稿队列 v1.1 起从未交付（P11 文档归真改口、移入 §6 backlog）。
- pytest 113→**155**（120 P1+P2 / 132 P4+P5 / 155 P6+P7+P8；P9–P12 无后端测试增量），swift test 16。全文 + 实施记录：`archive/v1.3.0_fix_plan.md`；审计报告：`archive/REVIEW_REPORT_v1.2.0.md`。

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
