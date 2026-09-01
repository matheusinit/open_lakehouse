select customer_id
from {{ ref('dim_customer_scd2') }}
where is_current
group by customer_id
having count(*) > 1
