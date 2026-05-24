-- LinoFinance v1.1.6 production backfill: classify investment accounts.
--
-- Reclassify two existing accounts from type='balance' to type='investment'.
-- Names are NOT modified. Each reclassification is mirrored into audit_logs
-- with a v1.1.6-backfill actor for traceability.
--
-- Pre-flight checklist (run BEFORE this file):
--   1. Take a fresh production DB snapshot:
--          python backend/scripts/backup_postgres.py
--      Confirm the dump file lands in a known location and is readable.
--   2. Sanity-check the two target rows are still present:
--          SELECT id, name, type FROM accounts
--           WHERE id IN (
--             'f4f140d8-a47d-42ff-a164-32cac90bf8d6',
--             '26f5c480-7376-44c1-af20-dc265432a5eb'
--           );
--      Expect exactly two rows, both with type='balance'.
--
-- Execution:
--          psql -d linofinance -f scripts/backfill_investment_accounts.sql
--
-- The whole script runs inside a single transaction.

BEGIN;

UPDATE accounts SET type = 'investment'
 WHERE id IN (
   'f4f140d8-a47d-42ff-a164-32cac90bf8d6',  -- Funds
   '26f5c480-7376-44c1-af20-dc265432a5eb'   -- Stock
 );

INSERT INTO audit_logs (id, actor, action_type, target_type, target_id,
                         before_snapshot, after_snapshot, note, created_at)
SELECT gen_random_uuid()::text,
       'admin:v1.1.6-backfill',
       'account.type.update',
       'account',
       a.id,
       jsonb_build_object('type','balance'),
       jsonb_build_object('type','investment'),
       'v1.1.6 backfill: classify investment accounts',
       now()
  FROM accounts a
 WHERE a.id IN (
   'f4f140d8-a47d-42ff-a164-32cac90bf8d6',
   '26f5c480-7376-44c1-af20-dc265432a5eb'
 );

COMMIT;
