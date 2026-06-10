from collections import defaultdict
from datetime import date as DateType, timedelta
from decimal import Decimal
from typing import Dict, Iterable, List, Optional, Tuple

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.constants import BASE_CURRENCY
from app.core.timeutils import app_today
from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.category import Category
from app.models.credit_statement_cycle import CreditStatementCycle
from app.models.entry import EntryCategoryLine, FinancialEntry
from app.models.reimbursement import ReimbursementClaim
from app.models.subscription import SubscriptionRule
from app.schemas.report import (
    CashFlowDailyNetRow,
    CashFlowPressureReport,
    CashFlowPressureWindow,
    CategoryExpenseReport,
    CategoryExpenseRow,
    CreditLiabilityTrendReport,
    CreditLiabilityTrendRow,
    CurrencyAmountSummary,
    MonthlyOverviewReport,
    ReimbursementReport,
    ReimbursementStatusSummary,
    SubscriptionReport,
)
from app.services.ledger import LedgerValidationError, convert_to_cny, quantize_money


ACTIVE_CASH_FLOW_STATUSES = {"expected", "confirmed", "partial"}
EXPECTED_REIMBURSEMENT_STATUSES = {
    "reimbursable",
    "invoice_pending",
    "submitted",
    "approved",
    "waiting_received",
    "received",
    "partial_received",
}
APPROVED_REIMBURSEMENT_STATUSES = {"approved", "waiting_received", "received", "partial_received"}
RECEIVED_REIMBURSEMENT_STATUSES = {"received", "partial_received"}
REIMBURSEMENT_REPORT_VIEWS = {
    "pre_reimbursement",
    "expected_net",
    "approved_net",
    "received_net",
    "personal_net",
}


def monthly_overview(
    db: Session,
    date_from: Optional[DateType],
    date_to: Optional[DateType],
) -> MonthlyOverviewReport:
    start, end = _date_range(date_from, date_to)
    income_cny, expense_cny = _entry_income_expense_totals(db, start, end)
    expected, approved, received = _reimbursement_offsets(db, start, end)
    future_inflow, future_outflow, _ = _cash_flow_totals(db, start, end)
    credit_liability = _credit_liability_total(db, end)

    return MonthlyOverviewReport(
        date_from=start,
        date_to=end,
        base_currency=BASE_CURRENCY,
        income_cny=income_cny,
        expense_cny=expense_cny,
        net_income_cny=quantize_money(income_cny - expense_cny),
        expected_reimbursement_cny=expected,
        approved_reimbursement_cny=approved,
        received_reimbursement_cny=received,
        personal_net_expense_cny=quantize_money(expense_cny - expected),
        future_inflow_cny=future_inflow,
        future_outflow_cny=future_outflow,
        future_net_cny=quantize_money(future_inflow - future_outflow),
        credit_liability_cny=credit_liability,
    )


def category_expenses(
    db: Session,
    date_from: Optional[DateType],
    date_to: Optional[DateType],
) -> CategoryExpenseReport:
    start, end = _date_range(date_from, date_to)
    rows_by_category: Dict[str, dict] = {}

    statement = (
        select(EntryCategoryLine, Category)
        .join(FinancialEntry, EntryCategoryLine.entry_id == FinancialEntry.id)
        .join(Category, EntryCategoryLine.category_id == Category.id)
        .where(
            FinancialEntry.status == "confirmed",
            FinancialEntry.date >= start,
            FinancialEntry.date <= end,
            EntryCategoryLine.direction == "expense",
        )
    )
    for line, category in db.execute(statement):
        converted = quantize_money(line.converted_cny_amount or Decimal("0"))
        category_row = rows_by_category.setdefault(
            category.id,
            {
                "category_name": category.name,
                "expense_cny": Decimal("0"),
                "currencies": defaultdict(lambda: [Decimal("0"), Decimal("0")]),
            },
        )
        category_row["expense_cny"] = quantize_money(category_row["expense_cny"] + converted)
        currency_totals = category_row["currencies"][line.currency]
        currency_totals[0] = quantize_money(currency_totals[0] + line.amount)
        currency_totals[1] = quantize_money(currency_totals[1] + converted)

    rows = [
        CategoryExpenseRow(
            category_id=category_id,
            category_name=row["category_name"],
            expense_cny=row["expense_cny"],
            currencies=_currency_summaries(row["currencies"]),
        )
        for category_id, row in rows_by_category.items()
    ]
    rows.sort(key=lambda item: item.expense_cny, reverse=True)
    total = quantize_money(sum((row.expense_cny for row in rows), Decimal("0")))
    return CategoryExpenseReport(
        date_from=start,
        date_to=end,
        base_currency=BASE_CURRENCY,
        total_expense_cny=total,
        rows=rows,
    )


def cash_flow_pressure(
    db: Session,
    anchor_date: Optional[DateType],
) -> CashFlowPressureReport:
    anchor = anchor_date or app_today()
    windows = []
    for days in (7, 30, 90):
        end = anchor + timedelta(days=days)
        inflow, outflow, count = _cash_flow_totals(db, anchor, end)
        windows.append(
            CashFlowPressureWindow(
                days=days,
                date_from=anchor,
                date_to=end,
                expected_inflow_cny=inflow,
                expected_outflow_cny=outflow,
                net_cny=quantize_money(inflow - outflow),
                item_count=count,
            )
        )
    return CashFlowPressureReport(
        anchor_date=anchor,
        base_currency=BASE_CURRENCY,
        windows=windows,
        daily_net_cny=daily_net_window(db, anchor, 30),
    )


def daily_net_window(
    db: Session,
    anchor_date: Optional[DateType],
    days: int = 30,
) -> List[CashFlowDailyNetRow]:
    anchor = anchor_date or app_today()
    rows = [
        CashFlowDailyNetRow(
            date=anchor + timedelta(days=offset),
            inflow_cny=Decimal("0"),
            outflow_cny=Decimal("0"),
            net_cny=Decimal("0"),
        )
        for offset in range(days)
    ]
    rows_by_date = {row.date: row for row in rows}
    statement = select(CashFlowItem).where(
        CashFlowItem.status.in_(ACTIVE_CASH_FLOW_STATUSES),
        CashFlowItem.expected_date >= anchor,
        CashFlowItem.expected_date < anchor + timedelta(days=days),
    )
    for item in db.execute(statement).scalars():
        row = rows_by_date.get(item.expected_date)
        if row is None:
            continue
        amount = quantize_money(item.converted_cny_amount or Decimal("0"))
        if item.direction == "inflow":
            row.inflow_cny = quantize_money(row.inflow_cny + amount)
        elif item.direction in {"outflow", "transfer"}:
            row.outflow_cny = quantize_money(row.outflow_cny + amount)
        row.net_cny = quantize_money(row.inflow_cny - row.outflow_cny)
    return rows


def credit_liability_trend(
    db: Session,
    date_from: Optional[DateType],
    date_to: Optional[DateType],
) -> CreditLiabilityTrendReport:
    start, end = _date_range(date_from, date_to)
    statement = (
        select(CreditStatementCycle, Account)
        .join(Account, CreditStatementCycle.credit_account_id == Account.id)
        .where(
            CreditStatementCycle.statement_date >= start,
            CreditStatementCycle.statement_date <= end,
        )
        .order_by(CreditStatementCycle.statement_date.asc())
    )
    rows = []
    for cycle, account in db.execute(statement):
        remaining = quantize_money(cycle.statement_amount - cycle.paid_amount)
        remaining_cny, _ = convert_to_cny(db, remaining, cycle.currency, cycle.statement_date)
        rows.append(
            CreditLiabilityTrendRow(
                cycle_id=cycle.id,
                credit_account_id=cycle.credit_account_id,
                account_name=account.name,
                statement_date=cycle.statement_date,
                due_date=cycle.due_date,
                currency=cycle.currency,
                statement_amount=cycle.statement_amount,
                paid_amount=cycle.paid_amount,
                remaining_amount=remaining,
                remaining_cny=remaining_cny,
                status=cycle.status,
            )
        )
    total = quantize_money(sum((row.remaining_cny for row in rows), Decimal("0")))
    return CreditLiabilityTrendReport(
        date_from=start,
        date_to=end,
        base_currency=BASE_CURRENCY,
        total_remaining_cny=total,
        rows=rows,
    )


def reimbursement_report(
    db: Session,
    date_from: Optional[DateType],
    date_to: Optional[DateType],
    view: str,
) -> ReimbursementReport:
    if view not in REIMBURSEMENT_REPORT_VIEWS:
        raise LedgerValidationError("Unsupported reimbursement report view")
    start, end = _date_range(date_from, date_to)
    claims = list(db.execute(select(ReimbursementClaim)).scalars())
    gross = Decimal("0")
    expected = Decimal("0")
    approved = Decimal("0")
    received = Decimal("0")
    status_totals: Dict[str, Tuple[Decimal, int]] = defaultdict(lambda: (Decimal("0"), 0))
    currency_totals: Dict[str, List[Decimal]] = defaultdict(lambda: [Decimal("0"), Decimal("0")])

    for claim in claims:
        amount_cny = quantize_money(claim.converted_cny_amount or Decimal("0"))
        original_date = _claim_original_entry_date(db, claim)
        received_date = _claim_received_date(db, claim)
        original_in_range = original_date is not None and start <= original_date <= end
        received_in_range = received_date is not None and start <= received_date <= end
        if not original_in_range and not received_in_range:
            continue

        if original_in_range and claim.status != "abandoned":
            gross = quantize_money(gross + amount_cny)
            currency_totals[claim.currency][0] = quantize_money(
                currency_totals[claim.currency][0] + claim.amount
            )
            currency_totals[claim.currency][1] = quantize_money(
                currency_totals[claim.currency][1] + amount_cny
            )
        if original_in_range and claim.status in EXPECTED_REIMBURSEMENT_STATUSES:
            expected = quantize_money(expected + amount_cny)
        if original_in_range and claim.status in APPROVED_REIMBURSEMENT_STATUSES:
            approved = quantize_money(approved + amount_cny)
        if received_in_range and claim.status in RECEIVED_REIMBURSEMENT_STATUSES:
            received = quantize_money(received + amount_cny)
        status_amount, status_count = status_totals[claim.status]
        status_totals[claim.status] = (
            quantize_money(status_amount + amount_cny),
            status_count + 1,
        )

    pre_reimbursement = gross
    expected_net = quantize_money(gross - expected)
    approved_net = quantize_money(gross - approved)
    received_net = quantize_money(gross - received)
    personal_net = expected_net
    selected = {
        "pre_reimbursement": pre_reimbursement,
        "expected_net": expected_net,
        "approved_net": approved_net,
        "received_net": received_net,
        "personal_net": personal_net,
    }[view]

    return ReimbursementReport(
        date_from=start,
        date_to=end,
        view=view,
        base_currency=BASE_CURRENCY,
        gross_reimbursable_expense_cny=gross,
        expected_offset_cny=expected,
        approved_offset_cny=approved,
        received_offset_cny=received,
        pre_reimbursement_expense_cny=pre_reimbursement,
        expected_net_expense_cny=expected_net,
        approved_net_expense_cny=approved_net,
        received_net_expense_cny=received_net,
        personal_net_expense_cny=personal_net,
        selected_net_expense_cny=selected,
        status_breakdown=[
            ReimbursementStatusSummary(status=status, amount_cny=amount, claim_count=count)
            for status, (amount, count) in sorted(status_totals.items())
        ],
        currencies=_currency_summaries(currency_totals),
    )


def subscription_report(db: Session, as_of: Optional[DateType]) -> SubscriptionReport:
    effective_date = as_of or app_today()
    rules = list(
        db.execute(
            select(SubscriptionRule)
            .where(
                SubscriptionRule.status == "active",
                SubscriptionRule.start_date <= effective_date,
            )
            .order_by(SubscriptionRule.next_charge_date.asc(), SubscriptionRule.created_at.asc())
        ).scalars()
    )
    monthly_total = Decimal("0")
    annual_total = Decimal("0")
    currency_totals: Dict[str, List[Decimal]] = defaultdict(lambda: [Decimal("0"), Decimal("0")])

    active_rules = []
    for rule in rules:
        if rule.end_date is not None and rule.end_date < effective_date:
            continue
        active_rules.append(rule)
        monthly_amount = _monthly_equivalent(rule.amount, rule.billing_interval)
        annual_amount = _annual_equivalent(rule.amount, rule.billing_interval)
        monthly_cny, _ = convert_to_cny(db, monthly_amount, rule.currency, rule.next_charge_date)
        annual_cny, _ = convert_to_cny(db, annual_amount, rule.currency, rule.next_charge_date)
        monthly_total = quantize_money(monthly_total + monthly_cny)
        annual_total = quantize_money(annual_total + annual_cny)
        currency_totals[rule.currency][0] = quantize_money(
            currency_totals[rule.currency][0] + monthly_amount
        )
        currency_totals[rule.currency][1] = quantize_money(
            currency_totals[rule.currency][1] + monthly_cny
        )

    upcoming_inflow, upcoming_outflow, _ = _cash_flow_totals(
        db,
        effective_date,
        effective_date + timedelta(days=30),
        cash_flow_type="subscription",
    )
    return SubscriptionReport(
        as_of=effective_date,
        base_currency=BASE_CURRENCY,
        active_subscription_count=len(active_rules),
        monthly_total_cny=monthly_total,
        annual_total_cny=annual_total,
        upcoming_30_days_cny=quantize_money(upcoming_outflow - upcoming_inflow),
        currencies=_currency_summaries(currency_totals),
    )


def _date_range(
    date_from: Optional[DateType],
    date_to: Optional[DateType],
) -> Tuple[DateType, DateType]:
    today = app_today()
    start = date_from or DateType(today.year, today.month, 1)
    end = date_to or today
    if start > end:
        raise LedgerValidationError("date_from cannot be after date_to")
    return start, end


def _entry_income_expense_totals(
    db: Session,
    start: DateType,
    end: DateType,
) -> Tuple[Decimal, Decimal]:
    income = Decimal("0")
    expense = Decimal("0")
    statement = (
        select(EntryCategoryLine)
        .join(FinancialEntry, EntryCategoryLine.entry_id == FinancialEntry.id)
        .where(
            FinancialEntry.status == "confirmed",
            FinancialEntry.date >= start,
            FinancialEntry.date <= end,
        )
    )
    for line in db.execute(statement).scalars():
        amount = quantize_money(line.converted_cny_amount or Decimal("0"))
        if line.direction == "income":
            income = quantize_money(income + amount)
        elif line.direction == "expense":
            expense = quantize_money(expense + amount)
    return income, expense


def _cash_flow_totals(
    db: Session,
    start: DateType,
    end: DateType,
    cash_flow_type: Optional[str] = None,
) -> Tuple[Decimal, Decimal, int]:
    statement = select(CashFlowItem).where(
        CashFlowItem.status.in_(ACTIVE_CASH_FLOW_STATUSES),
        CashFlowItem.expected_date >= start,
        CashFlowItem.expected_date <= end,
    )
    if cash_flow_type is not None:
        statement = statement.where(CashFlowItem.cash_flow_type == cash_flow_type)
    inflow = Decimal("0")
    outflow = Decimal("0")
    count = 0
    for item in db.execute(statement).scalars():
        count += 1
        amount = quantize_money(item.converted_cny_amount or Decimal("0"))
        if item.direction == "inflow":
            inflow = quantize_money(inflow + amount)
        elif item.direction in {"outflow", "transfer"}:
            outflow = quantize_money(outflow + amount)
    return inflow, outflow, count


def _reimbursement_offsets(
    db: Session,
    start: DateType,
    end: DateType,
) -> Tuple[Decimal, Decimal, Decimal]:
    expected = Decimal("0")
    approved = Decimal("0")
    received = Decimal("0")
    claims = db.execute(
        select(ReimbursementClaim)
    ).scalars()
    for claim in claims:
        amount = quantize_money(claim.converted_cny_amount or Decimal("0"))
        original_date = _claim_original_entry_date(db, claim)
        received_date = _claim_received_date(db, claim)
        original_in_range = original_date is not None and start <= original_date <= end
        received_in_range = received_date is not None and start <= received_date <= end
        if original_in_range and claim.status in EXPECTED_REIMBURSEMENT_STATUSES:
            expected = quantize_money(expected + amount)
        if original_in_range and claim.status in APPROVED_REIMBURSEMENT_STATUSES:
            approved = quantize_money(approved + amount)
        if received_in_range and claim.status in RECEIVED_REIMBURSEMENT_STATUSES:
            received = quantize_money(received + amount)
    return expected, approved, received


def _claim_original_entry_date(db: Session, claim: ReimbursementClaim) -> Optional[DateType]:
    entry = db.get(FinancialEntry, claim.linked_entry_id)
    return None if entry is None else entry.date


def _claim_received_date(db: Session, claim: ReimbursementClaim) -> Optional[DateType]:
    if claim.actual_received_date is not None:
        return claim.actual_received_date
    if claim.received_entry_id is None:
        return None
    entry = db.get(FinancialEntry, claim.received_entry_id)
    return None if entry is None else entry.date


def _credit_liability_total(db: Session, effective_date: DateType) -> Decimal:
    total = Decimal("0")
    accounts = db.execute(
        select(Account).where(Account.type == "credit", Account.status == "active")
    ).scalars()
    for account in accounts:
        amount, _ = convert_to_cny(db, account.current_liability, account.currency, effective_date)
        total = quantize_money(total + amount)
    return total


def _currency_summaries(currency_totals: Dict[str, Iterable[Decimal]]) -> List[CurrencyAmountSummary]:
    summaries = [
        CurrencyAmountSummary(
            currency=currency,
            amount=quantize_money(values[0]),
            converted_cny_amount=quantize_money(values[1]),
        )
        for currency, values in currency_totals.items()
    ]
    summaries.sort(key=lambda item: item.currency)
    return summaries


def _monthly_equivalent(amount: Decimal, interval: str) -> Decimal:
    if interval == "weekly":
        return quantize_money(amount * Decimal("52") / Decimal("12"))
    if interval == "monthly":
        return quantize_money(amount)
    if interval == "yearly":
        return quantize_money(amount / Decimal("12"))
    raise LedgerValidationError("Unsupported subscription interval")


def _annual_equivalent(amount: Decimal, interval: str) -> Decimal:
    if interval == "weekly":
        return quantize_money(amount * Decimal("52"))
    if interval == "monthly":
        return quantize_money(amount * Decimal("12"))
    if interval == "yearly":
        return quantize_money(amount)
    raise LedgerValidationError("Unsupported subscription interval")
