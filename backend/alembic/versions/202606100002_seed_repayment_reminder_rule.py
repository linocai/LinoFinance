"""seed default credit-repayment reminder NotificationRule

Revision ID: 202606100002
Revises: 202606100001
Create Date: 2026-06-10

Idempotently seeds one default repayment-reminder ``NotificationRule`` so the
scheduled credit-due reminder pipeline (``dispatch_due_credit_reminders`` ->
``_matching_rules``) has an active rule to match (audit 2.8). The matcher in
``push_dispatch.py`` requires ``status='active'``, ``rule_type='credit_repayment'``,
``channel='system'`` and an empty/subset ``trigger_payload`` (empty matches any
credit-due event).

Idempotent: if any ``credit_repayment`` / ``system`` rule already exists this
migration inserts nothing, so re-running upgrades (or running against a DB that
already has such a rule via the API) leaves the table unchanged.
"""
import json
from uuid import uuid4

from alembic import op
import sqlalchemy as sa

revision = "202606100002"
down_revision = "202606100001"
branch_labels = None
depends_on = None

SEED_TITLE = "信用卡还款提醒"
SEED_NOTE = "Seeded by v1.3.0 migration (audit 2.8); credit due T-5/3/1/0 reminders."


def _existing_repayment_rule_count(bind) -> int:
    return bind.execute(
        sa.text(
            "SELECT COUNT(*) FROM notification_rules "
            "WHERE rule_type = 'credit_repayment' AND channel = 'system'"
        )
    ).scalar_one()


def upgrade() -> None:
    bind = op.get_bind()
    if _existing_repayment_rule_count(bind) > 0:
        # A matching rule is already present (re-run or API-created); skip.
        return

    bind.execute(
        sa.text(
            "INSERT INTO notification_rules "
            "(id, title, rule_type, channel, trigger_payload, status, note, "
            " created_at, updated_at) "
            "VALUES "
            "(:id, :title, 'credit_repayment', 'system', :trigger_payload, "
            " 'active', :note, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
        ),
        {
            "id": str(uuid4()),
            "title": SEED_TITLE,
            # trigger_payload is a JSON column; empty object matches any
            # credit-due event payload (no extra filtering keys).
            "trigger_payload": json.dumps({}),
            "note": SEED_NOTE,
        },
    )


def downgrade() -> None:
    bind = op.get_bind()
    bind.execute(
        sa.text(
            "DELETE FROM notification_rules "
            "WHERE rule_type = 'credit_repayment' AND channel = 'system' "
            "AND title = :title AND note = :note"
        ),
        {"title": SEED_TITLE, "note": SEED_NOTE},
    )
