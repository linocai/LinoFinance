# API Contract Notes

Base path: `/api/v1`

## Phase 8 Transport Rules

- `GET /health`, OpenAPI, and docs routes are public.
- Non-public routes require `Authorization: Bearer <token>` when
  `LINOFINANCE_API_AUTH_TOKEN` is configured.
- Production startup requires `LINOFINANCE_API_AUTH_TOKEN`.
- Rate limiting is enabled when `LINOFINANCE_API_RATE_LIMIT_ENABLED=true` or
  `LINOFINANCE_ENVIRONMENT=production`.
- Responses include `x-request-id`; rate-limited responses return `429` with
  `Retry-After`, `X-RateLimit-Limit`, and `X-RateLimit-Remaining`.

## Health

`GET /health`

Response:

```json
{
  "status": "ok",
  "app": "LinoFinance API",
  "version": "0.1.0",
  "environment": "local",
  "auth_required": false,
  "rate_limit_enabled": false
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
  - `GET /reimbursement-claims`
  - `POST /reimbursement-claims`
  - `GET /reimbursement-claims/{claim_id}`
  - `POST /reimbursement-claims/{claim_id}/submit`
  - `POST /reimbursement-claims/{claim_id}/approve`
  - `POST /reimbursement-claims/{claim_id}/reject`
  - `POST /reimbursement-claims/{claim_id}/abandon`
  - `POST /reimbursement-claims/{claim_id}/mark-received`
  - `GET /installment-plans`
  - `POST /installment-plans`
  - `GET /installment-plans/{plan_id}`
  - `POST /installment-plans/{plan_id}/cancel`
  - `POST /installment-plans/{plan_id}/mark-paid-off`
  - `POST /installment-plans/{plan_id}/mark-early-paid-off`
  - `GET /subscription-rules`
  - `POST /subscription-rules`
  - `GET /subscription-rules/{rule_id}`
  - `POST /subscription-rules/{rule_id}/pause`
  - `POST /subscription-rules/{rule_id}/resume`
  - `POST /subscription-rules/{rule_id}/cancel`
  - `POST /subscription-rules/{rule_id}/generate-next`
  - `GET /ai/config`
  - `GET /ai/plans`
  - `POST /ai/plans`
  - `GET /ai/plans/{plan_id}`
  - `POST /ai/plans/{plan_id}/approve`
  - `POST /ai/plans/{plan_id}/reject`
  - `POST /ai/plans/{plan_id}/execute`
  - `POST /ai/actions/{action_id}/rollback`
  - `GET /notification-rules`
  - `POST /notification-rules`
  - `GET /notification-rules/{rule_id}`
  - `POST /notification-rules/{rule_id}/pause`
  - `POST /notification-rules/{rule_id}/resume`
  - `POST /notification-rules/{rule_id}/cancel`
  - `GET /audit-logs`
  - `GET /reports/monthly-overview`
  - `GET /reports/category-expenses`
  - `GET /reports/cash-flow-pressure`
  - `GET /reports/credit-liability-trend`
  - `GET /reports/reimbursements`
  - `GET /reports/subscriptions`
  - `GET /exports/csv`
  - `GET /exports/csv/{dataset}`
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

## Reimbursement Rules Implemented

- Confirmed reimbursable entry category lines auto-create reimbursement claims.
- Reimbursable lines require `reimbursement_expected_date` before an entry can be confirmed.
- Draft reimbursable entries do not create claims until confirmation.
- Each claim creates a linked `reimbursement` cash-flow inflow.
- Submitted/reimbursable claims keep the linked cash flow `expected`.
- Approved/waiting-received claims mark the linked cash flow `confirmed`.
- Received claims require a confirmed formal income entry payload via `mark-received`.
- Received reimbursement entries must include a matching `balance_in` movement and matching income category line.
- Voiding the original confirmed reimbursable expense abandons open claims and cancels their reimbursement cash flows.

## Installment And Subscription Rules Implemented

- Installment plans require a confirmed linked entry with a matching credit-card charge.
- Installment currency must match the linked credit account currency.
- Active installment plans generate one `installment` cash-flow item per payment period.
- Installment cash-flow items are `transfer` direction and do not create duplicate spending.
- Cancelling, marking paid off, or marking early paid off cancels open installment cash-flow items.
- Subscription rules support `weekly`, `monthly`, and `yearly` billing intervals.
- Active subscription rules generate the next `subscription` cash-flow item.
- Subscription cash-flow items are future outflows and do not affect balances until settled.
- Settling a subscription cash-flow item creates the formal confirmed entry, advances `next_charge_date`, and generates the next expected subscription cash flow.
- Paused subscriptions do not auto-advance on settlement; cancelled subscriptions cancel open generated cash flows.

## AI And Notification Rules Implemented

- AI provider settings are read from `.env` via `LINOFINANCE_AI_*` variables.
- Secrets are not returned by `GET /ai/config`; it only reports whether a key/base URL exists.
- AI plans are stored as structured actions before execution.
- Supported action protocol values include `CreateEntry`, `CreateCashFlowItem`, `MarkReimbursable`, `CreateInstallmentPlan`, `RecordCreditRepayment`, `GenerateNotificationRule`, and `VoidEntry`.
- Low-risk `CreateEntry` actions are complete CNY actions with amount less than or equal to `1000 CNY`; they become `auto_confirm_candidate`.
- Medium-risk actions require approval before execution.
- High-risk actions, such as `VoidEntry`, require approval and `strong_confirm = "EXECUTE_HIGH_RISK"`.
- AI executions write `AuditLog` records with before/after snapshots where available.
- Executed AI-created entries can be rolled back by voiding the generated entry.
- Executed AI-created cash-flow items and notification rules can be rolled back by cancellation when still eligible.
- Notification rules support `credit_repayment`, `cash_flow`, `reimbursement`, `subscription`, and `anomaly`.
- Notification channels support `in_app`, `system`, and `email`; client delivery is future frontend work.

## Report And CSV Export Rules Implemented

- Reports are backend-computed read models over confirmed ledger records and active future cash flows.
- Report date filters use inclusive `date_from` / `date_to` boundaries.
- Monthly overview includes income, expense, reimbursement offsets, future cash-flow pressure, and active credit liability in CNY.
- Category expense reports group confirmed expense category lines and include original-currency totals plus CNY totals.
- Cash-flow pressure reports summarize active `expected`, `confirmed`, and `partial` cash flows for 7/30/90 day windows.
- Transfer-direction future cash flows, such as credit repayment and installments, count as outflow pressure.
- Credit liability trend reports summarize statement cycles by statement date and include remaining original-currency and CNY amounts.
- Reimbursement reports support `pre_reimbursement`, `expected_net`, `approved_net`, `received_net`, and `personal_net` views.
- Subscription reports project active weekly/monthly/yearly rules into monthly and annual CNY equivalents.
- CSV export is V1-only CSV; each dataset endpoint returns `text/csv`.
- Export datasets include core ledger tables, cash-flow/reimbursement/credit/installment/subscription tables, AI/action/audit tables, and notification rules.
- CSV amount rows preserve original amount/currency fields and CNY conversion columns where the underlying table has them.

## Domain Rules For API Design

- The backend computes balances and report aggregates.
- Clients send original amount, currency, account movement, and category line data.
- Confirmed records must be complete before they can affect balances or reports.
- Draft records can be incomplete and must not affect balances or official reports.
- Credit card repayment is a transfer, not spending.
- AI-generated mutations must be represented as structured actions before execution.

## V1.1 Foundation Endpoints

- `GET /search?q=&limit=&types=` returns `{query, limit, items}` with cross-module hits for accounts, entries, cash-flow items, reimbursement claims, AI plans, and notification rules. `types` is a comma-separated filter.
- `POST /attachments` accepts multipart fields `owner_type`, `owner_id`, optional `uploaded_by`/`note`, and `file`. Supported owners are `entry_category_line`, `reimbursement_claim`, and `ai_action`. Files are stored under `LINOFINANCE_STORAGE_ROOT` with a relative `storage_key`, sha256 checksum, 10 MB per file, and 25 MB total for reimbursement owners.
- `GET /attachments/{id}` streams the stored file; `DELETE /attachments/{id}` soft-deletes metadata and removes the local file.
- `GET /reconciliation/accounts` returns expected amount, current amount, delta, and `needs_adjustment` per account using movements, credit cycles, and reconciliation adjustments.
- `POST /reconciliation/adjustments` creates an account adjustment against an observed `actual_amount`, updates the account's current balance/liability, and returns the adjustment row.
- `GET /ai/memos?period=YYYY-MM` lists non-archived AI memo records. `POST /ai/memos/generate` creates a memo from report aggregates and the configured AI provider. `PATCH /ai/memos/{id}` updates summary/status. `DELETE /ai/memos/{id}` archives the memo.
- `POST /push/devices` idempotently registers an iOS/macOS APNs device by `(platform, apns_token)`. `DELETE /push/devices/{id}` disables the device. Actual APNs delivery is reserved for a later phase.
