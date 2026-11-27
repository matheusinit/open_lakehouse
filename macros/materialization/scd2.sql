{% materialization scd2, adapter='trino' %}

# --------------------------------------------------
       1. Configuration
    -------------------------------------------------- #}

    {% set unique_key = config.get('unique_key') %}
    {% set tracked_columns = config.get('tracked_columns') %}
    {% set surrogate_key = config.get('surrogate_key', 'scd2_sk') %}
    {% set invalidate_hard_deletes = config.get(
        'invalidate_hard_deletes', true
    ) %}

    {% if not unique_key %}
        {{ exceptions.raise_compiler_error(
            "scd2 requires a unique_key configuration"
        ) }}
    {% endif %}

    {% if not tracked_columns %}
        {{ exceptions.raise_compiler_error(
            "scd2 requires tracked_columns configuration"
        ) }}
    {% endif %}

    {% set unique_keys = unique_key if unique_key is sequence
        and unique_key is not string else [unique_key] %}

    {% set valid_to_column = scd2_columns.get(
        'valid_to', 'valid_to'
    ) %}
    
    {% set is_current_column = scd2_columns.get(
        'is_current', 'is_current'
    ) %}
    
    {% set hash_column = scd2_columns.get(
        'attribute_hash', 'attribute_hash'
    ) %}
    
    {% set created_at_column = scd2_columns.get(
        'created_at', 'created_at'
    ) %}
    
    {% set updated_at_column = scd2_columns.get(
        'updated_at', 'updated_at'
    ) %}

    {# --------------------------------------------------
       2. Temporary relations
    -------------------------------------------------- #}

    {% set source_relation = this.incorporate(
        path={"identifier": this.identifier ~ "__scd2_source"}
    ) %}

    {% set changes_relation = this.incorporate(
        path={"identifier": this.identifier ~ "__scd2_changes"}
    ) %}

    {% set existing_relation = load_relation(this) %}

    {% set source_columns = [] %}

    {% set hash_expression = dbt_utils.generate_surrogate_key(
        tracked_columns
    ) %}

    {# --------------------------------------------------
       3. Materialization execution
    -------------------------------------------------- #}

    {% if existing_relation is none %}

        {{ log("Creating initial SCD2 dimension: " ~ this, info=true) }}

        {% call statement('create_initial_dimension') %}

            CREATE TABLE {{ this }} AS

            SELECT
                source.*,

                {{ hash_expression }} AS {{ adapter.quote(hash_column) }},
                
                CAST(uuid() AS VARCHAR) AS {{ adapter.quote(surrogate_key) }},
            
                CURRENT_TIMESTAMP AS {{ adapter.quote(valid_from_column) }},
            
                CAST(NULL AS TIMESTAMP WITH TIME ZONE) AS {{ adapter.quote(valid_to_column) }},
            
                TRUE AS {{ adapter.quote(is_current_column) }},
            
                CURRENT_TIMESTAMP AS {{ adapter.quote(created_at_column) }},
            
                CURRENT_TIMESTAMP AS {{ adapter.quote(updated_at_column) }}

            FROM (
                {{ sql }}
            ) source

        {% endcall %}

    {% else %}

        {{ log("Executing SCD2 merge: " ~ this, info=true) }}

        {# ----------------------------------------------
           3.1 Stage source records
        ---------------------------------------------- #}

        {% call statement('create_source_stage') %}

            CREATE TABLE {{ source_relation }} AS

            SELECT *
            FROM (
                {{ sql }}
            ) source

        {% endcall %}

        {% set source_columns = adapter.get_columns_in_relation(
            source_relation
        ) %}

        {% set business_columns = [] %}

        {% for column in source_columns %}
            {% do business_columns.append(column.name) %}
        {% endfor %}

        {% set column_list = [] %}

        {% for column in business_columns %}
            {% do column_list.append('source.' ~ adapter.quote(column)) %}
        {% endfor %}

        {% set business_select = column_list | join(',\n') %}

        {% set key_conditions = [] %}

        {% for key in unique_keys %}
            {% do key_conditions.append(
                'source.' ~ adapter.quote(key) ~
                ' = target.' ~ adapter.quote(key)
            ) %}
        {% endfor %}

        {% set key_join = key_conditions | join(' AND ') %}

        {% set changed_conditions = [] %}

        {% for column in tracked_columns %}
            {% do changed_conditions.append(
                'source.attribute_hash <> target.attribute_hash'
            ) %}
        {% endfor %}

        {# ----------------------------------------------
           3.2 Build action dataset
        ---------------------------------------------- #}

        {% call statement('create_scd2_changes') %}

            CREATE TABLE {{ changes_relation }} AS

            WITH source_data AS (

                SELECT
                    source.*,
                    {{ hash_expression }} AS attribute_hash

                FROM {{ source_relation }} source

            ),

            current_data AS (

                SELECT *
                FROM {{ this }}
                WHERE is_current = TRUE

            ),

            changed AS (

                SELECT source.*
                FROM source_data source

                INNER JOIN current_data target
                    ON {{ key_join }}

                WHERE source.attribute_hash
                    <> target.attribute_hash

            ),

            new_records AS (

                SELECT source.*
                FROM source_data source

                LEFT JOIN current_data target
                    ON {{ key_join }}

                WHERE target.{{ adapter.quote(unique_keys[0]) }} IS NULL

            )

            {% if invalidate_hard_deletes %}

            , deleted_records AS (

                SELECT target.*
                FROM current_data target

                LEFT JOIN source_data source
                    ON {{ key_conditions | map('replace', 'source.', 'source.') | join(' AND ') }}

                WHERE source.{{ adapter.quote(unique_keys[0]) }} IS NULL

            )

            {% endif %}

            SELECT
                {{ business_select }},
                source.attribute_hash,
                'EXPIRE' AS scd2_action,
                CURRENT_TIMESTAMP AS change_timestamp

            FROM changed source

            UNION ALL

            SELECT
                {{ business_select }},
                source.attribute_hash,
                'INSERT' AS scd2_action,
                CURRENT_TIMESTAMP AS change_timestamp

            FROM changed source

            UNION ALL

            SELECT
                {{ business_select }},
                source.attribute_hash,
                'INSERT' AS scd2_action,
                CURRENT_TIMESTAMP AS change_timestamp

            FROM new_records source

            {% if invalidate_hard_deletes %}

            UNION ALL

            SELECT
                {% for column in business_columns %}
                    target.{{ adapter.quote(column) }}{% if not loop.last %},{% endif %}
                {% endfor %},
                target.attribute_hash,
                'EXPIRE' AS scd2_action,
                CURRENT_TIMESTAMP AS change_timestamp

            FROM deleted_records target

            {% endif %}

        {% endcall %}

        {# ----------------------------------------------
           3.3 Apply SCD2 using MERGE
        ---------------------------------------------- #}

        {% set insert_columns = [] %}
        {% for column in business_columns %}
            {% do insert_columns.append(adapter.quote(column)) %}
        {% endfor %}

        {% do insert_columns.extend([
            'attribute_hash',
            adapter.quote(surrogate_key),
            'valid_from',
            'valid_to',
            'is_current',
            'created_at',
            'updated_at'
        ]) %}

        {% set insert_values = [] %}
        {% for column in business_columns %}
            {% do insert_values.append('source.' ~ adapter.quote(column)) %}
        {% endfor %}

        {% do insert_values.extend([
            'source.attribute_hash',
            'CAST(uuid() AS VARCHAR)',
            'source.change_timestamp',
            'CAST(NULL AS TIMESTAMP)',
            'TRUE',
            'source.change_timestamp',
            'source.change_timestamp'
        ]) %}

        {% call statement('scd2_merge') %}

            MERGE INTO {{ this }} AS target

            USING {{ changes_relation }} AS source

            ON (
                {{ key_conditions | join(' AND ') }}
                AND target.is_current = TRUE
                AND source.scd2_action = 'EXPIRE'
            )

            WHEN MATCHED AND source.scd2_action = 'EXPIRE'
            THEN UPDATE SET

                {{ adapter.quote(valid_to_column) }} = source.change_timestamp,
            
                {{ adapter.quote(is_current_column) }} = FALSE,
            
                {{ adapter.quote(updated_at_column) }} = source.change_timestamp

            WHEN NOT MATCHED
                AND source.scd2_action = 'INSERT'

            THEN INSERT (
                {{ insert_columns | join(', ') }}
            )

            VALUES (
                {{ insert_values | join(', ') }}
            )

        {% endcall %}

        {# ----------------------------------------------
           3.4 Clean up temporary relations
        ---------------------------------------------- #}

        {% do adapter.drop_relation(source_relation) %}
        {% do adapter.drop_relation(changes_relation) %}

    {% endif %}

    {{ return({'relations': [this]}) }}

{% endmaterialization %}
