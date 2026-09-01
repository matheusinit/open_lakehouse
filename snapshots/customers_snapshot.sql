{% snapshot customers_snapshot %}

{{
    config(
        unique_key='customer_id',
        strategy='timestamp',
        updated_at='updated_at',
        invalidate_hard_deletes=true
    )
}}

select
    customer_id,
    customer_name,
    email,
    country,
    state,
    city,
    customer_status,
    created_at,
    updated_at,
    _ingested_at,
    _processed_at
from {{ ref('stg_customers') }}

{% endsnapshot %}
