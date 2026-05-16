# LinoFinance State

Last updated: 2026-05-16

## Current Goal

Execute `plan.md` from Phase 0 onward. The current completed slice is Phase 6:
AI structured actions, risk gating, audit logs, and notification rules.

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
- Verification passed:
  - `python3 -m compileall backend/app backend/tests`
  - `cd backend && . .venv/bin/activate && pytest` (`38 passed`)
  - `cd backend && . .venv/bin/activate && ruff check .`
  - `cd backend && . .venv/bin/activate && alembic upgrade head --sql`
  - `cd frontend && swift test` (`10 passed`)

## Remaining

1. Start Phase 7 report aggregation and CSV export.
2. Add partial cash-flow settlement once reimbursement and partial payments need it.
3. Add credit statement cycle update/close endpoints if manual statement reconciliation needs editing after creation.
4. Add account balance recalculation/reconciliation command to rebuild balances from movements and cycle amounts.
5. Add seed scripts for default categories and initial USD/CNY rate in local/test setup.
6. Add real iOS/macOS app targets after shared Swift modules settle.
7. Prepare local PostgreSQL instructions or Docker Compose if a local database runner is desired.

## Decisions

- Backend stack: FastAPI + SQLAlchemy + Alembic + PostgreSQL.
- Frontend first step: Swift package for shared iOS/macOS code, with Xcode app shell added later.
- Client storage is not the primary source of truth; it is only cache/offline draft support.
- The backend venv lives at `backend/.venv` and is intentionally ignored by Git.
- The test FastAPI server on port 8000 was stopped after verification.

## Resume Command

```bash
git status --short --branch
```
