"""Business-timezone helpers (audit §3.4/§3.5, design decision D6).

The backend stores `created_at` as UTC-naive datetimes (see audit §3.2). Anchors
like "today" and per-day bucketing of those timestamps must resolve in the
configured business timezone (`LINOFINANCE_APP_TIMEZONE`, default Asia/Shanghai)
rather than the server's local clock or raw UTC, otherwise records near the UTC
day boundary land on the wrong calendar day.

py39 standard-library `zoneinfo` provides the timezone database lookup.
"""

from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

from app.core.config import get_settings


def app_timezone() -> ZoneInfo:
    """Return the configured business timezone."""
    return ZoneInfo(get_settings().app_timezone)


def app_today() -> date:
    """Return the current calendar date in the business timezone."""
    return datetime.now(app_timezone()).date()


def utc_to_app_date(dt: datetime) -> date:
    """Bucket a stored timestamp to a calendar date in the business timezone.

    `created_at` columns are UTC-naive; a naive ``dt`` is interpreted as UTC.
    Aware datetimes are honored as-is. The result is the local calendar date in
    the business timezone — e.g. a UTC timestamp at 16:00+ maps to the next day
    in Asia/Shanghai (UTC+8).
    """
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(app_timezone()).date()
