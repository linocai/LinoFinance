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

## Auth — Sign in with Apple (single-user gate)

`POST /auth/apple` (public — no token required; this is the bootstrap)

Request:

```json
{
  "identity_token": "<Apple identity JWT>",
  "device_label": "iPhone Air",
  "platform": "ios",
  "app_version": "1.3.0",
  "first_name": null,
  "last_name": null
}
```

Single-user gate (v1.3.0): LinoFinance is a single-user ledger. Access is gated
by the Apple `sub`:

- The **first** Apple `sub` to ever sign in (empty `users` table) is created
  active and receives a session — bootstrapping the owner.
- After that, any **new** `sub` is recorded as `disabled=True` (the row is
  persisted for ops to inspect) and is refused a session.
- A `sub` listed in `LINOFINANCE_APPLE_SUB_ALLOWLIST` (comma-separated, may be
  empty) self-activates even when the table is non-empty — the escape hatch for
  migrating to a new Apple ID. Look up your own `sub` in the `apple_user_id`
  field of `GET /auth/me`.
- A session whose user is later disabled (ops `UPDATE users SET disabled=true`)
  is rejected on its very next request — every gated route returns `401`.

Responses:

- `200` — `{ "session_token", "expires_at", "user" }`. The plaintext token is
  returned exactly once.
- `400` — invalid platform or unverifiable Apple identity token.
- `403` — `{ "detail": "User is disabled" }`: the `sub` is not the bootstrap
  user and not allowlisted (or was explicitly disabled).

Activation / disabling is an ops action (no admin API in v1.3.0); see
`docs/deployment.md` for the psql commands.

## Health

`GET /health`

Response:

```json
{
  "status": "ok",
  "app": "LinoFinance API",
  "version": "1.1.0",
  "environment": "local",
  "auth_required": false,
  "rate_limit_enabled": false,
  "apns_use_sandbox": true,
  "apns_dry_run": false
}
```

## Phase 1 Planned Endpoints

- Implemented:
  - `GET /accounts`
  - `POST /accounts`
  - `GET /accounts/{account_id}`
  - `PATCH /accounts/{account_id}` (v1.3.0)
  - `GET /categories`
  - `POST /categories`
  - `GET /categories/{category_id}`
  - `PATCH /categories/{category_id}` (v1.3.0)
  - `GET /currency-rates`
  - `POST /currency-rates`
  - `GET /currency-rates/{currency_rate_id}`
  - `PATCH /currency-rates/{currency_rate_id}` (v1.3.0)
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
- `POST /credit-statement-cycles` rejects a cycle whose `[cycle_start_date, cycle_end_date]`
  interval overlaps an existing (non-`voided`) cycle for the same credit account, returning
  `400` (v1.3.0, audit 2.6). Two inclusive intervals overlap iff
  `new_start <= other_end AND other_start <= new_end`. This keeps the credit-charge
  auto-assignment (which picks the most recent cycle by `cycle_start_date`) unambiguous;
  the auto-assignment logic itself is unchanged.

## Cash Flow Rules Implemented

- Cash-flow items represent future expectations and do not affect account balances.
- Supported statuses: `expected`, `confirmed`, `settled`, `cancelled`, `partial`.
- V1 create API accepts `expected` and `confirmed`; `partial` is reserved for later partial settlement workflows.
- `confirm` changes an `expected` item to `confirmed`.
- `cancel` is allowed only before settlement.
- `settle` requires an explicit formal entry payload and creates a confirmed `FinancialEntry`.
- `settle` returns `400` for a reimbursement-linked item (`linked_reimbursement_id`
  is set): those receivables settle only through the claim's `mark-received`
  action, which generates exactly one income entry. The generic settle path is
  blocked to prevent a second, double-counted entry (v1.3.0, audit 1.3).
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
- `GET /ai/plans` accepts additive filters `related_type` and `related_to`, matching executed action targets without changing the existing `status` filter.
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
- `GET /dashboard/summary` `today_pnl_by_currency` is the sum of `investment_daily`
  `AccountAdjustment` deltas whose adjustment day equals "today" in the business timezone
  (`LINOFINANCE_APP_TIMEZONE`, default Asia/Shanghai; v1.3.0, audit 2.3/2.17). It is a
  **source-filtered delta accumulation**, not a "last balance − first balance": multiple
  daily-pnl quick-records on the same investment account/day net to the same first-to-last
  difference, while reconciliation adjustments and transfer movements are excluded entirely. A
  currency that had at least one daily-pnl row today appears with amount `0` rather than being
  omitted. "Today" and the per-day bucketing of UTC-naive `created_at` both resolve in the
  business timezone, so records near the UTC day boundary land on the correct local day.
- Monthly overview includes income, expense, reimbursement offsets, future cash-flow pressure, and active credit liability in CNY.
- Monthly overview `personal_net_expense_cny = expense_cny - expected_reimbursement_cny` is a
  **full-expense口径**: it nets against *all* expenses in the window, not only the reimbursable
  ones. The reimbursement report's `personal_net` view (= `expected_net` = `gross - expected`)
  uses the **reimbursable-only gross口径**. These two "personal net" figures are intentionally
  different track and can diverge whenever non-reimbursable expenses exist in the window
  (v1.3.0, audit 2.2 double-track note).
- Category expense reports group confirmed expense category lines and include original-currency totals plus CNY totals.
- Cash-flow pressure reports summarize active `expected`, `confirmed`, and `partial` cash flows for 7/30/90 day windows.
- Cash-flow pressure responses include additive `daily_net_cny` rows for the next 30 days: `{date, inflow_cny, outflow_cny, net_cny}`.
- Transfer-direction future cash flows, such as credit repayment and installments, count as outflow pressure.
- Credit liability trend reports summarize statement cycles by statement date and include remaining original-currency and CNY amounts.
- Reimbursement reports support `pre_reimbursement`, `expected_net`, `approved_net`, `received_net`, and `personal_net` views.
- All five reimbursement views — including the `received_offset` accumulator — anchor on the
  claim's **original expense date** (the linked entry's date), not on the cash-received date
  (v1.3.0, audit 2.2). A claim contributes to a report window iff its original expense date
  falls in `[date_from, date_to]`; gross, expected, approved, and received offsets are then all
  measured against that same window. This eliminates the prior cross-month mismatch where an
  expense in month M received in month M+1 produced a spurious negative net in M+1 (zero gross
  minus a dangling received offset). The monthly-overview reimbursement offsets follow the same
  original-date anchor.
- Subscription reports project active weekly/monthly/yearly rules into monthly and annual CNY equivalents.
- CSV export is V1-only CSV; each dataset endpoint returns `text/csv`.
- Export datasets include core ledger tables, cash-flow/reimbursement/credit/installment/subscription tables, AI/action/audit tables, and notification rules. As of v1.3.0 (audit 2.7) the set also includes `categories`, `currency_rates`, `account_adjustments`, and `attachments` (attachment rows are metadata only — `storage_key`/`checksum_sha256`/etc; the file body is never part of the CSV), so exported `category_id`/`exchange_rate_id` references resolve within the export.
- CSV amount rows preserve original amount/currency fields and CNY conversion columns where the underlying table has them.
- `GET /audit-logs` accepts optional `limit` in addition to `target_type` and `target_id`; this is used by inspector surfaces for small recent-audit cards.

## Domain Rules For API Design

- The backend computes balances and report aggregates.
- Clients send original amount, currency, account movement, and category line data.
- Confirmed records must be complete before they can affect balances or reports.
- Draft records can be incomplete and must not affect balances or official reports.
- Credit card repayment is a transfer, not spending.
- AI-generated mutations must be represented as structured actions before execution.

## V1.1 Foundation Endpoints

- `GET /search?q=&limit=&types=` returns `{query, limit, items}` with cross-module hits for accounts, entries, cash-flow items, reimbursement claims, AI plans, and notification rules. `types` is a comma-separated filter.
- `POST /attachments` accepts multipart fields `owner_type`, `owner_id`, optional `uploaded_by`/`note`, and `file`. Supported owners are `entry_category_line`, `reimbursement_claim`, and `ai_action`. As of v1.3.0 (audit 2.4) the `(owner_type, owner_id)` pair must reference an existing entity or the upload returns `404`. Files are stored under `LINOFINANCE_STORAGE_ROOT` with a relative `storage_key`, sha256 checksum, 10 MB per file, and 25 MB total for reimbursement owners.
- `GET /attachments?owner_type=&owner_id=` returns undeleted attachments for an owner. `GET /attachments/{id}` streams the stored file. `DELETE /attachments/{id}` soft-deletes metadata and keeps the local file until scheduled cleanup removes files older than 30 days.
- `GET /reconciliation/accounts` returns expected amount, current amount, delta, and `needs_adjustment` per account using movements, credit cycles, and reconciliation adjustments.
- `POST /reconciliation/adjustments` creates an account adjustment against an observed `actual_amount`, updates the account's current balance/liability, writes an `account_adjustment.create` audit log, and returns the adjustment row.
- `GET /ai/memos?period=YYYY-MM` lists non-archived AI memo records. `POST /ai/memos/generate?tone=warm|terse|playful|professional` creates or updates the active memo for a period from report aggregates and the configured AI provider. The response includes additive `created_at` / `updated_at` timestamps and stores full stats JSON for overview, top categories, subscriptions, credit liabilities, reimbursements, and anomalies. `PATCH /ai/memos/{id}` updates summary/status. `DELETE /ai/memos/{id}` archives the memo.
- `POST /push/devices` idempotently registers an iOS/macOS APNs device by `(platform, apns_token)`. `DELETE /push/devices/{id}` disables the device. APNs delivery sends only to enabled devices when an active `system` notification rule matches the event payload. `LINOFINANCE_APNS_USE_SANDBOX` and `LINOFINANCE_APNS_DRY_RUN` control APNs environment and dry-run delivery; `/health` exposes both.
- `NotificationRule.rule_type` includes `ai_plan` for high-risk AI plans waiting for confirmation.

## V1.3.0 Master-Data Management (audit 2.5)

- `PATCH /accounts/{account_id}` patches a subset of editable fields: `name`, `include_in_net_worth`, `status`, `display_order`, `credit_limit`, `statement_day`, `due_day`, `minimum_payment`, `notes`. Uses `model_fields_set` three-state semantics (field absent = unchanged; explicit `null` = clear nullable field). Immutable fields (`type`, `currency`, `current_balance`, `current_liability`) are absent from the request schema (`extra="forbid"`), so any attempt to set them returns `422`; balances change only through reconciliation adjustments. Unknown account `id` returns `404`.
- `PATCH /categories/{category_id}` patches `name`, `is_active`, `display_order`. Immutable fields (`type`, `parent_id`) are forbidden (`422`). Unknown `id` returns `404`.
- `PATCH /currency-rates/{currency_rate_id}` patches only `rate` (`> 0`). It is rejected with `409` when the rate is already referenced by any entry category line, account movement, cash flow item, or reimbursement claim, preserving the "historical rates are never rewritten" rule. `from_currency`, `to_currency`, `date`, `source` are forbidden (`422`). Unknown `id` returns `404`.
- `currency_rates` now carries a unique constraint on `(from_currency, to_currency, date)`. `POST /currency-rates` returns `409` on a duplicate key. The v1.3.0 migration de-duplicates any pre-existing rows for the same key before adding the constraint, keeping the row with the most recent `created_at`.
