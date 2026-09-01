select customer_key
from {{ ref('dim_customer_scd2') }}
where valid_to is not null
  and valid_to <= valid_from
