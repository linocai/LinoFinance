from datetime import date as DateType
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


class ReconciliationAccountRead(BaseModel):
    account_id: str
    account_name: str
    account_type: str
    currency: str
    expected_amount: Decimal
    current_amount: Decimal
    delta_amount: Decimal
    needs_adjustment: bool


class ReconciliationAccountsResponse(BaseModel):
    threshold: Decimal
    items: List[ReconciliationAccountRead]


class AccountAdjustmentCreate(BaseModel):
    account_id: str
    actual_amount: Optional[Decimal] = None
    reason: str = Field(default="reconciliation", max_length=120)
    note: Optional[str] = None
    created_by: str = Field(default="system", max_length=120)


class AccountAdjustmentRead(BaseModel):
    id: str
    account_id: str
    reason: str
    delta_amount: Decimal
    currency: str
    balance_before: Decimal
    balance_after: Decimal
    source: str
    note: Optional[str] = None
    created_by: str

    model_config = ConfigDict(from_attributes=True)


# --- v2.2.0 P2 · 对账一致性/冲突检测器 (PROJECT_PLAN §5.4) -------------------


class ConflictPointer(BaseModel):
    """A jump-to pointer at the offending record (前端导航用)."""

    type: str  # credit_statement_cycle | cash_flow_item | reimbursement_claim | account
    id: str
    label: str


class ReconciliationConflict(BaseModel):
    code: str  # credit_three_way | statement_cashflow | balance_external | orphan
    severity: str  # conflict（红） | info（仅展示拆解）
    title: str
    # R1 信用三数拆解（仅 credit_three_way 填）。
    stored_liability: Optional[Decimal] = None
    sum_open_statements: Optional[Decimal] = None
    unbilled_charges: Optional[Decimal] = None
    expected_liability: Optional[Decimal] = None
    # R3 余额外部真相（仅 balance_external 填）。
    stored_balance: Optional[Decimal] = None
    external_actual: Optional[Decimal] = None
    # stored − expected（R1） / stored − external_actual（R3），其他项可省。
    delta: Optional[Decimal] = None
    # 该冲突 delta 的币种（前端按此渲染符号，外币卡才不会误标 ¥；reviewer B2）。
    currency: Optional[str] = None
    detail: Optional[str] = None
    offending: List[ConflictPointer] = Field(default_factory=list)
    # internal_recompute | jump_record | external_actual | none
    fix: str = "none"


class ReconciliationBreakdown(BaseModel):
    """R1 三数拆解（界面三数展示用，仅信用账户填）。"""

    stored_liability: Decimal
    open_statements_total: Decimal
    unbilled_charges: Decimal


class ReconciliationCheckAccount(BaseModel):
    account_id: str
    account_name: str
    account_type: str
    currency: str
    has_conflicts: bool
    conflicts: List[ReconciliationConflict] = Field(default_factory=list)
    breakdown: Optional[ReconciliationBreakdown] = None


class ReconciliationCheckResponse(BaseModel):
    checked_at: DateType
    has_conflicts: bool
    accounts: List[ReconciliationCheckAccount]
    # R4 孤儿/状态一致性 — 不绑某一账户的全局孤儿（现金流/报销/周期）。
    orphans: List[ReconciliationConflict] = Field(default_factory=list)


class CreditRecomputeResponse(BaseModel):
    account_id: str
    account_name: str
    stored_liability_before: Decimal
    recomputed_liability: Decimal
    delta: Decimal
    adjustment_id: Optional[str] = None
