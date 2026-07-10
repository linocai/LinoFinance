"""Fetch today's auto exchange rate(s) once (v3.0.0 P6).

Meant to run unattended off a systemd timer (see
``deploy/systemd/linofinance-jobs.service``, which already runs
``run_scheduled_jobs.py`` daily — this script reuses that same timer). Safe to
run more than once a day: ``exchange_rate_auto.fetch_daily_auto_rates`` only
inserts a rate when the day has none yet (manual or auto), so a re-run is a
no-op. Safe to leave fully unattended: network/parse failures are logged as a
warning and never raised (see the module docstring in
``app/services/exchange_rate_auto.py``).

Usage:
    cd backend && source .venv/bin/activate
    .venv/bin/python scripts/fetch_exchange_rates.py
"""
from __future__ import annotations

import argparse
from typing import List, Optional

from app import models  # noqa: F401  (register mappers)
from app.db.session import SessionLocal
from app.services import exchange_rate_auto


def main(argv: Optional[List[str]] = None) -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Fetch today's non-CNY -> CNY exchange rate from a free, keyless "
            "public API and store it as CurrencyRate(source='auto') when no "
            "rate — manual or auto — already exists for today."
        )
    )
    parser.parse_args(argv)

    with SessionLocal() as db:
        inserted = exchange_rate_auto.fetch_daily_auto_rates(db)

    if not inserted:
        print(
            "No new auto exchange rate inserted (today is already covered by "
            "a manual or earlier auto rate, or every fetch failed — see logs)."
        )
        return
    for row in inserted:
        print(
            f"Inserted {row.from_currency}/{row.to_currency} = {row.rate} "
            f"on {row.date} (source=auto)"
        )


if __name__ == "__main__":
    main()
