from decimal import Decimal
from typing import List

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.entry import AccountMovement, FinancialEntry
from app.models.installment import InstallmentPlan
from app.schemas.installment import InstallmentPlanCreate, InstallmentPlanRead
from app.services import ledger
from app.services.ledger import LedgerNotFoundError, LedgerValidationError, quantize_money
from app.services.schedule import add_months


def create_installment_plan(
    db: Session,
    payload: InstallmentPlanCreate,
    commit: bool = True,
) -> InstallmentPlanRead:
    entry = _get_confirmed_entry(db, payload.linked_entry_id)
    account = _get_credit_account(db, payload.credit_account_id)
    currency = payload.currency.upper()
    if account.currency != currency:
        raise LedgerValidationError("Installment currency must match credit account currency")
    _validate_linked_entry_credit_charge(db, entry.id, account.id, payload.total_amount, currency)

    total_due = quantize_money(payload.total_amount + payload.fee_amount + payload.interest_amount)
    payment_amount = quantize_money(payload.payment_amount or (total_due / payload.number_of_payments))
    end_date = add_months(payload.start_date, payload.number_of_payments - 1)

    plan = InstallmentPlan(
        linked_entry_id=entry.id,
        credit_account_id=account.id,
        total_amount=quantize_money(payload.total_amount),
        currency=currency,
        number_of_payments=payload.number_of_payments,
        payment_amount=payment_amount,
        fee_amount=quantize_money(payload.fee_amount),
        interest_amount=quantize_money(payload.interest_amount),
        start_date=payload.start_date,
        end_date=end_date,
        status=payload.status,
        note=payload.note,
    )
    db.add(plan)
    db.flush()

    if plan.status == "active":
        _generate_installment_cash_flows(db, plan, total_due)

    if commit:
        db.commit()
        db.refresh(plan)
    else:
        db.flush()
    return _read_plan(db, plan)


def list_installment_plans(db: Session) -> List[InstallmentPlanRead]:
    plans = db.execute(
        select(InstallmentPlan).order_by(InstallmentPlan.start_date.desc(), InstallmentPlan.created_at.desc())
    ).scalars()
    return [_read_plan(db, plan) for plan in plans]


def get_installment_plan(db: Session, plan_id: str) -> InstallmentPlanRead:
    plan = db.get(InstallmentPlan, plan_id)
    if plan is None:
        raise LedgerNotFoundError("Installment plan not found")
    return _read_plan(db, plan)


def cancel_installment_plan(db: Session, plan_id: str) -> InstallmentPlanRead:
    plan = _get_plan_or_raise(db, plan_id)
    if plan.status in {"paid_off", "early_paid_off", "cancelled"}:
        raise LedgerValidationError("Final installment plans cannot be cancelled")
    plan.status = "cancelled"
    _cancel_open_cash_flows(db, plan.id)
    db.commit()
    return get_installment_plan(db, plan_id)


def mark_installment_plan_paid_off(db: Session, plan_id: str, early: bool = False) -> InstallmentPlanRead:
    plan = _get_plan_or_raise(db, plan_id)
    if plan.status == "cancelled":
        raise LedgerValidationError("Cancelled installment plans cannot be paid off")
    plan.status = "early_paid_off" if early else "paid_off"
    _cancel_open_cash_flows(db, plan.id)
    db.commit()
    return get_installment_plan(db, plan_id)


def _generate_installment_cash_flows(db: Session, plan: InstallmentPlan, total_due: Decimal) -> None:
    generated_total = Decimal("0")
    for index in range(plan.number_of_payments):
        if index == plan.number_of_payments - 1:
            amount = quantize_money(total_due - generated_total)
        else:
            amount = plan.payment_amount
            generated_total = quantize_money(generated_total + amount)

        expected_date = add_months(plan.start_date, index)
        converted_cny_amount, exchange_rate_id = ledger.convert_to_cny(
            db,
            amount,
            plan.currency,
            expected_date,
        )
        item = CashFlowItem(
            title=f"Installment payment {index + 1}/{plan.number_of_payments}",
            direction="transfer",
            cash_flow_type="installment",
            amount=amount,
            currency=plan.currency,
            exchange_rate_id=exchange_rate_id,
            converted_cny_amount=converted_cny_amount,
            expected_date=expected_date,
            account_id=plan.credit_account_id,
            status="expected",
            linked_installment_plan_id=plan.id,
            note="Generated from installment plan.",
        )
        db.add(item)


def _cancel_open_cash_flows(db: Session, plan_id: str) -> None:
    items = db.execute(
        select(CashFlowItem).where(CashFlowItem.linked_installment_plan_id == plan_id)
    ).scalars()
    for item in items:
        if item.status in {"expected", "confirmed"}:
            item.status = "cancelled"


def _read_plan(db: Session, plan: InstallmentPlan) -> InstallmentPlanRead:
    count = db.execute(
        select(func.count(CashFlowItem.id)).where(CashFlowItem.linked_installment_plan_id == plan.id)
    ).scalar_one()
    return InstallmentPlanRead(
        id=plan.id,
        linked_entry_id=plan.linked_entry_id,
        credit_account_id=plan.credit_account_id,
        total_amount=plan.total_amount,
        currency=plan.currency,
        number_of_payments=plan.number_of_payments,
        payment_amount=plan.payment_amount,
        fee_amount=plan.fee_amount,
        interest_amount=plan.interest_amount,
        start_date=plan.start_date,
        end_date=plan.end_date,
        status=plan.status,
        generated_cash_flow_count=count,
        note=plan.note,
    )


def _get_confirmed_entry(db: Session, entry_id: str) -> FinancialEntry:
    entry = db.get(FinancialEntry, entry_id)
    if entry is None:
        raise LedgerValidationError("Linked entry not found")
    if entry.status != "confirmed":
        raise LedgerValidationError("Installment plans require a confirmed linked entry")
    return entry


def _get_credit_account(db: Session, account_id: str) -> Account:
    account = db.get(Account, account_id)
    if account is None:
        raise LedgerValidationError("Credit account not found")
    if account.type != "credit":
        raise LedgerValidationError("Installment plans require a credit account")
    return account


def _validate_linked_entry_credit_charge(
    db: Session,
    entry_id: str,
    account_id: str,
    amount: Decimal,
    currency: str,
) -> None:
    total = db.execute(
        select(func.coalesce(func.sum(AccountMovement.amount), 0)).where(
            AccountMovement.entry_id == entry_id,
            AccountMovement.account_id == account_id,
            AccountMovement.movement_type == "credit_charge",
            AccountMovement.currency == currency,
        )
    ).scalar_one()
    if quantize_money(total) < quantize_money(amount):
        raise LedgerValidationError("Linked entry must include matching credit charge")


def _get_plan_or_raise(db: Session, plan_id: str) -> InstallmentPlan:
    plan = db.get(InstallmentPlan, plan_id)
    if plan is None:
        raise LedgerNotFoundError("Installment plan not found")
    return plan
