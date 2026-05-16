import calendar
from datetime import date as DateType, timedelta
from typing import Optional


def add_months(value: DateType, months: int) -> DateType:
    month_index = value.month - 1 + months
    year = value.year + month_index // 12
    month = month_index % 12 + 1
    day = min(value.day, calendar.monthrange(year, month)[1])
    return DateType(year, month, day)


def next_subscription_date(
    value: DateType,
    interval: str,
    billing_day: Optional[int] = None,
) -> DateType:
    if interval == "weekly":
        return value + timedelta(days=7)
    if interval == "monthly":
        next_date = add_months(value, 1)
    elif interval == "yearly":
        next_date = add_months(value, 12)
    else:
        raise ValueError("Unsupported billing interval")

    if billing_day is None:
        return next_date

    day = min(billing_day, calendar.monthrange(next_date.year, next_date.month)[1])
    return DateType(next_date.year, next_date.month, day)
