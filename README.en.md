# Open Lakehouse

[Português](README.md) | [English](README.en.md)

A local environment for studying a lakehouse architecture with MinIO, Apache
Iceberg REST Catalog, Trino, and a browser-based SQL editor. The Python project
is managed with `uv` and has no third-party dependencies.

## Architecture

```text
CloudBeaver ──SQL/JDBC──> Trino ──HTTP──> Iceberg REST Catalog
                            │
                            └──S3──> MinIO
                                      └── warehouse/
```

- **CloudBeaver** provides the SQL editor and catalog browser.
- **Trino** executes queries and SQL operations against Iceberg tables.
- **Iceberg REST Catalog** coordinates the catalog and table commits.
- **MinIO** stores Parquet files, manifests, and Iceberg metadata.

## Data architecture

The project uses three logical stages:

```text
Raw → Staging → Analytics
```

### Raw

Keeps historical source records with as little transformation as possible:

- `raw.customers`
- `raw.plans`
- `raw.subscription_events`
- `raw.payments`

This layer preserves received data and allows downstream transformations to be
reprocessed. Some relations in this list represent the target design and might
not be implemented yet. Every raw table includes `_ingested_at`, recording when
each row first entered the lakehouse.

### Staging

Applies light normalization while keeping data close to the source grain:

- `staging.stg_customers`
- `staging.stg_plans`
- `staging.stg_subscription_events`
- `staging.stg_payments`

This layer is responsible for:

- type casting and standardization;
- column renaming;
- basic validation;
- exact duplicate handling;
- technical metadata normalization.

These relations can be views and do not necessarily require a separate
physical storage layer. When persistence, technical history, or incremental
processing is useful, they can also be materialized as Iceberg tables.
Currently, `stg_subscription_events` is an incremental table.

### Analytics

Contains consumption-ready dimensions, facts, snapshots, and aggregates:

- `analytics.dim_customer_scd2`
- `analytics.dim_plan_scd2`
- `analytics.fct_subscription_event`
- `analytics.fct_payment`
- `analytics.fct_subscription_daily_snapshot`
- `analytics.agg_monthly_recurring_revenue`
- `analytics.agg_customer_churn_monthly`

This separation keeps the architecture simple while making the role of each
model type explicit.

## Prerequisites

- Docker with Docker Compose
- `uv` only for running the small Python project

## Services

| Service | Address | Purpose |
| --- | --- | --- |
| MinIO API | `http://localhost:9000` | S3-compatible object storage |
| MinIO console | `http://localhost:9001` | Object storage web interface |
| Iceberg REST | `http://localhost:8181` | Iceberg metadata catalog |
| Trino | `http://localhost:8082` | SQL engine and monitoring interface |
| SQL editor | `http://localhost:8978` | CloudBeaver SQL client |

The default local MinIO and CloudBeaver credentials are
`admin` / `password123`. They are intended exclusively for local development.
Copy `.env.example` to `.env` before starting the services to customize them:

```sh
cp .env.example .env
```

Trino uses host port `8082` because port `8080` is commonly occupied. Change
`TRINO_PORT` in `.env` if needed.

## Start

```sh
docker compose up -d
docker compose ps
```

The one-shot `minio-init` service creates the private `warehouse` bucket before
the catalog starts. MinIO data and CloudBeaver settings are persisted in the
`minio-data` and `cloudbeaver-data` volumes.

## SQL editor

Open `http://localhost:8978` and sign in with `admin` / `password123`. Select
the preconfigured **Open Lakehouse (Trino)** connection and open a SQL editor.
The password is only used to access CloudBeaver; the local Trino connection
sends the `admin` username without a database password.

Example:

```sql
CREATE SCHEMA IF NOT EXISTS lakehouse.analytics
WITH (location = 's3://warehouse/analytics/');

CREATE TABLE lakehouse.analytics.customers (
    customer_id BIGINT,
    customer_name VARCHAR,
    created_at TIMESTAMP(6)
)
WITH (format = 'PARQUET');

INSERT INTO lakehouse.analytics.customers
VALUES (1, 'Alice', CURRENT_TIMESTAMP);

SELECT * FROM lakehouse.analytics.customers;
```

The `SQL_EDITOR_ADMIN` and `SQL_EDITOR_PASSWORD` variables initialize a new
volume. After the first initialization, change the password through
CloudBeaver's administration interface.

## Verify the environment

Run the included smoke test:

```sh
docker compose exec -T trino trino < infra/trino/smoke-test.sql
```

Open the interactive Trino client:

```sh
docker compose exec trino trino --catalog lakehouse
```

Other useful checks:

```sh
curl http://localhost:8181/v1/config
docker compose exec trino trino --execute "SHOW CATALOGS"
docker compose logs -f iceberg-rest trino sql-editor
```

The `infra/trino/iceberg-snapshot-lab.sql` file contains queries for exploring
snapshots, time travel, schema evolution, data files, and manifests.

```sh
docker compose exec -T trino trino \
  < infra/trino/iceberg-snapshot-lab.sql
```

Idempotently load or update the `raw.plans` and `raw.customers` reference
Iceberg tables with:

```sh
docker compose exec -T trino trino \
  < infra/trino/load-reference-data.sql
```

The `infra/trino/add-raw-ingestion-metadata.sql` script idempotently adds and
backfills `_ingested_at` in existing raw tables.

## Stop and clean up

Stop the containers while preserving data:

```sh
docker compose down
```

Also remove every persistent volume and its data:

```sh
docker compose down --volumes
```

To reset only the SQL editor without deleting MinIO data:

```sh
docker compose rm --stop --force sql-editor
docker volume rm open-lakehouse_cloudbeaver-data
docker compose up -d sql-editor
```

## Python

```sh
uv run main.py
```

## dbt with Trino

The `dbt-trino` adapter is installed through `uv`. The local `profiles.yml`
connects to Trino without a password and writes models to the `lakehouse`
catalog.

```sh
uv sync
uv run dbt debug --profiles-dir .
uv run dbt run --profiles-dir .
uv run dbt test --profiles-dir .
```

The incremental `stg_subscription_events` model creates a clean, one-to-one
representation of `lakehouse.raw.subscription_events` at
`lakehouse.staging.stg_subscription_events`. It normalizes strings and types,
then merges by `event_id`, inserting new events or updating versions with a
newer `recorded_at`. Set `DBT_TRINO_HOST`, `DBT_TRINO_PORT`, and
`DBT_TRINO_USER` in the environment to change the Trino connection.

The `stg_customers` model also maintains a one-to-one grain and uses
`_ingested_at` as its incremental watermark. Each run rereads records from two
days before the greatest `_ingested_at` already loaded and merges them by
`customer_id`. This window safely reprocesses recent or late-arriving records.

## Security notice

This environment does not enable TLS or Trino authentication and publishes
simple credentials for convenient local testing. Do not expose it directly to
the internet or use it as a production configuration.
