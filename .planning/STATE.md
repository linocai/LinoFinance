# LinoFinance State

Last updated: 2026-05-16

## Current Goal

Execute `plan.md` from Phase 0 onward. The backend is complete through Phase 7
and has the first Phase 8 production-hardening slice implemented. The current
frontend is the real Xcode macOS app against the local `6868` API by default,
with environment/UserDefaults support for a deployed domain API and API token.

## Completed

- Git repository initialized on `main`.
- Remote recorded as `origin = git@github.com:linocai/LinoFinance.git`; not pushed.
- `plan.md` created with confirmed product decisions:
  - manual USD/CNY rate starts at `6.8`;
  - credit cards need `CreditStatementCycle`;
  - reports support all reimbursement views;
  - AI auto-confirm candidate threshold is `1000 CNY`;
  - cloud DB is the source of truth behind domain API;
  - V1 export is CSV.
- Backend skeleton added under `backend/`.
- Alembic initial migration added with foundational ledger tables and USD/CNY seed.
- Frontend Swift package skeleton added under `frontend/`.
- Phase 1 foundation API started:
  - accounts list/create/get;
  - categories list/create/get;
  - currency rates list/create/get with normalized currency codes and trimmed rate output.
- Phase 1 entries API implemented:
  - entries list/create/get;
  - draft entries do not affect balances;
  - confirmed entries apply account movements immediately;
  - draft confirmation applies movements;
  - voiding confirmed entries rolls movements back;
  - expense/income category totals must match account movements in CNY;
  - USD entries use available manual USD/CNY rates.
- Dashboard summary API added with backend-computed balance total, credit liability total, net worth, and entry status counts.
- Phase 2 credit statement core implemented:
  - `CreditStatementCycle` list/create/get API;
  - statement cycles can only be created for credit accounts;
  - statement cycle currency must match credit account currency;
  - confirmed credit charges auto-assign a matching cycle when omitted, otherwise validate the explicit cycle;
  - confirmed credit repayments require an explicit cycle;
  - credit charges update cycle `statement_amount`;
  - credit repayments update cycle `paid_amount` and status;
  - voiding confirmed credit charges/repayments rolls back both account balances and cycle amounts.
- Phase 2 repayment cash-flow auto-generation is intentionally deferred until Phase 3 because `CashFlowItem` is not implemented yet; the linking field is already present.
- Frontend Phase 2 shared types added:
  - `CreditStatementCycle`;
  - `CreditStatementStatus`;
  - placeholder credit statement view for later app-shell integration.
- Phase 3 cash-flow core implemented:
  - `CashFlowItem` model and Alembic migration `202605160002`;
  - cash-flow list/create/get/confirm/cancel/settle API;
  - expected/confirmed cash flows do not affect balances;
  - settlement requires an explicit confirmed formal entry payload and only then affects balances;
  - credit statement cycles generate/update linked `credit_repayment` cash-flow items;
  - fully repaid statement cycles mark linked repayment cash flows as settled.
- Frontend Phase 3 shared types added:
  - `CashFlowItem`;
  - `CashFlowDirection`;
  - `CashFlowStatus`;
  - `CashFlowType`;
  - placeholder cash-flow view for later app-shell integration.
- Phase 4 reimbursement core implemented:
  - `ReimbursementClaim` model and Alembic migration `202605160003`;
  - reimbursement claim list/create/get/submit/approve/reject/abandon/mark-received API;
  - confirmed reimbursable entry category lines auto-create reimbursement claims and reimbursement cash-flow inflows;
  - draft reimbursable entries create claims only when confirmed;
  - reimbursable lines require `reimbursement_expected_date` before confirmation;
  - reimbursement receipt requires a formal confirmed income entry payload, which is the only thing that changes balances;
  - voiding original reimbursable expense abandons open claims and cancels linked reimbursement cash flows.
- Frontend Phase 4 shared types added:
  - `ReimbursementClaim`;
  - `ReimbursementStatus`;
  - placeholder reimbursement view for later app-shell integration.
- Phase 5 installment/subscription core implemented:
  - `InstallmentPlan` and `SubscriptionRule` models plus Alembic migration `202605160004`;
  - installment plan list/create/get/cancel/mark-paid-off/mark-early-paid-off API;
  - active installment plans require a confirmed matching credit-card charge and generate future `installment` transfer cash flows;
  - cancelling or paying off an installment plan cancels open generated cash flows;
  - subscription rule list/create/get/pause/resume/cancel/generate-next API;
  - active subscriptions generate expected future `subscription` cash-flow outflows;
  - settling a subscription cash flow creates the formal confirmed entry, advances `next_charge_date`, and generates the next expected cash flow.
- Frontend Phase 5 shared types added:
  - `InstallmentPlan`;
  - `InstallmentPlanStatus`;
  - `SubscriptionRule`;
  - `SubscriptionBillingInterval`;
  - `SubscriptionRuleStatus`;
  - placeholder installment and subscription views for later app-shell integration.
- Phase 6 AI and notification core implemented:
  - `.env`-driven AI provider settings added for API base URL, API key, model, timeout, and the `1000 CNY` auto-confirm limit;
  - `AIPlan`, `AIAction`, `AIActionExecution`, and `NotificationRule` models plus Alembic migration `202605160005`;
  - AI plan config/list/create/get/approve/reject/execute API;
  - AI action rollback API for supported created records;
  - action protocol covers `CreateEntry`, `CreateCashFlowItem`, `MarkReimbursable`, `CreateInstallmentPlan`, `RecordCreditRepayment`, `GenerateNotificationRule`, and `VoidEntry`;
  - low-risk complete CNY `CreateEntry` actions at or below `1000 CNY` become `auto_confirm_candidate`;
  - medium-risk actions require approval;
  - high-risk actions require approval plus `EXECUTE_HIGH_RISK`;
  - AI executions write `AuditLog` records with before/after snapshots where available;
  - notification rule list/create/get/pause/resume/cancel API added.
- Frontend Phase 6 shared types added:
  - `AIPlan`, `AIAction`, related status/risk/action enums;
  - `NotificationRule` and notification enums;
  - `AuditLog`;
  - `JSONValue` for AI/notification JSON payloads;
  - placeholder AI plan and notification rule views.
- Phase 7 report and CSV export core implemented:
  - `GET /reports/monthly-overview`;
  - `GET /reports/category-expenses`;
  - `GET /reports/cash-flow-pressure`;
  - `GET /reports/credit-liability-trend`;
  - `GET /reports/reimbursements`;
  - `GET /reports/subscriptions`;
  - report rows include original-currency display totals and CNY totals where relevant;
  - reimbursement report supports `pre_reimbursement`, `expected_net`, `approved_net`, `received_net`, and `personal_net` views;
  - `GET /exports/csv` lists available CSV datasets;
  - `GET /exports/csv/{dataset}` exports core ledger, cash-flow, reimbursement, credit, installment, subscription, audit, AI, and notification tables.
- Frontend Phase 7 shared types added:
  - report summary models and reimbursement report view enum;
  - `ExportDataset`;
  - placeholder reports view.
- Local macOS app added:
  - `frontend/LinoFinance.xcodeproj` with app target `LinoFinance`;
  - bundle id `com.lino.linofinance`;
  - Debug app path `frontend/.derivedData/Build/Products/Debug/LinoFinance.app`;
  - app icon source confirmed as `/Users/linotsai/Pictures/GPT Image/冈部伦太郎-简笔2.png`;
  - Xcode asset catalog generated under `frontend/LinoFinance/Resources/Assets.xcassets`;
  - local SQLite API runner added at `backend/scripts/run_local_sqlite.py`;
  - local preview API runs on `http://127.0.0.1:6868/api/v1`;
  - local SQLite DB path is `backend/.local/linofinance.sqlite3`;
  - macOS UI uses Sidebar + Content + Inspector with Dashboard, Accounts, and Entries wired to real API calls.
- macOS frontend full API-backed pass completed:
  - `LinoAPIClient` supports query GET, body/empty POST, CSV download, and structured API errors;
  - DTO/request coverage added for currency rates, entries confirm/void, cash flow, reimbursements, credit cycles, installments, subscriptions, reports, CSV exports, AI plans/actions, notification rules, and audit logs;
  - Dashboard now uses real report/AI summaries and shows the 30-day cash-flow net KPI when available;
  - Accounts supports balance/credit grouping and credit account fields;
  - Entries supports balance expense/income, credit charge, credit repayment, reimbursable lines, confirm, and void;
  - Cash Flow supports 7/30/90 pressure KPIs, create, confirm, cancel, and settle-to-entry;
  - Reimbursements supports Kanban status columns and submit/approve/reject/abandon/mark-received actions;
  - Credit supports credit account cards, statement cycles, installment plans, subscriptions, and status actions;
  - Reports supports monthly, category, cash-flow, credit, reimbursement, subscription, and CSV export views;
  - AI supports config status, natural-language plan creation, approve/reject/execute/rollback, and high-risk `EXECUTE_HIGH_RISK` confirmation;
  - Notifications supports rule list/create/pause/resume/cancel;
  - Settings shows local API state, AI config state, and manual USD/CNY rate entry;
  - Inspector details are implemented for accounts, entries, cash-flow items, reimbursements, credit cycles, installments, subscriptions, AI plans, and notification rules;
  - root content/empty/error states are top-aligned in the macOS three-column layout.
- Phase 8 production-hardening slice implemented:
  - backend settings added for production token auth, rate limiting, trusted proxy headers, CORS origins, public docs toggle, log level, and backup dir;
  - production startup now refuses to run without `LINOFINANCE_API_AUTH_TOKEN`;
  - non-public API routes support `Authorization: Bearer <token>` and `X-LinoFinance-API-Token`;
  - public `GET /health`, OpenAPI, and docs routes stay open;
  - in-memory per-client rate limiting added with `429`, `Retry-After`, and `X-RateLimit-*` headers;
  - request ID and JSON structured request/error logs added;
  - health response now reports auth/rate-limit flags;
  - PostgreSQL backup, restore, and production migration scripts added under `backend/scripts/`;
  - local PostgreSQL `docker-compose.yml`, systemd API service example, nginx HTTPS reverse-proxy example, and `docs/deployment.md` runbook added;
  - `Makefile` targets added for local PostgreSQL startup, manual backup, and production migration;
  - macOS `LinoAPIClient` and shared Swift package `APIClient` can attach Bearer tokens;
  - macOS app can read `LINOFINANCE_API_BASE_URL` / `LINOFINANCE_API_TOKEN`, `UserDefaults`, or bundle defaults before falling back to local `6868`;
  - Settings now shows API URL, token configured state, backend auth state, and backend rate-limit state.
- Pre-cloud final audit and blocking-bug repair completed:
  - `.planning/PRECLOUD_AUDIT.md` added, cross-checking `LinoFinance前置计划.md` and `LinoFinance前端设计方向.md`;
  - audit explicitly records shipped scope, fixed cloud blockers, and non-blocking backlog;
  - middleware order fixed so request IDs wrap all responses, auth runs before rate limiting, and `401` auth failures do not consume rate-limit quota;
  - V1 currency handling tightened to `CNY`/`USD`, with strict `exchange_rate_id` pair/date validation and `converted_cny_amount` consistency checks;
  - manual reimbursement claims now require a confirmed linked expense line, exact amount/currency match, and no existing claim for that `EntryCategoryLine`;
  - cash-flow settlement now requires matching direction, currency, amount, account, category, and entry shape before creating a confirmed entry;
  - subscription rules advance only after a matching subscription cash-flow settlement succeeds;
  - reimbursement report date semantics split original expense month from actual received month;
  - AI now supports `SetCashFlowStatus` and `UpdateReimbursementStatus` as medium-risk confirm-required actions with execution logs and rollback;
  - macOS Credit and Notifications context actions surface errors instead of silently swallowing them;
  - macOS Reimbursements shows all key statuses, chooses same-currency balance accounts for received reimbursements, and surfaces clear missing-account/category errors;
  - macOS Cash Flow no longer offers generic settlement for `transfer` cash flows.
- Verification passed:
  - `python3 -m compileall backend/app backend/tests`
  - `python3 -m compileall backend/app backend/scripts`
  - `cd backend && .venv/bin/pytest` (`56 passed`)
  - `cd backend && .venv/bin/ruff check .`
  - `cd backend && .venv/bin/alembic upgrade head --sql`
  - `cd frontend && swift test` (`12 passed`)
  - `xcodebuild -project frontend/LinoFinance.xcodeproj -scheme LinoFinance -configuration Debug -destination 'platform=macOS' -derivedDataPath frontend/.derivedData build` (`BUILD SUCCEEDED`)
  - `curl http://127.0.0.1:6868/api/v1/health` returned `status: ok`
  - screenshot review saved at `.planning/screenshots/macos-dashboard-focused.png`
  - screenshot review saved at `.planning/screenshots/macos-accounts-focused.png`

## Remaining

1. Perform actual cloud server provisioning, DNS, HTTPS certificates, production env file setup, and first live deployment using `docs/deployment.md`.
2. Add partial cash-flow settlement once reimbursement and partial payments need it.
3. Add credit statement cycle update/close endpoints if manual statement reconciliation needs editing after creation.
4. Add account balance recalculation/reconciliation command to rebuild balances from movements and cycle amounts.
5. Add seed scripts for default categories and initial USD/CNY rate in local/test setup.
6. Add app-level smoke/UI tests once the first macOS workflow stabilizes.
7. Add stronger production observability if needed: external error tracking, persistent rate-limit backend, log shipping, and uptime checks.
8. Later frontend polish still outstanding from the design direction: command palette (`⌘K`), Menu Bar Extra, account reconciliation UI, multi-window mode, richer charts, privacy blur, and deeper AI narrative insights.
9. Original cross-platform vision items intentionally deferred until after cloud baseline: iOS app, Widget, Live Activity, Shortcuts, real system notification delivery, attachment model/preview/printing, offline draft sync/conflict handling, and AI monthly narrative memo.
10. AI action backlog remains for `GenerateReport` and `CreateRecurringRule`; current report APIs and subscription APIs cover the blocking user workflows.

## Decisions

- Backend stack: FastAPI + SQLAlchemy + Alembic + PostgreSQL.
- Frontend official macOS path is `frontend/LinoFinance.xcodeproj`; SwiftPM remains for shared modules and tests.
- Client storage is not the primary source of truth; it is only cache/offline draft support.
- The backend venv lives at `backend/.venv` and is intentionally ignored by Git.
- Local development remains token-optional; configuring `LINOFINANCE_API_AUTH_TOKEN`
  enables auth locally, and production requires it.
- The test FastAPI server on port 8000 was stopped after verification.
- At last local macOS verification, the SQLite API on port `6868` was responding
  and `frontend/.derivedData/Build/Products/Debug/LinoFinance.app` had been opened.

## Resume Command

```bash
git status --short --branch
```
