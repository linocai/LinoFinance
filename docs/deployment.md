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

### Business timezone (v1.3.0)

```bash
# Resolves all "today" anchors (dashboard today-pnl, credit-due reminders,
# report windows) and buckets UTC-naive created_at to a local calendar date.
# Default is Asia/Shanghai; the timer (below) and this value must agree.
LINOFINANCE_APP_TIMEZONE=Asia/Shanghai
```

### Sign in with Apple (v1.2.0 + single-user gate v1.3.0)

```bash
# Comma-separated list of allowed Apple audiences (client_id / bundle ids).
LINOFINANCE_APPLE_SIGNIN_AUDIENCES=["com.lino.linofinance.ios"]
# Non-production only: skips JWKS verification (identity_token used verbatim as
# sub). Production startup hard-refuses this flag.
LINOFINANCE_APPLE_DEV_SHORTCUT=false
# Single-user gate escape hatch: comma-separated Apple `sub`s that self-activate
# even when the users table is non-empty (e.g. migrating to a new Apple ID).
# May be empty. Look up your own sub in GET /auth/me -> apple_user_id.
LINOFINANCE_APPLE_SUB_ALLOWLIST=
```

### APNs push (v1.2.0)

```bash
LINOFINANCE_APNS_TOPIC=com.lino.linofinance.ios          # APNs bundle topic
LINOFINANCE_APNS_KEY_ID=                                 # .p8 key id
LINOFINANCE_APNS_TEAM_ID=HX73DFL88G                      # Apple team id
LINOFINANCE_APNS_KEY_PATH=/etc/linofinance/apns_authkey.p8
LINOFINANCE_APNS_USE_SANDBOX=false                       # production APNs
LINOFINANCE_APNS_DRY_RUN=false                           # true = build but do not send
```

### Attachment storage

```bash
# Root directory for uploaded attachment files (relative storage_key under it).
LINOFINANCE_STORAGE_ROOT=/opt/linofinance/storage
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
`scripts/run_scheduled_jobs.py`; as of v3.0.0 P6 the same unit also runs
`scripts/fetch_exchange_rates.py` (daily auto exchange-rate fetch from the
free, keyless `open.er-api.com` — inserts `CurrencyRate(source="auto")` only
when today has no rate yet, manual or auto; never overwrites a manual entry;
no new env vars needed). Both run via a systemd timer. Use
`deploy/systemd/linofinance-jobs.service` (a `oneshot` unit with two
`ExecStart=` lines, sharing the same
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

Same fact applies to the v3.0.0 P6 `fetch_exchange_rates.py` line: if the timer
is not installed, no auto exchange rate is ever fetched — manually-entered
rates (`POST /currency-rates`) keep working exactly as before, this only means
the day is never auto-backfilled when a manual entry was skipped. This job is
optional (it augments, not replaces, manual rate entry).

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

## Single-User Gate Ops (v1.3.0)

LinoFinance is a single-user ledger. The first Apple `sub` to sign in against an
empty `users` table self-bootstraps as the active owner; every later new `sub`
is recorded `disabled=true` and refused a session. There is no admin API —
activation and disabling are psql operations. Connect with:

```bash
sudo -u postgres psql -d linofinance      # or the linofinance role
```

Confirm only the owner exists and is active:

```sql
SELECT id, apple_user_id, disabled, created_at FROM users ORDER BY created_at;
```

Activate a user (e.g. after migrating to a new Apple ID — prefer the
`LINOFINANCE_APPLE_SUB_ALLOWLIST` env over a manual flip when possible):

```sql
UPDATE users SET disabled = false WHERE apple_user_id = '<sub>';
```

Disable a user — its existing valid sessions are rejected on their **very next
request** (every gated route returns `401`, no app restart needed):

```sql
UPDATE users SET disabled = true WHERE apple_user_id = '<sub>';
```

If the table is empty after a fresh deploy, complete one Apple sign-in **as the
owner** as soon as possible to claim the bootstrap slot before anyone else.

## Smoke Test

Admin-token (ops) path:

```bash
curl https://finance.example.com/api/v1/health
curl -H "Authorization: Bearer $LINOFINANCE_API_AUTH_TOKEN" \
  https://finance.example.com/api/v1/ai/config
```

Expected: health is public; non-public routes return `401` without the token and
`200` with the token.

User-mode (Apple session) path: `/health` reports `auth_modes: ["admin",
"user"]` and the production `version`. A real session token comes from a
completed Apple sign-in (the plaintext token is returned once by `POST
/auth/apple`); with it, the same gated routes return `200`:

```bash
curl https://finance.example.com/api/v1/health   # version + auth_modes
curl -H "Authorization: Bearer <apple-session-token>" \
  https://finance.example.com/api/v1/auth/me      # 200 with the owner profile
```

Expected: a session token for a disabled user returns `401` on every gated
route; `POST /auth/apple` for a non-bootstrap, non-allowlisted `sub` returns
`403 {"detail": "User is disabled"}`.
