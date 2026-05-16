# LinoFinance

LinoFinance is a personal dual-currency finance control center with iOS/macOS
clients and a cloud API backend.

The current source of truth for implementation scope is [plan.md](plan.md).

## Current Architecture

- Backend: FastAPI, SQLAlchemy, Alembic, PostgreSQL.
- Frontend: SwiftUI shared Swift package plus a real Xcode macOS App target.
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

## Local PostgreSQL

```bash
docker compose up -d postgres
cd backend
source .venv/bin/activate
alembic upgrade head
```

## Frontend Quick Check

```bash
cd frontend
swift test
```

## Local macOS App

Use a local SQLite file database and run the API on port `6868`:

```bash
cd backend
source .venv/bin/activate
python scripts/run_local_sqlite.py
```

Build the macOS app with Xcode:

```bash
xcodebuild \
  -project frontend/LinoFinance.xcodeproj \
  -scheme LinoFinance \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath frontend/.derivedData \
  build
open frontend/.derivedData/Build/Products/Debug/LinoFinance.app
```

The local database lives at `backend/.local/linofinance.sqlite3` and is ignored
by Git.

## Production Notes

Phase 8 deployment scaffolding lives in [docs/deployment.md](docs/deployment.md).
Production API startup requires `LINOFINANCE_API_AUTH_TOKEN`; macOS clients can
point to a domain API with `LINOFINANCE_API_BASE_URL` and authenticate with
`LINOFINANCE_API_TOKEN`.

## Confirmed Product Defaults

- Manual USD/CNY initial rate: `6.8`.
- AI auto-confirm candidate threshold: `1000 CNY`.
- Credit card statements use a dedicated `CreditStatementCycle` object.
- Reports support reimbursement-before and multiple reimbursement-net views.
- API will eventually be reached through a domain name backed by the cloud server.
