# API Contract Notes

Base path: `/api/v1`

## Health

`GET /health`

Response:

```json
{
  "status": "ok",
  "app": "LinoFinance API",
  "version": "0.1.0",
  "environment": "local"
}
```

## Phase 1 Planned Endpoints

- Implemented:
  - `GET /accounts`
  - `POST /accounts`
  - `GET /accounts/{account_id}`
  - `GET /categories`
  - `POST /categories`
  - `GET /categories/{category_id}`
  - `GET /currency-rates`
  - `POST /currency-rates`
  - `GET /currency-rates/{currency_rate_id}`
- Planned next:
  - `GET /entries`
  - `POST /entries`
  - `POST /entries/{entry_id}/confirm`
  - `POST /entries/{entry_id}/void`
  - `GET /dashboard/summary`

## Domain Rules For API Design

- The backend computes balances and report aggregates.
- Clients send original amount, currency, account movement, and category line data.
- Confirmed records must be complete before they can affect balances or reports.
- Draft records can be incomplete and must not affect balances or official reports.
- Credit card repayment is a transfer, not spending.
- AI-generated mutations must be represented as structured actions before execution.
