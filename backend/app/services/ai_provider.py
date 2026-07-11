import json
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.timeutils import app_today
from app.models.ai_settings import AISettings
from app.schemas.ai import AIActionProposal
from app.services.ledger import LedgerValidationError


SYSTEM_PROMPT_TEMPLATE = """
You convert personal finance text into JSON actions for LinoFinance.
Today's date is {today}. If the user does not specify a date, assume the
event happened today; never invent dates in other months or years.

Return only a JSON object with this shape:
{{"actions":[{{"action_type":"CreateEntry","payload":{{}},"explanation":"..."}}],
"explanation":"...","confidence":0.0}}
Use exact snake_case backend field names. Do not use aliases like "type" when
the schema requires "cash_flow_type" or "rule_type".

Decision rule for action_type:
- If the text describes something that ALREADY HAPPENED (past or present-tense
  payments, purchases, receipts, transfers, expenses, income), emit ONE
  CreateEntry action with date = today (or the date the user specified).
  Common cues: "支付/买了/花了/收到/转账/给了/付了/到账".
- If the text describes a FUTURE scheduled or expected cash movement
  (upcoming salary, upcoming bill, planned subscription charge, expected
  reimbursement to be received), use CreateCashFlowItem.
  Common cues: "下个月/下周/明天/即将/计划/预计/到期/还款日".
Default to CreateEntry when uncertain.

Supported action_type values:
CreateEntry, CreateCashFlowItem, MarkReimbursable, CreateInstallmentPlan,
RecordCreditRepayment, GenerateNotificationRule, SetCashFlowStatus,
UpdateReimbursementStatus, VoidEntry.
VoidEntry reverses a posted entry; it is high-risk and always needs the user's
explicit confirmation before it can run.

{context}
When you fill account_movements[].account_id or category_lines[].category_id,
use ONLY the exact id values from the lists above. NEVER invent an id that is
not in those lists.

Category picking policy (category_lines[].category_id) — ALWAYS pick one:
1. Pick the listed category of the matching direction whose name best fits the
   merchant / purpose in the text. A close-enough match beats no match.
2. If nothing fits, pick the user's catch-all category — the one whose name
   contains "其他" or "待归类" (e.g. "其他支出") — and note in "explanation"
   that you used the catch-all.
3. Only leave category_id out when the lists contain NO category of the needed
   direction at all. A miscategorized entry is cheap for the user to fix later;
   a missing category blocks fully-automatic bookkeeping.

Account picking policy (account_movements[].account_id) — be conservative:
- Receipts usually show the paying card's bank and tail digits, e.g.
  "工商银行储蓄卡(3495)". Match those tail digits / bank name against the
  account names in the list (e.g. an account named "工商3495"); if exactly one
  account matches, use it confidently.
- If no listed account clearly matches, leave account_id out of the payload and
  explain the gap in "explanation" — a wrong account corrupts balances, so
  never guess between multiple plausible accounts.

Required payload shapes:
- CreateEntry (most common: a single past expense/income):
  {{"title": string,
   "date": "YYYY-MM-DD",
   "status": "confirmed",
   "category_lines": [
     {{"direction": "expense|income",
       "amount": decimal string,
       "currency": "CNY|USD"}}
   ],
   "account_movements": [
     {{"movement_type": "balance_in|balance_out|credit_charge|credit_repayment",
       "amount": decimal string,
       "currency": "CNY|USD"}}
   ]}}
- CreateCashFlowItem:
  {{"title": string, "direction": "inflow|outflow|transfer",
   "cash_flow_type": "salary|rent_income|reimbursement|subscription|credit_repayment|installment|one_time|other",
   "amount": decimal string, "currency": "CNY|USD", "expected_date": "YYYY-MM-DD"}}
- GenerateNotificationRule:
  {{"title": string,
   "rule_type": "credit_repayment|cash_flow|reimbursement|subscription|anomaly",
   "channel": "in_app|system|email",
   "trigger_payload": object, "next_trigger_date": "YYYY-MM-DD"}}
- SetCashFlowStatus:
  {{"cash_flow_item_id": string, "status": "expected|confirmed|cancelled"}}
- UpdateReimbursementStatus:
  {{"reimbursement_claim_id": string,
   "status": "reimbursable|invoice_pending|submitted|approved|waiting_received|rejected|abandoned"}}
""".strip()


@dataclass(frozen=True)
class ResolvedAIConfig:
    """AI provider config resolved with DB (`ai_settings`) taking priority over
    env (`LINOFINANCE_AI_*`). The HTTP-detail functions below take this object
    rather than a DB session, so the database never leaks into the transport
    layer."""

    provider: str
    base_url: Optional[str]
    api_key: Optional[str]
    model: Optional[str]
    request_timeout_seconds: int
    memo_max_tokens: int

    @property
    def is_configured(self) -> bool:
        return bool(self.base_url and self.api_key and self.model)


def _ai_settings_row(db: Session) -> Optional[AISettings]:
    """Return the single `ai_settings` row (or None). The table is single-row by
    contract; we take the earliest row deterministically if more than one exists."""
    return db.execute(
        select(AISettings).order_by(AISettings.created_at.asc(), AISettings.id.asc())
    ).scalars().first()


def resolve_ai_config(db: Session) -> ResolvedAIConfig:
    """Resolve base_url/api_key/model with DB > env priority (row-level: a stored
    row is the source of truth once present — a cleared field means cleared, it
    does NOT fall back to env; env is only the fallback when no row exists)."""
    settings = get_settings()
    row = _ai_settings_row(db)
    if row is not None:
        return ResolvedAIConfig(
            provider=settings.ai_provider,
            base_url=row.base_url,
            api_key=row.api_key,
            model=row.model,
            request_timeout_seconds=settings.ai_request_timeout_seconds,
            memo_max_tokens=settings.ai_memo_max_tokens,
        )
    return ResolvedAIConfig(
        provider=settings.ai_provider,
        base_url=settings.ai_api_base_url,
        api_key=settings.ai_api_key,
        model=settings.ai_model,
        request_timeout_seconds=settings.ai_request_timeout_seconds,
        memo_max_tokens=settings.ai_memo_max_tokens,
    )


_NOT_CONFIGURED_MESSAGE = (
    "AI is not configured; open Settings and fill in the AI base URL, API key, "
    "and model (or provide actions directly)"
)


def _render_context(context: Optional[Dict[str, Any]]) -> str:
    """Render the user's account/category lists for injection into the system
    prompt so the LLM can pick real ids instead of leaving them blank."""
    if not context:
        return (
            "No account or category list was provided; leave account_id and "
            "category_id out of the payload unless the user gave an explicit id."
        )
    lines: List[str] = []
    accounts = context.get("accounts") or []
    categories = context.get("categories") or []
    if accounts:
        lines.append("The user's existing accounts (use these exact account_id values):")
        for account in accounts:
            lines.append(
                f"- id={account.get('id')}  name={account.get('name')}  "
                f"type={account.get('type')}  currency={account.get('currency')}"
            )
    else:
        lines.append("The user has no accounts yet; leave account_id out of the payload.")
    if categories:
        lines.append("The user's existing categories (use these exact category_id values):")
        for category in categories:
            lines.append(
                f"- id={category.get('id')}  name={category.get('name')}  "
                f"type={category.get('type')}"
            )
    else:
        lines.append("The user has no categories yet; leave category_id out of the payload.")
    return "\n".join(lines)


def _build_system_prompt(context: Optional[Dict[str, Any]] = None) -> str:
    # v3.0.0 P1: use the business-timezone "today" (app_today), not the
    # server's UTC date.today() — a UTC-day boundary can put the prompt's
    # anchor date a day off from the user's Asia/Shanghai calendar day.
    # v3.0.0 P3: inject the user's real account/category lists so the LLM fills
    # genuine ids (the #1 root cause of AI bookkeeping failing was the old
    # prompt telling the LLM to leave ids blank while CreateEntry requires them).
    return SYSTEM_PROMPT_TEMPLATE.format(
        today=app_today().isoformat(),
        context=_render_context(context),
    )


def generate_action_proposals(
    source_text: str,
    config: ResolvedAIConfig,
    context: Optional[Dict[str, Any]] = None,
) -> Tuple[List[AIActionProposal], dict, str, object]:
    if not config.is_configured:
        raise LedgerValidationError(_NOT_CONFIGURED_MESSAGE)

    endpoint = _chat_completions_endpoint(config.base_url)
    request_body = {
        "model": config.model,
        "temperature": 0,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": _build_system_prompt(context)},
            {"role": "user", "content": source_text},
        ],
    }
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(request_body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {config.api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=config.request_timeout_seconds,
        ) as response:
            raw_response = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        # `exc` may embed the request URL but never the Authorization header /
        # api_key, so this is safe to surface.
        raise LedgerValidationError(f"AI provider request failed: {exc}") from exc

    content = raw_response["choices"][0]["message"]["content"]
    parsed = json.loads(content)
    actions = [
        AIActionProposal.model_validate(_normalize_action_item(item, source_text))
        for item in parsed.get("actions", [])
    ]
    # Defense-in-depth for the high-risk write-the-ledger path: never let an id
    # the LLM fabricated (not in the user's real lists) reach storage/execution.
    _reject_fabricated_ids(actions, context)
    return actions, raw_response, parsed.get("explanation"), parsed.get("confidence")


def generate_monthly_memo(prompt: str, config: ResolvedAIConfig) -> Dict[str, Any]:
    if not config.is_configured:
        raise LedgerValidationError(_NOT_CONFIGURED_MESSAGE)

    endpoint = _chat_completions_endpoint(config.base_url)
    request_body = {
        "model": config.model,
        "temperature": 0.2,
        "max_tokens": config.memo_max_tokens,
        "messages": [
            {"role": "system", "content": "Write concise Chinese finance memos in Markdown."},
            {"role": "user", "content": prompt},
        ],
    }
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(request_body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {config.api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=config.request_timeout_seconds,
        ) as response:
            raw_response = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise LedgerValidationError(f"AI provider request failed: {exc}") from exc

    message = raw_response["choices"][0]["message"]["content"]
    usage = raw_response.get("usage") or {}
    return {
        "summary": message,
        "prompt_token": usage.get("prompt_tokens", 0),
        "completion_token": usage.get("completion_tokens", 0),
        "generator": config.provider,
        "confidence": "0.8",
        "raw_response": raw_response,
    }


def _reject_fabricated_ids(
    actions: List[AIActionProposal],
    context: Optional[Dict[str, Any]],
) -> None:
    """Reject any account_id / category_id the LLM invented that is not in the
    user's real lists. Only enforced when a context was injected (LLM path); a
    caller that supplies actions directly is responsible for its own ids and is
    validated downstream by the ledger on execution.

    P3 posture = hard reject (clear 400) so a fabricated id cannot silently post
    against a non-existent account. Missing ids still fail the EntryCreate schema
    validation downstream; the P4 confirm UI will own letting the user fill a
    blank id before execution."""
    if not context:
        return
    account_ids = {a.get("id") for a in (context.get("accounts") or [])}
    category_ids = {c.get("id") for c in (context.get("categories") or [])}
    for action in actions:
        if action.action_type == "CreateEntry":
            payloads = [action.payload]
        elif action.action_type == "RecordCreditRepayment":
            payloads = [action.payload.get("entry", action.payload)]
        else:
            continue
        for payload in payloads:
            if not isinstance(payload, dict):
                continue
            for movement in payload.get("account_movements") or []:
                account_id = movement.get("account_id")
                if account_id and account_id not in account_ids:
                    raise LedgerValidationError(
                        f"AI referenced an unknown account_id '{account_id}' that is "
                        "not in your accounts; retry or add the account first"
                    )
            for line in payload.get("category_lines") or []:
                category_id = line.get("category_id")
                if category_id and category_id not in category_ids:
                    raise LedgerValidationError(
                        f"AI referenced an unknown category_id '{category_id}' that is "
                        "not in your categories; retry or add the category first"
                    )


def _chat_completions_endpoint(base_url: str) -> str:
    normalized = base_url.rstrip("/")
    if normalized.endswith("/chat/completions"):
        return normalized
    return f"{normalized}/chat/completions"


def _normalize_action_item(item: Dict[str, Any], source_text: str) -> Dict[str, Any]:
    normalized = dict(item)
    payload = dict(normalized.get("payload") or {})
    action_type = str(normalized.get("action_type") or "")
    if action_type == "CreateCashFlowItem":
        _rename(payload, "type", "cash_flow_type")
        _rename(payload, "cashflow_type", "cash_flow_type")
        _rename(payload, "date", "expected_date")
        _rename(payload, "expectedDate", "expected_date")
        if "cash_flow_type" not in payload:
            payload["cash_flow_type"] = _infer_cash_flow_type(payload, source_text)
        if "direction" not in payload:
            payload["direction"] = _infer_cash_flow_direction(payload, source_text)
    elif action_type == "GenerateNotificationRule":
        _rename(payload, "type", "rule_type")
        _rename(payload, "notification_type", "rule_type")
        _rename(payload, "trigger", "trigger_payload")
        _rename(payload, "triggerPayload", "trigger_payload")
        _rename(payload, "date", "next_trigger_date")
        _rename(payload, "next_date", "next_trigger_date")
        _rename(payload, "nextTriggerDate", "next_trigger_date")
        if "rule_type" not in payload:
            payload["rule_type"] = _infer_notification_rule_type(payload, source_text)
        payload.setdefault("channel", "in_app")
        payload.setdefault("trigger_payload", {})
    normalized["payload"] = payload
    return normalized


def _rename(payload: Dict[str, Any], old_key: str, new_key: str) -> None:
    if old_key in payload and new_key not in payload:
        payload[new_key] = payload.pop(old_key)


def _payload_text(payload: Dict[str, Any], source_text: str) -> str:
    return f"{source_text} {json.dumps(payload, ensure_ascii=False)}".lower()


def _infer_cash_flow_type(payload: Dict[str, Any], source_text: str) -> str:
    text = _payload_text(payload, source_text)
    if any(token in text for token in ("工资", "salary")):
        return "salary"
    if any(token in text for token in ("房租收入", "rent_income")):
        return "rent_income"
    if any(token in text for token in ("报销", "reimbursement")):
        return "reimbursement"
    if any(token in text for token in ("订阅", "subscription")):
        return "subscription"
    if any(token in text for token in ("信用卡", "还款", "credit_repayment")):
        return "credit_repayment"
    if any(token in text for token in ("分期", "installment")):
        return "installment"
    return "other"


def _infer_cash_flow_direction(payload: Dict[str, Any], source_text: str) -> str:
    text = _payload_text(payload, source_text)
    if any(token in text for token in ("inflow", "进账", "到账", "收入", "回款")):
        return "inflow"
    if any(token in text for token in ("transfer", "转账", "还款")):
        return "transfer"
    return "outflow"


def _infer_notification_rule_type(payload: Dict[str, Any], source_text: str) -> str:
    text = _payload_text(payload, source_text)
    if any(token in text for token in ("信用卡", "还款", "credit")):
        return "credit_repayment"
    if any(token in text for token in ("报销", "reimbursement")):
        return "reimbursement"
    if any(token in text for token in ("订阅", "subscription")):
        return "subscription"
    if any(token in text for token in ("异常", "anomaly")):
        return "anomaly"
    return "cash_flow"
