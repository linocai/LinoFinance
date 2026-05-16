# LinoFinance State

Last updated: 2026-05-16

## Current Goal

Execute `plan.md` from Phase 0 onward. The current slice is project foundation:
backend API skeleton, database migration baseline, frontend shared Swift modules,
and durable setup documentation.

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
- Verification passed:
  - `python3 -m compileall backend/app backend/tests`
  - `cd backend && . .venv/bin/activate && pytest` (`21 passed`)
  - `cd backend && . .venv/bin/activate && ruff check .`
  - `cd backend && . .venv/bin/activate && alembic upgrade head --sql`
  - `cd frontend && swift test` (`4 passed`)
  - `curl http://127.0.0.1:8000/api/v1/health`

## Remaining

1. Start Phase 4 reimbursement: reimbursement object, reimbursable entry linkage, reimbursement cash-flow generation.
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
