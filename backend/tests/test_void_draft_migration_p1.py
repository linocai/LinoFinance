"""P1 (v1.4.0) draft-removal data migration.

Exercises ``202606120001_void_legacy_draft_entries``: any leftover
``status='draft'`` ``FinancialEntry`` row is parked in ``voided`` so the table
only holds reachable statuses after the draft status is removed from the API.
The migration is verified against a temp SQLite DB built the same way the app
does (``create_all`` + alembic stamp), mirroring the v1.3.0 seed-migration test.
"""

from uuid import uuid4

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text

from app import models  # noqa: F401
from app.core.config import get_settings
from app.db.base import Base

# This migration chains after the v1.3.0 seed-repayment-rule migration.
PRIOR_HEAD = "202606100002"
DRAFT_VOID_HEAD = "202606120001"


def _build_engine(tmp_path, monkeypatch):
    db_path = tmp_path / "p1_draft.db"
    url = f"sqlite+pysqlite:///{db_path}"
    monkeypatch.setenv("LINOFINANCE_DATABASE_URL", url)
    get_settings.cache_clear()
    engine = create_engine(url)
    Base.metadata.create_all(bind=engine)
    return engine


def _alembic_config() -> Config:
    return Config("alembic.ini")


def _insert_entry(engine, status: str) -> str:
    entry_id = str(uuid4())
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO financial_entries "
                "(id, title, entry_type, date, status, created_by, "
                " created_at, updated_at) "
                "VALUES (:id, :title, 'single', '2026-05-16', :status, 'user', "
                " CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            ),
            {"id": entry_id, "title": f"{status} entry", "status": status},
        )
    return entry_id


def _status_of(engine, entry_id: str) -> str:
    with engine.connect() as conn:
        return conn.execute(
            text("SELECT status FROM financial_entries WHERE id = :id"),
            {"id": entry_id},
        ).scalar_one()


def _count_drafts(engine) -> int:
    with engine.connect() as conn:
        return conn.execute(
            text("SELECT COUNT(*) FROM financial_entries WHERE status = 'draft'")
        ).scalar_one()


def test_migration_voids_legacy_draft_entries(tmp_path, monkeypatch) -> None:
    engine = _build_engine(tmp_path, monkeypatch)
    cfg = _alembic_config()
    command.stamp(cfg, PRIOR_HEAD)

    # Seed a leftover draft plus a confirmed/voided control row.
    draft_id = _insert_entry(engine, "draft")
    confirmed_id = _insert_entry(engine, "confirmed")
    voided_id = _insert_entry(engine, "voided")

    command.upgrade(cfg, "head")

    # The draft was parked in voided; no draft rows remain.
    assert _count_drafts(engine) == 0
    assert _status_of(engine, draft_id) == "voided"
    # Other statuses are untouched.
    assert _status_of(engine, confirmed_id) == "confirmed"
    assert _status_of(engine, voided_id) == "voided"

    get_settings.cache_clear()


def test_migration_is_noop_without_drafts(tmp_path, monkeypatch) -> None:
    engine = _build_engine(tmp_path, monkeypatch)
    cfg = _alembic_config()
    command.stamp(cfg, PRIOR_HEAD)

    confirmed_id = _insert_entry(engine, "confirmed")

    command.upgrade(cfg, "head")

    assert _count_drafts(engine) == 0
    assert _status_of(engine, confirmed_id) == "confirmed"

    get_settings.cache_clear()
