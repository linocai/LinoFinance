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
  - `GET /credit-statement-cycles`
  - `POST /credit-statement-cycles`
  - `GET /credit-statement-cycles/{cycle_id}`
  - `GET /cash-flow-items`
  - `POST /cash-flow-items`
  - `GET /cash-flow-items/{item_id}`
  - `POST /cash-flow-items/{item_id}/confirm`
  - `POST /cash-flow-items/{item_id}/cancel`
  - `POST /cash-flow-items/{item_id}/settle`
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
- Credit card charges must belong to a `CreditStatementCycle`.
- If a credit charge omits `statement_cycle_id`, the backend auto-assigns the matching cycle by account and entry date.
- Credit card repayments must explicitly provide `statement_cycle_id`.
- Credit card charges increase a cycle's `statement_amount`; repayments increase its `paid_amount`.
- Voiding confirmed credit charges or repayments rolls back both account balances and cycle amounts.
- Credit repayment entries should use `transfer_out` for the balance account side and `credit_repayment` for the credit account side.
- Credit statement cycles create/update linked repayment cash-flow items when statement amount changes.

## Cash Flow Rules Implemented

- Cash-flow items represent future expectations and do not affect account balances.
- Supported statuses: `expected`, `confirmed`, `settled`, `cancelled`, `partial`.
- V1 create API accepts `expected` and `confirmed`; `partial` is reserved for later partial settlement workflows.
- `confirm` changes an `expected` item to `confirmed`.
- `cancel` is allowed only before settlement.
- `settle` requires an explicit formal entry payload and creates a confirmed `FinancialEntry`.
- Only the settled formal entry affects account balances and reports.
- Credit statement cycles generate `credit_repayment` cash-flow items.
- Fully repaid credit statement cycles mark the linked repayment cash flow as `settled`.

## Domain Rules For API Design

- The backend computes balances and report aggregates.
- Clients send original amount, currency, account movement, and category line data.
- Confirmed records must be complete before they can affect balances or reports.
- Draft records can be incomplete and must not affect balances or official reports.
- Credit card repayment is a transfer, not spending.
- AI-generated mutations must be represented as structured actions before execution.
