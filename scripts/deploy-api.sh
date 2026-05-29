#!/usr/bin/env bash
# LinoFinance backend deploy script.
#
# Usage:
#   scripts/deploy-api.sh [--dry-run] [--force]
#
# What it does (live mode):
#   1. Stamp a UTC release id (YYYYMMDD-HHMMSS).
#   2. rsync backend/ (minus .venv, __pycache__, .local, .backups, tests)
#      to <DEPLOY_USER>@<DEPLOY_HOST>:/opt/linofinance/app/releases/<stamp>/backend/.
#   3. On remote, create a per-release venv and `pip install -e . --quiet`.
#   4. On remote, run `python scripts/production_migrate.py`
#      (takes its own pre-migration backup by default).
#   5. Atomically flip the /opt/linofinance/app/current symlink to the
#      new release.
#   6. `sudo systemctl restart linofinance-api`.
#   7. Probe https://lf.linotsai.top/api/v1/health and fail if version
#      != "1.1.7" or status != "ok".
#
# Dry-run mode (--dry-run): print every command, contact nothing.
# This script never pushes commits, never tags, never alters the local
# repo. Live deploy must be triggered manually by the operator.

set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_HOST="${DEPLOY_HOST:-118.178.122.194}"
DEPLOY_BASE="${DEPLOY_BASE:-/opt/linofinance/app}"
SERVICE_UNIT="${SERVICE_UNIT:-linofinance-api}"
HEALTH_URL="${HEALTH_URL:-https://lf.linotsai.top/api/v1/health}"
EXPECTED_VERSION="${EXPECTED_VERSION:-1.1.7}"

DRY_RUN=0
# Honour `FORCE=1 scripts/deploy-api.sh` (env-var override, per plan).
FORCE="${FORCE:-0}"
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        -h|--help)
            sed -n '2,24p' "$0"
            exit 0
            ;;
        *)
            echo "deploy-api.sh: unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

# repo root = parent of scripts/
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"

if [[ ! -d "$BACKEND_DIR" ]]; then
    echo "deploy-api.sh: backend directory not found at $BACKEND_DIR" >&2
    exit 2
fi

STAMP="$(date -u +%Y%m%d-%H%M%S)"
RELEASE_DIR="$DEPLOY_BASE/releases/$STAMP"
REMOTE_TARGET="$RELEASE_DIR/backend"
SSH_TARGET="$DEPLOY_USER@$DEPLOY_HOST"

# --- Helpers -----------------------------------------------------------------

# `run` either prints the command (dry-run) or executes it.
run() {
    if (( DRY_RUN )); then
        printf '[dry-run] %s\n' "$*"
    else
        eval "$@"
    fi
}

# `remote` prepares an ssh command and pipes it through `run`.
remote() {
    local script="$1"
    run "ssh '$SSH_TARGET' bash -se <<'REMOTE_EOF'
$script
REMOTE_EOF"
}

banner() {
    printf '\n=== %s ===\n' "$*"
}

# --- Plan --------------------------------------------------------------------

banner "LinoFinance deploy plan"
printf 'mode           : %s\n' "$([[ $DRY_RUN -eq 1 ]] && echo DRY-RUN || echo LIVE)"
printf 'release stamp  : %s\n' "$STAMP"
printf 'release dir    : %s:%s\n' "$SSH_TARGET" "$RELEASE_DIR"
printf 'service unit   : %s\n' "$SERVICE_UNIT"
printf 'health url     : %s\n' "$HEALTH_URL"
printf 'expected ver   : %s\n' "$EXPECTED_VERSION"
printf 'force          : %s\n' "$FORCE"

if (( DRY_RUN == 0 )); then
    if ! command -v ssh >/dev/null 2>&1; then
        echo "deploy-api.sh: ssh not found" >&2
        exit 3
    fi
fi

# --- Step 1: ensure release dir does not exist (unless FORCE) ----------------
#
# /opt/linofinance is owned by the `linofinance` system user, so all writes
# on the remote must go through `sudo -u linofinance` (or `sudo` for chown).
# The `deploy` user has NOPASSWD sudo per the HZ ops manual.

banner "Step 1: claim release dir"
remote "
if [ -e '$RELEASE_DIR' ]; then
    if [ '$FORCE' = '1' ]; then
        echo 'force: removing existing $RELEASE_DIR'
        sudo rm -rf '$RELEASE_DIR'
    else
        echo 'refusing to overwrite existing $RELEASE_DIR (use FORCE=1 to rebuild)' >&2
        exit 4
    fi
fi
sudo install -d -m 755 -o linofinance -g linofinance '$REMOTE_TARGET'
"

# --- Step 2: rsync ----------------------------------------------------------
# Use --rsync-path so the remote side runs rsync under sudo and can write
# into the linofinance-owned release dir.

banner "Step 2: rsync backend/"
run "rsync -az --delete \
    --rsync-path='sudo -u linofinance rsync' \
    --exclude='.venv' \
    --exclude='__pycache__' \
    --exclude='.local' \
    --exclude='.backups' \
    --exclude='tests' \
    '$BACKEND_DIR/' \
    '$SSH_TARGET:$REMOTE_TARGET/'"

# --- Step 3: build per-release venv and install -----------------------------

banner "Step 3: build per-release venv"
remote "
sudo -u linofinance bash -se <<'INNER_EOF'
cd '$REMOTE_TARGET'
python3 -m venv .venv
.venv/bin/pip install --upgrade pip setuptools wheel --quiet
.venv/bin/pip install -e . --quiet
INNER_EOF
"

# --- Step 4: run production migration ----------------------------------------
# Load the env file (root:linofinance 640) into the migration shell so the
# script sees LINOFINANCE_DATABASE_URL etc.

banner "Step 4: run production_migrate.py"
remote "
sudo bash -se <<'INNER_EOF'
set -a
. /etc/linofinance/api.env
set +a
cd '$REMOTE_TARGET'
sudo -E -u linofinance .venv/bin/python scripts/production_migrate.py
INNER_EOF
"

# --- Step 5: atomically flip the current symlink ------------------------------

banner "Step 5: flip /opt/linofinance/app/current"
remote "
sudo -u linofinance bash -se <<'INNER_EOF'
cd '$DEPLOY_BASE'
PREV_TARGET=\$(readlink current || true)
ln -sfn '$RELEASE_DIR' current.new
mv -T current.new current
echo \"previous release: \$PREV_TARGET\"
INNER_EOF
"

# --- Step 6: restart service -------------------------------------------------

banner "Step 6: systemctl restart $SERVICE_UNIT"
remote "sudo systemctl restart '$SERVICE_UNIT'"

# --- Step 7: health probe ----------------------------------------------------

banner "Step 7: health probe"
if (( DRY_RUN )); then
    printf '[dry-run] curl -fsS %s\n' "$HEALTH_URL"
    printf '[dry-run] expect: status="ok" version="%s"\n' "$EXPECTED_VERSION"
    banner "Dry-run complete (no remote contact)"
    exit 0
fi

# Live mode: probe up to 10 times with backoff while the unit warms up.
attempt=0
max_attempts=10
sleep_secs=2
while :; do
    attempt=$((attempt + 1))
    body="$(curl -fsS "$HEALTH_URL" 2>/dev/null || true)"
    if echo "$body" | grep -q "\"version\":\"$EXPECTED_VERSION\""; then
        if echo "$body" | grep -q '"status":"ok"'; then
            printf 'health ok: %s\n' "$body"
            break
        fi
    fi
    if (( attempt >= max_attempts )); then
        echo "deploy-api.sh: health probe failed after $attempt attempts" >&2
        echo "deploy-api.sh: last body: ${body:-<empty>}" >&2
        echo "deploy-api.sh: to roll back, run on $SSH_TARGET:" >&2
        echo "deploy-api.sh:   ln -sfn <prev-release> $DEPLOY_BASE/current \\" >&2
        echo "deploy-api.sh:     && sudo systemctl restart $SERVICE_UNIT" >&2
        exit 5
    fi
    printf 'attempt %d/%d health pending; sleeping %ds\n' "$attempt" "$max_attempts" "$sleep_secs"
    sleep "$sleep_secs"
done

banner "Live deploy complete"
