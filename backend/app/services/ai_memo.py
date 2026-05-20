from datetime import date as DateType
from decimal import Decimal
from pathlib import Path
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.ai_memo import AIMemo
from app.schemas.ai_memo import AIMemoGenerateRequest, AIMemoPatch
from app.services import ai_provider, report
from app.services.ledger import LedgerNotFoundError, LedgerValidationError


def list_memos(db: Session, period: Optional[str] = None) -> list[AIMemo]:
    statement = select(AIMemo).where(AIMemo.status != "archived")
    if period:
        start = _period_start(period)
        statement = statement.where(AIMemo.period_start == start)
    statement = statement.order_by(AIMemo.period_start.desc(), AIMemo.created_at.desc())
    return list(db.execute(statement).scalars().all())


def generate_memo(db: Session, payload: AIMemoGenerateRequest) -> AIMemo:
    if payload.period_end < payload.period_start:
        raise LedgerValidationError("period_end must be after period_start")

    stats = _memo_stats(db, payload.period_start, payload.period_end)
    prompt = _render_prompt(payload.period_start, payload.period_end, stats)
    result = ai_provider.generate_monthly_memo(prompt)
    memo = AIMemo(
        period_start=payload.period_start,
        period_end=payload.period_end,
        summary=result["summary"],
        stats_json=stats,
        prompt_token=result.get("prompt_token", 0),
        completion_token=result.get("completion_token", 0),
        generator=result.get("generator", "openai_compatible"),
        status=payload.status,
        confidence=Decimal(str(result.get("confidence", "0"))),
    )
    db.add(memo)
    db.commit()
    db.refresh(memo)
    return memo


def patch_memo(db: Session, memo_id: str, payload: AIMemoPatch) -> AIMemo:
    memo = db.get(AIMemo, memo_id)
    if memo is None:
        raise LedgerNotFoundError("AI memo not found")
    if payload.summary is not None:
        memo.summary = payload.summary
    if payload.status is not None:
        memo.status = payload.status
    db.commit()
    db.refresh(memo)
    return memo


def archive_memo(db: Session, memo_id: str) -> None:
    memo = db.get(AIMemo, memo_id)
    if memo is None:
        raise LedgerNotFoundError("AI memo not found")
    memo.status = "archived"
    db.commit()


def _memo_stats(db: Session, start: DateType, end: DateType) -> dict:
    overview = report.monthly_overview(db, start, end)
    return {
        "base_currency": overview.base_currency,
        "income_cny": str(overview.income_cny),
        "expense_cny": str(overview.expense_cny),
        "net_income_cny": str(overview.net_income_cny),
        "future_net_cny": str(overview.future_net_cny),
        "credit_liability_cny": str(overview.credit_liability_cny),
        "expected_reimbursement_cny": str(overview.expected_reimbursement_cny),
    }


def _render_prompt(start: DateType, end: DateType, stats: dict) -> str:
    template_path = Path(__file__).parent / "prompts" / "ai_memo_zh.md"
    template = template_path.read_text(encoding="utf-8")
    return template.format(period_start=start.isoformat(), period_end=end.isoformat(), stats=stats)


def _period_start(period: str) -> DateType:
    try:
        year_text, month_text = period.split("-", maxsplit=1)
        return DateType(int(year_text), int(month_text), 1)
    except ValueError as exc:
        raise LedgerValidationError("period must use YYYY-MM format") from exc
