# Open Lakehouse

[Português](README.md) | [English](README.en.md)

Ambiente local para estudar uma arquitetura lakehouse com MinIO, Apache
Iceberg REST Catalog, Trino e um editor SQL no navegador. O projeto Python é
gerenciado com `uv` e não possui dependências de terceiros.

## Arquitetura

```text
CloudBeaver ──SQL/JDBC──> Trino ──HTTP──> Iceberg REST Catalog
                            │
                            └──S3──> MinIO
                                      └── warehouse/
```

- **CloudBeaver** fornece o editor SQL e o navegador de catálogos.
- **Trino** executa consultas e operações SQL sobre as tabelas Iceberg.
- **Iceberg REST Catalog** coordena o catálogo e os commits das tabelas.
- **MinIO** armazena arquivos Parquet, manifests e metadados Iceberg.

## Arquitetura de dados

O projeto adota três estágios lógicos:

```text
Raw → Staging → Analytics
```

### Raw

Mantém os registros históricos das fontes com o mínimo possível de
transformação:

- `raw.customers`
- `raw.plans`
- `raw.subscription_events`
- `raw.payments`

Essa camada preserva os dados recebidos e permite reprocessar as transformações
posteriores. Algumas relações da lista representam o desenho alvo e podem ainda
não estar implementadas. Todas as tabelas raw possuem `_ingested_at`, que
registra quando cada linha entrou pela primeira vez no lakehouse.

### Staging

Aplica uma normalização leve e mantém os dados próximos ao grain das fontes:

- `staging.stg_customers`
- `staging.stg_plans`
- `staging.stg_subscription_events`
- `staging.stg_payments`

Responsabilidades dessa camada:

- conversão e padronização de tipos;
- renomeação de colunas;
- validações básicas;
- tratamento de duplicatas exatas;
- normalização de metadados técnicos.

Essas relações podem ser views e não precisam obrigatoriamente de uma camada
física própria. Quando persistência, histórico técnico ou processamento
incremental forem úteis, elas também podem ser materializadas como tabelas
Iceberg. Atualmente, `stg_subscription_events` é uma tabela incremental.

### Analytics

Contém os modelos dimensionais, fatos, snapshots e agregações prontos para
consumo:

- `analytics.dim_customer_scd2`
- `analytics.dim_plan_scd2`
- `analytics.fct_subscription_event`
- `analytics.fct_payment`
- `analytics.fct_subscription_daily_snapshot`
- `analytics.agg_monthly_recurring_revenue`
- `analytics.agg_customer_churn_monthly`

Essa separação mantém a arquitetura simples, ao mesmo tempo que torna explícito
o papel de cada tipo de modelo.

## Pré-requisitos

- Docker com Docker Compose
- `uv` somente para executar o pequeno projeto Python

## Serviços

| Serviço | Endereço | Finalidade |
| --- | --- | --- |
| API do MinIO | `http://localhost:9000` | Armazenamento compatível com S3 |
| Console do MinIO | `http://localhost:9001` | Interface web do armazenamento |
| Iceberg REST | `http://localhost:8181` | Catálogo de metadados Iceberg |
| Trino | `http://localhost:8082` | Engine SQL e interface de monitoramento |
| Editor SQL | `http://localhost:8978` | Cliente SQL CloudBeaver |

As credenciais padrão locais do MinIO e do CloudBeaver são
`admin` / `password123`. Elas são destinadas exclusivamente ao desenvolvimento
local. Copie `.env.example` para `.env` antes de iniciar os serviços para
personalizá-las:

```sh
cp .env.example .env
```

O Trino usa a porta `8082` no host porque a porta `8080` costuma estar ocupada.
Altere `TRINO_PORT` no `.env` se necessário.

## Iniciar

```sh
docker compose up -d
docker compose ps
```

O serviço temporário `minio-init` cria o bucket privado `warehouse` antes da
inicialização do catálogo. Os dados do MinIO e as configurações do CloudBeaver
são mantidos nos volumes `minio-data` e `cloudbeaver-data`.

## Editor SQL

Acesse `http://localhost:8978` e entre com `admin` / `password123`. Selecione a
conexão pré-configurada **Open Lakehouse (Trino)** e abra um editor SQL. A senha
é usada apenas para acessar o CloudBeaver; a conexão local com o Trino envia o
usuário `admin` sem senha de banco de dados.

Exemplo:

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

As variáveis `SQL_EDITOR_ADMIN` e `SQL_EDITOR_PASSWORD` inicializam um volume
novo. Após a primeira inicialização, altere a senha pela administração do
CloudBeaver.

## Verificar o ambiente

Execute o teste básico incluído:

```sh
docker compose exec -T trino trino < infra/trino/smoke-test.sql
```

Abra o cliente interativo do Trino:

```sh
docker compose exec trino trino --catalog lakehouse
```

Outras verificações úteis:

```sh
curl http://localhost:8181/v1/config
docker compose exec trino trino --execute "SHOW CATALOGS"
docker compose logs -f iceberg-rest trino sql-editor
```

O arquivo `infra/trino/iceberg-snapshot-lab.sql` contém consultas para explorar
snapshots, time travel, evolução de schema, arquivos de dados e manifests.

```sh
docker compose exec -T trino trino \
  < infra/trino/iceberg-snapshot-lab.sql
```

Carregue ou atualize as tabelas Iceberg de referência `raw.plans` e
`raw.customers` de forma idempotente com:

```sh
docker compose exec -T trino trino \
  < infra/trino/load-reference-data.sql
```

O script `infra/trino/add-raw-ingestion-metadata.sql` adiciona e preenche
`_ingested_at` de forma idempotente nas tabelas raw existentes.

## Parar e limpar

Pare os contêineres preservando os dados:

```sh
docker compose down
```

Remova também todos os volumes e dados persistidos do ambiente:

```sh
docker compose down --volumes
```

Para redefinir somente o editor SQL, sem apagar os dados do MinIO:

```sh
docker compose rm --stop --force sql-editor
docker volume rm open-lakehouse_cloudbeaver-data
docker compose up -d sql-editor
```

## Python

```sh
uv run main.py
```

## dbt com Trino

O adapter `dbt-trino` está instalado pelo `uv`. O profile local em
`profiles.yml` conecta ao Trino sem senha e grava os modelos no catálogo
`lakehouse`.

```sh
uv sync
uv run dbt debug --profiles-dir .
uv run dbt run --profiles-dir .
uv run dbt test --profiles-dir .
```

O modelo incremental `stg_subscription_events` cria uma representação limpa e
1:1 de `lakehouse.raw.subscription_events` em
`lakehouse.staging.stg_subscription_events`. Ele normaliza textos e tipos e faz
`MERGE` por `event_id`, inserindo eventos inéditos ou atualizando versões com
`recorded_at` mais recente. Para alterar o endereço do Trino, configure
`DBT_TRINO_HOST`, `DBT_TRINO_PORT` e `DBT_TRINO_USER` no ambiente.

O modelo `stg_customers` também mantém grain 1:1 e usa `_ingested_at` como
watermark incremental. Em cada execução, ele relê os registros desde dois dias
antes do maior `_ingested_at` já carregado e faz `MERGE` por `customer_id`. Essa
janela permite reprocessar com segurança registros recentes ou atrasados.

## Aviso de segurança

Este ambiente não habilita TLS nem autenticação no Trino e publica credenciais
simples para facilitar testes locais. Não o exponha diretamente à internet nem
o utilize como configuração de produção.
