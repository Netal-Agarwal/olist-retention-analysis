-- =============================================================================
-- 03_quality_checks.sql
-- Purpose : prove the load into the clean schema is complete and correct.
-- Business question: "Can we trust the database copy of the data?" Every
--           Phase 4+ number depends on the answer being yes.
-- Tables  : all 8 clean.* tables, and the analysis.* views (section 7).
--           The views must exist first (src.create_views or src.load_to_postgres).
--
-- One query, runnable as-is in pgAdmin. Each row is one check:
--   check_name | expected | actual | passed
-- Expected values are copied from Phase 2 outputs; the source is cited next to
-- each one. Sources:
--   [CS] outputs/phase2_cleaning_summary.csv   (section,metric)
--   [PS] outputs/phase2_profile_summary.csv    (metric)
-- src/run_quality_checks.py runs this, saves outputs/phase3_quality_checks.csv
-- and fails if any check does not pass.
-- =============================================================================

with checks (check_name, expected, actual) as (

    -- -------------------------------------------------------------------------
    -- 1. Row counts: every processed row arrived, none extra.
    -- -------------------------------------------------------------------------
    select 'rows: customers', 99441,        -- [CS] reconciliation,customers_processed_rows
           (select count(*) from clean.customers)
    union all
    select 'rows: sellers', 3095,           -- [CS] reconciliation,sellers_processed_rows
           (select count(*) from clean.sellers)
    union all
    select 'rows: products', 32951,         -- [CS] reconciliation,products_processed_rows
           (select count(*) from clean.products)
    union all
    select 'rows: geolocation', 19010,      -- [CS] reconciliation,geolocation_processed_rows
           (select count(*) from clean.geolocation)
    union all
    select 'rows: orders', 99441,           -- [CS] reconciliation,orders_processed_rows
           (select count(*) from clean.orders)
    union all
    select 'rows: order_items', 112650,     -- [CS] reconciliation,order_items_processed_rows
           (select count(*) from clean.order_items)
    union all
    select 'rows: order_payments', 103886,  -- [CS] reconciliation,order_payments_processed_rows
           (select count(*) from clean.order_payments)
    union all
    select 'rows: order_reviews', 98673,    -- [CS] reconciliation,order_reviews_processed_rows
           (select count(*) from clean.order_reviews)

    -- -------------------------------------------------------------------------
    -- 2. Key business counts.
    -- -------------------------------------------------------------------------
    union all
    -- Counted from the status text (not the flag), so it also confirms the flag.
    select 'business: delivered orders (status = delivered)', 96478,  -- [PS] delivered_orders
           (select count(*) from clean.orders where order_status = 'delivered')
    union all
    -- The real person is customer_unique_id, not customer_id.
    select 'business: distinct customer_unique_id', 96096,  -- [PS] unique_customer_unique_id
           (select count(distinct customer_unique_id) from clean.customers)
    union all
    -- One review per order: group reviews by order and keep groups with more
    -- than one row (HAVING filters groups, WHERE filters rows). Expect none.
    -- Expected 0: Phase 2 rule "one review per order" (docs/metrics.md metric 10).
    select 'business: orders with more than one review', 0,
           (select count(*)
              from (select order_id
                      from clean.order_reviews
                     group by order_id
                    having count(*) > 1) as multi)

    -- -------------------------------------------------------------------------
    -- 3. Orphans: child rows whose parent is missing.
    -- LEFT JOIN keeps every child row; where no parent matched, the parent's
    -- columns are NULL, so "parent key IS NULL" finds the orphans.
    -- The foreign keys already make orphans impossible; these queries show how
    -- you would find them in a database without foreign keys.
    -- Expected 0 for all: [PS] the six "integrity: ... not in ..." rows.
    -- -------------------------------------------------------------------------
    union all
    select 'orphans: orders without customer', 0,
           (select count(*)
              from clean.orders o
              left join clean.customers c on c.customer_id = o.customer_id
             where c.customer_id is null)
    union all
    select 'orphans: order_items without order', 0,
           (select count(*)
              from clean.order_items oi
              left join clean.orders o on o.order_id = oi.order_id
             where o.order_id is null)
    union all
    select 'orphans: order_items without product', 0,
           (select count(*)
              from clean.order_items oi
              left join clean.products p on p.product_id = oi.product_id
             where p.product_id is null)
    union all
    select 'orphans: order_items without seller', 0,
           (select count(*)
              from clean.order_items oi
              left join clean.sellers s on s.seller_id = oi.seller_id
             where s.seller_id is null)
    union all
    select 'orphans: order_payments without order', 0,
           (select count(*)
              from clean.order_payments op
              left join clean.orders o on o.order_id = op.order_id
             where o.order_id is null)
    union all
    select 'orphans: order_reviews without order', 0,
           (select count(*)
              from clean.order_reviews r
              left join clean.orders o on o.order_id = r.order_id
             where o.order_id is null)

    -- -------------------------------------------------------------------------
    -- 4. Zip prefixes with no geolocation row (why there is no FK to geolocation).
    -- Same LEFT JOIN ... IS NULL pattern; here we EXPECT some.
    -- -------------------------------------------------------------------------
    union all
    select 'geo: customers with no geolocation match', 279,  -- [CS] flags,customers.flag_zip_not_in_geolocation
           (select count(*)
              from clean.customers c
              left join clean.geolocation g on g.geolocation_zip_code_prefix = c.customer_zip_code_prefix
             where g.geolocation_zip_code_prefix is null)
    union all
    select 'geo: sellers with no geolocation match', 7,      -- [CS] flags,sellers.flag_zip_not_in_geolocation
           (select count(*)
              from clean.sellers s
              left join clean.geolocation g on g.geolocation_zip_code_prefix = s.seller_zip_code_prefix
             where g.geolocation_zip_code_prefix is null)

    -- -------------------------------------------------------------------------
    -- 5. Flag columns: TRUE counts must equal Phase 2.
    -- All expected values: [CS] section "flags", metric = <table>.<column>.
    -- "where flag" is short for "where flag = true".
    -- -------------------------------------------------------------------------
    union all select 'flag: orders.is_delivered', 96478,
           (select count(*) from clean.orders where is_delivered)
    union all select 'flag: orders.in_analysis_window', 99092,
           (select count(*) from clean.orders where in_analysis_window)
    union all select 'flag: orders.flag_delivered_missing_customer_date', 8,
           (select count(*) from clean.orders where flag_delivered_missing_customer_date)
    union all select 'flag: orders.flag_carrier_before_approval', 1359,
           (select count(*) from clean.orders where flag_carrier_before_approval)
    union all select 'flag: orders.flag_carrier_before_purchase', 166,
           (select count(*) from clean.orders where flag_carrier_before_purchase)
    union all select 'flag: orders.flag_delivery_before_carrier', 23,
           (select count(*) from clean.orders where flag_delivery_before_carrier)
    union all select 'flag: orders.flag_cancelled_with_delivery_date', 6,
           (select count(*) from clean.orders where flag_cancelled_with_delivery_date)
    union all select 'flag: orders.flag_no_items', 775,
           (select count(*) from clean.orders where flag_no_items)
    union all select 'flag: orders.flag_no_payment', 1,
           (select count(*) from clean.orders where flag_no_payment)
    union all select 'flag: orders.flag_payment_mismatch', 303,
           (select count(*) from clean.orders where flag_payment_mismatch)
    union all select 'flag: customers.flag_zip_not_in_geolocation', 279,
           (select count(*) from clean.customers where flag_zip_not_in_geolocation)
    union all select 'flag: order_items.flag_price_above_p99', 1117,
           (select count(*) from clean.order_items where flag_price_above_p99)
    union all select 'flag: order_items.flag_freight_above_p99', 1124,
           (select count(*) from clean.order_items where flag_freight_above_p99)
    union all select 'flag: order_items.flag_zero_freight', 383,
           (select count(*) from clean.order_items where flag_zero_freight)
    union all select 'flag: order_payments.flag_zero_value', 9,
           (select count(*) from clean.order_payments where flag_zero_value)
    union all select 'flag: order_payments.flag_payment_type_not_defined', 3,
           (select count(*) from clean.order_payments where flag_payment_type_not_defined)
    union all select 'flag: order_reviews.flag_multiple_reviews', 547,
           (select count(*) from clean.order_reviews where flag_multiple_reviews)
    union all select 'flag: products.flag_missing_category', 610,
           (select count(*) from clean.products where flag_missing_category)
    union all select 'flag: products.flag_zero_weight', 4,
           (select count(*) from clean.products where flag_zero_weight)
    union all select 'flag: products.flag_missing_dimensions', 2,
           (select count(*) from clean.products where flag_missing_dimensions)
    union all select 'flag: sellers.flag_zip_not_in_geolocation', 7,
           (select count(*) from clean.sellers where flag_zip_not_in_geolocation)

    -- -------------------------------------------------------------------------
    -- 6. Value sanity.
    -- Expected 0: docs/data_dictionary.md / Phase 2 profiling found minimum
    -- price R$0.85 and minimum freight and payment R$0.00 (no negatives).
    -- -------------------------------------------------------------------------
    union all
    select 'value: negative price', 0,
           (select count(*) from clean.order_items where price < 0)
    union all
    select 'value: negative freight_value', 0,
           (select count(*) from clean.order_items where freight_value < 0)
    union all
    select 'value: negative payment_value', 0,
           (select count(*) from clean.order_payments where payment_value < 0)
    union all
    -- Expected 0: [PS] "date_issue: customer delivery before purchase".
    -- Delivered orders with no customer date compare as NULL and are not counted.
    select 'value: delivered orders delivered before purchase', 0,
           (select count(*)
              from clean.orders
             where is_delivered
               and order_delivered_customer_date < order_purchase_timestamp)

    -- -------------------------------------------------------------------------
    -- 7. Views (analysis.*, built by sql/04_base_views.sql).
    -- Prove the SQL views reproduce the Phase 2 Python numbers exactly.
    -- -------------------------------------------------------------------------
    union all
    select 'views: v_orders rows = delivered orders', 96478,  -- [PS] delivered_orders
           (select count(*) from analysis.v_orders)
    union all
    select 'views: v_customers rows = customers with a delivered order', 93358,  -- [PS] customers_with_delivered_order
           (select count(*) from analysis.v_customers)
    union all
    select 'views: in-window cohort customers', 93094,  -- [CS] first_order_rule_B,cohort_customers_in_window
           (select count(*) from analysis.v_customers where in_window_cohort)
    union all
    select 'views: lifetime repeaters (later date)', 2004,  -- [CS] repeat_rule_A,lifetime_repeaters_without_same_day
           (select count(*) from analysis.v_customers where in_window_cohort and is_repeat_lifetime)
    union all
    select 'views: 180d eligible customers', 56188,  -- [CS] first_order_rule_B,eligible_180_day_customers
           (select count(*) from analysis.v_customers where eligible_180d)
    union all
    select 'views: 180d repeaters (later date)', 1112,  -- [CS] repeat_rule_A,within_180_days_repeaters_without_same_day
           (select count(*) from analysis.v_customers where is_repeat_180d)
    union all
    -- Expected 0: v_orders must have one row per order (items and payments
    -- aggregated before joining). Rows minus distinct order_ids = duplicates.
    select 'views: v_orders duplicate order_id rows', 0,
           (select count(*) - count(distinct order_id) from analysis.v_orders)
    union all
    -- Money reconciliation, in cents (whole numbers fit the bigint columns).
    -- Expected: recomputed independently from the clean tables (no Phase 2
    -- figure exists for delivered orders only). Proves no double counting.
    select 'views: v_orders product_value total = delivered sum(price) (cents)',
           (select (sum(oi.price) * 100)::bigint
              from clean.order_items oi
              join clean.orders o on o.order_id = oi.order_id
             where o.is_delivered),
           (select (sum(product_value) * 100)::bigint from analysis.v_orders)

    -- -------------------------------------------------------------------------
    -- 8. Buckets, bands and seller columns (Phase 4B).
    -- Reconciliation: every order / customer lands in exactly one bucket, so
    -- the bucket counts add up to the known totals (no gaps, no overlaps).
    -- -------------------------------------------------------------------------
    union all
    -- 96,478 delivered - 8 with no delivery date = 96,470.
    -- [PS] delivered_orders - [CS] flags,orders.flag_delivered_missing_customer_date
    select 'buckets: delay_bucket rows (orders with a delivery date)', 96478 - 8,
           (select count(*) from analysis.v_orders where delay_bucket is not null)
    union all
    select 'buckets: delay_bucket NULL rows (no delivery date)', 8,  -- [CS] flags,orders.flag_delivered_missing_customer_date
           (select count(*) from analysis.v_orders where delay_bucket is null)
    union all
    -- Bucket and flag agree: on-time bucket = not late; the 4 late buckets = late.
    select 'buckets: delay buckets 2-5 rows = is_late rows', 0,
           (select count(*) from analysis.v_orders
             -- left(..., 1) = the bucket number; NULL bucket and NULL is_late match.
             where (left(delay_bucket, 1) <> '1') is distinct from is_late)
    union all
    select 'buckets: delivery_speed_bucket rows (orders with a delivery date)', 96478 - 8,  -- same sources as above
           (select count(*) from analysis.v_orders where delivery_speed_bucket is not null)
    union all
    -- Every delivered order has items (so a main seller): same + cross = all.
    select 'buckets: same-state + cross-state orders = delivered orders', 96478,  -- [PS] delivered_orders
           (select count(*) from analysis.v_orders where is_same_state is not null)
    union all
    select 'buckets: freight_share_band rows = delivered orders', 96478,  -- [PS] delivered_orders
           (select count(*) from analysis.v_orders where freight_share_band is not null)
    union all
    -- The single order with no payment row is a delivered order (checked:
    -- clean.orders where flag_no_payment has order_status = 'delivered').
    select 'buckets: installment_band NULL rows (no payment)', 1,  -- [CS] flags,orders.flag_no_payment
           (select count(*) from analysis.v_orders where installment_band is null)
    union all
    select 'buckets: order_value_band rows = delivered orders', 96478,  -- [PS] delivered_orders
           (select count(*) from analysis.v_orders where order_value_band is not null)
    union all
    -- Customer level: the first-order delay buckets (incl. NULL) cover every
    -- eligible customer, and their repeaters add up to the 180d total.
    select 'buckets: eligible customers summed over first_delay_bucket', 56188,  -- [CS] first_order_rule_B,eligible_180_day_customers
           (select sum(n)::bigint from (select count(*) as n from analysis.v_customers
                                         where eligible_180d group by first_delay_bucket) g)
    union all
    select 'buckets: 180d repeaters summed over first_delay_bucket', 1112,  -- [CS] repeat_rule_A,within_180_days_repeaters_without_same_day
           (select sum(n)::bigint from (select count(*) filter (where is_repeat_180d) as n
                                          from analysis.v_customers
                                         where eligible_180d group by first_delay_bucket) g)
)

select check_name,
       expected::bigint          as expected,
       actual::bigint            as actual,
       (actual = expected)       as passed
from checks;
