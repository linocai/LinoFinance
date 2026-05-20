import json
import urllib.error
import urllib.request
from typing import Any, Dict, List, Tuple

from app.core.config import get_settings
from app.schemas.ai import AIActionProposal
from app.services.ledger import LedgerValidationError


SYSTEM_PROMPT = """
You convert personal finance text into JSON actions for LinoFinance.
Return only a JSON object with this shape:
{"actions":[{"action_type":"CreateEntry","payload":{},"explanation":"..."}],
"explanation":"...","confidence":0.0}
Use exact snake_case backend field names. Do not use aliases like "type" when
the schema requires "cash_flow_type" or "rule_type".
Use only supported action_type values:
CreateEntry, CreateCashFlowItem, MarkReimbursable, CreateInstallmentPlan,
RecordCreditRepayment, GenerateNotificationRule, SetCashFlowStatus,
UpdateReimbursementStatus.
Do not invent account_id or category_id values if the user did not provide them.

Required payload shapes for common actions:
- CreateCashFlowItem:
  {"title": string, "direction": "inflow|outflow|transfer",
   "cash_flow_type": "salary|rent_income|reimbursement|subscription|credit_repayment|installment|one_time|other",
   "amount": decimal string, "currency": "CNY|USD", "expected_date": "YYYY-MM-DD"}
- GenerateNotificationRule:
  {"title": string,
   "rule_type": "credit_repayment|cash_flow|reimbursement|subscription|anomaly",
   "channel": "in_app|system|email",
   "trigger_payload": object, "next_trigger_date": "YYYY-MM-DD"}
- SetCashFlowStatus:
  {"cash_flow_item_id": string, "status": "expected|confirmed|cancelled"}
- UpdateReimbursementStatus:
  {"reimbursement_claim_id": string,
   "status": "reimbursable|invoice_pending|submitted|approved|waiting_received|rejected|abandoned"}
""".strip()


def generate_action_proposals(
    source_text: str,
) -> Tuple[List[AIActionProposal], dict, str, object]:
    settings = get_settings()
    if not settings.ai_api_base_url or not settings.ai_api_key or not settings.ai_model:
        raise LedgerValidationError(
            "AI provider is not configured; set LINOFINANCE_AI_API_BASE_URL, "
            "LINOFINANCE_AI_API_KEY, and LINOFINANCE_AI_MODEL or provide actions directly"
        )

    endpoint = _chat_completions_endpoint(settings.ai_api_base_url)
    request_body = {
        "model": settings.ai_model,
        "temperature": 0,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": source_text},
        ],
    }
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(request_body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {settings.ai_api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=settings.ai_request_timeout_seconds,
        ) as response:
            raw_response = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise LedgerValidationError(f"AI provider request failed: {exc}") from exc

    content = raw_response["choices"][0]["message"]["content"]
    parsed = json.loads(content)
    actions = [
        AIActionProposal.model_validate(_normalize_action_item(item, source_text))
        for item in parsed.get("actions", [])
    ]
    return actions, raw_response, parsed.get("explanation"), parsed.get("confidence")


def generate_monthly_memo(prompt: str) -> Dict[str, Any]:
    settings = get_settings()
    if not settings.ai_api_base_url or not settings.ai_api_key or not settings.ai_model:
        raise LedgerValidationError(
            "AI provider is not configured; set LINOFINANCE_AI_API_BASE_URL, "
            "LINOFINANCE_AI_API_KEY, and LINOFINANCE_AI_MODEL"
        )

    endpoint = _chat_completions_endpoint(settings.ai_api_base_url)
    request_body = {
        "model": settings.ai_model,
        "temperature": 0.2,
        "max_tokens": settings.ai_memo_max_tokens,
        "messages": [
            {"role": "system", "content": "Write concise Chinese finance memos in Markdown."},
            {"role": "user", "content": prompt},
        ],
    }
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(request_body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {settings.ai_api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=settings.ai_request_timeout_seconds,
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
        "generator": settings.ai_provider,
        "confidence": "0.8",
        "raw_response": raw_response,
    }


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
