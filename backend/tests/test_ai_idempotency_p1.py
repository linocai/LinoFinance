"""v3.1.0 P1 — AI plan content-fingerprint idempotency.

Covers the short-window dedup on ``POST /ai/plans``: a same-content resubmit
inside the window returns the EXISTING plan (HTTP 200, no new plan, no second LLM
call), while different content or a resubmit outside the window mints a new plan
(201). Also fixes the fingerprint algorithm's stability (key-order / metadata
independence) and固化s the end-to-end idempotency that root-causes the v3.0.0
review 重要-3 (resubmit-then-reject orphan-plan double-execute).

No real LLM call is ever made — the pure-text path is monkeypatched to a canned
proposal with a call counter; the actions-provided path needs no model at all.
"""
from datetime import datetime, timedelta, timezone

from app.models.ai import AIPlan
from app.schemas.ai import AIActionProposal
from app.services import ai, ai_provider


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def create_account(client, name="Checking", balance="500"):
    response = client.post(
        "/api/v1/accounts",
        json={"name": name, "type": "balance", "currency": "CNY", "current_balance": balance},
    )
    assert response.status_code == 201
    return response.json()


def create_category(client, name="Food", category_type="expense"):
    response = client.post("/api/v1/categories", json={"name": name, "type": category_type})
    assert response.status_code == 201
    return response.json()


def _entry_action(account_id, category_id, amount="88", title="Lunch"):
    return {
        "action_type": "CreateEntry",
        "payload": {
            "title": title,
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {"category_id": category_id, "direction": "expense", "amount": amount, "currency": "CNY"}
            ],
            "account_movements": [
                {"account_id": account_id, "movement_type": "balance_out", "amount": amount, "currency": "CNY"}
            ],
        },
        "explanation": "Small CNY expense.",
    }


def _rewind_created_at(client, plan_id, seconds):
    session = client.session_factory()
    try:
        plan = session.get(AIPlan, plan_id)
        plan.created_at = datetime.now(timezone.utc) - timedelta(seconds=seconds)
        session.commit()
    finally:
        session.close()


# --------------------------------------------------------------------------- #
# ① same source_text, no client actions → dedup + LLM called exactly once
# --------------------------------------------------------------------------- #
def test_same_text_no_actions_dedups_and_calls_llm_once(client, monkeypatch) -> None:
    account = create_account(client)
    category = create_category(client)
    proposal = AIActionProposal.model_validate(_entry_action(account["id"], category["id"]))
    counter = {"calls": 0}

    def fake_generate(source_text, config, context=None):
        counter["calls"] += 1
        return [proposal], {"raw": "stub"}, "explanation", 0.9

    monkeypatch.setattr(ai_provider, "generate_action_proposals", fake_generate)

    first = client.post("/api/v1/ai/plans", json={"source_text": "午餐 88 元"})
    assert first.status_code == 201

    second = client.post("/api/v1/ai/plans", json={"source_text": "午餐 88 元"})
    assert second.status_code == 200

    assert first.json()["id"] == second.json()["id"]
    assert counter["calls"] == 1  # dedup short-circuits the second LLM call
    assert len(client.get("/api/v1/ai/plans").json()) == 1


# --------------------------------------------------------------------------- #
# ② same source_text + same client actions → one plan (no second execute)
# --------------------------------------------------------------------------- #
def test_same_actions_dedup_returns_same_plan(client) -> None:
    account = create_account(client)
    category = create_category(client)
    body = {"source_text": "午餐 88 元", "actions": [_entry_action(account["id"], category["id"])]}

    first = client.post("/api/v1/ai/plans", json=body)
    assert first.status_code == 201
    plan_id = first.json()["id"]

    second = client.post("/api/v1/ai/plans", json=body)
    assert second.status_code == 200
    assert second.json()["id"] == plan_id

    plans = client.get("/api/v1/ai/plans").json()
    assert len(plans) == 1
    # No duplicate actions were appended to the reused plan.
    assert len(second.json()["actions"]) == len(first.json()["actions"]) == 1


# --------------------------------------------------------------------------- #
# ③a out of window → new plan (201)
# --------------------------------------------------------------------------- #
def test_out_of_window_creates_new_plan(client) -> None:
    account = create_account(client)
    category = create_category(client)
    body = {"source_text": "午餐 88 元", "actions": [_entry_action(account["id"], category["id"])]}

    first = client.post("/api/v1/ai/plans", json=body)
    assert first.status_code == 201
    plan_id = first.json()["id"]

    # Push the first plan's created_at just outside the idempotency window.
    _rewind_created_at(client, plan_id, ai.IDEMPOTENCY_WINDOW_SECONDS + 60)

    second = client.post("/api/v1/ai/plans", json=body)
    assert second.status_code == 201  # window closed → fresh plan
    assert second.json()["id"] != plan_id
    assert len(client.get("/api/v1/ai/plans").json()) == 2


# A duplicate still inside the window (rewound to just under the cutoff) is deduped.
def test_within_window_still_dedups(client) -> None:
    account = create_account(client)
    category = create_category(client)
    body = {"source_text": "午餐 88 元", "actions": [_entry_action(account["id"], category["id"])]}

    first = client.post("/api/v1/ai/plans", json=body)
    assert first.status_code == 201
    plan_id = first.json()["id"]

    _rewind_created_at(client, plan_id, ai.IDEMPOTENCY_WINDOW_SECONDS - 30)

    second = client.post("/api/v1/ai/plans", json=body)
    assert second.status_code == 200
    assert second.json()["id"] == plan_id


# --------------------------------------------------------------------------- #
# ③b different content (amount / source_text / action) → new plan
# --------------------------------------------------------------------------- #
def test_different_content_creates_new_plan(client) -> None:
    account = create_account(client)
    category = create_category(client)

    first = client.post(
        "/api/v1/ai/plans",
        json={"source_text": "午餐 88 元", "actions": [_entry_action(account["id"], category["id"], amount="88")]},
    )
    assert first.status_code == 201

    # Different amount → different payload → different fingerprint.
    diff_amount = client.post(
        "/api/v1/ai/plans",
        json={"source_text": "午餐 88 元", "actions": [_entry_action(account["id"], category["id"], amount="99")]},
    )
    assert diff_amount.status_code == 201
    assert diff_amount.json()["id"] != first.json()["id"]

    # Different source_text, same action → different fingerprint.
    diff_text = client.post(
        "/api/v1/ai/plans",
        json={"source_text": "晚餐 88 元", "actions": [_entry_action(account["id"], category["id"], amount="88")]},
    )
    assert diff_text.status_code == 201
    assert diff_text.json()["id"] != first.json()["id"]

    assert len(client.get("/api/v1/ai/plans").json()) == 3


# --------------------------------------------------------------------------- #
# ④ fingerprint stability — key order / excluded metadata / strip
# --------------------------------------------------------------------------- #
def test_fingerprint_is_stable_across_key_order_and_metadata() -> None:
    action_a = AIActionProposal.model_validate(
        {"action_type": "CreateEntry", "payload": {"a": "1", "b": {"x": 1, "y": 2}}}
    )
    # Same content, keys shuffled at both levels.
    action_b = AIActionProposal.model_validate(
        {"action_type": "CreateEntry", "payload": {"b": {"y": 2, "x": 1}, "a": "1"}}
    )
    fp_a = ai.compute_content_fingerprint("买咖啡 30 元", [action_a])
    fp_b = ai.compute_content_fingerprint("买咖啡 30 元", [action_b])
    assert fp_a == fp_b
    assert len(fp_a) == 64  # sha256 hex fits VARCHAR(64) exactly

    # explanation / confidence do not affect the ledger outcome → excluded.
    action_meta = AIActionProposal.model_validate(
        {"action_type": "CreateEntry", "payload": {"a": "1", "b": {"x": 1, "y": 2}}, "explanation": "x", "confidence": 0.4}
    )
    assert ai.compute_content_fingerprint("买咖啡 30 元", [action_meta]) == fp_a

    # source_text is stripped before hashing.
    assert ai.compute_content_fingerprint("  买咖啡 30 元  ", [action_a]) == fp_a

    # different action_type → different fingerprint.
    action_void = AIActionProposal.model_validate({"action_type": "VoidEntry", "payload": {"entry_id": "e1"}})
    assert ai.compute_content_fingerprint("买咖啡 30 元", [action_void]) != fp_a

    # empty-actions (pure text) marker is stable and distinct from any action.
    assert ai.compute_content_fingerprint("买咖啡 30 元", []) == ai.compute_content_fingerprint("买咖啡 30 元", [])
    assert ai.compute_content_fingerprint("买咖啡 30 元", []) != fp_a


# --------------------------------------------------------------------------- #
# ⑤ dedup returns an already-executed plan; second execute is state-gated (400)
#    → same-content create-then-execute is idempotent end-to-end (no double post)
# --------------------------------------------------------------------------- #
def test_dedup_returns_executed_plan_and_second_execute_is_gated(client) -> None:
    account = create_account(client)
    category = create_category(client)
    body = {"source_text": "午餐 88 元", "actions": [_entry_action(account["id"], category["id"])]}

    first = client.post("/api/v1/ai/plans", json=body)
    assert first.status_code == 201
    plan_id = first.json()["id"]
    assert first.json()["status"] == "auto_confirm_candidate"

    executed = client.post(f"/api/v1/ai/plans/{plan_id}/execute", json={})
    assert executed.status_code == 200
    assert executed.json()["status"] == "executed"
    balance_after_one = client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"]
    assert balance_after_one == "412.00"

    # Same content resubmit inside the window → the SAME (now executed) plan, 200.
    resubmit = client.post("/api/v1/ai/plans", json=body)
    assert resubmit.status_code == 200
    assert resubmit.json()["id"] == plan_id
    assert resubmit.json()["status"] == "executed"

    # Re-executing the deduped plan is blocked by the state gate → no double post.
    second_execute = client.post(f"/api/v1/ai/plans/{plan_id}/execute", json={})
    assert second_execute.status_code == 400
    assert second_execute.json()["detail"] == "AI plan has already been executed"

    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "412.00"


# --------------------------------------------------------------------------- #
# ⑥ root cause v3.0.0 重要-3: resubmit after a reject returns the SAME plan
#    (no new orphan minted) — the "at most one executable" invariant is now
#    server-side, not a best-effort client reject.
# --------------------------------------------------------------------------- #
def test_resubmit_after_reject_returns_same_plan_no_orphan(client) -> None:
    account = create_account(client)
    category = create_category(client)
    # amount > 1000 → medium risk → requires_confirmation (not auto-executable).
    body = {
        "source_text": "买电脑 5000 元",
        "actions": [_entry_action(account["id"], category["id"], amount="5000", title="Laptop")],
    }

    first = client.post("/api/v1/ai/plans", json=body)
    assert first.status_code == 201
    plan_id = first.json()["id"]
    assert first.json()["status"] == "requires_confirmation"

    rejected = client.post(f"/api/v1/ai/plans/{plan_id}/reject", json={})
    assert rejected.status_code == 200
    assert rejected.json()["status"] == "rejected"

    # Resubmit same content within window → SAME plan id, no fresh orphan.
    resubmit = client.post("/api/v1/ai/plans", json=body)
    assert resubmit.status_code == 200
    assert resubmit.json()["id"] == plan_id
    assert resubmit.json()["status"] == "rejected"
    assert len(client.get("/api/v1/ai/plans").json()) == 1

    # And the reused rejected plan cannot be executed (terminal state gate).
    execute_attempt = client.post(f"/api/v1/ai/plans/{plan_id}/execute", json={})
    assert execute_attempt.status_code == 400
    assert execute_attempt.json()["detail"] == "Final AI plans cannot be executed"


# --------------------------------------------------------------------------- #
# migration-chain: content_fingerprint column + non-unique index reach head
# --------------------------------------------------------------------------- #
def test_ai_plan_migration_adds_fingerprint_column_and_index(tmp_path, monkeypatch) -> None:
    from alembic import command
    from alembic.config import Config
    from sqlalchemy import create_engine, inspect

    from app.core.config import get_settings

    db_path = tmp_path / "p1_fingerprint.db"
    url = f"sqlite+pysqlite:///{db_path}"
    monkeypatch.setenv("LINOFINANCE_DATABASE_URL", url)
    get_settings.cache_clear()
    engine = create_engine(url)

    # Build the schema the way the app does (create_all already makes the column
    # + index), stamp at the prior head, then upgrade the last hop to head; the
    # add-column / add-index guards must keep this migration a no-op on this path.
    from app.db.base import Base

    Base.metadata.create_all(bind=engine)
    cfg = Config("alembic.ini")
    command.stamp(cfg, "202607100001")
    command.upgrade(cfg, "head")

    inspector = inspect(engine)
    columns = {c["name"] for c in inspector.get_columns("ai_plans")}
    assert "content_fingerprint" in columns
    index_columns = [ix["column_names"] for ix in inspector.get_indexes("ai_plans")]
    assert ["content_fingerprint"] in index_columns
    # The idempotency index must be non-unique (dedup lives in the query).
    fingerprint_indexes = [
        ix for ix in inspector.get_indexes("ai_plans") if ix["column_names"] == ["content_fingerprint"]
    ]
    assert fingerprint_indexes and all(not ix["unique"] for ix in fingerprint_indexes)

    get_settings.cache_clear()
