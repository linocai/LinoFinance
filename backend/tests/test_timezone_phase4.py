"""P4 · 时区闭环 (audit §3.4/§3.5, design decision D6).

Covers the business-timezone helpers and the daily-pnl day bucketing across the
UTC day boundary. Default business timezone is Asia/Shanghai (UTC+8).
"""

from datetime import date, datetime, timezone
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import models  # noqa: F401
from app.core.timeutils import app_today, utc_to_app_date
from app.db.base import Base
from app.models.account import Account
from app.models.reconciliation import AccountAdjustment
from app.services.dashboard import _today_pnl_by_currency


# --- utc_to_app_date: cross-day boundary (happy) --------------------------


def test_utc_to_app_date_before_boundary_same_day() -> None:
    # 15:59 UTC on 2026-06-10 is 23:59 Shanghai on the same calendar day.
    naive = datetime(2026, 6, 10, 15, 59, 0)
    assert utc_to_app_date(naive) == date(2026, 6, 10)


def test_utc_to_app_date_at_boundary_rolls_to_next_day() -> None:
    # 16:00 UTC on 2026-06-10 is 00:00 Shanghai on 2026-06-11 (UTC+8).
    naive = datetime(2026, 6, 10, 16, 0, 0)
    assert utc_to_app_date(naive) == date(2026, 6, 11)


def test_utc_to_app_date_after_boundary_next_day() -> None:
    naive = datetime(2026, 6, 10, 20, 30, 0)
    assert utc_to_app_date(naive) == date(2026, 6, 11)


def test_utc_to_app_date_treats_naive_as_utc() -> None:
    # A naive datetime is interpreted as UTC; an explicit-UTC aware datetime with
    # the same wall-clock components must bucket to the same date.
    naive = datetime(2026, 6, 10, 18, 0, 0)
    aware = datetime(2026, 6, 10, 18, 0, 0, tzinfo=timezone.utc)
    assert utc_to_app_date(naive) == utc_to_app_date(aware) == date(2026, 6, 11)


def test_utc_to_app_date_honors_aware_offset() -> None:
    # 23:30 at +08:00 is 15:30 UTC -> 23:30 Shanghai -> same local day.
    aware = datetime(2026, 6, 10, 23, 30, 0, tzinfo=timezone(_shanghai_offset()))
    assert utc_to_app_date(aware) == date(2026, 6, 10)


# --- utc_to_app_date: failure / wrong-naive interpretation ----------------


def test_utc_to_app_date_naive_not_bucketed_as_local_clock() -> None:
    # Regression guard for the pre-fix bug: a stored 23:00 UTC timestamp must NOT
    # stay on the original day — under Asia/Shanghai it belongs to the next day.
    naive = datetime(2026, 6, 10, 23, 0, 0)
    assert utc_to_app_date(naive) != date(2026, 6, 10)
    assert utc_to_app_date(naive) == date(2026, 6, 11)


def test_app_today_returns_a_date() -> None:
    assert isinstance(app_today(), date)


def _shanghai_offset():
    from datetime import timedelta

    return timedelta(hours=8)


# --- daily-pnl "today" bucketing at the UTC boundary ----------------------


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    session_local = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    session = session_local()
    try:
        yield session
    finally:
        session.close()


def _seed_investment_adjustment(session, created_at: datetime) -> None:
    account = Account(
        id="acct-1",
        name="Funds",
        type="investment",
        currency="CNY",
        current_balance=Decimal("1000"),
        include_in_net_worth=True,
        status="active",
    )
    session.add(account)
    session.flush()
    adjustment = AccountAdjustment(
        id="adj-1",
        account_id="acct-1",
        delta_amount=Decimal("50"),
        currency="CNY",
        balance_before=Decimal("1000"),
        balance_after=Decimal("1050"),
        source="investment_daily",
        reason="daily_pnl",
    )
    adjustment.created_at = created_at
    session.add(adjustment)
    session.commit()


def test_today_pnl_buckets_utc_evening_into_next_local_day(db_session) -> None:
    # An adjustment created 2026-06-10 18:00 UTC belongs to 2026-06-11 in
    # Shanghai. Asking for "today = 2026-06-11" must include it.
    _seed_investment_adjustment(db_session, datetime(2026, 6, 10, 18, 0, 0))

    rows = _today_pnl_by_currency(db_session, date(2026, 6, 11))
    pnl = {row.currency: row.amount for row in rows}
    assert pnl.get("CNY") == Decimal("50")


def test_today_pnl_excludes_when_local_day_differs(db_session) -> None:
    # Same UTC-evening adjustment must NOT show up when "today = 2026-06-10"
    # (its local Shanghai date is the 11th, not the 10th).
    _seed_investment_adjustment(db_session, datetime(2026, 6, 10, 18, 0, 0))

    rows = _today_pnl_by_currency(db_session, date(2026, 6, 10))
    assert rows == []
