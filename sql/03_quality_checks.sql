-- =============================================================================
-- 03_quality_checks.sql
-- Purpose : prove the load into the clean schema is complete and correct.
-- Business question: "Can we trust the database copy of the data?" Every
--           Phase 4+ number depends on the answer being yes.
-- Tables  : all 8 clean.* tables.
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
)

select check_name,
       expected::bigint          as expected,
       actual::bigint            as actual,
       (actual = expected)       as passed
from checks;
