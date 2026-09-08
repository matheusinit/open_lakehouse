select customer_key
from {{ ref('dim_customer') }}
where valid_to is not null
  and valid_to <= valid_from
