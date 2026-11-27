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

        -- Custom column names for SCD2
        -- scd2_columns = {
        --     'valid_from': 'start_date',
        --     'valid_to': 'end_date',
        --     'is_current': 'current_flag',
        --     'attribute_hash': 'row_hash',
        --     'created_at': 'created_timestamp',
        --     'updated_at': 'updated_timestamp'
        -- }
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