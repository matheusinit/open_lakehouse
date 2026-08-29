{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='event_id',
        on_schema_change='sync_all_columns'
    )
}}

with cleaned_source as (
    select
        nullif(trim(event_id), '') as event_id,
        lower(nullif(trim(event_type), '')) as event_type,
        cast(customer_id as bigint) as customer_id,
        cast(subscription_id as bigint) as subscription_id,
        cast(plan_id as integer) as plan_id,
        cast(amount as decimal(10, 2)) as amount,
        upper(nullif(trim(currency), '')) as currency,
        lower(nullif(trim(status), '')) as status,
        cast(event_time as timestamp(6) with time zone) as event_time,
        cast(recorded_at as timestamp(6) with time zone) as recorded_at
    from {{ source('raw', 'subscription_events') }}
),

incremental_events as (
    select source.*
    from cleaned_source as source
    {% if is_incremental() %}
    left join {{ this }} as target
        on source.event_id = target.event_id
    where target.event_id is null
       or source.recorded_at > target.recorded_at
    {% endif %}
)

select *
from incremental_events

