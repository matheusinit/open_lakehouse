-- Backfill date used for records loaded before ingestion metadata was added.
-- This script is safe to rerun: columns are added conditionally and only NULL
-- ingestion timestamps are backfilled.

ALTER TABLE lakehouse.raw.customers
ADD COLUMN IF NOT EXISTS _ingested_at TIMESTAMP(6) WITH TIME ZONE;

UPDATE lakehouse.raw.customers
SET _ingested_at = TIMESTAMP '2026-08-30 00:00:00 UTC'
WHERE _ingested_at IS NULL;

ALTER TABLE lakehouse.raw.plans
ADD COLUMN IF NOT EXISTS _ingested_at TIMESTAMP(6) WITH TIME ZONE;

UPDATE lakehouse.raw.plans
SET _ingested_at = TIMESTAMP '2026-08-30 00:00:00 UTC'
WHERE _ingested_at IS NULL;

ALTER TABLE lakehouse.raw.subscription_events
ADD COLUMN IF NOT EXISTS _ingested_at TIMESTAMP(6) WITH TIME ZONE;

UPDATE lakehouse.raw.subscription_events
SET _ingested_at = TIMESTAMP '2026-08-30 00:00:00 UTC'
WHERE _ingested_at IS NULL;

