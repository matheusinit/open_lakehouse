{{
    config(
        materialized = 'scd2',
        unique_key = 'customer_id',
        tracked_columns = [
            'customer_name',
            'email',
            'country',
            'state',
            'city',
            'customer_status'
        ],
        surrogate_key = 'customer_sk',
        invalidate_hard_deletes = true
    )
}}

SELECT
    customer_id,
    customer_name,
    email,
    country,
    state,
    city,
    customer_status,
    created_at,
    updated_at
FROM {{ ref('stg_customers') }}