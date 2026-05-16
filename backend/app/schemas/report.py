from datetime import date as DateType
from decimal import Decimal
from typing import List

from pydantic import BaseModel, field_serializer

from app.schemas.entry import format_decimal


class CurrencyAmountSummary(BaseModel):
    currency: str
    amount: Decimal
    converted_cny_amount: Decimal

    @field_serializer("amount", "converted_cny_amount")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)


class MonthlyOverviewReport(BaseModel):
    date_from: DateType
    date_to: DateType
    base_currency: str
    income_cny: Decimal
    expense_cny: Decimal
    net_income_cny: Decimal
    expected_reimbursement_cny: Decimal
    approved_reimbursement_cny: Decimal
    received_reimbursement_cny: Decimal
    personal_net_expense_cny: Decimal
    future_inflow_cny: Decimal
    future_outflow_cny: Decimal
    future_net_cny: Decimal
    credit_liability_cny: Decimal

    @field_serializer(
        "income_cny",
        "expense_cny",
        "net_income_cny",
        "expected_reimbursement_cny",
        "approved_reimbursement_cny",
        "received_reimbursement_cny",
        "personal_net_expense_cny",
        "future_inflow_cny",
        "future_outflow_cny",
        "future_net_cny",
        "credit_liability_cny",
    )
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)


class CategoryExpenseRow(BaseModel):
    category_id: str
    category_name: str
    expense_cny: Decimal
    currencies: List[CurrencyAmountSummary]

    @field_serializer("expense_cny")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)


class CategoryExpenseReport(BaseModel):
    date_from: DateType
    date_to: DateType
    base_currency: str
    total_expense_cny: Decimal
    rows: List[CategoryExpenseRow]

    @field_serializer("total_expense_cny")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)


class CashFlowPressureWindow(BaseModel):
    days: int
    date_from: DateType
    date_to: DateType
    expected_inflow_cny: Decimal
    expected_outflow_cny: Decimal
    net_cny: Decimal
    item_count: int

    @field_serializer("expected_inflow_cny", "expected_outflow_cny", "net_cny")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)


class CashFlowPressureReport(BaseModel):
    anchor_date: DateType
    base_currency: str
    windows: List[CashFlowPressureWindow]


class CreditLiabilityTrendRow(BaseModel):
    cycle_id: str
    credit_account_id: str
    account_name: str
    statement_date: DateType
    due_date: DateType
    currency: str
    statement_amount: Decimal
    paid_amount: Decimal
    remaining_amount: Decimal
    remaining_cny: Decimal
    status: str

    @field_serializer("statement_amount", "paid_amount", "remaining_amount", "remaining_cny")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)


class CreditLiabilityTrendReport(BaseModel):
    date_from: DateType
    date_to: DateType
    base_currency: str
    total_remaining_cny: Decimal
    rows: List[CreditLiabilityTrendRow]

    @field_serializer("total_remaining_cny")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)


class ReimbursementStatusSummary(BaseModel):
    status: str
    amount_cny: Decimal
    claim_count: int

    @field_serializer("amount_cny")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)


class ReimbursementReport(BaseModel):
    date_from: DateType
    date_to: DateType
    view: str
    base_currency: str
    gross_reimbursable_expense_cny: Decimal
    expected_offset_cny: Decimal
    approved_offset_cny: Decimal
    received_offset_cny: Decimal
    pre_reimbursement_expense_cny: Decimal
    expected_net_expense_cny: Decimal
    approved_net_expense_cny: Decimal
    received_net_expense_cny: Decimal
    personal_net_expense_cny: Decimal
    selected_net_expense_cny: Decimal
    status_breakdown: List[ReimbursementStatusSummary]
    currencies: List[CurrencyAmountSummary]

    @field_serializer(
        "gross_reimbursable_expense_cny",
        "expected_offset_cny",
        "approved_offset_cny",
        "received_offset_cny",
        "pre_reimbursement_expense_cny",
        "expected_net_expense_cny",
        "approved_net_expense_cny",
        "received_net_expense_cny",
        "personal_net_expense_cny",
        "selected_net_expense_cny",
    )
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)


class SubscriptionReport(BaseModel):
    as_of: DateType
    base_currency: str
    active_subscription_count: int
    monthly_total_cny: Decimal
    annual_total_cny: Decimal
    upcoming_30_days_cny: Decimal
    currencies: List[CurrencyAmountSummary]

    @field_serializer("monthly_total_cny", "annual_total_cny", "upcoming_30_days_cny")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)


class ExportDataset(BaseModel):
    name: str
    filename: str


class ExportDatasetList(BaseModel):
    datasets: List[ExportDataset]
