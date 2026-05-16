from datetime import date as DateType
from decimal import Decimal, ROUND_HALF_UP
from typing import Iterable, List, Optional, Tuple

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.constants import BASE_CURRENCY
from app.models.account import Account
from app.models.category import Category
from app.models.currency_rate import CurrencyRate
from app.models.entry import AccountMovement, EntryCategoryLine, FinancialEntry
from app.schemas.entry import EntryCreate, EntryRead

MONEY_QUANT = Decimal("0.01")

SPENDING_MOVEMENT_TYPES = {"balance_out", "credit_charge"}
INCOME_MOVEMENT_TYPES = {"balance_in"}
TRANSFER_MOVEMENT_TYPES = {"transfer_in", "transfer_out", "credit_repayment"}
SUPPORTED_MOVEMENT_TYPES = SPENDING_MOVEMENT_TYPES | INCOME_MOVEMENT_TYPES | TRANSFER_MOVEMENT_TYPES


class LedgerError(Exception):
    pass


class LedgerNotFoundError(LedgerError):
    pass


class LedgerValidationError(LedgerError):
    pass


def create_entry(db: Session, payload: EntryCreate) -> EntryRead:
    entry = FinancialEntry(
        title=payload.title,
        entry_type=payload.entry_type,
        date=payload.date,
        start_date=payload.start_date,
        end_date=payload.end_date,
        status=payload.status,
        note=payload.note,
        created_by=payload.created_by,
    )
    db.add(entry)
    db.flush()

    lines = [
        _create_category_line(db, entry.id, payload.date, line)
        for line in payload.category_lines
    ]
    movements = [
        _create_account_movement(db, entry.id, payload.date, movement)
        for movement in payload.account_movements
    ]

    if entry.status == "confirmed":
        _validate_confirmable(entry, lines, movements)
        _apply_movements(db, movements, sign=Decimal("1"))

    db.commit()
    return get_entry(db, entry.id)


def list_entries(db: Session) -> List[EntryRead]:
    entries = db.execute(
        select(FinancialEntry).order_by(FinancialEntry.date.desc(), FinancialEntry.created_at.desc())
    ).scalars()
    return [get_entry(db, entry.id) for entry in entries]


def get_entry(db: Session, entry_id: str) -> EntryRead:
    entry = db.get(FinancialEntry, entry_id)
    if entry is None:
        raise LedgerNotFoundError("Entry not found")

    lines, movements = _load_entry_parts(db, entry_id)
    return EntryRead.from_models(entry, lines, movements)


def confirm_entry(db: Session, entry_id: str) -> EntryRead:
    entry = db.get(FinancialEntry, entry_id)
    if entry is None:
        raise LedgerNotFoundError("Entry not found")
    if entry.status == "confirmed":
        return get_entry(db, entry_id)
    if entry.status != "draft":
        raise LedgerValidationError("Only draft entries can be confirmed")

    lines, movements = _load_entry_parts(db, entry_id)
    _validate_confirmable(entry, lines, movements)
    _apply_movements(db, movements, sign=Decimal("1"))
    entry.status = "confirmed"

    db.commit()
    return get_entry(db, entry_id)


def void_entry(db: Session, entry_id: str) -> EntryRead:
    entry = db.get(FinancialEntry, entry_id)
    if entry is None:
        raise LedgerNotFoundError("Entry not found")
    if entry.status == "voided":
        return get_entry(db, entry_id)
    if entry.status not in {"draft", "confirmed"}:
        raise LedgerValidationError("Only draft or confirmed entries can be voided")

    lines, movements = _load_entry_parts(db, entry_id)
    if entry.status == "confirmed":
        _apply_movements(db, movements, sign=Decimal("-1"))
    entry.status = "voided"

    db.commit()
    return get_entry(db, entry_id)


def convert_to_cny(
    db: Session,
    amount: Decimal,
    currency: str,
    entry_date: DateType,
    exchange_rate_id: Optional[str] = None,
) -> Tuple[Decimal, Optional[str]]:
    normalized_currency = currency.upper()
    if normalized_currency == BASE_CURRENCY:
        return quantize_money(amount), None

    rate = _resolve_rate(db, normalized_currency, entry_date, exchange_rate_id)
    return quantize_money(amount * rate.rate), rate.id


def _create_category_line(db: Session, entry_id: str, entry_date: DateType, payload) -> EntryCategoryLine:
    category = db.get(Category, payload.category_id)
    if category is None:
        raise LedgerValidationError("Category not found")

    amount = quantize_money(payload.amount)
    if amount <= 0:
        raise LedgerValidationError("Category line amount must be greater than 0")

    converted_cny_amount, exchange_rate_id = _resolve_payload_conversion(
        db,
        amount,
        payload.currency,
        entry_date,
        payload.exchange_rate_id,
        payload.converted_cny_amount,
    )
    line = EntryCategoryLine(
        entry_id=entry_id,
        category_id=payload.category_id,
        direction=payload.direction,
        amount=amount,
        currency=payload.currency.upper(),
        exchange_rate_id=exchange_rate_id,
        converted_cny_amount=converted_cny_amount,
        reimbursable_flag=payload.reimbursable_flag,
        note=payload.note,
    )
    db.add(line)
    db.flush()
    return line


def _create_account_movement(
    db: Session,
    entry_id: str,
    entry_date: DateType,
    payload,
) -> AccountMovement:
    account = db.get(Account, payload.account_id)
    if account is None:
        raise LedgerValidationError("Account not found")
    if payload.movement_type not in SUPPORTED_MOVEMENT_TYPES:
        raise LedgerValidationError("Unsupported account movement type")

    amount = quantize_money(payload.amount)
    if amount <= 0:
        raise LedgerValidationError("Account movement amount must be greater than 0")

    converted_cny_amount, exchange_rate_id = _resolve_payload_conversion(
        db,
        amount,
        payload.currency,
        entry_date,
        payload.exchange_rate_id,
        payload.converted_cny_amount,
    )
    movement = AccountMovement(
        entry_id=entry_id,
        account_id=payload.account_id,
        statement_cycle_id=payload.statement_cycle_id,
        movement_type=payload.movement_type,
        amount=amount,
        currency=payload.currency.upper(),
        exchange_rate_id=exchange_rate_id,
        converted_cny_amount=converted_cny_amount,
        note=payload.note,
    )
    db.add(movement)
    db.flush()
    return movement


def _resolve_payload_conversion(
    db: Session,
    amount: Decimal,
    currency: str,
    entry_date: DateType,
    exchange_rate_id: Optional[str],
    converted_cny_amount: Optional[Decimal],
) -> Tuple[Decimal, Optional[str]]:
    if converted_cny_amount is not None:
        return quantize_money(converted_cny_amount), exchange_rate_id
    return convert_to_cny(db, amount, currency, entry_date, exchange_rate_id)


def _resolve_rate(
    db: Session,
    from_currency: str,
    entry_date: DateType,
    exchange_rate_id: Optional[str],
) -> CurrencyRate:
    if exchange_rate_id is not None:
        rate = db.get(CurrencyRate, exchange_rate_id)
        if rate is None:
            raise LedgerValidationError("Currency rate not found")
        return rate

    rate = db.execute(
        select(CurrencyRate)
        .where(
            CurrencyRate.from_currency == from_currency,
            CurrencyRate.to_currency == BASE_CURRENCY,
            CurrencyRate.date <= entry_date,
        )
        .order_by(CurrencyRate.date.desc())
        .limit(1)
    ).scalar_one_or_none()
    if rate is None:
        raise LedgerValidationError(f"No {from_currency}/{BASE_CURRENCY} rate is available")
    return rate


def _validate_confirmable(
    entry: FinancialEntry,
    lines: List[EntryCategoryLine],
    movements: List[AccountMovement],
) -> None:
    if not movements:
        raise LedgerValidationError("Confirmed entries must include account movements")

    if not lines and not _is_transfer_only(movements):
        raise LedgerValidationError("Confirmed non-transfer entries must include category lines")

    for line in lines:
        if line.amount <= 0:
            raise LedgerValidationError("Category line amount must be greater than 0")
    for movement in movements:
        if movement.amount <= 0:
            raise LedgerValidationError("Account movement amount must be greater than 0")

    expense_total = _sum_line_cny(lines, "expense")
    income_total = _sum_line_cny(lines, "income")
    spending_total = _sum_movement_cny(movements, SPENDING_MOVEMENT_TYPES)
    income_movement_total = _sum_movement_cny(movements, INCOME_MOVEMENT_TYPES)

    if expense_total != spending_total:
        raise LedgerValidationError("Expense category total must match spending movements")
    if income_total != income_movement_total:
        raise LedgerValidationError("Income category total must match income movements")

    if entry.start_date and entry.end_date and entry.start_date > entry.end_date:
        raise LedgerValidationError("Entry start date cannot be after end date")


def _apply_movements(db: Session, movements: Iterable[AccountMovement], sign: Decimal) -> None:
    for movement in movements:
        account = db.get(Account, movement.account_id)
        if account is None:
            raise LedgerValidationError("Account not found")

        signed_amount = movement.amount * sign
        if movement.movement_type in {"balance_in", "transfer_in"}:
            account.current_balance = quantize_money(account.current_balance + signed_amount)
        elif movement.movement_type in {"balance_out", "transfer_out"}:
            account.current_balance = quantize_money(account.current_balance - signed_amount)
        elif movement.movement_type == "credit_charge":
            account.current_liability = quantize_money(account.current_liability + signed_amount)
        elif movement.movement_type == "credit_repayment":
            account.current_liability = quantize_money(account.current_liability - signed_amount)
        else:
            raise LedgerValidationError("Unsupported account movement type")


def _load_entry_parts(
    db: Session,
    entry_id: str,
) -> Tuple[List[EntryCategoryLine], List[AccountMovement]]:
    lines = list(
        db.execute(
            select(EntryCategoryLine).where(EntryCategoryLine.entry_id == entry_id)
        ).scalars()
    )
    movements = list(
        db.execute(
            select(AccountMovement).where(AccountMovement.entry_id == entry_id)
        ).scalars()
    )
    return lines, movements


def _sum_line_cny(lines: Iterable[EntryCategoryLine], direction: str) -> Decimal:
    return quantize_money(
        sum(
            (
                line.converted_cny_amount or Decimal("0")
                for line in lines
                if line.direction == direction
            ),
            Decimal("0"),
        )
    )


def _sum_movement_cny(movements: Iterable[AccountMovement], movement_types: set) -> Decimal:
    return quantize_money(
        sum(
            (
                movement.converted_cny_amount or Decimal("0")
                for movement in movements
                if movement.movement_type in movement_types
            ),
            Decimal("0"),
        )
    )


def _is_transfer_only(movements: Iterable[AccountMovement]) -> bool:
    movement_types = {movement.movement_type for movement in movements}
    return bool(movement_types) and movement_types.issubset(TRANSFER_MOVEMENT_TYPES)


def quantize_money(value: Decimal) -> Decimal:
    return value.quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)
