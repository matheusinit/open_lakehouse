-- Iceberg snapshot and schema-evolution lab for subscription_events.
--
-- Recorded initial-data snapshot: 8517201855004834902
-- Snapshot after adding evt-011 and evt-012: 3461771529904976311
-- Current state was rolled back to the initial-data snapshot.
--
-- The INSERT and ALTER statements below have already been executed. Do not
-- rerun the INSERT unless duplicate event IDs are intentional.
-- Rollback command already executed:
-- ALTER TABLE lakehouse.raw.subscription_events
-- EXECUTE rollback_to_snapshot(8517201855004834902);

-- 1. Inspect every data snapshot and its per-commit metrics.
SELECT
    snapshot_id,
    parent_id,
    operation,
    committed_at,
    element_at(summary, 'added-records') AS added_records,
    element_at(summary, 'added-data-files') AS added_data_files,
    element_at(summary, 'total-records') AS total_records,
    element_at(summary, 'total-data-files') AS total_data_files,
    element_at(summary, 'manifests-created') AS manifests_created
FROM lakehouse.raw."subscription_events$snapshots"
ORDER BY committed_at;

-- 2. These are the new events that produced snapshot 3461771529904976311.
-- Already executed:
-- INSERT INTO lakehouse.raw.subscription_events VALUES
--     ('evt-011', 'payment_failed', 1003, 503, 20, DECIMAL '99.90',
--      'BRL', 'failed', from_iso8601_timestamp('2026-02-05T10:00:00Z'),
--      from_iso8601_timestamp('2026-02-05T10:00:03Z')),
--     ('evt-012', 'payment_approved', 1003, 503, 20, DECIMAL '99.90',
--      'BRL', 'approved', from_iso8601_timestamp('2026-02-06T10:00:00Z'),
--      from_iso8601_timestamp('2026-02-06T10:00:02Z'));

-- 3. The nullable column was added without rewriting existing data files.
-- Already executed:
-- ALTER TABLE lakehouse.raw.subscription_events
-- ADD COLUMN source_system VARCHAR COMMENT 'System that produced the event';

DESCRIBE lakehouse.raw.subscription_events;

-- Existing rows read NULL for the newly added column.
SELECT event_id, event_type, source_system
FROM lakehouse.raw.subscription_events
ORDER BY event_id;

-- 4. Query the table exactly as it existed after the initial 10-row insert.
SELECT event_id, event_type, event_time
FROM lakehouse.raw.subscription_events
FOR VERSION AS OF 8517201855004834902
ORDER BY event_id;

-- Compare historical and current row counts.
SELECT 'initial snapshot' AS table_version, count(*) AS row_count
FROM lakehouse.raw.subscription_events
FOR VERSION AS OF 8517201855004834902
UNION ALL
SELECT 'current', count(*)
FROM lakehouse.raw.subscription_events;

-- 5. Inspect every current Parquet data file and the snapshot that added it.
SELECT
    file_path,
    partition,
    record_count,
    file_size_in_bytes,
    added_snapshot_id
FROM lakehouse.raw."subscription_events$files"
ORDER BY added_snapshot_id, file_path;

-- 6. Inspect current manifests and how many files/rows each introduced.
SELECT
    path,
    added_snapshot_id,
    added_data_files_count,
    added_rows_count,
    existing_data_files_count,
    existing_rows_count,
    deleted_data_files_count,
    deleted_rows_count,
    partition_summaries
FROM lakehouse.raw."subscription_events$manifests"
ORDER BY added_snapshot_id, path;

-- 7. Schema evolution changes table metadata even when no snapshot is added.
-- Notice the last two metadata entries share the same latest_snapshot_id:
-- the first is the two-row append; the second adds source_system.
SELECT
    timestamp,
    latest_snapshot_id,
    latest_schema_id,
    file
FROM lakehouse.raw."subscription_events$metadata_log_entries"
ORDER BY timestamp;
