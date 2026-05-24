from datetime import date as DateType
from decimal import Decimal
from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.category import Category
from app.models.credit_statement_cycle import CreditStatementCycle
from app.schemas.cash_flow import (
    CashFlowItemCreate,
    CashFlowItemRead,
    CashFlowItemUpdate,
    CashFlowSettle,
    CashFlowSettleRead,
)
from app.services import ledger
from app.services.ledger import LedgerNotFoundError, LedgerValidationError, quantize_money


def create_cash_flow_item(
    db: Session,
    payload: CashFlowItemCreate,
    commit: bool = True,
) -> CashFlowItemRead:
    item = _build_cash_flow_item(db, payload)
    db.add(item)
    if commit:
        db.commit()
        db.refresh(item)
    else:
        db.flush()
    return CashFlowItemRead.model_validate(item)


def list_cash_flow_items(
    db: Session,
    status: Optional[str] = None,
    date_from: Optional[DateType] = None,
    date_to: Optional[DateType] = None,
    include_cancelled: bool = False,
) -> List[CashFlowItemRead]:
    statement = select(CashFlowItem)
    if status is not None:
        # Explicit status filter wins; include_cancelled is ignored.
        statement = statement.where(CashFlowItem.status == status)
    elif not include_cancelled:
        statement = statement.where(CashFlowItem.status != "cancelled")
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
    return set_cash_flow_status(db, item_id, "confirmed")


def cancel_cash_flow_item(db: Session, item_id: str) -> CashFlowItemRead:
    return set_cash_flow_status(db, item_id, "cancelled")


def set_cash_flow_status(
    db: Session,
    item_id: str,
    status: str,
    commit: bool = True,
) -> CashFlowItemRead:
    item = _get_cash_flow_or_raise(db, item_id)
    if status not in {"expected", "confirmed", "cancelled"}:
        raise LedgerValidationError("Unsupported cash flow status")
    if item.status == status:
        # Idempotent no-op for any matching status (incl. cancelled→cancel).
        return CashFlowItemRead.model_validate(item)
    if item.status == "settled":
        raise LedgerValidationError("Settled cash flow items cannot be changed")
    if item.status == "cancelled":
        # Cancelled is terminal for non-cancel targets.
        raise LedgerValidationError("Cancelled cash flow items cannot be changed")
    if status == "confirmed" and item.status != "expected":
        raise LedgerValidationError("Only expected cash flow items can be confirmed")
    item.status = status
    if commit:
        db.commit()
        return get_cash_flow_item(db, item_id)
    db.flush()
    return CashFlowItemRead.model_validate(item)


def settle_cash_flow_item(
    db: Session,
    item_id: str,
    payload: CashFlowSettle,
) -> CashFlowSettleRead:
    item = _get_cash_flow_or_raise(db, item_id)
    if item.status in {"settled", "cancelled"}:
        raise LedgerValidationError("Only active cash flow items can be settled")
    _validate_settlement_payload(item, payload)

    entry_payload = payload.entry.model_copy(update={"status": "confirmed"})
    entry = ledger.create_entry(db, entry_payload, commit=False)
    item.status = "settled"
    item.linked_entry_id = entry.id
    if item.linked_subscription_rule_id is not None:
        from app.services.subscription import advance_subscription_after_settlement

        advance_subscription_after_settlement(db, item.linked_subscription_rule_id)
    db.commit()

    return CashFlowSettleRead(
        cash_flow_item=get_cash_flow_item(db, item_id),
        entry=ledger.get_entry(db, entry.id),
    )


def update_cash_flow_item(
    db: Session,
    item_id: str,
    payload: CashFlowItemUpdate,
) -> CashFlowItemRead:
    """Patch a cash flow item.

    Uses ``payload.model_fields_set`` as the sentinel to distinguish
    "field absent" (leave unchanged) from "field explicitly null"
    (clear the value, only meaningful for the optional foreign-key
    columns). ``settled`` and ``cancelled`` rows are immutable here —
    callers must go through the dedicated lifecycle endpoints.
    """

    item = _get_cash_flow_or_raise(db, item_id)
    if item.status in {"settled", "cancelled"}:
        raise LedgerValidationError(
            "Settled or cancelled cash flow items cannot be edited"
        )

    provided = payload.model_fields_set

    if "title" in provided:
        item.title = payload.title
    if "direction" in provided:
        item.direction = payload.direction
    if "cash_flow_type" in provided:
        item.cash_flow_type = payload.cash_flow_type
    if "expected_date" in provided:
        item.expected_date = payload.expected_date
    if "account_id" in provided:
        item.account_id = payload.account_id
    if "category_id" in provided:
        item.category_id = payload.category_id
    if "recurrence_rule" in provided:
        item.recurrence_rule = payload.recurrence_rule
    if "note" in provided:
        item.note = payload.note

    money_provided = bool(
        provided & {"amount", "currency", "exchange_rate_id", "converted_cny_amount"}
    )
    if money_provided:
        new_amount = (
            quantize_money(payload.amount) if "amount" in provided else item.amount
        )
        if "currency" in provided and payload.currency is not None:
            new_currency = payload.currency.upper()
        else:
            new_currency = item.currency
        new_rate_id = (
            payload.exchange_rate_id
            if "exchange_rate_id" in provided
            else item.exchange_rate_id
        )
        new_converted = (
            payload.converted_cny_amount
            if "converted_cny_amount" in provided
            else None
        )

        if new_currency != "CNY" and not new_rate_id:
            raise LedgerValidationError(
                "exchange_rate_id is required when currency is not CNY"
            )

        converted, resolved_rate_id = _resolve_payload_conversion(
            db,
            new_amount,
            new_currency,
            item.expected_date,
            new_rate_id,
            new_converted,
        )
        item.amount = new_amount
        item.currency = new_currency
        item.exchange_rate_id = resolved_rate_id
        item.converted_cny_amount = converted

    _validate_update_links(db, item)

    db.flush()
    db.commit()
    return get_cash_flow_item(db, item_id)


def _validate_update_links(db: Session, item: CashFlowItem) -> None:
    """Re-validate optional link columns against the post-mutation state."""

    if item.account_id is not None:
        account = db.get(Account, item.account_id)
        if account is None:
            raise LedgerValidationError("Account not found")
        if account.currency != item.currency:
            raise LedgerValidationError(
                "Cash flow currency must match linked account currency"
            )

    if item.category_id is not None and db.get(Category, item.category_id) is None:
        raise LedgerValidationError("Category not found")


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
        linked_subscription_rule_id=payload.linked_subscription_rule_id,
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
    expected_cny_amount, resolved_exchange_rate_id = ledger.convert_to_cny(
        db,
        amount,
        currency,
        expected_date,
        exchange_rate_id,
    )
    if converted_cny_amount is not None and quantize_money(converted_cny_amount) != expected_cny_amount:
        raise LedgerValidationError("converted_cny_amount does not match the exchange rate")
    return expected_cny_amount, resolved_exchange_rate_id


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


def _validate_settlement_payload(item: CashFlowItem, payload: CashFlowSettle) -> None:
    if item.direction == "inflow":
        _require_matching_line(item, payload, "income")
        _require_matching_movement(item, payload, {"balance_in"})
    elif item.direction == "outflow":
        _require_matching_line(item, payload, "expense")
        _require_matching_movement(item, payload, {"balance_out"})
    elif item.direction == "transfer":
        _require_matching_movement(item, payload, {"credit_repayment", "transfer_in", "transfer_out"})
        if payload.entry.category_lines:
            raise LedgerValidationError("Transfer cash flow settlement cannot include category lines")
    else:
        raise LedgerValidationError("Unsupported cash flow direction")


def _require_matching_line(item: CashFlowItem, payload: CashFlowSettle, direction: str) -> None:
    for line in payload.entry.category_lines:
        if line.direction != direction:
            continue
        if line.currency.upper() != item.currency:
            continue
        if quantize_money(line.amount) != item.amount:
            continue
        if item.category_id is not None and line.category_id != item.category_id:
            continue
        return
    raise LedgerValidationError("Settlement entry category lines must match the cash flow item")


def _require_matching_movement(
    item: CashFlowItem,
    payload: CashFlowSettle,
    movement_types: set[str],
) -> None:
    for movement in payload.entry.account_movements:
        if movement.movement_type not in movement_types:
            continue
        if movement.currency.upper() != item.currency:
            continue
        if quantize_money(movement.amount) != item.amount:
            continue
        if item.account_id is not None and movement.account_id != item.account_id:
            continue
        return
    raise LedgerValidationError("Settlement entry account movements must match the cash flow item")
