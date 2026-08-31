{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='plan_id',
        on_schema_change='sync_all_columns'
    )
}}

with model_execution as (
    select cast(current_timestamp as timestamp(6) with time zone) as processed_at
),

source_plans as (
    select *
    from {{ source('raw', 'plans') }}
    {% if is_incremental() %}
    where _ingested_at >= (
        select coalesce(
            max(_ingested_at) - interval '2' day,
            timestamp '1970-01-01 00:00:00 UTC'
        )
        from {{ this }}
    )
    {% endif %}
),

cleaned_source as (
    select
        cast(plan_id as integer) as plan_id,
        nullif(trim(plan_name), '') as plan_name,
        nullif(trim(plan_description), '') as plan_description,
        lower(nullif(trim(billing_cycle), '')) as billing_cycle,
        cast(price as decimal(10, 2)) as price,
        upper(nullif(trim(currency), '')) as currency,
        cast(max_users as integer) as max_users,
        lower(nullif(trim(plan_status), '')) as plan_status,
        cast(created_at as timestamp(6) with time zone) as created_at,
        cast(updated_at as timestamp(6) with time zone) as updated_at,
        cast(_ingested_at as timestamp(6) with time zone) as _ingested_at,
        execution.processed_at as _processed_at
    from source_plans
    cross join model_execution as execution
)

select *
from cleaned_source
