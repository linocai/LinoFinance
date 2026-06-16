"""v2.2.0 P1 — credit-liability recompute data migration.

Exercises ``202606160001_recompute_credit_liability``: a credit account whose
stored ``current_liability`` has drifted from ``Σ(non-voided cycle: statement −
paid)`` (the −1400 / 800 开账误录 bug) is recomputed to ``Σcycle`` on upgrade, the
drift is parked in a traceable ``account_adjustments`` + ``audit_logs`` trail, and
``downgrade`` restores the original stored value. Verified against a temp SQLite
DB built the same way the app does (``create_all`` + alembic stamp), mirroring
the existing migration tests.
"""
from decimal import Decimal
from uuid import uuid4

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text

from app import models  # noqa: F401
from app.core.config import get_settings
from app.db.base import Base

PRIOR_HEAD = "202606150001"
RECOMPUTE_HEAD = "202606160001"
ADJUSTMENT_SOURCE = "liability_recompute"
AUDIT_ACTION = "account.liability_recompute"


def _build_engine(tmp_path, monkeypatch):
    db_path = tmp_path / "p1_credit_liability.db"
    url = f"sqlite+pysqlite:///{db_path}"
    monkeypatch.setenv("LINOFINANCE_DATABASE_URL", url)
    get_settings.cache_clear()
    engine = create_engine(url)
    Base.metadata.create_all(bind=engine)
    return engine


def _alembic_config() -> Config:
    return Config("alembic.ini")


def _insert_credit_account(engine, name, stored_liability: str) -> str:
    account_id = str(uuid4())
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO accounts "
                "(id, name, type, currency, current_balance, current_liability, "
                " include_in_net_worth, status, display_order, created_at, updated_at) "
                "VALUES (:id, :name, 'credit', 'CNY', 0, :liab, 1, 'active', 0, "
                " CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            ),
            {"id": account_id, "name": name, "liab": stored_liability},
        )
    return account_id


def _insert_cycle(
    engine, account_id, statement_amount: str, paid_amount: str, status: str = "statement_generated"
) -> None:
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO credit_statement_cycles "
                "(id, credit_account_id, cycle_start_date, cycle_end_date, "
                " statement_date, due_date, currency, statement_amount, "
                " minimum_payment, paid_amount, status, created_at, updated_at) "
                "VALUES (:id, :aid, '2026-05-01', '2026-05-31', '2026-06-01', "
                " '2026-06-20', 'CNY', :stmt, 0, :paid, :status, "
                " CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            ),
            {
                "id": str(uuid4()),
                "aid": account_id,
                "stmt": statement_amount,
                "paid": paid_amount,
                "status": status,
            },
        )


def _liability(engine, account_id) -> Decimal:
    with engine.connect() as conn:
        return Decimal(
            conn.execute(
                text("SELECT current_liability FROM accounts WHERE id = :id"),
                {"id": account_id},
            ).scalar_one()
        )


def _count(engine, table, where_clause, params) -> int:
    with engine.connect() as conn:
        return conn.execute(
            text(f"SELECT COUNT(*) FROM {table} WHERE {where_clause}"), params
        ).scalar_one()


def test_recompute_fixes_drifted_credit_account(tmp_path, monkeypatch) -> None:
    engine = _build_engine(tmp_path, monkeypatch)
    cfg = _alembic_config()
    command.stamp(cfg, PRIOR_HEAD)

    # Drifted card: stored 1400, but Σcycle = 600 (the 800 开账误录).
    drifted = _insert_credit_account(engine, "花呗", "1400")
    _insert_cycle(engine, drifted, statement_amount="600", paid_amount="0")
    # Healthy card: stored 250 already equals Σcycle (100 + 250 − 100 paid).
    healthy = _insert_credit_account(engine, "Healthy", "250")
    _insert_cycle(engine, healthy, statement_amount="250", paid_amount="0", status="open")

    command.upgrade(cfg, "head")

    # Drifted account归正 to Σcycle = 600.
    assert _liability(engine, drifted) == Decimal("600.00")
    # Healthy account untouched (no spurious adjustment).
    assert _liability(engine, healthy) == Decimal("250.00")

    # Drift parked: one adjustment row + one audit row for the drifted account.
    assert (
        _count(
            engine,
            "account_adjustments",
            "account_id = :aid AND source = :src",
            {"aid": drifted, "src": ADJUSTMENT_SOURCE},
        )
        == 1
    )
    assert (
        _count(
            engine,
            "audit_logs",
            "target_id = :aid AND action_type = :act",
            {"aid": drifted, "act": AUDIT_ACTION},
        )
        == 1
    )
    # No adjustment created for the healthy account.
    assert (
        _count(
            engine,
            "account_adjustments",
            "account_id = :aid AND source = :src",
            {"aid": healthy, "src": ADJUSTMENT_SOURCE},
        )
        == 0
    )

    # Adjustment trail records the抹平 delta (600 − 1400 = −800).
    with engine.connect() as conn:
        delta, before, after = conn.execute(
            text(
                "SELECT delta_amount, balance_before, balance_after "
                "FROM account_adjustments "
                "WHERE account_id = :aid AND source = :src"
            ),
            {"aid": drifted, "src": ADJUSTMENT_SOURCE},
        ).one()
    assert Decimal(delta) == Decimal("-800.00")
    assert Decimal(before) == Decimal("1400.00")
    assert Decimal(after) == Decimal("600.00")

    get_settings.cache_clear()


def test_recompute_downgrade_restores_original_liability(tmp_path, monkeypatch) -> None:
    engine = _build_engine(tmp_path, monkeypatch)
    cfg = _alembic_config()
    command.stamp(cfg, PRIOR_HEAD)

    drifted = _insert_credit_account(engine, "花呗", "1400")
    _insert_cycle(engine, drifted, statement_amount="600", paid_amount="0")

    command.upgrade(cfg, "head")
    assert _liability(engine, drifted) == Decimal("600.00")

    command.downgrade(cfg, PRIOR_HEAD)
    # Original stored value restored; trail rows removed.
    assert _liability(engine, drifted) == Decimal("1400.00")
    assert (
        _count(
            engine,
            "account_adjustments",
            "source = :src",
            {"src": ADJUSTMENT_SOURCE},
        )
        == 0
    )
    assert (
        _count(
            engine,
            "audit_logs",
            "action_type = :act",
            {"act": AUDIT_ACTION},
        )
        == 0
    )

    get_settings.cache_clear()


def test_recompute_is_noop_when_no_drift(tmp_path, monkeypatch) -> None:
    engine = _build_engine(tmp_path, monkeypatch)
    cfg = _alembic_config()
    command.stamp(cfg, PRIOR_HEAD)

    healthy = _insert_credit_account(engine, "Healthy", "300")
    _insert_cycle(engine, healthy, statement_amount="300", paid_amount="0", status="open")

    command.upgrade(cfg, "head")

    assert _liability(engine, healthy) == Decimal("300.00")
    assert (
        _count(
            engine,
            "account_adjustments",
            "source = :src",
            {"src": ADJUSTMENT_SOURCE},
        )
        == 0
    )

    get_settings.cache_clear()
