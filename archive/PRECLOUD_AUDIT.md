# Pre-Cloud Audit

Last updated: 2026-05-16

## Scope

本轮只处理上云阻断项：后端数据正确性、主流程闭环、安全/部署前稳定性，以及当前 macOS 客户端可用性。真实云服务器、DNS、证书、线上环境变量和首次部署按 `docs/deployment.md` 执行，不在本轮本地代码施工内。

对照文件：

- `LinoFinance前置计划.md`
- `LinoFinance前端设计方向.md`

## Aligned And Completed

- 双币种 V1 目标已收敛为 `CNY` / `USD`，所有金额保留原币种与 CNY 折算。
- 账户、分类、正式/草稿记录、账户变动、信用账单周期、信用消费/还款、未来现金流、报销、分期、订阅、AI 计划、通知规则、报表与 CSV 导出均已有后端 API。
- macOS 当前客户端已接入真实 API，覆盖 Dashboard、Accounts、Entries、Cash Flow、Reimbursements、Credit、Reports、AI、Notifications、Settings。
- Phase 8 已补生产硬化基础：API token 鉴权、限流、请求 ID、结构化日志、生产 token 强校验、备份/恢复脚本、Docker Compose、systemd/nginx 示例和部署 runbook。

## Fixed Pre-Cloud Blockers

- 中间件顺序已修正：请求 ID 最外层，鉴权早于限流；缺失/无效 token 的 `401` 不消耗限流额度，合法 token 首次请求不会被前一个非法请求误伤。
- 汇率一致性已收紧：V1 只接受 `CNY`/`USD`；汇率记录只能是非 CNY 到 `CNY`；显式 `exchange_rate_id` 必须匹配请求币种到 `CNY`，且汇率日期不能晚于交易日期；客户端传入的 `converted_cny_amount` 必须与服务端计算一致。
- 报销绑定已收紧：手工报销必须绑定已确认 entry 的支出分类明细；金额/币种必须匹配；同一个 `EntryCategoryLine` 不能重复生成报销对象。
- 现金流结算已收紧：结算 entry 必须与 cash-flow 的方向、币种、金额、账户、分类和类型匹配；不匹配时不会创建正式 entry，也不会推进订阅下一期。
- 订阅推进已收紧：只有匹配订阅规则的正式消费 entry 结算成功后，才推进 `next_charge_date` 并生成下一期现金流。
- 报销报表日期口径已修正：报销前支出、预计抵扣、批准抵扣按原始消费 entry 日期归属；已到账回款按实际到账日期或到账 entry 日期归属。
- AI 结构化动作已补阻断缺口：`SetCashFlowStatus` 和 `UpdateReimbursementStatus` 支持创建、审批、执行、审计日志和回滚，均按中风险处理并需要用户确认。
- macOS Credit / Notifications 上下文菜单操作不再 `try?` 静默吞错；失败会写入对应 ViewModel error，成功后刷新相关模块。
- macOS Reimbursement Kanban 显示所有关键状态：`reimbursable`、`invoice_pending`、`submitted`、`approved`、`waiting_received`、`partial_received`、`received`、`rejected`、`abandoned`。
- macOS 报销到账会选择与报销币种匹配的余额账户；没有匹配账户时显示明确错误。
- macOS Cash Flow 对 `transfer` 类型不再提供错误的“结算为正式记录”入口；信用还款/分期转账仍通过 Entries 的信用还款流程处理。

## Non-Blocking Backlog

这些来自原始愿景，但本轮不上云前不展开实现：

- iOS app、Widget、Live Activity、Shortcuts、语音/拍照快速录入。
- 真实系统通知投递；当前只有通知规则与 in-app 管理 API/UI。
- 附件模型、发票附件上传、附件预览和批量打印。
- 离线草稿、同步队列、冲突解决。
- 隐私模糊模式、金额隐藏、长按显示。
- 菜单栏快速入口、`⌘K`、多窗口、全局快捷键。
- 更复杂图表、趋势图、AI 月度洞察和 narrative memo。
- 账户核对 UI、余额重算/对账命令、默认分类和初始汇率 seed。
- `GenerateReport`、`CreateRecurringRule` AI action；现阶段由普通报表 API 和订阅 API 承载主要能力。

## Verification

- `python3 -m compileall backend/app backend/tests`
- `cd backend && .venv/bin/pytest` (`56 passed`)
- `cd frontend && swift test` (`12 passed`)
- `xcodebuild -project frontend/LinoFinance.xcodeproj -scheme LinoFinance -configuration Debug -destination 'platform=macOS' -derivedDataPath frontend/.derivedData build` (`BUILD SUCCEEDED`)
- `python3 -m compileall backend/app backend/scripts`
- `cd backend && .venv/bin/ruff check .`
- `cd backend && .venv/bin/alembic upgrade head --sql`
