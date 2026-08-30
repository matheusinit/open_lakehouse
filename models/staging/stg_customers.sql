{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='customer_id',
        on_schema_change='sync_all_columns'
    )
}}

-- todo: change the watermark of incremental load from raw layer by using _ingested_at with lookback window
-- to get late arriving data

with current_source_snapshot as (
    select
        history.snapshot_id as source_snapshot_id,
        cast(
            snapshots.committed_at as timestamp(6) with time zone
        ) as source_snapshot_committed_at
    from lakehouse.raw."customers$history" as history
    inner join lakehouse.raw."customers$snapshots" as snapshots
        on history.snapshot_id = snapshots.snapshot_id
    where history.is_current_ancestor
    order by history.made_current_at desc
    limit 1
),

cleaned_source as (
    select
        cast(customer_id as bigint) as customer_id,
        nullif(trim(customer_name), '') as customer_name,
        lower(nullif(trim(email), '')) as email,
        upper(nullif(trim(country), '')) as country,
        upper(nullif(trim(state), '')) as state,
        nullif(trim(city), '') as city,
        lower(nullif(trim(customer_status), '')) as customer_status,
        cast(created_at as timestamp(6) with time zone) as created_at,
        cast(updated_at as timestamp(6) with time zone) as updated_at
    from {{ source('raw', 'customers') }}
),

{% if is_incremental() %}
processed_snapshot as (
    select max(source_snapshot_id) as source_snapshot_id
    from {{ this }}
),
{% endif %}

customers_to_process as (
    select
        source.*,
        snapshot.source_snapshot_id,
        snapshot.source_snapshot_committed_at
    from cleaned_source as source
    cross join current_source_snapshot as snapshot
    {% if is_incremental() %}
    cross join processed_snapshot as processed
    where processed.source_snapshot_id is null
       or snapshot.source_snapshot_id <> processed.source_snapshot_id
    {% endif %}
)

select *
from customers_to_process
