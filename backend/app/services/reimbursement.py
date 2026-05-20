from decimal import Decimal
from typing import Iterable, List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.entry import EntryCategoryLine, FinancialEntry
from app.models.reimbursement import ReimbursementClaim
from app.schemas.reimbursement import (
    ReimbursementClaimCreate,
    ReimbursementClaimRead,
    ReimbursementReceive,
    ReimbursementReceiveRead,
)
from app.services import ledger
from app.services.ledger import LedgerNotFoundError, LedgerValidationError, quantize_money


CONFIRMED_CASH_FLOW_STATUSES = {"approved", "waiting_received"}
FINAL_STATUSES = {"received", "rejected", "abandoned"}


def create_reimbursement_claim(
    db: Session,
    payload: ReimbursementClaimCreate,
) -> ReimbursementClaimRead:
    entry = _get_confirmed_entry(db, payload.linked_entry_id)
    if payload.linked_entry_line_id is None:
        raise LedgerValidationError("Manual reimbursement claims must link an expense line")
    line = _get_entry_line(db, payload.linked_entry_line_id, entry.id)
    _validate_claim_matches_line(db, payload, line)
    converted_cny_amount, exchange_rate_id = _resolve_payload_conversion(
        db,
        quantize_money(payload.amount),
        payload.currency,
        payload.expected_date,
        payload.exchange_rate_id,
        payload.converted_cny_amount,
    )
    claim = ReimbursementClaim(
        linked_entry_id=entry.id,
        linked_entry_line_id=line.id if line is not None else None,
        amount=quantize_money(payload.amount),
        currency=payload.currency.upper(),
        exchange_rate_id=exchange_rate_id,
        converted_cny_amount=converted_cny_amount,
        payer=payload.payer,
        expected_date=payload.expected_date,
        status=payload.status,
        invoice_attachment_ids=payload.invoice_attachment_ids,
        note=payload.note,
    )
    db.add(claim)
    db.flush()
    _sync_reimbursement_cash_flow(db, claim)
    db.commit()
    db.refresh(claim)
    return ReimbursementClaimRead.model_validate(claim)


def update_claim_status(
    db: Session,
    claim_id: str,
    status: str,
    commit: bool = True,
    allow_final_source: bool = False,
) -> ReimbursementClaimRead:
    claim = _get_claim_or_raise(db, claim_id)
    if not allow_final_source:
        _ensure_not_final(claim)
    if status == "received" or status == "partial_received":
        raise LedgerValidationError("Received reimbursement status requires mark-received")
    if status not in {
        "reimbursable",
        "invoice_pending",
        "submitted",
        "approved",
        "waiting_received",
        "rejected",
        "abandoned",
    }:
        raise LedgerValidationError("Unsupported reimbursement status")
    claim.status = status
    _sync_reimbursement_cash_flow(db, claim)
    if commit:
        db.commit()
        return get_reimbursement_claim(db, claim_id)
    db.flush()
    return ReimbursementClaimRead.model_validate(claim)


def create_claims_for_entry(
    db: Session,
    entry: FinancialEntry,
    lines: Iterable[EntryCategoryLine],
) -> None:
    if entry.status != "confirmed":
        return

    for line in lines:
        if not line.reimbursable_flag:
            continue
        existing = db.execute(
            select(ReimbursementClaim).where(ReimbursementClaim.linked_entry_line_id == line.id)
        ).scalar_one_or_none()
        if existing is not None:
            continue
        if line.reimbursement_expected_date is None:
            raise LedgerValidationError("Reimbursable lines require reimbursement_expected_date")

        claim = ReimbursementClaim(
            linked_entry_id=entry.id,
            linked_entry_line_id=line.id,
            amount=line.amount,
            currency=line.currency,
            exchange_rate_id=line.exchange_rate_id,
            converted_cny_amount=line.converted_cny_amount,
            payer=line.reimbursement_payer or "company",
            expected_date=line.reimbursement_expected_date,
            status=line.reimbursement_status or "reimbursable",
            invoice_attachment_ids=None,
            note=line.note,
        )
        db.add(claim)
        db.flush()
        _sync_reimbursement_cash_flow(db, claim)


def abandon_claims_for_entry(db: Session, entry_id: str) -> None:
    claims = db.execute(
        select(ReimbursementClaim).where(ReimbursementClaim.linked_entry_id == entry_id)
    ).scalars()
    for claim in claims:
        if claim.status in FINAL_STATUSES:
            continue
        claim.status = "abandoned"
        cash_flow = _get_claim_cash_flow(db, claim)
        if cash_flow is not None and cash_flow.status != "settled":
            cash_flow.status = "cancelled"


def list_reimbursement_claims(
    db: Session,
    status: Optional[str] = None,
) -> List[ReimbursementClaimRead]:
    statement = select(ReimbursementClaim)
    if status is not None:
        statement = statement.where(ReimbursementClaim.status == status)
    claims = db.execute(
        statement.order_by(ReimbursementClaim.expected_date.asc(), ReimbursementClaim.created_at.asc())
    ).scalars()
    return [ReimbursementClaimRead.model_validate(claim) for claim in claims]


def get_reimbursement_claim(db: Session, claim_id: str) -> ReimbursementClaimRead:
    claim = _get_claim_or_raise(db, claim_id)
    return ReimbursementClaimRead.model_validate(claim)


def submit_claim(db: Session, claim_id: str) -> ReimbursementClaimRead:
    claim = _get_claim_or_raise(db, claim_id)
    _ensure_not_final(claim)
    claim.status = "submitted"
    _sync_reimbursement_cash_flow(db, claim)
    db.commit()
    return get_reimbursement_claim(db, claim_id)


def approve_claim(db: Session, claim_id: str) -> ReimbursementClaimRead:
    claim = _get_claim_or_raise(db, claim_id)
    _ensure_not_final(claim)
    claim.status = "approved"
    _sync_reimbursement_cash_flow(db, claim)
    db.commit()
    try:
        from app.services import push_dispatch

        push_dispatch.dispatch_reimbursement_status(db, claim_id, "approved")
    except Exception:
        pass
    return get_reimbursement_claim(db, claim_id)


def reject_claim(db: Session, claim_id: str) -> ReimbursementClaimRead:
    claim = _get_claim_or_raise(db, claim_id)
    _ensure_not_final(claim)
    claim.status = "rejected"
    cash_flow = _get_claim_cash_flow(db, claim)
    if cash_flow is not None:
        cash_flow.status = "cancelled"
    db.commit()
    return get_reimbursement_claim(db, claim_id)


def abandon_claim(db: Session, claim_id: str) -> ReimbursementClaimRead:
    claim = _get_claim_or_raise(db, claim_id)
    _ensure_not_final(claim)
    claim.status = "abandoned"
    cash_flow = _get_claim_cash_flow(db, claim)
    if cash_flow is not None:
        cash_flow.status = "cancelled"
    db.commit()
    return get_reimbursement_claim(db, claim_id)


def mark_claim_received(
    db: Session,
    claim_id: str,
    payload: ReimbursementReceive,
) -> ReimbursementReceiveRead:
    claim = _get_claim_or_raise(db, claim_id)
    _ensure_not_final(claim)

    account = db.get(Account, payload.received_account_id)
    if account is None:
        raise LedgerValidationError("Received account not found")
    if account.currency != claim.currency:
        raise LedgerValidationError("Received account currency must match reimbursement currency")
    _validate_received_entry_payload(claim, payload)

    entry_payload = payload.entry.model_copy(update={"status": "confirmed"})
    entry = ledger.create_entry(db, entry_payload, commit=False)

    claim.status = "received"
    claim.actual_received_date = payload.actual_received_date
    claim.received_account_id = payload.received_account_id
    claim.received_entry_id = entry.id

    cash_flow = _get_claim_cash_flow(db, claim)
    if cash_flow is not None:
        cash_flow.status = "settled"
        cash_flow.linked_entry_id = entry.id
        cash_flow.account_id = payload.received_account_id

    db.commit()
    try:
        from app.services import push_dispatch

        push_dispatch.dispatch_reimbursement_status(db, claim_id, "received")
    except Exception:
        pass
    return ReimbursementReceiveRead(
        reimbursement_claim=get_reimbursement_claim(db, claim_id),
        entry=ledger.get_entry(db, entry.id),
    )


def _sync_reimbursement_cash_flow(db: Session, claim: ReimbursementClaim) -> None:
    status = "confirmed" if claim.status in CONFIRMED_CASH_FLOW_STATUSES else "expected"
    if claim.status == "received":
        status = "settled"
    elif claim.status in {"rejected", "abandoned"}:
        status = "cancelled"

    existing = _get_claim_cash_flow(db, claim)
    if existing is not None:
        existing.title = f"Reimbursement from {claim.payer}"
        existing.direction = "inflow"
        existing.cash_flow_type = "reimbursement"
        existing.amount = claim.amount
        existing.currency = claim.currency
        existing.exchange_rate_id = claim.exchange_rate_id
        existing.converted_cny_amount = claim.converted_cny_amount
        existing.expected_date = claim.expected_date
        existing.status = status
        existing.linked_reimbursement_id = claim.id
        return

    item = CashFlowItem(
        title=f"Reimbursement from {claim.payer}",
        direction="inflow",
        cash_flow_type="reimbursement",
        amount=claim.amount,
        currency=claim.currency,
        exchange_rate_id=claim.exchange_rate_id,
        converted_cny_amount=claim.converted_cny_amount,
        expected_date=claim.expected_date,
        account_id=None,
        category_id=None,
        recurrence_rule=None,
        status=status,
        linked_reimbursement_id=claim.id,
        note="Generated from reimbursement claim.",
    )
    db.add(item)
    db.flush()
    claim.cash_flow_item_id = item.id


def _resolve_payload_conversion(
    db: Session,
    amount: Decimal,
    currency: str,
    expected_date,
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


def _get_confirmed_entry(db: Session, entry_id: str) -> FinancialEntry:
    entry = db.get(FinancialEntry, entry_id)
    if entry is None:
        raise LedgerValidationError("Linked entry not found")
    if entry.status != "confirmed":
        raise LedgerValidationError("Reimbursement claims require a confirmed linked entry")
    return entry


def _get_entry_line(
    db: Session,
    line_id: Optional[str],
    entry_id: str,
) -> Optional[EntryCategoryLine]:
    if line_id is None:
        return None
    line = db.get(EntryCategoryLine, line_id)
    if line is None:
        raise LedgerValidationError("Linked entry line not found")
    if line.entry_id != entry_id:
        raise LedgerValidationError("Linked entry line must belong to linked entry")
    return line


def _validate_claim_matches_line(
    db: Session,
    payload: ReimbursementClaimCreate,
    line: EntryCategoryLine,
) -> None:
    if line.direction != "expense":
        raise LedgerValidationError("Reimbursement claims must link an expense line")
    if line.currency != payload.currency.upper():
        raise LedgerValidationError("Reimbursement currency must match linked expense line")
    if quantize_money(line.amount) != quantize_money(payload.amount):
        raise LedgerValidationError("Reimbursement amount must match linked expense line")
    existing = db.execute(
        select(ReimbursementClaim).where(ReimbursementClaim.linked_entry_line_id == line.id)
    ).scalar_one_or_none()
    if existing is not None:
        raise LedgerValidationError("Reimbursement claim already exists for linked expense line")


def _get_claim_or_raise(db: Session, claim_id: str) -> ReimbursementClaim:
    claim = db.get(ReimbursementClaim, claim_id)
    if claim is None:
        raise LedgerNotFoundError("Reimbursement claim not found")
    return claim


def _get_claim_cash_flow(db: Session, claim: ReimbursementClaim) -> Optional[CashFlowItem]:
    if claim.cash_flow_item_id is None:
        return None
    return db.get(CashFlowItem, claim.cash_flow_item_id)


def _ensure_not_final(claim: ReimbursementClaim) -> None:
    if claim.status in FINAL_STATUSES:
        raise LedgerValidationError("Final reimbursement claims cannot be changed")


def _validate_received_entry_payload(
    claim: ReimbursementClaim,
    payload: ReimbursementReceive,
) -> None:
    matching_movements = [
        movement
        for movement in payload.entry.account_movements
        if movement.account_id == payload.received_account_id
        and movement.movement_type == "balance_in"
        and movement.currency.upper() == claim.currency
        and quantize_money(movement.amount) == claim.amount
    ]
    if not matching_movements:
        raise LedgerValidationError("Received entry must include matching balance_in movement")

    matching_income_lines = [
        line
        for line in payload.entry.category_lines
        if line.direction == "income"
        and line.currency.upper() == claim.currency
        and quantize_money(line.amount) == claim.amount
    ]
    if not matching_income_lines:
        raise LedgerValidationError("Received entry must include matching income category line")
