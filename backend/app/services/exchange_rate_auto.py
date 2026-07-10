"""Automatic daily exchange-rate ingestion (v3.0.0 P6, §3/§5.8 D3=甲).

Pulls a free, keyless public API (``open.er-api.com``) once per non-CNY
currency LinoFinance supports and inserts a ``CurrencyRate(source="auto")``
row — but *only* when no rate at all (manual or auto) exists yet for that
``(from_currency, CNY, today)`` triple. A manual entry (``source="manual"``)
always wins: this module never edits or overwrites an existing row, so a
human correction is permanent once made. Re-running on the same day is a
no-op (idempotent) once any rate — manual or auto — is on file for today.

Network failures (timeout, DNS, non-2xx status, malformed JSON, a response
missing the expected rate) are all swallowed here and logged as a warning —
this augments the ledger, it must never block or crash a caller. It is meant
to run unattended off a systemd timer (``deploy/systemd/linofinance-jobs.*``,
CLI entry ``scripts/fetch_exchange_rates.py``).

Direction of conversion: ``open.er-api.com/v6/latest/{base}`` returns rates
*from* ``base`` to every other currency directly — e.g. ``base=USD`` gives
``rates["CNY"]`` = how many CNY one USD buys. LinoFinance's ``CurrencyRate``
semantics are exactly "1 unit of ``from_currency`` = ``rate`` * CNY" with
``to_currency`` always CNY (``app.core.constants.BASE_CURRENCY``), so
requesting with ``base=<non-CNY currency>`` and reading
``rates[BASE_CURRENCY]`` needs no inversion and no precision loss from a
manual ``1/x`` flip.
"""
from __future__ import annotations

import json
import logging
import urllib.request
from datetime import date as DateType
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.constants import BASE_CURRENCY, SUPPORTED_CURRENCIES
from app.core.timeutils import app_today
from app.models.currency_rate import CurrencyRate

LOGGER = logging.getLogger("linofinance.exchange_rate_auto")

# Free, no-key exchange rate API: https://www.exchangerate-api.com/docs/free
_API_URL_TEMPLATE = "https://open.er-api.com/v6/latest/{base}"
_REQUEST_TIMEOUT_SECONDS = 10
_SOURCE_AUTO = "auto"

# Same 8-decimal scale as `currency_rates.rate` (`Numeric(18, 8)`); quantizing
# here keeps the stored value identical to what a re-read returns instead of
# relying on the DB driver to silently round a longer Decimal on write.
_RATE_QUANT = Decimal("0.00000001")

# Currencies to auto-fetch a rate for, derived from the supported set (not
# hardcoded to USD) so a future currency addition in
# `app.core.constants.SUPPORTED_CURRENCIES` is picked up automatically.
AUTO_FETCH_CURRENCIES: List[str] = sorted(SUPPORTED_CURRENCIES - {BASE_CURRENCY})


def fetch_daily_auto_rates(db: Session) -> List[CurrencyRate]:
    """Insert today's auto rate for each supported non-CNY currency that has no
    rate yet (manual or auto). Never raises: every per-currency fetch is
    isolated so one bad response can't block the others, and the caller (an API
    request path or the scheduled CLI script) never has to handle this failing.
    Returns the rows actually inserted (empty when everything was already
    covered, or every fetch failed)."""
    today = app_today()
    inserted: List[CurrencyRate] = []
    for from_currency in AUTO_FETCH_CURRENCIES:
        try:
            row = _fetch_and_insert_one(db, from_currency, today)
        except Exception as exc:  # network/parse/anything — see module docstring.
            db.rollback()
            LOGGER.warning(
                "Auto exchange rate fetch failed for %s/%s: %s",
                from_currency,
                BASE_CURRENCY,
                exc,
            )
            continue
        if row is not None:
            inserted.append(row)
    return inserted


def _fetch_and_insert_one(
    db: Session, from_currency: str, today: DateType
) -> Optional[CurrencyRate]:
    if _rate_already_covers_today(db, from_currency, today):
        return None  # a manual entry or a prior auto run already covers today

    rate_value = _fetch_rate(from_currency)

    row = CurrencyRate(
        from_currency=from_currency,
        to_currency=BASE_CURRENCY,
        rate=rate_value,
        date=today,
        source=_SOURCE_AUTO,
    )
    db.add(row)
    try:
        db.commit()
    except IntegrityError:
        # Lost a race against a concurrent insert (manual or auto) for the same
        # day; the unique constraint on (from_currency, to_currency, date) is
        # the real guard here — this just keeps a rare race from surfacing as
        # an unhandled error instead of the intended no-op.
        db.rollback()
        return None
    db.refresh(row)
    return row


def _rate_already_covers_today(db: Session, from_currency: str, today: DateType) -> bool:
    existing = db.execute(
        select(CurrencyRate.id).where(
            CurrencyRate.from_currency == from_currency,
            CurrencyRate.to_currency == BASE_CURRENCY,
            CurrencyRate.date == today,
        )
    ).first()
    return existing is not None


def _fetch_rate(from_currency: str) -> Decimal:
    """Fetch and parse ``from_currency -> BASE_CURRENCY``. Raises on any
    failure (network, non-2xx, bad JSON, missing/non-numeric/non-positive
    rate); `fetch_daily_auto_rates` is the one place that swallows it."""
    url = _API_URL_TEMPLATE.format(base=from_currency)
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=_REQUEST_TIMEOUT_SECONDS) as response:
        payload = json.loads(response.read().decode("utf-8"))

    result = payload.get("result")
    if result not in (None, "success"):
        raise ValueError(f"exchange rate API returned a non-success result: {result!r}")

    rates = payload.get("rates")
    if not isinstance(rates, dict):
        raise ValueError("exchange rate API response missing a 'rates' object")
    raw_rate = rates.get(BASE_CURRENCY)
    if raw_rate is None:
        raise ValueError(f"exchange rate API response has no {BASE_CURRENCY} rate")

    try:
        rate = Decimal(str(raw_rate))
    except InvalidOperation as exc:
        raise ValueError(f"non-numeric rate from exchange rate API: {raw_rate!r}") from exc
    if rate <= 0:
        raise ValueError(f"non-positive rate from exchange rate API: {rate}")
    return rate.quantize(_RATE_QUANT, rounding=ROUND_HALF_UP)
