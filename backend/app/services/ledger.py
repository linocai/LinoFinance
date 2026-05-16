from datetime import date as DateType
from decimal import Decimal, ROUND_HALF_UP
from typing import Iterable, List, Optional, Tuple

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.constants import BASE_CURRENCY, SUPPORTED_CURRENCIES
from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.category import Category
from app.models.credit_statement_cycle import CreditStatementCycle
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


def create_entry(db: Session, payload: EntryCreate, commit: bool = True) -> EntryRead:
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
        _create_reimbursement_claims_for_entry(db, entry, lines)

    if commit:
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
    _create_reimbursement_claims_for_entry(db, entry, lines)

    db.commit()
    return get_entry(db, entry_id)


def void_entry(db: Session, entry_id: str, commit: bool = True) -> EntryRead:
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
        _abandon_reimbursement_claims_for_entry(db, entry.id)
    entry.status = "voided"

    if commit:
        db.commit()
    return get_entry(db, entry_id)


def sync_credit_statement_cash_flow(db: Session, cycle: CreditStatementCycle) -> None:
    remaining_amount = quantize_money(cycle.statement_amount - cycle.paid_amount)
    existing = _get_statement_cash_flow(db, cycle.linked_cash_flow_item_id)

    if remaining_amount <= 0:
        if existing is not None:
            existing.amount = Decimal("0")
            existing.converted_cny_amount = Decimal("0")
            existing.status = "settled"
        return

    converted_cny_amount, exchange_rate_id = convert_to_cny(
        db,
        remaining_amount,
        cycle.currency,
        cycle.due_date,
    )
    status = "confirmed" if cycle.status != "open" else "expected"

    if existing is not None:
        existing.title = f"{cycle.currency} credit card repayment"
        existing.direction = "transfer"
        existing.cash_flow_type = "credit_repayment"
        existing.amount = remaining_amount
        existing.currency = cycle.currency
        existing.exchange_rate_id = exchange_rate_id
        existing.converted_cny_amount = converted_cny_amount
        existing.expected_date = cycle.due_date
        existing.account_id = cycle.credit_account_id
        existing.category_id = None
        existing.status = status
        existing.linked_statement_cycle_id = cycle.id
        return

    item = CashFlowItem(
        title=f"{cycle.currency} credit card repayment",
        direction="transfer",
        cash_flow_type="credit_repayment",
        amount=remaining_amount,
        currency=cycle.currency,
        exchange_rate_id=exchange_rate_id,
        converted_cny_amount=converted_cny_amount,
        expected_date=cycle.due_date,
        account_id=cycle.credit_account_id,
        category_id=None,
        recurrence_rule=None,
        status=status,
        linked_statement_cycle_id=cycle.id,
        note="Generated from credit statement cycle.",
    )
    db.add(item)
    db.flush()
    cycle.linked_cash_flow_item_id = item.id


def convert_to_cny(
    db: Session,
    amount: Decimal,
    currency: str,
    entry_date: DateType,
    exchange_rate_id: Optional[str] = None,
) -> Tuple[Decimal, Optional[str]]:
    normalized_currency = normalize_currency(currency)
    if normalized_currency == BASE_CURRENCY:
        if exchange_rate_id is not None:
            raise LedgerValidationError("CNY amounts cannot use an exchange rate")
        return quantize_money(amount), None

    rate = _resolve_rate(db, normalized_currency, entry_date, exchange_rate_id)
    return quantize_money(amount * rate.rate), rate.id


def normalize_currency(currency: str) -> str:
    normalized_currency = currency.upper()
    if normalized_currency not in SUPPORTED_CURRENCIES:
        raise LedgerValidationError("Unsupported currency for V1")
    return normalized_currency


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
        reimbursement_payer=payload.reimbursement_payer,
        reimbursement_expected_date=payload.reimbursement_expected_date,
        reimbursement_status=payload.reimbursement_status,
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
    if payload.currency.upper() != account.currency:
        raise LedgerValidationError("Account movement currency must match account currency")

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
    statement_cycle = _resolve_statement_cycle_for_movement(
        db,
        account,
        payload.movement_type,
        entry_date,
        payload.statement_cycle_id,
    )

    movement = AccountMovement(
        entry_id=entry_id,
        account_id=payload.account_id,
        statement_cycle_id=statement_cycle.id if statement_cycle is not None else None,
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
    expected_cny_amount, resolved_exchange_rate_id = convert_to_cny(
        db,
        amount,
        currency,
        entry_date,
        exchange_rate_id,
    )
    if converted_cny_amount is not None and quantize_money(converted_cny_amount) != expected_cny_amount:
        raise LedgerValidationError("converted_cny_amount does not match the exchange rate")
    return expected_cny_amount, resolved_exchange_rate_id


def _resolve_statement_cycle_for_movement(
    db: Session,
    account: Account,
    movement_type: str,
    entry_date: DateType,
    statement_cycle_id: Optional[str],
) -> Optional[CreditStatementCycle]:
    _validate_movement_account_type(account, movement_type)

    if movement_type not in {"credit_charge", "credit_repayment"}:
        if statement_cycle_id is not None:
            raise LedgerValidationError("Only credit movements can link to statement cycles")
        return None

    if movement_type == "credit_charge" and statement_cycle_id is None:
        statement_cycle = db.execute(
            select(CreditStatementCycle)
            .where(
                CreditStatementCycle.credit_account_id == account.id,
                CreditStatementCycle.cycle_start_date <= entry_date,
                CreditStatementCycle.cycle_end_date >= entry_date,
            )
            .order_by(CreditStatementCycle.cycle_start_date.desc())
            .limit(1)
        ).scalar_one_or_none()
        if statement_cycle is None:
            raise LedgerValidationError("Credit charge requires a matching statement cycle")
    elif statement_cycle_id is None:
        raise LedgerValidationError("Credit repayment requires a statement cycle")
    else:
        statement_cycle = db.get(CreditStatementCycle, statement_cycle_id)
        if statement_cycle is None:
            raise LedgerValidationError("Credit statement cycle not found")

    if statement_cycle.credit_account_id != account.id:
        raise LedgerValidationError("Statement cycle must belong to the credit account")
    if statement_cycle.currency != account.currency:
        raise LedgerValidationError("Statement cycle currency must match credit account currency")
    if movement_type == "credit_charge" and not (
        statement_cycle.cycle_start_date <= entry_date <= statement_cycle.cycle_end_date
    ):
        raise LedgerValidationError("Credit charge date must fall inside the statement cycle")
    return statement_cycle


def _validate_movement_account_type(account: Account, movement_type: str) -> None:
    if movement_type in {"credit_charge", "credit_repayment"} and account.type != "credit":
        raise LedgerValidationError("Credit movements require a credit account")
    if movement_type in {"balance_in", "balance_out", "transfer_in", "transfer_out"} and account.type != "balance":
        raise LedgerValidationError("Balance movements require a balance account")


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
        if rate.from_currency != from_currency or rate.to_currency != BASE_CURRENCY:
            raise LedgerValidationError("Currency rate does not match the requested currency pair")
        if rate.date > entry_date:
            raise LedgerValidationError("Currency rate cannot be dated after the entry date")
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
        if line.reimbursable_flag and line.reimbursement_expected_date is None:
            raise LedgerValidationError("Reimbursable lines require reimbursement_expected_date")
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
            _apply_statement_cycle_movement(db, movement, sign)
        elif movement.movement_type == "credit_repayment":
            account.current_liability = quantize_money(account.current_liability - signed_amount)
            _apply_statement_cycle_movement(db, movement, sign)
        else:
            raise LedgerValidationError("Unsupported account movement type")


def _apply_statement_cycle_movement(
    db: Session,
    movement: AccountMovement,
    sign: Decimal,
) -> None:
    if movement.statement_cycle_id is None:
        raise LedgerValidationError("Credit movement requires a statement cycle")

    cycle = db.get(CreditStatementCycle, movement.statement_cycle_id)
    if cycle is None:
        raise LedgerValidationError("Credit statement cycle not found")

    signed_amount = movement.amount * sign
    if movement.movement_type == "credit_charge":
        cycle.statement_amount = quantize_money(cycle.statement_amount + signed_amount)
    elif movement.movement_type == "credit_repayment":
        cycle.paid_amount = quantize_money(cycle.paid_amount + signed_amount)

    if cycle.statement_amount < 0:
        raise LedgerValidationError("Statement cycle amount cannot be negative")
    if cycle.paid_amount < 0:
        raise LedgerValidationError("Statement cycle paid amount cannot be negative")
    _refresh_statement_cycle_status(cycle)
    sync_credit_statement_cash_flow(db, cycle)


def _refresh_statement_cycle_status(cycle: CreditStatementCycle) -> None:
    if cycle.statement_amount == 0 and cycle.paid_amount == 0:
        if cycle.status in {"paid", "partially_paid", "statement_generated"}:
            cycle.status = "open"
        return
    if cycle.paid_amount >= cycle.statement_amount:
        cycle.status = "paid"
    elif cycle.paid_amount > 0:
        cycle.status = "partially_paid"
    elif cycle.status in {"paid", "partially_paid"}:
        cycle.status = "statement_generated"


def _get_statement_cash_flow(db: Session, item_id: Optional[str]) -> Optional[CashFlowItem]:
    if item_id is None:
        return None
    return db.get(CashFlowItem, item_id)


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


def _create_reimbursement_claims_for_entry(
    db: Session,
    entry: FinancialEntry,
    lines: List[EntryCategoryLine],
) -> None:
    from app.services.reimbursement import create_claims_for_entry

    create_claims_for_entry(db, entry, lines)


def _abandon_reimbursement_claims_for_entry(db: Session, entry_id: str) -> None:
    from app.services.reimbursement import abandon_claims_for_entry

    abandon_claims_for_entry(db, entry_id)


def quantize_money(value: Decimal) -> Decimal:
    return value.quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)
