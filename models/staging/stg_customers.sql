{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='customer_id',
        on_schema_change='sync_all_columns'
    )
}}

with model_execution as (
    select cast(current_timestamp as timestamp(6) with time zone) as processed_at
),

source_customers as (
    select *
    from {{ source('raw', 'customers') }}
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
        cast(customer_id as bigint) as customer_id,
        nullif(trim(customer_name), '') as customer_name,
        lower(nullif(trim(email), '')) as email,
        upper(nullif(trim(country), '')) as country,
        upper(nullif(trim(state), '')) as state,
        nullif(trim(city), '') as city,
        lower(nullif(trim(customer_status), '')) as customer_status,
        cast(created_at as timestamp(6) with time zone) as created_at,
        cast(updated_at as timestamp(6) with time zone) as updated_at,
        cast(_ingested_at as timestamp(6) with time zone) as _ingested_at,
        execution.processed_at as _processed_at
    from source_customers
    cross join model_execution as execution
)

select *
from cleaned_source
