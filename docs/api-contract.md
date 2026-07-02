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
- Rate limiting today is keyed per client and applies to gated routes. `POST
  /auth/apple` rides the **public** path (it is the unauthenticated bootstrap)
  and is therefore **not** rate-limited as of v1.3.0. A dedicated limiter for the
  auth bootstrap is tracked in `PROJECT_PLAN.md` §6 backlog.

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
  "version": "1.3.0",
  "environment": "local",
  "auth_required": false,
  "auth_modes": ["admin", "user"],
  "rate_limit_enabled": false,
  "apns_use_sandbox": true,
  "apns_dry_run": false
}
```

`auth_modes` (v1.2.0) is the static list `["admin", "user"]`: the API accepts both
the admin environment token (`LINOFINANCE_API_AUTH_TOKEN`, ops bypass) and Apple
session tokens (`auth_sessions`). `version` reflects `app_version` from settings,
so production `/health` is the canonical "what is deployed" probe.

## Phase 1 Planned Endpoints

- Implemented:
  - `GET /accounts`
  - `POST /accounts`
  - `GET /accounts/{account_id}`
  - `PATCH /accounts/{account_id}` (v1.3.0)
  - `POST /accounts/{account_id}/daily-pnl` (v1.1.6)
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
  - `PATCH /credit-statement-cycles/{cycle_id}` (v2.3.0)
  - `POST /credit-statement-cycles/{cycle_id}/mark-paid` (v2.3.0)
  - `POST /credit-statement-cycles/{cycle_id}/void` (v2.3.0)
  - `GET /cash-flow-items`
  - `POST /cash-flow-items`
  - `GET /cash-flow-items/{item_id}`
  - `PATCH /cash-flow-items/{item_id}` (v1.1.7)
  - `POST /cash-flow-items/{item_id}/confirm`
  - `POST /cash-flow-items/{item_id}/cancel`
  - `POST /cash-flow-items/{item_id}/settle`
  - `GET /reimbursement-claims`
  - `POST /reimbursement-claims`
  - `GET /reimbursement-claims/{claim_id}`
  - `POST /reimbursement-claims/{claim_id}/submit` (v2.1.0: retained no-op; returns the claim unchanged — see below)
  - `POST /reimbursement-claims/{claim_id}/approve` (v2.1.0: retained no-op; returns the claim unchanged)
  - `POST /reimbursement-claims/{claim_id}/reject` (v2.1.0: retained, mapped to abandon)
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
  - `POST /entries/{entry_id}/void`
  - `GET /dashboard/summary`
- Planned next:
  - Expand `GET /dashboard/summary` into richer report cards after Phase 1 entries settle.
  - Add entry update/edit endpoints after basic create/void semantics are stable.

## Entry Rules Implemented

- The `draft` entry status is removed (v1.4.0). `POST /entries` accepts only
  `status: "confirmed"` (the default when omitted); sending `draft` returns
  `422`. The `POST /entries/{entry_id}/confirm` route is removed (`404`); entries
  are confirmed at creation time. `/void` semantics are unchanged. A one-time
  data migration parks any legacy `status='draft'` row in `voided`.
- `confirmed` entries must include account movements.
- Confirmed non-transfer entries must include category lines.
- Expense category totals must match `balance_out + credit_charge` movement totals in CNY.
- Income category totals must match `balance_in` movement totals in CNY.
- CNY amounts convert to themselves.
- Non-CNY amounts use the latest available rate on or before the entry date.
- Voiding a confirmed entry reverses its balance/liability effect.
- Credit card charges increase `current_liability`; credit repayment decreases it and is treated as transfer movement.
- **Credit `current_liability` is a derived value (v2.2.0 P1, D1=甲): it always equals `Σ(non-voided statement cycle: statement_amount − paid_amount)`.** The stored `accounts.current_liability` column is a cache of exactly this sum, recomputed after every cycle/charge/repayment mutation, so it can never drift from the cycle total (root-cause fix for the historical "opening liability number that no cycle covered"). There is no "unbilled charges" concept in the current model (every `credit_charge` is forced into a cycle at creation), so the cycle sum is the whole truth.
- **`POST /accounts` rejects a non-zero `current_liability` on a credit account with `422` (v2.2.0 P1).** Opening credit debt must be expressed by creating an opening statement cycle (so it is covered by `Σcycle`), never as a bare opening number on the account. A credit account is always created with `current_liability = 0`; the column then tracks `Σcycle`.
- Credit card charges must belong to a `CreditStatementCycle`.
- If a credit charge omits `statement_cycle_id`, the backend auto-assigns the matching **non-`voided`** cycle by account and entry date. A `voided` cycle never absorbs a new charge (it is excluded from liability and reconciliation scans, so a charge landing on it would silently vanish); with no valid covering cycle the charge is rejected with `400` "Credit charge requires a matching statement cycle", prompting the user to create a valid cycle first (v2.3.0 评审修补 重要-1).
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
- **`PATCH /credit-statement-cycles/{cycle_id}` (v2.3.0)** — partial update of a cycle.
  All body fields optional (`model_fields_set` sentinel): `cycle_start_date`,
  `cycle_end_date`, `statement_date`, `due_date`, `statement_amount`, `minimum_payment`,
  `paid_amount`, `note`. `currency` and the owning account cannot be changed. Validation:
  `paid_amount <= statement_amount`; date order `start <= end`, `statement >= end`,
  `due >= statement`; the (possibly edited) `[start, end]` interval must not overlap another
  non-`voided` cycle on the same account (the cycle never overlaps itself). On success the
  linked repayment cash flow is re-synced and `current_liability` is re-derived from
  `Σ(non-voided cycle: statement − paid)` so the invariant always holds. Errors → `400`;
  editing a `voided` cycle → `400`; missing cycle → `404`. Returns `200 CreditStatementCycleRead`.
- **`POST /credit-statement-cycles/{cycle_id}/mark-paid` (v2.3.0)** — sets
  `paid_amount := statement_amount`, status `paid`, re-syncs the linked repayment cash flow
  and re-derives `current_liability` (the cycle's contribution becomes 0). The linked repayment
  cash flow has no settlement entry (mark-paid records no movement), so it is **cancelled** to 0
  rather than left as a `settled`-with-no-`linked_entry_id` row — that would otherwise be flagged
  as an R4① orphan ("已结算现金流缺记账"); v2.3.0 评审修补 重要-2.
  The double-decrement safety comes from the **assignment** `paid := statement` (not an
  accumulation) combined with `current_liability` being a `Σcycle`-derived quantity: even the
  settle-via-cash-flow path mutates `cycle.paid` then re-derives, so the two paths converge on the
  correct liability and never double-count. A `voided` cycle →
  `400`; missing cycle → `404`. Returns `200 CreditStatementCycleRead`.
- **`POST /credit-statement-cycles/{cycle_id}/void` (v2.3.0)** — sets status `voided` (excluded
  from `Σcycle` so it no longer contributes to liability), cancels the linked repayment cash
  flow, and re-derives `current_liability`. Idempotent: voiding an already-`voided` cycle
  returns it unchanged (`200`). Missing cycle → `404`. Returns `200 CreditStatementCycleRead`.

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
- When a credit statement cycle's remaining reaches 0 the linked repayment cash flow is settled to
  0 **only if it already carries a `linked_entry_id`** (a real settlement); otherwise (mark-paid,
  or a direct `credit_repayment` movement that zeroes the cycle) the auto-generated repayment
  placeholder is **cancelled** to 0, so it is never left as a `settled`-with-no-entry R4① orphan
  (v2.3.0 评审修补 重要-2).
- `GET /cash-flow-items` hides `cancelled` items by default (v1.1.5); pass
  `include_cancelled=true` to include them. An explicit `status` filter wins and
  ignores `include_cancelled`.
- `POST /cash-flow-items/{item_id}/cancel` is idempotent (v1.1.5): cancelling an
  already-`cancelled` item returns `200` with the unchanged item rather than
  erroring. `settled` items cannot be cancelled.
- `PATCH /cash-flow-items/{item_id}` (v1.1.7) edits a non-terminal item using
  `model_fields_set` three-state semantics (absent = unchanged, explicit `null` =
  clear). Only `expected` / `confirmed` items are editable; `settled` and
  `cancelled` are locked. When the patched currency is non-CNY the request must
  carry a valid `exchange_rate_id`; the backend recomputes `converted_cny_amount`
  from the resolved rate. Zero migration.
- `PATCH /cash-flow-items/{item_id}` rejects direct edits to **system-linked**
  items with `400` (v2.4.0 #2). An item is system-linked when any of
  `linked_statement_cycle_id` / `linked_installment_plan_id` /
  `linked_reimbursement_id` / `linked_subscription_rule_id` is set — it is
  generated and kept in sync by an upstream source object, so a direct edit would
  be silently overwritten by the next source-side sync (and, for statement
  cycles, would detach the row and flag the R2 reconciliation detector). The
  guard lives in the service layer (`update_cash_flow_item`), so it also covers
  admin-token and AI callers, not just the UI. Message:
  `系统联动现金流不可直接编辑，请修改其背后的账单周期 / 分期 / 报销源；订阅项仅可补账户/分类以便结算`.
  The one exception: a **subscription-linked** item
  (`linked_subscription_rule_id` set) may be patched with a subset of
  `{account_id, category_id}` and nothing else — this feeds the client's
  "fill the missing account, then settle" flow (subscription cash flows are
  one-shot generated with no persistent source-side overwrite, so the patched
  account/category survives to settlement). Any other patch to a
  subscription-linked item — or any patch at all to a cycle/installment/
  reimbursement-linked item — returns `400`. `settled` / `cancelled` items are
  still locked first. `linked_entry_id` is a settlement product, not a source
  link, and does not trigger the guard. Zero migration.

## Reimbursement Rules Implemented

**Status enum (v2.1.0 P2 — collapsed to three single-user states):**
`pending` (待回款) / `received` (已到账) / `abandoned` (已放弃). The create
schema pattern is `^(pending|received|abandoned)$` and defaults to `pending`;
a reimbursable entry category line may pre-set only `reimbursement_status:
"pending"` (pattern `^pending$`). Legacy values (`reimbursable`,
`invoice_pending`, `submitted`, `approved`, `waiting_received`,
`partial_received`, `rejected`) are rejected with `422`. Existing rows are
remapped by Alembic migration `202606150001`
(`reimbursable/invoice_pending/submitted/approved/waiting_received → pending`,
`partial_received → received`, `rejected → abandoned`).

- Confirmed reimbursable entry category lines auto-create reimbursement claims (status `pending`).
- Reimbursable lines require `reimbursement_expected_date` before an entry can be confirmed.
- Each claim creates a linked `reimbursement` cash-flow inflow.
- `pending` claims keep the linked cash flow `expected`; `received` settles it; `abandoned` cancels it.
- `received` claims require a confirmed formal income entry payload via `mark-received`
  (`pending → received`); the claim records the chosen `received_account_id`,
  `actual_received_date`, and balancing income entry.
- Received reimbursement entries must include a matching `balance_in` movement and matching income category line.
- Voiding the original confirmed reimbursable expense abandons open claims and cancels their reimbursement cash flows.
- `received` and `abandoned` are final; further status changes are rejected (`400`).
- **Retained-endpoint semantics (v2.1.0 D4):** the single-user redesign drops the
  approval ceremony but keeps the endpoints so old clients don't `404`. They never
  write a non-three-state value: `submit`/`approve` are idempotent no-ops that return
  the claim in its current state; `reject` is mapped to `abandon` (`pending → abandoned`).

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
- `GET /dashboard/summary` (revamped v1.1.6) returns the four dashboard cards plus
  entry counts: `disposable_30d_by_currency` (future-month disposable),
  `investment_total_cny` / `investment_total_by_currency` (investment accounts),
  `net_worth_cny` (= `balance_total_cny` − `credit_liability_total_cny` +
  investments), `cash_flow_30d_by_currency` (next-30-day net cash flow), and
  `today_pnl_by_currency`, alongside `confirmed_entry_count` / `voided_entry_count`.
  `draft_entry_count` is **deprecated (v1.4.0)** and pinned to `0` — the field is
  retained only so already-installed iOS 1.3 clients (whose DTO declares it a
  non-optional `let`) keep decoding the response. All CNY totals quantize to the
  product money scale.
- `GET /dashboard/summary` (additive v1.4.0) also returns a per-currency net-worth
  breakdown: `balance_total_by_currency`, `credit_liability_by_currency`, and
  `net_worth_by_currency` (each `[{currency, amount}]`). Amounts are in original
  currency with **no FX conversion**; per currency
  `net = balance + investment − credit liability`, mirroring the CNY formula. CNY
  is always present; other currencies appear only when the amount is non-zero
  (same `_pack_with_cny_floor` rule as the other by-currency lists), so a USD
  net worth of exactly 0 omits the USD row from `net_worth_by_currency` even when
  USD balance/credit rows are non-zero.
- `POST /accounts/{account_id}/daily-pnl` (v1.1.6) records an investment account's
  newly observed balance; the backend computes the delta from the prior balance,
  writes an `account_adjustment` (`source='investment_daily'`) plus an audit log,
  and updates the account balance. The recorded delta is what feeds
  `today_pnl_by_currency`.
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
- Reimbursement reports support three `view` values (v2.1.0 P2): `expected_net`,
  `received_net`, and `personal_net` (default). Legacy views `pre_reimbursement`
  and `approved_net` are removed; passing them fails query validation with `422`.
  Under three states there is no separate "approved" stage, so the `expected`
  offset counts both `pending` and `received` claims, and `personal_net` equals
  `expected_net` (`gross - expected`). The response object still serializes the
  legacy fields `pre_reimbursement_expense_cny` (= gross), `approved_offset_cny`
  / `approved_net_expense_cny` (aliased to the expected offset / `expected_net`)
  for the AI memo layer; only the *selectable* `view` set was collapsed.
- All reimbursement views — including the `received_offset` accumulator — anchor on the
  claim's **original expense date** (the linked entry's date), not on the cash-received date
  (v1.3.0, audit 2.2). A claim contributes to a report window iff its original expense date
  falls in `[date_from, date_to]`; gross, expected, and received offsets are then all
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
- `GET /reconciliation/accounts` returns expected amount, current amount, delta, and `needs_adjustment` per account. For balance/investment accounts this uses movements + reconciliation adjustments; for credit accounts both `expected_amount` and `current_amount` read the single source of truth (`Σ(non-voided cycle: statement_amount − paid_amount)`), so a credit account never shows phantom drift (v2.2.0 P1).
- `POST /reconciliation/adjustments` creates an account adjustment against an observed `actual_amount`, updates the account's current balance, writes an `account_adjustment.create` audit log, and returns the adjustment row. **As of v2.2.0 P1 this path applies only to balance/investment accounts — a credit account returns `400`** ("liability is derived from statement cycles"), because setting an actual liability would violate the `current_liability ≡ Σcycle` invariant; credit corrections go through the statement cycles instead.
- `GET /reconciliation/check` (v2.2.0 P2) is the **read-only multi-dimension consistency/conflict detector** — it never writes the DB. It returns `{checked_at, has_conflicts, accounts[], orphans[]}`. `has_conflicts` is true iff any `conflict`-severity item exists (`info` items don't count). Each account carries `{account_id, account_name, account_type, currency, has_conflicts, conflicts[], breakdown?}`. A `conflict` object is `{code, severity (conflict|info), title, delta?, currency? (the delta's currency so foreign-currency cards render the right symbol; v2.2.0 B2), detail?, offending[], fix (internal_recompute|jump_record|external_actual|none), ...code-specific numbers}`; each `offending` pointer is `{type (credit_statement_cycle|cash_flow_item|reimbursement_claim|account), id, label}` for front-end navigation. Checks:
  - **R1 `credit_three_way`** (credit accounts only): splits the liability into 本期待还 (earliest unpaid cycle remaining) / 其他期未还 / 合计 and fills `breakdown {stored_liability, open_statements_total, unbilled_charges}` plus the conflict's `stored_liability / sum_open_statements / unbilled_charges / expected_liability / delta`. `unbilled_charges` is always `0.00` (the current model has no unbilled-charges concept). Under the P1 derived liability the three numbers are self-consistent, so R1 is normally an `info` breakdown (`fix=none`); if stored has drifted from `Σcycle` (legacy data) it becomes a `conflict` with `fix=internal_recompute`.
  - **R2 `statement_cashflow`** (credit accounts): each non-voided cycle with a remaining balance must have exactly one linked repayment cash-flow item whose `amount` equals `statement − paid`; a missing / cancelled / amount-mismatched link is a `conflict` (`fix=jump_record`).
  - **R3 `balance_external`** (balance/investment accounts): compares the stored balance against the user's last recorded external actual (most recent `source='reconciliation'` adjustment's `balance_after`). No prior record → an `info` prompt to record one; a non-zero gap → a `conflict` with `stored_balance / external_actual / delta` and `fix=external_actual` (record the real number via `POST /reconciliation/adjustments`). Credit accounts get no `balance_external` item — their correction is R1 recompute.
  - **R4 orphans** (global `orphans[]`, D4 宽, read-only): ① a `settled` cash-flow item with no `linked_entry_id`; ② a `received` reimbursement claim with no `received_entry_id`; ③ a non-voided cycle with a remaining balance and no linked cash flow. Each is a `conflict` with `code=orphan`, `fix=jump_record`, and an offending pointer — flagged only, never auto-fixed.
- `POST /reconciliation/recompute-credit/{account_id}` (v2.2.0 P2) re-derives a credit account's `current_liability := Σ(non-voided cycle: statement − paid)` (reusing the P1 single source of truth) and returns `{account_id, account_name, stored_liability_before, recomputed_liability, delta, adjustment_id}`. When the stored value had drifted it persists the corrected liability and leaves a traceable trail (`AccountAdjustment(source='liability_recompute')` + `audit_log(account.liability_recompute)`, mirroring the P1 migration); an already-aligned account is a no-op (`delta=0.00`, `adjustment_id=null`). A non-credit account returns `400`; an unknown `account_id` returns `404`.
- `GET /ai/memos?period=YYYY-MM` lists non-archived AI memo records. `POST /ai/memos/generate?tone=warm|terse|playful|professional` creates or updates the active memo for a period from report aggregates and the configured AI provider. The response includes additive `created_at` / `updated_at` timestamps and stores full stats JSON for overview, top categories, subscriptions, credit liabilities, reimbursements, and anomalies. `PATCH /ai/memos/{id}` updates summary/status. `DELETE /ai/memos/{id}` archives the memo.
- `POST /push/devices` idempotently registers an iOS/macOS APNs device by `(platform, apns_token)`. `DELETE /push/devices/{id}` disables the device. APNs delivery sends only to enabled devices when an active `system` notification rule matches the event payload. `LINOFINANCE_APNS_USE_SANDBOX` and `LINOFINANCE_APNS_DRY_RUN` control APNs environment and dry-run delivery; `/health` exposes both.
- `NotificationRule.rule_type` includes `ai_plan` for high-risk AI plans waiting for confirmation.

## V1.3.0 Master-Data Management (audit 2.5)

- `PATCH /accounts/{account_id}` patches a subset of editable fields: `name`, `include_in_net_worth`, `status`, `display_order`, `credit_limit`, `statement_day`, `due_day`, `minimum_payment`, `notes`. Uses `model_fields_set` three-state semantics (field absent = unchanged; explicit `null` = clear nullable field). Immutable fields (`type`, `currency`, `current_balance`, `current_liability`) are absent from the request schema (`extra="forbid"`), so any attempt to set them returns `422`; balances change only through reconciliation adjustments. Unknown account `id` returns `404`.
- `PATCH /categories/{category_id}` patches `name`, `is_active`, `display_order`. Immutable fields (`type`, `parent_id`) are forbidden (`422`). Unknown `id` returns `404`.
- `PATCH /currency-rates/{currency_rate_id}` patches only `rate` (`> 0`). It is rejected with `409` when the rate is already referenced by any entry category line, account movement, cash flow item, or reimbursement claim, preserving the "historical rates are never rewritten" rule. `from_currency`, `to_currency`, `date`, `source` are forbidden (`422`). Unknown `id` returns `404`.
- `currency_rates` now carries a unique constraint on `(from_currency, to_currency, date)`. `POST /currency-rates` returns `409` on a duplicate key. The v1.3.0 migration de-duplicates any pre-existing rows for the same key before adding the constraint, keeping the row with the most recent `created_at`.
