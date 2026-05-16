# LinoFinance State

Last updated: 2026-05-16

## Current Goal

Execute the post-cloud client expansion. Backend and macOS app are deployed
and production-smoked; the current work adds an iPhone-only iOS app that reuses
the existing cloud API, DTOs, repositories, view models, and business screens.

## Completed

- Git repository initialized on `main`.
- Remote recorded as `origin = git@github.com:linocai/LinoFinance.git`; main is pushed.
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
  - app icon updated from `/Users/linotsai/Pictures/GPT Image/personal-bookkeeping-appicon-v1.png`;
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
- First cloud deployment completed on `hz`:
  - public API domain: `https://lf.linotsai.top/api/v1`;
  - remote app root: `/opt/linofinance`;
  - current release symlink: `/opt/linofinance/app/current`;
  - deployed release: `/opt/linofinance/app/releases/20260516-171352`;
  - production env file: `/etc/linofinance/api.env` (`root:linofinance`, `640`);
  - systemd service: `linofinance-api`, running as user/group `linofinance` on `127.0.0.1:8000`;
  - PostgreSQL database/user: `linofinance` on local PostgreSQL 16;
  - Nginx site: `/etc/nginx/sites-available/linofinance`;
  - Let's Encrypt cert issued for `lf.linotsai.top`, expiring `2026-08-14`;
  - initial production DB backup created at `/opt/linofinance/backups/linofinance-initial-20260516T092054Z.dump`.
- Production AI provider smoke completed after user filled `/etc/linofinance/api.env`:
  - `/api/v1/ai/config` now reports `base_url_configured: true`, `api_key_configured: true`, model `deepseek-v4-flash`;
  - initial natural-language plan attempts proved provider connectivity but exposed loose model payload field names;
  - `backend/app/services/ai_provider.py` hotfixed with stricter action schema prompt and common payload field normalization;
  - remote `linofinance-api` restarted successfully;
  - authenticated `POST https://lf.linotsai.top/api/v1/ai/plans` created a medium-risk `CreateCashFlowItem` plan through the live provider, then the smoke plan was rejected for cleanup.
- iPhone Air iOS app implementation completed locally:
  - Xcode target `LinoFinanceiOS` added with product name `LinoF`, bundle id `com.lino.linofinance.ios`, iPhone-only device family, iOS 18.0 deployment target, and shared scheme `LinoFinance iOS`;
  - iOS app uses the same `AppIcon` catalog and default API `https://lf.linotsai.top/api/v1`;
  - `FinanceModule` and `InspectorSelection` moved into shared navigation for macOS/iOS reuse;
  - `LinoFinanceApp` now routes to `MacRootView` on macOS and `iOSRootView` on iOS;
  - iOS root has fixed tabs `总览 / 记账 / 现金流 / 信用 / 更多`, with 更多 linking to accounts, reimbursements, reports, AI, notifications, and settings;
  - shared `FinanceModuleContentView` and `SelectionDetailView` let macOS inspector and iOS detail sheets render the same business content;
  - `SecureTokenStore` added with Security/Keychain storage for `linofinance.apiToken`;
  - `AppEnvironment` can reconfigure API URL/token at runtime, rebuild clients/view models, and skip protected refreshes until a token is configured;
  - Settings now exposes API URL/token save and token clear actions;
  - Reports no longer hard-depend on AppKit and exports CSV to ShareLink on iOS while preserving Finder reveal on macOS;
  - mobile-visible action menus were added for entries, cash flow, credit installment/subscription, and notification rows;
  - dashboard, reports, credit, entries, reimbursements, and detail rows were adjusted to avoid fixed desktop-only widths on iPhone.
- Initial macOS account setup repair completed:
  - production currency rate check found one active manual `USD -> CNY` rate: `6.8` dated `2026-05-16`;
  - account row conversion bug fixed so USD account rows use the latest CNY rate instead of showing original USD amount as approximate CNY;
  - user-provided June-December credit/loan bills were written to production as 25 statement cycles and linked cash-flow items;
  - account liabilities set to: 花呗 `823.80 CNY`, 白条 `1772.17 CNY`, 工商3375 `4337.27 CNY`, 工商5438 `20.00 USD`, 车贷 `17731.00 CNY`;
  - 白条 monthly figures summed to `1771.57`, so December was adjusted from `14.89` to `15.49` because the user explicitly said total `1772.17` is authoritative;
  - production backup before direct adjustment: `/opt/linofinance/backups/linofinance-before-initial-bills-20260516T112839Z.dump`;
  - updated macOS app copied to `/Users/linotsai/Applications/LinoF.app` and relaunched.
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
  - remote `alembic upgrade head` reached `202605160005`
  - remote `systemctl is-active linofinance-api nginx postgresql@16-main` returned active
  - `curl https://lf.linotsai.top/api/v1/health` returned production `status: ok`
  - `curl https://lf.linotsai.top/api/v1/ai/config` without token returned `401`
  - authenticated `GET https://lf.linotsai.top/api/v1/ai/config` returned `200` with `api_key_configured: true`
  - authenticated AI provider smoke created plan `35ed12c9-f582-4061-99bc-5ac5f243931e` and rejected it after verification
  - `cd frontend && swift test` (`12 passed`) after iOS shared-code changes
  - macOS Debug build still succeeds after iOS changes:
    `xcodebuild -project frontend/LinoFinance.xcodeproj -scheme LinoFinance -configuration Debug -destination 'platform=macOS' -derivedDataPath frontend/.derivedData build`
  - iOS Swift typecheck passed with simulator SDK:
    `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios18.0-simulator ...`
  - full iOS Simulator xcodebuild is blocked on this machine because no iOS simulator runtime is installed; `iPhone Air` exists only as unavailable `iOS 26.4`
  - after account conversion fix: `cd frontend && swift test` (`12 passed`)
  - after account conversion fix: macOS Debug build `BUILD SUCCEEDED`
  - production API verification showed 25 statement cycles, 25 linked cash-flow items, and matching cycle totals for 花呗/白条/工商3375/工商5438/车贷

## Remaining

1. Install an iOS simulator runtime on the Mac, then run:
   `xcodebuild -project frontend/LinoFinance.xcodeproj -scheme 'LinoFinance iOS' -configuration Debug -destination 'platform=iOS Simulator,name=iPhone Air' -derivedDataPath frontend/.derivedData-ios build`.
2. Manual iPhone Air smoke after simulator runtime is available: first-launch no-token settings prompt, token save, `/health`, `/ai/config`, all 10 modules, create flows, status actions, and CSV sharing.
3. Add partial cash-flow settlement once reimbursement and partial payments need it.
4. Add credit statement cycle update/close endpoints if manual statement reconciliation needs editing after creation.
5. Add account balance recalculation/reconciliation command to rebuild balances from movements and cycle amounts.
6. Add seed scripts for default categories and initial USD/CNY rate in local/test setup.
7. Add app-level smoke/UI tests once macOS/iOS workflow stabilizes.
8. Add stronger production observability if needed: external error tracking, persistent rate-limit backend, log shipping, and uptime checks.
9. Later frontend polish still outstanding from the design direction: command palette (`⌘K`), Menu Bar Extra, account reconciliation UI, multi-window mode, richer charts, privacy blur, and deeper AI narrative insights.
10. Remaining cross-platform vision items intentionally deferred: Widget, Live Activity, Shortcuts, real system notification delivery, attachment model/preview/printing, offline draft sync/conflict handling, and AI monthly narrative memo.
11. AI action backlog remains for `GenerateReport` and `CreateRecurringRule`; current report APIs and subscription APIs cover the blocking user workflows.

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
