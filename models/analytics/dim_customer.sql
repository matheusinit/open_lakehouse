{{ config(materialized='view') }}

select
    cast(dbt_scd_id as varchar) as customer_key,
    customer_id,
    customer_name,
    email,
    country,
    state,
    city,
    customer_status,
    created_at,
    updated_at,
    cast(dbt_valid_from as timestamp(6) with time zone) as valid_from,
    cast(dbt_valid_to as timestamp(6) with time zone) as valid_to,
    dbt_valid_to is null as is_current
from {{ ref('customers_snapshot') }}
