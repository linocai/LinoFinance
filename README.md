# LinoFinance

LinoFinance is a personal dual-currency finance control center with iOS/macOS
clients and a cloud API backend.

The current source of truth for implementation scope is [plan.md](plan.md).

## Current Architecture

- Backend: FastAPI, SQLAlchemy, Alembic, PostgreSQL.
- Frontend: SwiftUI-oriented shared Swift package for iOS/macOS modules.
- Storage: cloud database is the primary source of truth.
- Client local storage: cache, offline drafts, and retry queue only.
- V1 export: CSV.

## Backend Quick Start

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
pip install -e ".[dev]"
cp .env.example .env
alembic upgrade head
uvicorn app.main:app --reload
```

Health endpoint:

```bash
curl http://127.0.0.1:8000/api/v1/health
```

## Frontend Quick Check

```bash
cd frontend
swift test
```

## Confirmed Product Defaults

- Manual USD/CNY initial rate: `6.8`.
- AI auto-confirm candidate threshold: `1000 CNY`.
- Credit card statements use a dedicated `CreditStatementCycle` object.
- Reports support reimbursement-before and multiple reimbursement-net views.
- API will eventually be reached through a domain name backed by the cloud server.
