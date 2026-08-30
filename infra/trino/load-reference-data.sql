CREATE SCHEMA IF NOT EXISTS lakehouse.raw
WITH (location = 's3://warehouse/raw/');

CREATE TABLE IF NOT EXISTS lakehouse.raw.plans (
    plan_id INTEGER,
    plan_name VARCHAR,
    plan_description VARCHAR,
    billing_cycle VARCHAR,
    price DECIMAL(10, 2),
    currency VARCHAR,
    max_users INTEGER,
    plan_status VARCHAR,
    created_at TIMESTAMP(6) WITH TIME ZONE,
    updated_at TIMESTAMP(6) WITH TIME ZONE,
    _ingested_at TIMESTAMP(6) WITH TIME ZONE
)
WITH (
    format = 'PARQUET',
    format_version = 2
);

MERGE INTO lakehouse.raw.plans AS target
USING (
    VALUES
        (
            10,
            'Basic',
            'Basic subscription for individual customers',
            'monthly',
            DECIMAL '49.90',
            'BRL',
            1,
            'active',
            from_iso8601_timestamp('2025-01-01T00:00:00Z'),
            from_iso8601_timestamp('2025-01-01T00:00:00Z')
        ),
        (
            20,
            'Pro',
            'Advanced subscription with additional features',
            'monthly',
            DECIMAL '99.90',
            'BRL',
            5,
            'active',
            from_iso8601_timestamp('2025-01-01T00:00:00Z'),
            from_iso8601_timestamp('2025-01-01T00:00:00Z')
        )
) AS source (
    plan_id,
    plan_name,
    plan_description,
    billing_cycle,
    price,
    currency,
    max_users,
    plan_status,
    created_at,
    updated_at
)
ON target.plan_id = source.plan_id
WHEN MATCHED AND source.updated_at > target.updated_at THEN
    UPDATE SET
        plan_name = source.plan_name,
        plan_description = source.plan_description,
        billing_cycle = source.billing_cycle,
        price = source.price,
        currency = source.currency,
        max_users = source.max_users,
        plan_status = source.plan_status,
        created_at = source.created_at,
        updated_at = source.updated_at
WHEN NOT MATCHED THEN
    INSERT (
        plan_id,
        plan_name,
        plan_description,
        billing_cycle,
        price,
        currency,
        max_users,
        plan_status,
        created_at,
        updated_at,
        _ingested_at
    )
    VALUES (
        source.plan_id,
        source.plan_name,
        source.plan_description,
        source.billing_cycle,
        source.price,
        source.currency,
        source.max_users,
        source.plan_status,
        source.created_at,
        source.updated_at,
        cast(CURRENT_TIMESTAMP as timestamp(6) with time zone)
    );

CREATE TABLE IF NOT EXISTS lakehouse.raw.customers (
    customer_id BIGINT,
    customer_name VARCHAR,
    email VARCHAR,
    country VARCHAR,
    state VARCHAR,
    city VARCHAR,
    customer_status VARCHAR,
    created_at TIMESTAMP(6) WITH TIME ZONE,
    updated_at TIMESTAMP(6) WITH TIME ZONE,
    _ingested_at TIMESTAMP(6) WITH TIME ZONE
)
WITH (
    format = 'PARQUET',
    format_version = 2
);

MERGE INTO lakehouse.raw.customers AS target
USING (
    VALUES
        (
            BIGINT '1001',
            'Alex Silva',
            'alex.silva@example.com',
            'BR',
            'SP',
            'São Paulo',
            'active',
            from_iso8601_timestamp('2025-12-15T09:00:00Z'),
            from_iso8601_timestamp('2025-12-15T09:00:00Z')
        ),
        (
            BIGINT '1002',
            'Bianca Souza',
            'bianca.souza@example.com',
            'BR',
            'RJ',
            'Rio de Janeiro',
            'active',
            from_iso8601_timestamp('2025-12-20T14:30:00Z'),
            from_iso8601_timestamp('2025-12-20T14:30:00Z')
        ),
        (
            BIGINT '1003',
            'Carlos Oliveira',
            'carlos.oliveira@example.com',
            'BR',
            'RN',
            'Natal',
            'active',
            from_iso8601_timestamp('2026-01-18T11:00:00Z'),
            from_iso8601_timestamp('2026-01-18T11:00:00Z')
        )
) AS source (
    customer_id,
    customer_name,
    email,
    country,
    state,
    city,
    customer_status,
    created_at,
    updated_at
)
ON target.customer_id = source.customer_id
WHEN MATCHED AND source.updated_at > target.updated_at THEN
    UPDATE SET
        customer_name = source.customer_name,
        email = source.email,
        country = source.country,
        state = source.state,
        city = source.city,
        customer_status = source.customer_status,
        created_at = source.created_at,
        updated_at = source.updated_at
WHEN NOT MATCHED THEN
    INSERT (
        customer_id,
        customer_name,
        email,
        country,
        state,
        city,
        customer_status,
        created_at,
        updated_at,
        _ingested_at
    )
    VALUES (
        source.customer_id,
        source.customer_name,
        source.email,
        source.country,
        source.state,
        source.city,
        source.customer_status,
        source.created_at,
        source.updated_at,
        cast(CURRENT_TIMESTAMP as timestamp(6) with time zone)
    );
