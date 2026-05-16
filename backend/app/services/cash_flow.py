from datetime import date as DateType
from decimal import Decimal
from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.category import Category
from app.models.credit_statement_cycle import CreditStatementCycle
from app.schemas.cash_flow import CashFlowItemCreate, CashFlowItemRead, CashFlowSettle, CashFlowSettleRead
from app.services import ledger
from app.services.ledger import LedgerNotFoundError, LedgerValidationError, quantize_money


def create_cash_flow_item(db: Session, payload: CashFlowItemCreate) -> CashFlowItemRead:
    item = _build_cash_flow_item(db, payload)
    db.add(item)
    db.commit()
    db.refresh(item)
    return CashFlowItemRead.model_validate(item)


def list_cash_flow_items(
    db: Session,
    status: Optional[str] = None,
    date_from: Optional[DateType] = None,
    date_to: Optional[DateType] = None,
) -> List[CashFlowItemRead]:
    statement = select(CashFlowItem)
    if status is not None:
        statement = statement.where(CashFlowItem.status == status)
    if date_from is not None:
        statement = statement.where(CashFlowItem.expected_date >= date_from)
    if date_to is not None:
        statement = statement.where(CashFlowItem.expected_date <= date_to)

    items = db.execute(
        statement.order_by(CashFlowItem.expected_date.asc(), CashFlowItem.created_at.asc())
    ).scalars()
    return [CashFlowItemRead.model_validate(item) for item in items]


def get_cash_flow_item(db: Session, item_id: str) -> CashFlowItemRead:
    item = db.get(CashFlowItem, item_id)
    if item is None:
        raise LedgerNotFoundError("Cash flow item not found")
    return CashFlowItemRead.model_validate(item)


def confirm_cash_flow_item(db: Session, item_id: str) -> CashFlowItemRead:
    item = _get_cash_flow_or_raise(db, item_id)
    if item.status == "expected":
        item.status = "confirmed"
    elif item.status != "confirmed":
        raise LedgerValidationError("Only expected cash flow items can be confirmed")
    db.commit()
    return get_cash_flow_item(db, item_id)


def cancel_cash_flow_item(db: Session, item_id: str) -> CashFlowItemRead:
    item = _get_cash_flow_or_raise(db, item_id)
    if item.status in {"settled", "cancelled"}:
        raise LedgerValidationError("Settled or cancelled cash flow items cannot be cancelled")
    item.status = "cancelled"
    db.commit()
    return get_cash_flow_item(db, item_id)


def settle_cash_flow_item(
    db: Session,
    item_id: str,
    payload: CashFlowSettle,
) -> CashFlowSettleRead:
    item = _get_cash_flow_or_raise(db, item_id)
    if item.status in {"settled", "cancelled"}:
        raise LedgerValidationError("Only active cash flow items can be settled")

    entry_payload = payload.entry.model_copy(update={"status": "confirmed"})
    entry = ledger.create_entry(db, entry_payload, commit=False)
    item.status = "settled"
    item.linked_entry_id = entry.id
    db.commit()

    return CashFlowSettleRead(
        cash_flow_item=get_cash_flow_item(db, item_id),
        entry=ledger.get_entry(db, entry.id),
    )


def _build_cash_flow_item(db: Session, payload: CashFlowItemCreate) -> CashFlowItem:
    amount = quantize_money(payload.amount)
    converted_cny_amount, exchange_rate_id = _resolve_payload_conversion(
        db,
        amount,
        payload.currency,
        payload.expected_date,
        payload.exchange_rate_id,
        payload.converted_cny_amount,
    )
    _validate_optional_links(db, payload)

    return CashFlowItem(
        title=payload.title,
        direction=payload.direction,
        cash_flow_type=payload.cash_flow_type,
        amount=amount,
        currency=payload.currency.upper(),
        exchange_rate_id=exchange_rate_id,
        converted_cny_amount=converted_cny_amount,
        expected_date=payload.expected_date,
        account_id=payload.account_id,
        category_id=payload.category_id,
        recurrence_rule=payload.recurrence_rule,
        status=payload.status,
        linked_reimbursement_id=payload.linked_reimbursement_id,
        linked_installment_plan_id=payload.linked_installment_plan_id,
        linked_statement_cycle_id=payload.linked_statement_cycle_id,
        note=payload.note,
    )


def _resolve_payload_conversion(
    db: Session,
    amount: Decimal,
    currency: str,
    expected_date: DateType,
    exchange_rate_id: Optional[str],
    converted_cny_amount: Optional[Decimal],
) -> tuple:
    if converted_cny_amount is not None:
        return quantize_money(converted_cny_amount), exchange_rate_id
    return ledger.convert_to_cny(db, amount, currency, expected_date, exchange_rate_id)


def _validate_optional_links(db: Session, payload: CashFlowItemCreate) -> None:
    if payload.account_id is not None:
        account = db.get(Account, payload.account_id)
        if account is None:
            raise LedgerValidationError("Account not found")
        if account.currency != payload.currency.upper():
            raise LedgerValidationError("Cash flow currency must match linked account currency")

    if payload.category_id is not None and db.get(Category, payload.category_id) is None:
        raise LedgerValidationError("Category not found")

    if payload.linked_statement_cycle_id is not None:
        cycle = db.get(CreditStatementCycle, payload.linked_statement_cycle_id)
        if cycle is None:
            raise LedgerValidationError("Credit statement cycle not found")


def _get_cash_flow_or_raise(db: Session, item_id: str) -> CashFlowItem:
    item = db.get(CashFlowItem, item_id)
    if item is None:
        raise LedgerNotFoundError("Cash flow item not found")
    return item


