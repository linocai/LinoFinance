import csv
import io
import json
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, Type

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.ai import AIAction, AIActionExecution, AIPlan
from app.models.audit_log import AuditLog
from app.models.cash_flow import CashFlowItem
from app.models.credit_statement_cycle import CreditStatementCycle
from app.models.entry import AccountMovement, EntryCategoryLine, FinancialEntry
from app.models.installment import InstallmentPlan
from app.models.notification import NotificationRule
from app.models.reimbursement import ReimbursementClaim
from app.models.subscription import SubscriptionRule
from app.schemas.entry import format_decimal
from app.schemas.report import ExportDataset, ExportDatasetList
from app.services.ledger import LedgerValidationError


DATASET_MODELS: Dict[str, Type] = {
    "entries": FinancialEntry,
    "entry_category_lines": EntryCategoryLine,
    "account_movements": AccountMovement,
    "accounts": Account,
    "cash_flow_items": CashFlowItem,
    "reimbursement_claims": ReimbursementClaim,
    "credit_statement_cycles": CreditStatementCycle,
    "installment_plans": InstallmentPlan,
    "subscription_rules": SubscriptionRule,
    "audit_logs": AuditLog,
    "ai_plans": AIPlan,
    "ai_actions": AIAction,
    "ai_action_executions": AIActionExecution,
    "notification_rules": NotificationRule,
}


def list_export_datasets() -> ExportDatasetList:
    return ExportDatasetList(
        datasets=[
            ExportDataset(name=name, filename=f"{name}.csv")
            for name in sorted(DATASET_MODELS.keys())
        ]
    )


def export_dataset_csv(db: Session, dataset: str) -> str:
    model = DATASET_MODELS.get(dataset)
    if model is None:
        raise LedgerValidationError("Unsupported export dataset")

    columns = list(model.__table__.columns)
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([column.name for column in columns])
    rows = db.execute(select(model).order_by(model.created_at.asc())).scalars()
    for row in rows:
        writer.writerow([_csv_value(getattr(row, column.name)) for column in columns])
    return output.getvalue()


def csv_filename(dataset: str) -> str:
    if dataset not in DATASET_MODELS:
        raise LedgerValidationError("Unsupported export dataset")
    return f"{dataset}.csv"


def _csv_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, Decimal):
        return format_decimal(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)
