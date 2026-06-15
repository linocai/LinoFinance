from datetime import date as DateType
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.report import (
    CashFlowPressureReport,
    CategoryExpenseReport,
    CreditLiabilityTrendReport,
    MonthlyOverviewReport,
    ReimbursementReport,
    SubscriptionReport,
)
from app.services import report
from app.services.ledger import LedgerValidationError

router = APIRouter()


@router.get("/monthly-overview", response_model=MonthlyOverviewReport)
def monthly_overview(
    date_from: Optional[DateType] = None,
    date_to: Optional[DateType] = None,
    db: Session = Depends(get_db),
) -> MonthlyOverviewReport:
    return _report_or_400(lambda: report.monthly_overview(db, date_from, date_to))


@router.get("/category-expenses", response_model=CategoryExpenseReport)
def category_expenses(
    date_from: Optional[DateType] = None,
    date_to: Optional[DateType] = None,
    db: Session = Depends(get_db),
) -> CategoryExpenseReport:
    return _report_or_400(lambda: report.category_expenses(db, date_from, date_to))


@router.get("/cash-flow-pressure", response_model=CashFlowPressureReport)
def cash_flow_pressure(
    anchor_date: Optional[DateType] = None,
    db: Session = Depends(get_db),
) -> CashFlowPressureReport:
    return _report_or_400(lambda: report.cash_flow_pressure(db, anchor_date))


@router.get("/credit-liability-trend", response_model=CreditLiabilityTrendReport)
def credit_liability_trend(
    date_from: Optional[DateType] = None,
    date_to: Optional[DateType] = None,
    db: Session = Depends(get_db),
) -> CreditLiabilityTrendReport:
    return _report_or_400(lambda: report.credit_liability_trend(db, date_from, date_to))


@router.get("/reimbursements", response_model=ReimbursementReport)
def reimbursement_report(
    date_from: Optional[DateType] = None,
    date_to: Optional[DateType] = None,
    # v2.1.0 P2: view collapsed to three values; a legacy value (e.g.
    # pre_reimbursement / approved_net) fails query validation with 422.
    view: str = Query(default="personal_net", pattern="^(expected_net|received_net|personal_net)$"),
    db: Session = Depends(get_db),
) -> ReimbursementReport:
    return _report_or_400(lambda: report.reimbursement_report(db, date_from, date_to, view))


@router.get("/subscriptions", response_model=SubscriptionReport)
def subscription_report(
    as_of: Optional[DateType] = None,
    db: Session = Depends(get_db),
) -> SubscriptionReport:
    return _report_or_400(lambda: report.subscription_report(db, as_of))


def _report_or_400(operation):
    try:
        return operation()
    except LedgerValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
