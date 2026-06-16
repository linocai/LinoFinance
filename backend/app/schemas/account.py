from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator


class AccountCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    type: str = Field(pattern="^(balance|credit|investment)$")
    currency: str = Field(min_length=3, max_length=3)
    current_balance: Decimal = Decimal("0")
    current_liability: Decimal = Decimal("0")
    include_in_net_worth: bool = True
    status: str = "active"
    display_order: int = 0
    credit_limit: Optional[Decimal] = None
    statement_day: Optional[int] = Field(default=None, ge=1, le=31)
    due_day: Optional[int] = Field(default=None, ge=1, le=31)
    minimum_payment: Optional[Decimal] = None
    notes: Optional[str] = None

    @model_validator(mode="after")
    def _credit_liability_is_derived(self) -> "AccountCreate":
        # v2.2.0 P1 (D1=甲): ``current_liability`` is a *derived* value computed
        # from the account's statement cycles, never a free opening number. An
        # opening credit balance must be expressed by creating an opening
        # statement cycle (so it is covered by ``Σcycle`` and can never drift —
        # PROJECT_PLAN §5.2 病灶 A). A non-zero opening liability on a credit
        # account is therefore rejected.
        if self.type == "credit" and self.current_liability != Decimal("0"):
            raise ValueError(
                "Credit accounts cannot be created with a non-zero "
                "current_liability; express an opening balance by creating an "
                "opening statement cycle instead"
            )
        return self

    def model_dump(self, *args, **kwargs):
        data = super().model_dump(*args, **kwargs)
        data["currency"] = data["currency"].upper()
        # Credit liability is always derived from cycles, never seeded; force the
        # stored column to 0 at creation regardless of input default.
        if data.get("type") == "credit":
            data["current_liability"] = Decimal("0")
        return data


class AccountUpdate(BaseModel):
    """Patch a subset of editable account fields (audit 2.5).

    Immutable fields (``type`` / ``currency`` / ``current_balance`` /
    ``current_liability``) are intentionally absent from this schema; balance
    changes flow through reconciliation adjustments. Uses ``model_fields_set``
    in the service to distinguish "field absent" from "field set to null".
    """

    model_config = ConfigDict(extra="forbid")

    name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    include_in_net_worth: Optional[bool] = None
    status: Optional[str] = None
    display_order: Optional[int] = None
    credit_limit: Optional[Decimal] = None
    statement_day: Optional[int] = Field(default=None, ge=1, le=31)
    due_day: Optional[int] = Field(default=None, ge=1, le=31)
    minimum_payment: Optional[Decimal] = None
    notes: Optional[str] = None


class AccountRead(BaseModel):
    id: str
    name: str
    type: str
    currency: str
    current_balance: Decimal
    current_liability: Decimal
    include_in_net_worth: bool
    status: str
    display_order: int
    credit_limit: Optional[Decimal] = None
    statement_day: Optional[int] = None
    due_day: Optional[int] = None
    minimum_payment: Optional[Decimal] = None
    notes: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

