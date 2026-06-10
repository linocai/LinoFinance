"""P8 repayment-reminder pipeline (audit 2.8).

Exercises the v1.3.0 seed migration that inserts a default ``credit_repayment`` /
``system`` ``NotificationRule`` and verifies the scheduled credit-due reminder
job can select that seeded rule and dispatch (dry-run) without any
hand-created rule.
"""

from datetime import date

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from app import models  # noqa: F401
from app.core.config import get_settings
from app.db.base import Base
from app.models.account import Account
from app.models.credit_statement_cycle import CreditStatementCycle
from app.models.notification import NotificationRule
from app.models.push import PushDevice
from app.services import push_dispatch

# The seed migration chains after the P6 currency-rate migration.
PRIOR_HEAD = "202606100001"
SEED_HEAD = "202606100002"


def _build_engine(tmp_path, monkeypatch):
    db_path = tmp_path / "p8.db"
    url = f"sqlite+pysqlite:///{db_path}"
    # alembic/env.py reads settings.database_url (env-driven, cached), so point
    # the whole config at this SQLite file and refresh the cache.
    monkeypatch.setenv("LINOFINANCE_DATABASE_URL", url)
    get_settings.cache_clear()
    engine = create_engine(url)
    # Create the schema the same way the app/tests do, then stamp at the
    # pre-seed revision so `upgrade head` runs only the seed data migration.
    Base.metadata.create_all(bind=engine)
    return engine, str(db_path)


def _alembic_config() -> Config:
    return Config("alembic.ini")


def _count_seed_rules(engine) -> int:
    with engine.connect() as conn:
        return conn.execute(
            text(
                "SELECT COUNT(*) FROM notification_rules "
                "WHERE rule_type = 'credit_repayment' AND channel = 'system'"
            )
        ).scalar_one()


def test_seed_migration_is_idempotent(tmp_path, monkeypatch) -> None:
    engine, db_path = _build_engine(tmp_path, monkeypatch)
    cfg = _alembic_config()

    command.stamp(cfg, PRIOR_HEAD)
    command.upgrade(cfg, "head")
    assert _count_seed_rules(engine) == 1

    # Running upgrade again (already at head) must not double-insert.
    command.upgrade(cfg, "head")
    assert _count_seed_rules(engine) == 1

    # Downgrade removes the seeded rule, re-upgrade re-inserts exactly one.
    command.downgrade(cfg, PRIOR_HEAD)
    assert _count_seed_rules(engine) == 0
    command.upgrade(cfg, "head")
    assert _count_seed_rules(engine) == 1

    get_settings.cache_clear()


def test_seed_migration_skips_when_rule_already_exists(tmp_path, monkeypatch) -> None:
    engine, db_path = _build_engine(tmp_path, monkeypatch)
    cfg = _alembic_config()
    command.stamp(cfg, PRIOR_HEAD)

    # Pre-create a matching rule (as the API would) before the seed runs.
    Session = sessionmaker(bind=engine)
    with Session() as db:
        db.add(
            NotificationRule(
                title="Pre-existing",
                rule_type="credit_repayment",
                channel="system",
                trigger_payload={},
                status="active",
            )
        )
        db.commit()

    command.upgrade(cfg, "head")
    # The seed migration must not add a second rule.
    assert _count_seed_rules(engine) == 1

    get_settings.cache_clear()


def test_scheduled_job_selects_seeded_rule(tmp_path, monkeypatch) -> None:
    engine, db_path = _build_engine(tmp_path, monkeypatch)
    monkeypatch.setenv("LINOFINANCE_APNS_DRY_RUN", "true")
    get_settings.cache_clear()
    cfg = _alembic_config()
    command.stamp(cfg, PRIOR_HEAD)
    command.upgrade(cfg, "head")
    assert _count_seed_rules(engine) == 1

    anchor = date(2026, 5, 20)
    Session = sessionmaker(bind=engine)
    with Session() as db:
        account = Account(
            name="Visa",
            type="credit",
            currency="CNY",
            current_balance=0,
            current_liability=0,
        )
        db.add(account)
        db.flush()
        # Due in 3 days, still owing.
        db.add(
            CreditStatementCycle(
                credit_account_id=account.id,
                cycle_start_date=date(2026, 4, 1),
                cycle_end_date=date(2026, 4, 30),
                statement_date=date(2026, 5, 1),
                due_date=date(2026, 5, 23),
                currency="CNY",
                statement_amount=3375,
                paid_amount=0,
                status="statement_generated",
            )
        )
        db.add(
            PushDevice(
                device_id="iphone-air",
                platform="ios",
                apns_token="apns-token",
                enabled=True,
            )
        )
        db.commit()

        results = push_dispatch.dispatch_due_credit_reminders(db, anchor_date=anchor)

    # Exactly one due cycle matched, the seeded rule was selected, and the
    # dry-run dispatch reported a send (no manual rule was created).
    assert len(results) == 1
    assert results[0].matched_rules == 1
    assert results[0].sent == 1
    assert results[0].dry_run is True

    get_settings.cache_clear()
