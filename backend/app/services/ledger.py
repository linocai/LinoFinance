from datetime import date as DateType
from decimal import Decimal, ROUND_HALF_UP
from typing import Iterable, List, Optional, Tuple

from sqlalchemy import exists, select
from sqlalchemy.orm import Session

from app.core.constants import BASE_CURRENCY, SUPPORTED_CURRENCIES
from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.category import Category
from app.models.credit_statement_cycle import CreditStatementCycle
from app.models.currency_rate import CurrencyRate
from app.models.entry import AccountMovement, EntryCategoryLine, FinancialEntry
from app.models.installment import InstallmentPlan
from app.models.reimbursement import ReimbursementClaim
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
    entry_id, generated_statement_cycle_ids = _persist_entry(db, payload)
    if commit:
        db.commit()
        _dispatch_generated_statement_cycles(db, generated_statement_cycle_ids)
    return get_entry(db, entry_id)


def _persist_entry(db: Session, payload: EntryCreate) -> Tuple[str, set]:
    """Build + apply a fresh entry (rows, movements, claims) in the session.

    Extracted from ``create_entry`` so the void+recreate edit path
    (``replace_entry``) reuses the exact same creation logic — including cycle
    attachment, liability recompute and reimbursement-claim generation — instead
    of re-implementing it. Does NOT commit; returns ``(entry_id, generated
    statement-cycle ids)`` so the caller commits once and dispatches pushes.
    """
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
        generated_statement_cycle_ids = _apply_movements(db, movements, sign=Decimal("1"))
        _create_reimbursement_claims_for_entry(db, entry, lines)
    else:
        generated_statement_cycle_ids = set()

    return entry.id, generated_statement_cycle_ids


# The only statuses an entry may be in for edit/void. ``voided`` is terminal;
# anything else is a data anomaly.
_EDITABLE_ENTRY_STATUSES = {"draft", "confirmed"}

_STRUCTURAL_LINK_EDIT_MESSAGE = (
    "此记账是结算 / 报销到账 / 分期的系统联动产物，"
    "请编辑其来源的现金流 / 报销 / 分期项，不可直接编辑"
)

_FINAL_REIMBURSEMENT_EDIT_MESSAGE = (
    "此支出关联的报销已到账/已放弃（终态），请先在报销页处理后再编辑"
)


def replace_entry(
    db: Session,
    entry_id: str,
    payload: EntryCreate,
    commit: bool = True,
) -> EntryRead:
    """Edit an entry = void the old one + recreate from ``payload`` (D2=甲).

    A single transaction: ``void_entry`` reverses the old entry's movements and
    abandons its pending reimbursement claims (the original row is kept
    ``voided`` for audit), then ``_persist_entry`` builds a brand-new entry from
    the full replacement payload (replace semantics — the body is a complete new
    ``EntryCreate``, not a field-level merge). Returns the **new** entry (new
    id). Any failure in either half leaves nothing committed; the route rolls
    back. Because recreate re-runs ``_create_account_movement`` /
    ``_apply_movements``, a moved credit charge re-attaches to whichever cycle
    now covers its date (possibly a different cycle; both cycles' totals and the
    account liability recompute), and reimbursable lines spawn fresh claims — so
    the pending-receivable net-worth term follows the edit with no double count.
    """
    entry = db.get(FinancialEntry, entry_id)
    if entry is None:
        raise LedgerNotFoundError("Entry not found")
    _guard_entry_editable(db, entry)

    void_entry(db, entry_id, commit=False)
    new_entry_id, generated_statement_cycle_ids = _persist_entry(db, payload)

    if commit:
        db.commit()
        _dispatch_generated_statement_cycles(db, generated_statement_cycle_ids)
    return get_entry(db, new_entry_id)


def _guard_entry_editable(db: Session, entry: FinancialEntry) -> None:
    """Reject-edit face for ``replace_entry`` (validate before any mutation).

    - ``voided`` (or any non-draft/confirmed) entry → rejected: a voided row is
      terminal audit history and must never be resurrected/recreated.
    - Structurally-linked entries → rejected (see ``_entry_is_structurally_linked``).

    - Source-expense entries whose reimbursement claim has reached a FINAL
      status (received / abandoned) → rejected (see
      ``_entry_has_final_reimbursement_claim``). The pending case stays editable.

    ``created_by`` is intentionally *not* a gate: an ``ai``-authored entry is a
    normal formal ledger record the user may freely edit, and settlement entries
    inherit the client's ``created_by`` (usually ``user``), so the field is not a
    reliable structural signal. The real signal is an inbound FK reference from
    an upstream object, which is what we detect below.
    """
    if entry.status == "voided":
        raise LedgerValidationError("Voided entries cannot be edited")
    if entry.status not in _EDITABLE_ENTRY_STATUSES:
        raise LedgerValidationError("Only draft or confirmed entries can be edited")
    if _entry_is_structurally_linked(db, entry.id):
        raise LedgerValidationError(_STRUCTURAL_LINK_EDIT_MESSAGE)
    if _entry_has_final_reimbursement_claim(db, entry.id):
        raise LedgerValidationError(_FINAL_REIMBURSEMENT_EDIT_MESSAGE)


def _entry_is_structurally_linked(db: Session, entry_id: str) -> bool:
    """True when the entry is the *product* of an upstream object.

    void+recreate would orphan the upstream reference (it still points at the
    now-``voided`` row) and mint an untracked new entry, double-counting. Such
    entries must be edited via their source object instead:

    - ``CashFlowItem.linked_entry_id`` — a settled cash flow's product entry
      (subscription / installment / generic settle / reimbursement received).
    - ``ReimbursementClaim.received_entry_id`` — a reimbursement's received
      (income) entry.
    - ``InstallmentPlan.linked_entry_id`` — an installment plan's source
      credit-charge entry.

    Deliberately excluded: ``ReimbursementClaim.linked_entry_id`` (the *source*
    expense entry) **while its claim is still pending**. Editing that is the
    intended flow — void abandons its pending claims and recreate re-issues them
    (matrix item 3), exactly like a plain void+recreate. Once that claim reaches
    a FINAL status the void+recreate flow breaks, so the *separate*
    ``_entry_has_final_reimbursement_claim`` guard (below, checked in
    ``_guard_entry_editable``) rejects that case.
    """
    if (
        db.execute(
            select(CashFlowItem.id)
            .where(CashFlowItem.linked_entry_id == entry_id)
            .limit(1)
        ).scalar()
        is not None
    ):
        return True
    if (
        db.execute(
            select(ReimbursementClaim.id)
            .where(ReimbursementClaim.received_entry_id == entry_id)
            .limit(1)
        ).scalar()
        is not None
    ):
        return True
    if (
        db.execute(
            select(InstallmentPlan.id)
            .where(InstallmentPlan.linked_entry_id == entry_id)
            .limit(1)
        ).scalar()
        is not None
    ):
        return True
    return False


def _entry_has_final_reimbursement_claim(db: Session, entry_id: str) -> bool:
    """True when a FINAL-status reimbursement claim references this entry as its
    source expense (``ReimbursementClaim.linked_entry_id``).

    The source-expense case is normally editable — ``_entry_is_structurally_linked``
    excludes it on purpose so void+recreate can abandon the entry's *pending*
    claims and re-issue them. But once a claim on this entry is FINAL
    (``received`` / ``abandoned``, from ``reimbursement.FINAL_STATUSES``), that
    flow silently corrupts the ledger:

    - ``received``: an income entry (E2) was already created and the claim is
      terminal. ``void_entry`` → ``abandon_claims_for_entry`` *skips* FINAL claims
      (it only abandons pending ones), so the void reverses the source expense
      while the received claim + its income entry survive → **phantom income**;
      recreate then mints a fresh ``pending`` claim → the same reimbursement is
      represented twice (received + new pending), **double-counting** the
      pending-receivable net-worth term.
    - ``abandoned``: same skip → recreate silently re-issues a pending claim for
      a reimbursement the user already gave up on, re-inflating the receivable.

    So an entry carrying any FINAL claim must be handled on the reimbursement
    page first (un-receive / re-open), never via void+recreate (v3.0.0 评审
    重要-1).
    """
    from app.services.reimbursement import FINAL_STATUSES

    return (
        db.execute(
            select(ReimbursementClaim.id)
            .where(
                ReimbursementClaim.linked_entry_id == entry_id,
                ReimbursementClaim.status.in_(FINAL_STATUSES),
            )
            .limit(1)
        ).scalar()
        is not None
    )


def list_entries(
    db: Session,
    *,
    account_id: Optional[str] = None,
    limit: Optional[int] = None,
    offset: int = 0,
) -> List[EntryRead]:
    """List entries, newest first, optionally filtered/paginated (v2.4.0 #3).

    - ``account_id`` — return whole entries that have *any* movement on the
      account, using an EXISTS subquery (a bare JOIN would duplicate an entry
      with multiple movements on the same account). Filter is status-agnostic
      (voided entries are returned too; the client self-filters). The full
      movement set is preserved on each entry — we never trim to a subset.
    - ``limit=None`` — no LIMIT/OFFSET at all, i.e. a *true* full scan that is
      byte-for-byte equal to the old per-row path (the three full-scan callers
      rely on this). Only when ``limit`` is passed do we slice, after filtering.
    - N+1 is eliminated: after selecting the entry ids we load *all* their
      category lines and movements in two batch ``IN`` queries (there is no ORM
      relationship on ``FinancialEntry`` to ``selectinload``), each ordered by
      ``created_at ASC, id ASC`` so the assembled ``EntryRead`` is identical to
      the old ``_load_entry_parts`` output (whose insertion order was only an
      unguaranteed coincidence — Postgres ``IN`` gives no ordering; the frontend
      ``kind(of:)`` reads ``categoryLines.first.direction``).
    """
    statement = select(FinancialEntry).order_by(
        FinancialEntry.date.desc(), FinancialEntry.created_at.desc()
    )
    if account_id is not None:
        statement = statement.where(
            exists().where(
                AccountMovement.entry_id == FinancialEntry.id,
                AccountMovement.account_id == account_id,
            )
        )
    if limit is not None:
        statement = statement.limit(limit).offset(offset)

    entries = list(db.execute(statement).scalars())
    if not entries:
        return []

    entry_ids = [entry.id for entry in entries]
    lines_by_entry, movements_by_entry = _load_entry_parts_bulk(db, entry_ids)
    return [
        EntryRead.from_models(
            entry,
            lines_by_entry.get(entry.id, []),
            movements_by_entry.get(entry.id, []),
        )
        for entry in entries
    ]


def get_entry(db: Session, entry_id: str) -> EntryRead:
    entry = db.get(FinancialEntry, entry_id)
    if entry is None:
        raise LedgerNotFoundError("Entry not found")

    lines, movements = _load_entry_parts(db, entry_id)
    return EntryRead.from_models(entry, lines, movements)


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
            # Distinguish "mark-paid full-clear" (no linked entry — the future
            # repayment never needs fulfilling, so cancel it) from "settle reached
            # 0" (has a linked_entry_id — a real settlement, keep it settled).
            # Leaving the mark-paid placeholder as ``settled`` with no linked entry
            # makes the R4① detector ("已结算现金流缺记账") flag a self-made
            # orphan on every mark-paid, polluting reconciliation trust
            # (v2.3.0 评审修补 重要-2).
            if existing.linked_entry_id is None:
                existing.status = "cancelled"
            else:
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
        # Exclude voided cycles from auto-assignment: a voided cycle is excluded
        # from ``sum_open_statement_total`` (liability) and from the R1/R2/R4
        # reconciliation scans, so letting a new charge land on a voided cycle
        # would make the consumption silently vanish (v2.3.0 评审修补 重要-1).
        # ``void_cycle`` first lets users create voided cycles at runtime, so this
        # filter is now load-bearing. With no *valid* cycle covering the date the
        # existing "requires a matching statement cycle" raise still fires (422),
        # prompting the user to create a valid cycle first.
        statement_cycle = db.execute(
            select(CreditStatementCycle)
            .where(
                CreditStatementCycle.credit_account_id == account.id,
                CreditStatementCycle.status != "voided",
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
    if movement_type in {"balance_in", "balance_out", "transfer_in", "transfer_out"} and account.type == "credit":
        raise LedgerValidationError("Balance movements require a non-credit account")


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


def _apply_movements(db: Session, movements: Iterable[AccountMovement], sign: Decimal) -> set[str]:
    generated_statement_cycle_ids: set[str] = set()
    # Credit accounts touched in this batch — their ``current_liability`` is a
    # *derived* value (v2.2.0 P1, single source of truth) and is recomputed from
    # cycles once, after all cycle mutations land, rather than independently
    # accumulated per movement (the old path that let the field drift from
    # ``Σcycle``; see PROJECT_PLAN §5.2 病灶 A/C).
    touched_credit_accounts: dict[str, Account] = {}
    for movement in movements:
        account = db.get(Account, movement.account_id)
        if account is None:
            raise LedgerValidationError("Account not found")

        signed_amount = movement.amount * sign
        if movement.movement_type in {"balance_in", "transfer_in"}:
            account.current_balance = quantize_money(account.current_balance + signed_amount)
        elif movement.movement_type in {"balance_out", "transfer_out"}:
            account.current_balance = quantize_money(account.current_balance - signed_amount)
        elif movement.movement_type in {"credit_charge", "credit_repayment"}:
            if cycle_id := _apply_statement_cycle_movement(db, movement, sign):
                generated_statement_cycle_ids.add(cycle_id)
            touched_credit_accounts[account.id] = account
        else:
            raise LedgerValidationError("Unsupported account movement type")

    # ``current_liability`` ≡ Σ(non-voided cycle: statement_amount − paid_amount).
    for account in touched_credit_accounts.values():
        recompute_credit_liability(db, account)
    return generated_statement_cycle_ids


def _apply_statement_cycle_movement(
    db: Session,
    movement: AccountMovement,
    sign: Decimal,
) -> Optional[str]:
    if movement.statement_cycle_id is None:
        raise LedgerValidationError("Credit movement requires a statement cycle")

    cycle = db.get(CreditStatementCycle, movement.statement_cycle_id)
    if cycle is None:
        raise LedgerValidationError("Credit statement cycle not found")

    previous_statement_amount = cycle.statement_amount
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
    if (
        movement.movement_type == "credit_charge"
        and sign > 0
        and previous_statement_amount <= 0
        and cycle.statement_amount > 0
    ):
        return cycle.id
    return None


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


def _dispatch_generated_statement_cycles(db: Session, cycle_ids: set[str]) -> None:
    if not cycle_ids:
        return
    try:
        from app.services import push_dispatch

        for cycle_id in cycle_ids:
            push_dispatch.dispatch_credit_statement_generated(db, cycle_id)
    except Exception:
        pass


def _get_statement_cash_flow(db: Session, item_id: Optional[str]) -> Optional[CashFlowItem]:
    if item_id is None:
        return None
    return db.get(CashFlowItem, item_id)


def _load_entry_parts(
    db: Session,
    entry_id: str,
) -> Tuple[List[EntryCategoryLine], List[AccountMovement]]:
    # Order matches the batch loader (``_load_entry_parts_bulk``) so the
    # single-entry ``get_entry`` output is byte-for-byte identical to the list
    # endpoint's — a deterministic ``created_at ASC, id ASC`` order that replaces
    # the former no-ORDER-BY reliance on coincidental insertion order (which
    # Postgres never guaranteed; v2.4.0 #3, PROJECT_PLAN §5.5 风险1).
    lines = list(
        db.execute(
            select(EntryCategoryLine)
            .where(EntryCategoryLine.entry_id == entry_id)
            .order_by(EntryCategoryLine.created_at.asc(), EntryCategoryLine.id.asc())
        ).scalars()
    )
    movements = list(
        db.execute(
            select(AccountMovement)
            .where(AccountMovement.entry_id == entry_id)
            .order_by(AccountMovement.created_at.asc(), AccountMovement.id.asc())
        ).scalars()
    )
    return lines, movements


def _load_entry_parts_bulk(
    db: Session,
    entry_ids: List[str],
) -> Tuple[dict, dict]:
    """Batch-load lines and movements for many entries (v2.4.0 #3, kills N+1).

    Returns two dicts keyed by ``entry_id``. Both queries carry an explicit
    ``ORDER BY created_at ASC, id ASC`` so the per-entry order matches the old
    single-entry ``_load_entry_parts`` (which relied on unguaranteed insertion
    order). Grouping is done in-memory to keep the row order the query produced.
    """
    lines_by_entry: dict = {}
    movements_by_entry: dict = {}
    if not entry_ids:
        return lines_by_entry, movements_by_entry

    line_rows = db.execute(
        select(EntryCategoryLine)
        .where(EntryCategoryLine.entry_id.in_(entry_ids))
        .order_by(EntryCategoryLine.created_at.asc(), EntryCategoryLine.id.asc())
    ).scalars()
    for line in line_rows:
        lines_by_entry.setdefault(line.entry_id, []).append(line)

    movement_rows = db.execute(
        select(AccountMovement)
        .where(AccountMovement.entry_id.in_(entry_ids))
        .order_by(AccountMovement.created_at.asc(), AccountMovement.id.asc())
    ).scalars()
    for movement in movement_rows:
        movements_by_entry.setdefault(movement.entry_id, []).append(movement)

    return lines_by_entry, movements_by_entry


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


# Cycle statuses that no longer represent an outstanding receivable from the
# card. ``voided`` cycles are reversed/discarded and never count toward the
# liability; everything else (``open`` / ``statement_generated`` /
# ``partially_paid`` / ``paid``) contributes its ``statement_amount −
# paid_amount`` remainder (a fully ``paid`` cycle contributes 0 naturally, so it
# is harmless to include).
CREDIT_LIABILITY_EXCLUDED_CYCLE_STATUSES = {"voided"}


def sum_open_statement_total(db: Session, credit_account_id: str) -> Decimal:
    """The single source of truth for a credit account's liability.

    ``current_liability`` ≡ ``Σ(non-voided cycle: statement_amount −
    paid_amount)`` (v2.2.0 P1, PROJECT_PLAN §5.2 公式 / D1=甲). The current data
    model has no "unbilled charges" concept (every credit_charge is forced into a
    cycle at creation, see ``_resolve_statement_cycle_for_movement``), so this
    cycle sum is the whole truth. Used by both the ledger recompute writer and
    the reconciliation reader so the two can never disagree.
    """
    total = Decimal("0")
    rows: Iterable[CreditStatementCycle] = db.execute(
        select(CreditStatementCycle).where(
            CreditStatementCycle.credit_account_id == credit_account_id
        )
    ).scalars()
    for cycle in rows:
        if cycle.status in CREDIT_LIABILITY_EXCLUDED_CYCLE_STATUSES:
            continue
        total = quantize_money(total + cycle.statement_amount - cycle.paid_amount)
    return total


def recompute_credit_liability(db: Session, account: Account) -> Decimal:
    """Re-derive and persist ``account.current_liability`` from its cycles.

    The stored ``current_liability`` column is a cache of ``sum_open_statement_total``
    — never independently accumulated — so it can never drift (病灶 A/C 根治).
    No-op for non-credit accounts. Returns the recomputed liability.
    """
    if account.type != "credit":
        return quantize_money(account.current_liability)
    total = sum_open_statement_total(db, account.id)
    account.current_liability = total
    return total


def quantize_money(value: Decimal) -> Decimal:
    return value.quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)
