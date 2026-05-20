from typing import Iterable, List, Optional, Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.account import Account
from app.models.ai import AIPlan
from app.models.cash_flow import CashFlowItem
from app.models.entry import FinancialEntry
from app.models.notification import NotificationRule
from app.models.reimbursement import ReimbursementClaim
from app.schemas.search import SearchHit, SearchResponse

SUPPORTED_SEARCH_TYPES = {
    "account",
    "entry",
    "cash_flow_item",
    "reimbursement_claim",
    "ai_plan",
    "notification_rule",
}


def search(
    db: Session,
    query: str,
    limit: Optional[int] = None,
    types: Optional[Sequence[str]] = None,
) -> SearchResponse:
    settings = get_settings()
    normalized_query = query.strip()
    result_limit = min(limit or settings.search_result_limit, settings.search_result_limit)
    selected_types = _normalize_types(types)
    if not normalized_query:
        return SearchResponse(query=normalized_query, limit=result_limit, items=[])

    hits: List[SearchHit] = []
    if "account" in selected_types:
        hits.extend(_search_accounts(db, normalized_query))
    if "entry" in selected_types:
        hits.extend(_search_entries(db, normalized_query))
    if "cash_flow_item" in selected_types:
        hits.extend(_search_cash_flow_items(db, normalized_query))
    if "reimbursement_claim" in selected_types:
        hits.extend(_search_reimbursements(db, normalized_query))
    if "ai_plan" in selected_types:
        hits.extend(_search_ai_plans(db, normalized_query))
    if "notification_rule" in selected_types:
        hits.extend(_search_notifications(db, normalized_query))

    hits.sort(key=lambda item: item.relevance, reverse=True)
    return SearchResponse(query=normalized_query, limit=result_limit, items=hits[:result_limit])


def _normalize_types(types: Optional[Sequence[str]]) -> set[str]:
    if not types:
        return set(SUPPORTED_SEARCH_TYPES)
    requested = {item.strip() for item in types if item.strip()}
    return requested & SUPPORTED_SEARCH_TYPES or set(SUPPORTED_SEARCH_TYPES)


def _like(query: str) -> str:
    return f"%{query}%"


def _relevance(query: str, *values: object) -> float:
    lowered_query = query.lower()
    text = " ".join(str(value or "") for value in values).lower()
    if lowered_query == text:
        return 2.0
    if text.startswith(lowered_query):
        return 1.5
    return 1.0


def _search_accounts(db: Session, query: str) -> Iterable[SearchHit]:
    rows = db.execute(
        select(Account).where(Account.name.ilike(_like(query))).order_by(Account.display_order)
    ).scalars()
    for account in rows:
        yield SearchHit(
            type="account",
            id=account.id,
            title=account.name,
            subtitle=f"{account.type} / {account.currency}",
            relevance=_relevance(query, account.name),
            target=f"accounts/{account.id}",
            metadata={"status": account.status},
        )


def _search_entries(db: Session, query: str) -> Iterable[SearchHit]:
    rows = db.execute(
        select(FinancialEntry).where(
            FinancialEntry.title.ilike(_like(query)) | FinancialEntry.note.ilike(_like(query))
        )
    ).scalars()
    for entry in rows:
        yield SearchHit(
            type="entry",
            id=entry.id,
            title=entry.title,
            subtitle=f"{entry.status} / {entry.date.isoformat()}",
            relevance=_relevance(query, entry.title, entry.note),
            target=f"entries/{entry.id}",
            metadata={"status": entry.status},
        )


def _search_cash_flow_items(db: Session, query: str) -> Iterable[SearchHit]:
    rows = db.execute(
        select(CashFlowItem).where(
            CashFlowItem.title.ilike(_like(query)) | CashFlowItem.note.ilike(_like(query))
        )
    ).scalars()
    for item in rows:
        yield SearchHit(
            type="cash_flow_item",
            id=item.id,
            title=item.title,
            subtitle=f"{item.direction} / {item.expected_date.isoformat()}",
            relevance=_relevance(query, item.title, item.note),
            target=f"cash-flow-items/{item.id}",
            metadata={"status": item.status},
        )


def _search_reimbursements(db: Session, query: str) -> Iterable[SearchHit]:
    rows = db.execute(
        select(ReimbursementClaim).where(
            ReimbursementClaim.payer.ilike(_like(query)) | ReimbursementClaim.note.ilike(_like(query))
        )
    ).scalars()
    for claim in rows:
        yield SearchHit(
            type="reimbursement_claim",
            id=claim.id,
            title=claim.payer,
            subtitle=f"{claim.status} / {claim.expected_date.isoformat()}",
            relevance=_relevance(query, claim.payer, claim.note),
            target=f"reimbursement-claims/{claim.id}",
            metadata={"status": claim.status},
        )


def _search_ai_plans(db: Session, query: str) -> Iterable[SearchHit]:
    rows = db.execute(
        select(AIPlan).where(
            AIPlan.source_text.ilike(_like(query)) | AIPlan.explanation.ilike(_like(query))
        )
    ).scalars()
    for plan in rows:
        yield SearchHit(
            type="ai_plan",
            id=plan.id,
            title=plan.source_text[:80],
            subtitle=f"{plan.status} / {plan.risk_level}",
            relevance=_relevance(query, plan.source_text, plan.explanation),
            target=f"ai/plans/{plan.id}",
            metadata={"status": plan.status},
        )


def _search_notifications(db: Session, query: str) -> Iterable[SearchHit]:
    rows = db.execute(
        select(NotificationRule).where(
            NotificationRule.title.ilike(_like(query))
            | NotificationRule.note.ilike(_like(query))
        )
    ).scalars()
    for rule in rows:
        yield SearchHit(
            type="notification_rule",
            id=rule.id,
            title=rule.title,
            subtitle=f"{rule.rule_type} / {rule.status}",
            relevance=_relevance(query, rule.title, rule.note),
            target=f"notification-rules/{rule.id}",
            metadata={"status": rule.status},
        )
