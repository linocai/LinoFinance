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
  - `GET /entries`
  - `POST /entries`
  - `POST /entries/{entry_id}/confirm`
  - `POST /entries/{entry_id}/void`
  - `GET /dashboard/summary`
- Planned next:
  - Expand `GET /dashboard/summary` into richer report cards after Phase 1 entries settle.
  - Add entry update/edit endpoints after basic create/confirm/void semantics are stable.

## Entry Rules Implemented

- `draft` entries can be incomplete and do not affect account balances.
- `confirmed` entries must include account movements.
- Confirmed non-transfer entries must include category lines.
- Expense category totals must match `balance_out + credit_charge` movement totals in CNY.
- Income category totals must match `balance_in` movement totals in CNY.
- CNY amounts convert to themselves.
- Non-CNY amounts use the latest available rate on or before the entry date.
- Voiding a confirmed entry reverses its balance/liability effect.
- Credit card charges increase `current_liability`; credit repayment decreases it and is treated as transfer movement.

## Domain Rules For API Design

- The backend computes balances and report aggregates.
- Clients send original amount, currency, account movement, and category line data.
- Confirmed records must be complete before they can affect balances or reports.
- Draft records can be incomplete and must not affect balances or official reports.
- Credit card repayment is a transfer, not spending.
- AI-generated mutations must be represented as structured actions before execution.
