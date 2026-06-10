# LinoFinance Deployment Runbook

This runbook covers the Phase 8 production shape: PostgreSQL as the source of
truth, FastAPI behind HTTPS, token-protected API calls, rate limiting, backups,
and a repeatable migration flow.

## Runtime Environment

Required production values:

```bash
LINOFINANCE_ENVIRONMENT=production
LINOFINANCE_DATABASE_URL=postgresql+psycopg://linofinance:replace-me@127.0.0.1:5432/linofinance
LINOFINANCE_API_AUTH_TOKEN=replace-with-a-long-random-token
LINOFINANCE_API_RATE_LIMIT_ENABLED=true
LINOFINANCE_API_RATE_LIMIT_PER_MINUTE=120
LINOFINANCE_TRUSTED_PROXY_HEADERS=true
LINOFINANCE_PUBLIC_DOCS_ENABLED=false
LINOFINANCE_BACKUP_DIR=/var/backups/linofinance
```

Optional:

```bash
LINOFINANCE_CORS_ALLOWED_ORIGINS=["https://finance.example.com"]
LINOFINANCE_LOG_LEVEL=INFO
LINOFINANCE_AI_API_BASE_URL=
LINOFINANCE_AI_API_KEY=
LINOFINANCE_AI_MODEL=
```

Production startup refuses to run without `LINOFINANCE_API_AUTH_TOKEN`.

## Local PostgreSQL

For local PostgreSQL instead of SQLite:

```bash
docker compose up -d postgres
cd backend
source .venv/bin/activate
alembic upgrade head
uvicorn app.main:app --reload
```

## API Service

Use `deploy/systemd/linofinance-api.service` as the systemd starting point.
Create `/etc/linofinance/api.env` from the production environment values above,
then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now linofinance-api
sudo systemctl status linofinance-api
```

## Scheduled Jobs (定时任务)

Credit-due reminders (T-5/3/1/0) and soft-deleted attachment cleanup run via
`scripts/run_scheduled_jobs.py`, driven by a systemd timer. Use
`deploy/systemd/linofinance-jobs.service` (a `oneshot` unit sharing the same
`User`/`Group`/`EnvironmentFile=/etc/linofinance/api.env` as the API) and
`deploy/systemd/linofinance-jobs.timer`:

```bash
sudo cp deploy/systemd/linofinance-jobs.service /etc/systemd/system/
sudo cp deploy/systemd/linofinance-jobs.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now linofinance-jobs.timer
systemctl list-timers linofinance-jobs.timer        # confirm next run
sudo systemctl start linofinance-jobs.service       # run once now (optional)
journalctl -u linofinance-jobs.service --since today
```

The timer fires daily at `09:00` in the app business timezone
(`OnCalendar=*-*-* 09:00:00 Asia/Shanghai`; the trailing timezone token needs
systemd >= 252 — on older systemd remove it and run the host in
`Asia/Shanghai`). The reminder window anchors on `app_today()` derived from
`LINOFINANCE_APP_TIMEZONE`, so keep both aligned.

**Fact (audit 2.8):** if `linofinance-jobs.timer` is not installed and enabled,
nothing ever calls `dispatch_due_credit_reminders`, so the T-5 / T-3 / T-1 /
T-0 credit repayment reminders never fire. The `credit_statement_generated`
push (fired inline when a cycle is created) still works without the timer; only
the day-relative due reminders depend on it. A default `credit_repayment` /
`system` `NotificationRule` is seeded by the v1.3.0 data migration so the
matcher has an active rule out of the box.

## HTTPS Reverse Proxy

Use `deploy/nginx/linofinance.conf.example` as the nginx starting point. Replace
`finance.example.com`, install TLS certificates, then reload nginx.

The API remains mounted at:

```text
https://finance.example.com/api/v1
```

Clients must send:

```text
Authorization: Bearer <LINOFINANCE_API_AUTH_TOKEN>
```

## Backups

Create a custom-format PostgreSQL backup:

```bash
cd backend
source .venv/bin/activate
python scripts/backup_postgres.py --label daily
```

Each backup writes a `.dump` plus a `.manifest.json` containing a SHA-256 digest
and a redacted database URL.

Restore requires an explicit destructive confirmation:

```bash
cd backend
source .venv/bin/activate
python scripts/restore_postgres.py /var/backups/linofinance/linofinance-daily-YYYYMMDDTHHMMSSZ.dump \
  --confirm RESTORE_LINOFINANCE
```

## Migration Flow

The production migration wrapper takes a pre-migration backup by default, then
runs Alembic:

```bash
cd backend
source .venv/bin/activate
python scripts/production_migrate.py
```

Use `--skip-backup` only when a fresh verified backup already exists.

## Smoke Test

```bash
curl https://finance.example.com/api/v1/health
curl -H "Authorization: Bearer $LINOFINANCE_API_AUTH_TOKEN" \
  https://finance.example.com/api/v1/ai/config
```

Expected: health is public; non-public routes return `401` without the token and
`200` with the token.
