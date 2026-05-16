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
- Verification passed:
  - `python3 -m compileall backend/app backend/tests`
  - `cd backend && . .venv/bin/activate && pytest` (`10 passed`)
  - `cd backend && . .venv/bin/activate && ruff check .`
  - `cd backend && . .venv/bin/activate && alembic upgrade head --sql`
  - `cd frontend && swift test` (`2 passed`)
  - `curl http://127.0.0.1:8000/api/v1/health`

## Remaining

1. Add entry edit/update rules, especially what can be edited after confirmation.
2. Add account balance recalculation/reconciliation command to rebuild balances from movements.
3. Add seed scripts for default categories and initial USD/CNY rate in local/test setup.
4. Add real iOS/macOS app targets after shared Swift modules settle.
5. Prepare local PostgreSQL instructions or Docker Compose if a local database runner is desired.

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
