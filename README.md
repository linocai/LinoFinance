# LinoFinance

LinoFinance is a personal dual-currency finance control center with iOS/macOS
clients and a cloud API backend.

Historical planning and design docs are under [archive/](archive/). For day-to-day operations see [docs/deployment.md](docs/deployment.md). The current shipped version is tracked in [PROJECT_PLAN.md](PROJECT_PLAN.md).

## Current Architecture

- Backend: FastAPI, SQLAlchemy, Alembic, PostgreSQL.
- Frontend: SwiftUI shared Swift package plus a real Xcode macOS App target.
- Storage: cloud database is the primary source of truth.
- Client model: online-only — every read/write goes to the cloud API; there is
  no local cache, offline-draft queue, or retry queue. Offline capability is in
  the backlog (see [PROJECT_PLAN.md](PROJECT_PLAN.md) §6).
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

## Planning & Product Decisions

The single source of truth for the active plan, durable product decisions
(manual USD/CNY rate, AI auto-confirm threshold, credit statement cycles,
reimbursement views, etc.), and the per-version changelog is
[PROJECT_PLAN.md](PROJECT_PLAN.md). Repo-specific engineering conventions and
pitfalls live in [CLAUDE.md](CLAUDE.md). Historical per-version plans are under
[archive/](archive/).
