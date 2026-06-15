"""P2 (v2.1.0) reimbursement status-collapse data migration.

Exercises ``202606150001_collapse_reimbursement_statuses``: every legacy
nine-state ``reimbursement_claims.status`` value is remapped to one of the three
single-user states (pending / received / abandoned). The migration is verified
against a temp SQLite DB built the same way the app does (``create_all`` +
alembic stamp), mirroring the v1.4.0 draft-void migration test.
"""

from uuid import uuid4

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text

from app import models  # noqa: F401
from app.core.config import get_settings
from app.db.base import Base

# This migration chains after the v1.4.0 draft-void migration.
PRIOR_HEAD = "202606120001"
COLLAPSE_HEAD = "202606150001"

# old status -> expected new three-state value
EXPECTED_MAPPING = {
    "reimbursable": "pending",
    "invoice_pending": "pending",
    "submitted": "pending",
    "approved": "pending",
    "waiting_received": "pending",
    "partial_received": "received",
    "rejected": "abandoned",
    # already-collapsed values are left untouched
    "received": "received",
    "abandoned": "abandoned",
}


def _build_engine(tmp_path, monkeypatch):
    db_path = tmp_path / "p2_reimbursement.db"
    url = f"sqlite+pysqlite:///{db_path}"
    monkeypatch.setenv("LINOFINANCE_DATABASE_URL", url)
    get_settings.cache_clear()
    engine = create_engine(url)
    Base.metadata.create_all(bind=engine)
    return engine


def _alembic_config() -> Config:
    return Config("alembic.ini")


def _insert_entry(engine) -> str:
    entry_id = str(uuid4())
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO financial_entries "
                "(id, title, entry_type, date, status, created_by, "
                " created_at, updated_at) "
                "VALUES (:id, 'expense', 'single', '2026-05-16', 'confirmed', 'user', "
                " CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            ),
            {"id": entry_id},
        )
    return entry_id


def _insert_claim(engine, linked_entry_id: str, status: str) -> str:
    claim_id = str(uuid4())
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO reimbursement_claims "
                "(id, linked_entry_id, amount, currency, payer, expected_date, "
                " status, created_at, updated_at) "
                "VALUES (:id, :entry, 100, 'CNY', 'company', '2026-06-10', "
                " :status, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            ),
            {"id": claim_id, "entry": linked_entry_id, "status": status},
        )
    return claim_id


def _status_of(engine, claim_id: str) -> str:
    with engine.connect() as conn:
        return conn.execute(
            text("SELECT status FROM reimbursement_claims WHERE id = :id"),
            {"id": claim_id},
        ).scalar_one()


def _distinct_statuses(engine):
    with engine.connect() as conn:
        return {
            row[0]
            for row in conn.execute(text("SELECT DISTINCT status FROM reimbursement_claims"))
        }


def test_migration_collapses_all_legacy_statuses(tmp_path, monkeypatch) -> None:
    engine = _build_engine(tmp_path, monkeypatch)
    cfg = _alembic_config()
    command.stamp(cfg, PRIOR_HEAD)

    entry_id = _insert_entry(engine)
    claim_ids = {
        old_status: _insert_claim(engine, entry_id, old_status)
        for old_status in EXPECTED_MAPPING
    }

    command.upgrade(cfg, "head")

    # Every legacy value is remapped to its three-state target.
    for old_status, claim_id in claim_ids.items():
        assert _status_of(engine, claim_id) == EXPECTED_MAPPING[old_status], old_status

    # Only the three canonical states remain in the table.
    assert _distinct_statuses(engine) <= {"pending", "received", "abandoned"}

    get_settings.cache_clear()


def test_migration_is_idempotent_on_three_state_rows(tmp_path, monkeypatch) -> None:
    engine = _build_engine(tmp_path, monkeypatch)
    cfg = _alembic_config()
    command.stamp(cfg, PRIOR_HEAD)

    entry_id = _insert_entry(engine)
    pending_id = _insert_claim(engine, entry_id, "pending")
    received_id = _insert_claim(engine, entry_id, "received")
    abandoned_id = _insert_claim(engine, entry_id, "abandoned")

    command.upgrade(cfg, "head")

    assert _status_of(engine, pending_id) == "pending"
    assert _status_of(engine, received_id) == "received"
    assert _status_of(engine, abandoned_id) == "abandoned"

    get_settings.cache_clear()
