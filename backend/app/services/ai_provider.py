import json
import urllib.error
import urllib.request
from typing import List, Tuple

from app.core.config import get_settings
from app.schemas.ai import AIActionProposal
from app.services.ledger import LedgerValidationError


SYSTEM_PROMPT = """
You convert personal finance text into JSON actions for LinoFinance.
Return only a JSON object with this shape:
{"actions":[{"action_type":"CreateEntry","payload":{},"explanation":"..."}],
"explanation":"...","confidence":0.0}
Use only supported action_type values:
CreateEntry, CreateCashFlowItem, MarkReimbursable, CreateInstallmentPlan,
RecordCreditRepayment, GenerateNotificationRule.
Do not invent account_id or category_id values if the user did not provide them.
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
    actions = [AIActionProposal.model_validate(item) for item in parsed.get("actions", [])]
    return actions, raw_response, parsed.get("explanation"), parsed.get("confidence")


def _chat_completions_endpoint(base_url: str) -> str:
    normalized = base_url.rstrip("/")
    if normalized.endswith("/chat/completions"):
        return normalized
    return f"{normalized}/chat/completions"
