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

AI provider values are intentionally local-only. Put real values in `backend/.env`:

```bash
LINOFINANCE_AI_API_BASE_URL=https://example.com/v1
LINOFINANCE_AI_API_KEY=replace-me
LINOFINANCE_AI_MODEL=replace-me
```

The backend treats this as an OpenAI-compatible chat-completions endpoint. The API
never returns the key, only whether the key/base URL is configured.

Production hardening values:

```bash
LINOFINANCE_ENVIRONMENT=production
LINOFINANCE_API_AUTH_TOKEN=replace-with-a-long-random-token
LINOFINANCE_API_RATE_LIMIT_ENABLED=true
LINOFINANCE_API_RATE_LIMIT_PER_MINUTE=120
LINOFINANCE_TRUSTED_PROXY_HEADERS=true
```

Non-health API routes require `Authorization: Bearer <token>` whenever a token is
configured. See `../docs/deployment.md` for nginx, systemd, backup, restore, and
migration flow notes.

Health check:

```bash
curl http://127.0.0.1:8000/api/v1/health
```

## Confirmed Defaults

- Initial manual USD/CNY rate: `6.8`
- AI auto-confirm candidate limit: `1000 CNY`
- V1 export format: CSV
- Primary storage: cloud database, not client local storage
