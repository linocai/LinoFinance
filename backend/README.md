# LinoFinance Backend

FastAPI + SQLAlchemy + Alembic backend. The backend is the source of truth for the
ledger; iOS and macOS clients call it through a domain API.

## Local Setup

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

Health check:

```bash
curl http://127.0.0.1:8000/api/v1/health
```

## Confirmed Defaults

- Initial manual USD/CNY rate: `6.8`
- AI auto-confirm candidate limit: `1000 CNY`
- V1 export format: CSV
- Primary storage: cloud database, not client local storage
