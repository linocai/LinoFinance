from datetime import date as DateType
from decimal import Decimal
from pathlib import Path
from statistics import mean, pstdev
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.ai_memo import AIMemo
from app.models.category import Category
from app.models.entry import EntryCategoryLine, FinancialEntry
from app.schemas.ai_memo import AIMemoGenerateRequest, AIMemoPatch
from app.services import ai_provider, report
from app.services.ledger import LedgerNotFoundError, LedgerValidationError


TONE_INSTRUCTIONS = {
    "warm": "温暖、像给未来的自己写信，但保持克制和具体。",
    "terse": "简短、直接、只保留最关键的结论和行动项。",
    "playful": "轻松、有一点幽默感，但不要稀释财务风险。",
    "professional": "专业、清晰、像财务顾问给出的月度复盘。",
}


def list_memos(db: Session, period: Optional[str] = None) -> list[AIMemo]:
    statement = select(AIMemo).where(AIMemo.status != "archived")
    if period:
        start = _period_start(period)
        statement = statement.where(AIMemo.period_start == start)
    statement = statement.order_by(AIMemo.period_start.desc(), AIMemo.created_at.desc())
    return list(db.execute(statement).scalars().all())


def generate_memo(db: Session, payload: AIMemoGenerateRequest, tone: Optional[str] = None) -> AIMemo:
    if payload.period_end < payload.period_start:
        raise LedgerValidationError("period_end must be after period_start")
    if tone is not None and tone not in TONE_INSTRUCTIONS:
        raise LedgerValidationError("Unsupported AI memo tone")

    stats = _memo_stats(db, payload.period_start, payload.period_end)
    previous_memo = _previous_memo_summary(db, payload.period_start)
    prompt = _render_prompt(payload.period_start, payload.period_end, stats, tone, previous_memo)
    # v3.0.0 P3: memo generation also resolves AI config DB > env.
    config = ai_provider.resolve_ai_config(db)
    result = ai_provider.generate_monthly_memo(prompt, config)
    memo = _active_memo_for_period(db, payload.period_start, payload.period_end)
    if memo is None:
        memo = AIMemo(period_start=payload.period_start, period_end=payload.period_end)
        db.add(memo)
    memo.summary = result["summary"]
    memo.stats_json = stats
    memo.prompt_token = result.get("prompt_token", 0)
    memo.completion_token = result.get("completion_token", 0)
    memo.generator = result.get("generator", "openai_compatible")
    memo.status = payload.status
    memo.confidence = Decimal(str(result.get("confidence", "0")))
    db.commit()
    db.refresh(memo)
    return memo


def _active_memo_for_period(db: Session, start: DateType, end: DateType) -> Optional[AIMemo]:
    return db.execute(
        select(AIMemo)
        .where(
            AIMemo.period_start == start,
            AIMemo.period_end == end,
            AIMemo.status != "archived",
        )
        .order_by(AIMemo.updated_at.desc(), AIMemo.created_at.desc())
    ).scalars().first()


def _previous_memo_summary(db: Session, start: DateType) -> str:
    memo = db.execute(
        select(AIMemo)
        .where(
            AIMemo.period_end < start,
            AIMemo.status != "archived",
        )
        .order_by(AIMemo.period_end.desc(), AIMemo.updated_at.desc())
    ).scalars().first()
    if memo is None:
        return "无上一期用户编辑备忘录。"
    return memo.summary


def _memo_stats(db: Session, start: DateType, end: DateType) -> dict:
    overview = report.monthly_overview(db, start, end)
    categories = report.category_expenses(db, start, end)
    subscriptions = report.subscription_report(db, end)
    reimbursements = report.reimbursement_report(db, start, end, "expected_net")
    credit = report.credit_liability_trend(db, start, end)
    return {
        "base_currency": overview.base_currency,
        "period": {"start": start.isoformat(), "end": end.isoformat()},
        "overview": {
            "income_cny": str(overview.income_cny),
            "expense_cny": str(overview.expense_cny),
            "net_income_cny": str(overview.net_income_cny),
            "future_inflow_cny": str(overview.future_inflow_cny),
            "future_outflow_cny": str(overview.future_outflow_cny),
            "future_net_cny": str(overview.future_net_cny),
            "credit_liability_cny": str(overview.credit_liability_cny),
            "expected_reimbursement_cny": str(overview.expected_reimbursement_cny),
            "approved_reimbursement_cny": str(overview.approved_reimbursement_cny),
            "received_reimbursement_cny": str(overview.received_reimbursement_cny),
            "personal_net_expense_cny": str(overview.personal_net_expense_cny),
        },
        "top_expense_categories": [
            {
                "category_id": row.category_id,
                "category_name": row.category_name,
                "expense_cny": str(row.expense_cny),
            }
            for row in categories.rows[:5]
        ],
        "subscriptions": {
            "active_count": subscriptions.active_subscription_count,
            "monthly_total_cny": str(subscriptions.monthly_total_cny),
            "annual_total_cny": str(subscriptions.annual_total_cny),
            "upcoming_30_days_cny": str(subscriptions.upcoming_30_days_cny),
        },
        "credit_liabilities": {
            "total_remaining_cny": str(credit.total_remaining_cny),
            "rows": [
                {
                    "cycle_id": row.cycle_id,
                    "account_name": row.account_name,
                    "due_date": row.due_date.isoformat(),
                    "remaining_cny": str(row.remaining_cny),
                    "status": row.status,
                }
                for row in credit.rows
            ],
        },
        "reimbursements": {
            "gross_reimbursable_expense_cny": str(reimbursements.gross_reimbursable_expense_cny),
            "expected_offset_cny": str(reimbursements.expected_offset_cny),
            "approved_offset_cny": str(reimbursements.approved_offset_cny),
            "received_offset_cny": str(reimbursements.received_offset_cny),
            "selected_net_expense_cny": str(reimbursements.selected_net_expense_cny),
            "status_breakdown": [
                {
                    "status": item.status,
                    "amount_cny": str(item.amount_cny),
                    "claim_count": item.claim_count,
                }
                for item in reimbursements.status_breakdown
            ],
        },
        "anomalies": _expense_anomalies(db, start, end),
    }


def _expense_anomalies(db: Session, start: DateType, end: DateType) -> list[dict]:
    rows = []
    statement = (
        select(EntryCategoryLine, FinancialEntry, Category)
        .join(FinancialEntry, EntryCategoryLine.entry_id == FinancialEntry.id)
        .join(Category, EntryCategoryLine.category_id == Category.id)
        .where(
            FinancialEntry.status == "confirmed",
            FinancialEntry.date >= start,
            FinancialEntry.date <= end,
            EntryCategoryLine.direction == "expense",
        )
    )
    for line, entry, category in db.execute(statement):
        amount = line.converted_cny_amount or Decimal("0")
        rows.append(
            {
                "entry_id": entry.id,
                "title": entry.title,
                "date": entry.date.isoformat(),
                "category_name": category.name,
                "amount_cny": amount,
            }
        )
    if not rows:
        return []
    values = [row["amount_cny"] for row in rows]
    average = mean(values)
    deviation = pstdev(values) if len(values) > 1 else Decimal("0")
    anomalies = []
    for row in rows:
        z_score = Decimal("0") if deviation == 0 else (row["amount_cny"] - average) / deviation
        if len(values) >= 3 and z_score >= Decimal("2"):
            anomalies.append(
                {
                    "entry_id": row["entry_id"],
                    "title": row["title"],
                    "date": row["date"],
                    "category_name": row["category_name"],
                    "amount_cny": str(row["amount_cny"]),
                    "z_score": str(z_score.quantize(Decimal("0.01"))),
                }
            )
    anomalies.sort(key=lambda item: Decimal(item["amount_cny"]), reverse=True)
    return anomalies[:5]


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


def _render_prompt(
    start: DateType,
    end: DateType,
    stats: dict,
    tone: Optional[str],
    previous_memo: str,
) -> str:
    template_path = Path(__file__).parent / "prompts" / "ai_memo_zh.md"
    template = template_path.read_text(encoding="utf-8")
    return template.format(
        period_start=start.isoformat(),
        period_end=end.isoformat(),
        stats=stats,
        tone_instruction=TONE_INSTRUCTIONS.get(tone or "professional", TONE_INSTRUCTIONS["professional"]),
        previous_memo=previous_memo,
    )


def _period_start(period: str) -> DateType:
    try:
        year_text, month_text = period.split("-", maxsplit=1)
        return DateType(int(year_text), int(month_text), 1)
    except ValueError as exc:
        raise LedgerValidationError("period must use YYYY-MM format") from exc
