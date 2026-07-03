from decimal import Decimal
from typing import List

from pydantic import BaseModel, field_serializer

from app.schemas.entry import format_decimal


class CurrencyAmount(BaseModel):
    currency: str
    amount: Decimal

    @field_serializer("amount")
    def serialize_amount(self, value: Decimal) -> str:
        return format_decimal(value)


class DashboardSummary(BaseModel):
    base_currency: str
    balance_total_cny: Decimal
    credit_liability_total_cny: Decimal
    net_worth_cny: Decimal
    draft_entry_count: int
    confirmed_entry_count: int
    voided_entry_count: int

    # new in v1.1.6 — additive, defaults keep older callers safe
    investment_total_cny: Decimal = Decimal("0")
    investment_total_by_currency: List[CurrencyAmount] = []
    today_pnl_by_currency: List[CurrencyAmount] = []
    disposable_30d_by_currency: List[CurrencyAmount] = []
    cash_flow_30d_by_currency: List[CurrencyAmount] = []

    # new in v1.4.0 — additive per-currency net-worth breakdown.
    # CNY always present; other currencies only when non-zero. net per currency
    # = balance + investment − credit liability (original currency, no FX).
    balance_total_by_currency: List[CurrencyAmount] = []
    credit_liability_by_currency: List[CurrencyAmount] = []
    net_worth_by_currency: List[CurrencyAmount] = []

    # new in v2.5.0 — additive: pending reimbursement receivable now folded into
    # net worth. `..._total_cny` is the CNY-converted sum (real-time convert with
    # a stored-`converted_cny_amount` fallback when a currency has no rate for
    # today); `..._by_currency` are the original-currency buckets (CNY always
    # present; other currencies only when non-zero). Only status=="pending"
    # claims count — received/abandoned are excluded (§5.3).
    reimbursement_receivable_total_cny: Decimal = Decimal("0")
    reimbursement_receivable_by_currency: List[CurrencyAmount] = []

    @field_serializer(
        "balance_total_cny",
        "credit_liability_total_cny",
        "net_worth_cny",
        "investment_total_cny",
        "reimbursement_receivable_total_cny",
    )
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)
