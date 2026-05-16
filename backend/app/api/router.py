from fastapi import APIRouter

from app.api.routes import (
    accounts,
    ai,
    audit_logs,
    cash_flow,
    categories,
    credit_statement_cycles,
    currency_rates,
    dashboard,
    entries,
    health,
    installments,
    notification_rules,
    reimbursements,
    subscriptions,
)

api_router = APIRouter()
api_router.include_router(accounts.router, prefix="/accounts", tags=["accounts"])
api_router.include_router(ai.router, prefix="/ai", tags=["ai"])
api_router.include_router(audit_logs.router, prefix="/audit-logs", tags=["audit-logs"])
api_router.include_router(cash_flow.router, prefix="/cash-flow-items", tags=["cash-flow"])
api_router.include_router(categories.router, prefix="/categories", tags=["categories"])
api_router.include_router(
    credit_statement_cycles.router,
    prefix="/credit-statement-cycles",
    tags=["credit-statement-cycles"],
)
api_router.include_router(currency_rates.router, prefix="/currency-rates", tags=["currency-rates"])
api_router.include_router(entries.router, prefix="/entries", tags=["entries"])
api_router.include_router(dashboard.router, prefix="/dashboard", tags=["dashboard"])
api_router.include_router(installments.router, prefix="/installment-plans", tags=["installments"])
api_router.include_router(
    notification_rules.router,
    prefix="/notification-rules",
    tags=["notification-rules"],
)
api_router.include_router(reimbursements.router, prefix="/reimbursement-claims", tags=["reimbursements"])
api_router.include_router(subscriptions.router, prefix="/subscription-rules", tags=["subscriptions"])
api_router.include_router(health.router, tags=["health"])
