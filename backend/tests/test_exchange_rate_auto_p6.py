"""v3.0.0 P6 — automatic daily exchange-rate ingestion.

Exercises ``app.services.exchange_rate_auto.fetch_daily_auto_rates`` (called by
the CLI entry ``scripts/fetch_exchange_rates.py``, meant for an unattended
systemd timer): it inserts a ``CurrencyRate(source="auto")`` row only when
today has no rate at all yet, a manual entry always wins and is never
overwritten, re-runs are idempotent, and every flavor of fetch failure
(network, timeout, malformed body, missing/garbage rate) is swallowed rather
than raised. The real public API is never called here — every HTTP call is
mocked, mirroring the ``ai_provider`` HTTP-mocking pattern in
``test_phase6_ai_notifications.py``.
"""
import importlib.util
import json
import urllib.error
from datetime import date
from decimal import Decimal
from pathlib import Path

from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import models  # noqa: F401  (register mappers)
from app.db.base import Base
from app.models.currency_rate import CurrencyRate
from app.services import exchange_rate_auto


class _FakeRateResponse:
    """Minimal stand-in for the urllib response context manager (mirrors
    ``_FakeLLMResponse`` in ``test_phase6_ai_notifications.py``)."""

    def __init__(self, payload: dict) -> None:
        self._data = json.dumps(payload).encode("utf-8")

    def read(self) -> bytes:
        return self._data

    def __enter__(self) -> "_FakeRateResponse":
        return self

    def __exit__(self, *exc) -> bool:
        return False


def _mock_rate(monkeypatch, payload: dict, capture: list = None):
    def fake_urlopen(request, timeout=None):
        if capture is not None:
            capture.append(request.full_url)
        assert timeout == exchange_rate_auto._REQUEST_TIMEOUT_SECONDS
        return _FakeRateResponse(payload)

    monkeypatch.setattr(exchange_rate_auto.urllib.request, "urlopen", fake_urlopen)


# --- happy path --------------------------------------------------------------


def test_inserts_auto_rate_when_none_exists_today(client, monkeypatch) -> None:
    fixed_today = date(2020, 1, 15)
    monkeypatch.setattr(exchange_rate_auto, "app_today", lambda: fixed_today)
    captured_urls: list = []
    _mock_rate(
        monkeypatch,
        {"result": "success", "base_code": "USD", "rates": {"USD": 1, "CNY": 7.1234, "EUR": 0.9}},
        captured_urls,
    )

    with client.session_factory() as db:
        inserted = exchange_rate_auto.fetch_daily_auto_rates(db)

        # Direction check: requested with base=USD (never base=CNY), and
        # `rates["CNY"]` (7.1234, "1 USD = 7.1234 CNY") is taken literally, never
        # inverted (1/7.1234 ≈ 0.14 would be an obviously wrong USD/CNY rate).
        assert captured_urls == ["https://open.er-api.com/v6/latest/USD"]
        assert len(inserted) == 1
        row = inserted[0]
        assert row.from_currency == "USD"
        assert row.to_currency == "CNY"
        assert row.rate == Decimal("7.1234")
        assert row.source == "auto"
        assert row.date == fixed_today

        persisted = db.execute(select(CurrencyRate)).scalars().all()
        assert len(persisted) == 1


def test_prior_day_rate_does_not_block_todays_auto_insert(client, monkeypatch) -> None:
    """Only *today's* rate is checked — an older manual rate on file must not
    suppress today's auto insert."""
    fixed_today = date(2020, 1, 15)
    monkeypatch.setattr(exchange_rate_auto, "app_today", lambda: fixed_today)

    with client.session_factory() as db:
        db.add(
            CurrencyRate(
                from_currency="USD",
                to_currency="CNY",
                rate=Decimal("6.5"),
                date=date(2020, 1, 14),
                source="manual",
            )
        )
        db.commit()

        _mock_rate(monkeypatch, {"result": "success", "rates": {"CNY": 7.2}})
        inserted = exchange_rate_auto.fetch_daily_auto_rates(db)

        assert len(inserted) == 1
        assert inserted[0].date == fixed_today
        assert inserted[0].rate == Decimal("7.2")
        assert inserted[0].source == "auto"

        rows = db.execute(select(CurrencyRate)).scalars().all()
        assert len(rows) == 2  # yesterday's manual + today's auto, both kept


# --- manual priority / never overwrite ---------------------------------------


def test_manual_rate_blocks_auto_insert_and_network_call(client, monkeypatch) -> None:
    fixed_today = date(2020, 1, 15)
    monkeypatch.setattr(exchange_rate_auto, "app_today", lambda: fixed_today)

    with client.session_factory() as db:
        db.add(
            CurrencyRate(
                from_currency="USD",
                to_currency="CNY",
                rate=Decimal("6.8"),
                date=fixed_today,
                source="manual",
            )
        )
        db.commit()

        def _unexpected_call(request, timeout=None):
            raise AssertionError("must not hit the network once today is already covered")

        monkeypatch.setattr(exchange_rate_auto.urllib.request, "urlopen", _unexpected_call)

        inserted = exchange_rate_auto.fetch_daily_auto_rates(db)

        assert inserted == []
        rows = db.execute(select(CurrencyRate).where(CurrencyRate.date == fixed_today)).scalars().all()
        assert len(rows) == 1
        assert rows[0].source == "manual"
        assert rows[0].rate == Decimal("6.8")  # untouched — never overwritten


def test_second_run_same_day_is_idempotent(client, monkeypatch) -> None:
    fixed_today = date(2020, 1, 15)
    monkeypatch.setattr(exchange_rate_auto, "app_today", lambda: fixed_today)
    call_count = {"n": 0}

    def fake_urlopen(request, timeout=None):
        call_count["n"] += 1
        return _FakeRateResponse({"result": "success", "rates": {"CNY": 7.0}})

    monkeypatch.setattr(exchange_rate_auto.urllib.request, "urlopen", fake_urlopen)

    with client.session_factory() as db:
        first = exchange_rate_auto.fetch_daily_auto_rates(db)
        assert len(first) == 1
        assert call_count["n"] == 1

        second = exchange_rate_auto.fetch_daily_auto_rates(db)
        assert second == []
        assert call_count["n"] == 1  # already covered today -> no repeat network call

        rows = db.execute(select(CurrencyRate)).scalars().all()
        assert len(rows) == 1


# --- failures are swallowed, never raised, never block ------------------------


def test_network_and_timeout_errors_are_swallowed_and_logged(client, monkeypatch) -> None:
    fixed_today = date(2020, 1, 15)
    monkeypatch.setattr(exchange_rate_auto, "app_today", lambda: fixed_today)

    def fake_urlopen(request, timeout=None):
        raise urllib.error.URLError("simulated network timeout")

    monkeypatch.setattr(exchange_rate_auto.urllib.request, "urlopen", fake_urlopen)

    # Spy the LOGGER.warning call directly rather than going through pytest's
    # `caplog` handler pipeline: a handful of *other* test modules invoke
    # `alembic.command` programmatically, which runs `alembic/env.py`'s
    # `fileConfig(config.config_file_name)` — Python's stdlib default for that
    # call is `disable_existing_loggers=True`, which silently flips
    # `.disabled = True` on every already-created logger not listed in
    # `alembic.ini`'s `[loggers]` (root/sqlalchemy/alembic only). Since our
    # module-level `LOGGER` is created at import time (during pytest
    # collection, before any test body runs), it can end up disabled by the
    # time this test executes purely due to full-suite test order — a
    # pre-existing, suite-wide caplog footgun unrelated to this module's own
    # correctness. Patching the bound method sidesteps the whole
    # level/handler/disabled pipeline so this assertion is robust regardless.
    warnings_logged: list = []
    monkeypatch.setattr(
        exchange_rate_auto.LOGGER,
        "warning",
        lambda message, *args, **kwargs: warnings_logged.append(message),
    )

    with client.session_factory() as db:
        inserted = exchange_rate_auto.fetch_daily_auto_rates(db)

        assert inserted == []
        assert db.execute(select(CurrencyRate)).scalars().all() == []
        assert any("Auto exchange rate fetch failed" in message for message in warnings_logged)
        # The swallowed failure must not poison the session with a pending
        # rollback state — the caller's session stays usable afterwards.
        db.execute(select(CurrencyRate)).scalars().all()


def test_non_json_response_body_is_swallowed(client, monkeypatch) -> None:
    class _GarbageResponse:
        def read(self) -> bytes:
            return b"not json at all"

        def __enter__(self) -> "_GarbageResponse":
            return self

        def __exit__(self, *exc) -> bool:
            return False

    fixed_today = date(2020, 1, 15)
    monkeypatch.setattr(exchange_rate_auto, "app_today", lambda: fixed_today)
    monkeypatch.setattr(
        exchange_rate_auto.urllib.request,
        "urlopen",
        lambda request, timeout=None: _GarbageResponse(),
    )

    with client.session_factory() as db:
        inserted = exchange_rate_auto.fetch_daily_auto_rates(db)
        assert inserted == []
        assert db.execute(select(CurrencyRate)).scalars().all() == []


def test_bad_rate_payload_shapes_are_swallowed(client, monkeypatch) -> None:
    """A grab-bag of "the API responded but the shape is useless" cases: an
    explicit error result, a missing `rates` object, a missing target currency,
    a non-numeric rate, and non-positive rates. None may raise or insert a row."""
    fixed_today = date(2020, 1, 15)
    monkeypatch.setattr(exchange_rate_auto, "app_today", lambda: fixed_today)

    bad_payloads = [
        {"result": "error", "error-type": "invalid-base-currency"},
        {"result": "success", "rates": {"EUR": 0.9}},  # no CNY key
        {"result": "success", "rates": "not-a-dict"},
        {"result": "success", "rates": {"CNY": "not-a-number"}},
        {"result": "success", "rates": {"CNY": -1}},
        {"result": "success", "rates": {"CNY": 0}},
    ]

    with client.session_factory() as db:
        for bad_payload in bad_payloads:
            _mock_rate(monkeypatch, bad_payload)
            inserted = exchange_rate_auto.fetch_daily_auto_rates(db)
            assert inserted == [], f"must no-op for payload: {bad_payload!r}"

        assert db.execute(select(CurrencyRate)).scalars().all() == []


# --- CLI entry point smoke ----------------------------------------------------


def test_cli_entry_point_smoke(monkeypatch) -> None:
    """Import and run `scripts/fetch_exchange_rates.py`'s `main()` against an
    isolated in-memory DB with a mocked HTTP call. This never touches the real
    network, nor the app's real (Postgres-configured) `SessionLocal` the script
    imports by default — that binding is monkeypatched out on the loaded script
    module before `main()` runs, exactly like patching any other module-level
    name for a test."""
    script_path = Path(__file__).resolve().parents[1] / "scripts" / "fetch_exchange_rates.py"
    spec = importlib.util.spec_from_file_location("fetch_exchange_rates_script", script_path)
    assert spec is not None and spec.loader is not None
    script_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(script_module)  # runs at module scope only — no argv/main() yet

    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    isolated_session_local = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    Base.metadata.create_all(bind=engine)
    monkeypatch.setattr(script_module, "SessionLocal", isolated_session_local)

    fixed_today = date(2020, 1, 15)
    monkeypatch.setattr(exchange_rate_auto, "app_today", lambda: fixed_today)
    _mock_rate(monkeypatch, {"result": "success", "rates": {"CNY": 6.91}})

    script_module.main([])  # argv=[] so pytest's own CLI flags never leak into argparse

    with isolated_session_local() as db:
        rows = db.execute(select(CurrencyRate)).scalars().all()
    assert len(rows) == 1
    assert rows[0].source == "auto"
    assert rows[0].from_currency == "USD"
    assert rows[0].rate == Decimal("6.91")
