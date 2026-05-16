from fastapi import APIRouter

from app.api.routes import (
    accounts,
    categories,
    credit_statement_cycles,
    currency_rates,
    dashboard,
    entries,
    health,
)

api_router = APIRouter()
api_router.include_router(accounts.router, prefix="/accounts", tags=["accounts"])
api_router.include_router(categories.router, prefix="/categories", tags=["categories"])
api_router.include_router(
    credit_statement_cycles.router,
    prefix="/credit-statement-cycles",
    tags=["credit-statement-cycles"],
)
api_router.include_router(currency_rates.router, prefix="/currency-rates", tags=["currency-rates"])
api_router.include_router(entries.router, prefix="/entries", tags=["entries"])
api_router.include_router(dashboard.router, prefix="/dashboard", tags=["dashboard"])
api_router.include_router(health.router, tags=["health"])
