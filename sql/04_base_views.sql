-- =============================================================================
-- 04_base_views.sql
-- Purpose : create the `analysis` schema and three reusable views that apply
--           the docs/metrics.md rules ONCE, so every later query starts from
--           the same definitions:
--             analysis.v_orders        one row per delivered order
--             analysis.v_customers     one row per customer_unique_id with a delivered order
--             analysis.v_customer_rfm  one row per in-window-cohort customer, with RFM scores
-- Business question: "Who buys, when, how much, and do they come back?" These
--           views are the base for retention (05_retention.sql), RFM
--           (06_rfm.sql) and the Power BI reporting layer.
-- Tables  : clean.orders, clean.customers, clean.order_items, clean.products,
--           clean.order_payments, clean.order_reviews
--
-- Re-runnable: CREATE OR REPLACE VIEW. Views store only the query, not data, so
-- they always reflect the current clean.* tables.
-- Note: CREATE OR REPLACE cannot remove or reorder columns of an existing view.
-- If you change the column list, drop the views first
-- (src/create_views.py: drop_views, or re-run src.load_to_postgres).
-- Run it in the `olist` database only (src/create_views.py runs it for you).
-- =============================================================================

create schema if not exists analysis;

-- -----------------------------------------------------------------------------
-- a. analysis.v_orders: one row per DELIVERED order (docs/metrics.md metric 2).
-- order_items and order_payments have several rows per order, so each is
-- aggregated to ONE row per order in its own CTE before any join. Joining the
-- raw rows directly would multiply money (an order with 3 items and 2 payments
-- would appear 6 times).
-- -----------------------------------------------------------------------------
create or replace view analysis.v_orders as
with items as (
    -- One row per order: money and counts summed over its item lines.
    select order_id,
           sum(price)                as product_value,  -- product revenue (metrics.md metric 3)
           sum(freight_value)        as freight_value,  -- freight revenue (freight is per item)
           count(*)                  as n_items,        -- number of item lines
           count(distinct seller_id) as n_sellers       -- different sellers in the order
    from clean.order_items
    group by order_id
),
-- "First row per group" CTEs below use DISTINCT ON (PostgreSQL-specific):
-- it keeps the FIRST row of each order_id in the ORDER BY order. It gives the
-- same result as ROW_NUMBER() ... WHERE rn = 1, but the planner estimates its
-- row count correctly (one row per order). With "rn = 1" it guessed ~0.5% of
-- rows, chose a nested loop and a filtered query on this view ran for minutes.
main_item as (
    -- The most expensive item of each order; its category is the order's main
    -- category. Ties on price go to the lowest order_item_id (repeatable).
    -- The same item also gives the order's main seller (Phase 4B): orders with
    -- several sellers (1,275 delivered orders) are attributed to the seller of
    -- the most expensive item.
    select distinct on (oi.order_id)
           oi.order_id,
           p.category_name_english as main_category,
           oi.seller_id            as main_seller_id
    from clean.order_items oi
    join clean.products p on p.product_id = oi.product_id
    order by oi.order_id, oi.price desc, oi.order_item_id
),
payment_totals as (
    -- One row per order: the largest number of instalments used by any payment.
    select order_id,
           max(payment_installments) as max_installments
    from clean.order_payments
    group by order_id
),
main_payment as (
    -- The payment type that paid the most of the order (largest payment_value;
    -- ties go to the lowest payment_sequential). 'not_defined' rows are left
    -- out (metrics.md: excluded from payment-type analysis).
    select distinct on (order_id)
           order_id,
           payment_type as main_payment_type
    from clean.order_payments
    where not flag_payment_type_not_defined
    order by order_id, payment_value desc, payment_sequential
)
select
    o.order_id,
    o.customer_id,
    c.customer_unique_id,                                  -- the real person (metrics.md metric 1)
    c.customer_state,
    c.customer_city,
    o.order_purchase_timestamp,
    o.order_purchase_timestamp::date                       as purchase_date,   -- calendar day of the purchase
    date_trunc('month', o.order_purchase_timestamp)::date  as purchase_month,  -- first day of the purchase month
    o.in_analysis_window,                                  -- purchase in 2017-01-01..2018-08-31
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    -- Days from purchase to customer delivery, with decimals (e.g. 8.43).
    -- extract(epoch ...) gives seconds; 86,400 seconds = 1 day.
    -- NULL for the 8 delivered orders with no customer delivery date.
    round((extract(epoch from (o.order_delivered_customer_date - o.order_purchase_timestamp))
           / 86400)::numeric, 2)                           as delivery_days,
    -- Whole days between the delivery DATE and the promised DATE.
    -- date - date gives an integer. Negative = arrived early, 0 = on the day.
    o.order_delivered_customer_date::date
        - o.order_estimated_delivery_date::date            as delay_days,
    -- Late = delivered on a later calendar day than promised (metrics.md metric 7).
    -- Compared as dates, not timestamps: the estimate has no time of day
    -- (it is stored as midnight), so a 10:00 delivery on the promised day
    -- would wrongly look late as a timestamp. NULL when no delivery date.
    o.order_delivered_customer_date::date
        > o.order_estimated_delivery_date::date            as is_late,
    i.product_value,
    i.freight_value,
    i.product_value + i.freight_value                      as order_value,     -- what the customer paid for goods + shipping
    -- Share of the order total that was shipping (metrics.md metric 9).
    -- nullif avoids dividing by zero; it is NULL if the order had no items.
    round(i.freight_value / nullif(i.product_value + i.freight_value, 0), 4) as freight_share,
    i.n_items,
    i.n_sellers,
    mi.main_category,                                      -- category of the highest-priced item
    pt.max_installments,
    mp.main_payment_type,                                  -- payment type with the largest payment_value
    r.review_score,                                        -- NULL when the order has no review (never 0)
    o.flag_delivered_missing_customer_date,
    o.flag_carrier_before_approval,
    o.flag_carrier_before_purchase,
    o.flag_delivery_before_carrier,
    o.flag_payment_mismatch,
    -- ---- Added in Phase 4B (new columns go at the END so CREATE OR REPLACE works) ----
    mi.main_seller_id,                                     -- seller of the highest-priced item
    s.seller_state,                                        -- state of that seller
    -- Seller and customer in the same state (a rough proxy for short distance).
    s.seller_state = c.customer_state                      as is_same_state,
    -- Buckets and bands are defined ONCE here so SQL queries, quality checks
    -- and Power BI all use the same edges. The number prefix makes labels sort
    -- in the right order. CASE stops at the first true line, so each line only
    -- needs its upper edge. NULL inputs fall through to NULL (no ELSE).
    case
        when o.order_delivered_customer_date is null then null
        when o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date <= 0  then '1 early/on time'
        when o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date <= 3  then '2 1-3 days late'
        when o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date <= 7  then '3 4-7 days late'
        when o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date <= 14 then '4 8-14 days late'
        else '5 15+ days late'
    end                                                    as delay_bucket,
    -- Delivery speed on the decimal delivery time (purchase -> customer), in days.
    case
        when o.order_delivered_customer_date is null then null
        when o.order_delivered_customer_date - o.order_purchase_timestamp <= interval '7 days'  then '1 <=7 days'
        when o.order_delivered_customer_date - o.order_purchase_timestamp <= interval '14 days' then '2 8-14 days'
        when o.order_delivered_customer_date - o.order_purchase_timestamp <= interval '21 days' then '3 15-21 days'
        when o.order_delivered_customer_date - o.order_purchase_timestamp <= interval '30 days' then '4 22-30 days'
        else '5 >30 days'
    end                                                    as delivery_speed_bucket,
    -- Freight as a share of the order total (metrics.md metric 9).
    case
        when i.product_value + i.freight_value is null or i.product_value + i.freight_value = 0 then null
        when i.freight_value / (i.product_value + i.freight_value) < 0.10 then '1 <10%'
        when i.freight_value / (i.product_value + i.freight_value) < 0.20 then '2 10-20%'
        when i.freight_value / (i.product_value + i.freight_value) < 0.30 then '3 20-30%'
        when i.freight_value / (i.product_value + i.freight_value) < 0.40 then '4 30-40%'
        else '5 >=40%'
    end                                                    as freight_share_band,
    -- Largest instalment count of the order. 0 (2 payment rows in the data)
    -- is treated as a single payment. NULL when the order has no payment row.
    case
        when pt.max_installments is null then null
        when pt.max_installments <= 1  then '1 0-1'
        when pt.max_installments <= 3  then '2 2-3'
        when pt.max_installments <= 6  then '3 4-6'
        when pt.max_installments <= 10 then '4 7-10'
        else '5 >10'
    end                                                    as installment_band,
    -- Order value (product + freight, R$) in round-number bands.
    case
        when i.product_value + i.freight_value is null then null
        when i.product_value + i.freight_value < 50  then '1 <50'
        when i.product_value + i.freight_value < 100 then '2 50-100'
        when i.product_value + i.freight_value < 200 then '3 100-200'
        when i.product_value + i.freight_value < 500 then '4 200-500'
        else '5 >=500'
    end                                                    as order_value_band
from clean.orders o
join clean.customers c       on c.customer_id = o.customer_id   -- every order has a customer (FK)
-- LEFT JOINs: an order with no items, payment or review is still kept.
left join items i            on i.order_id  = o.order_id
left join main_item mi       on mi.order_id = o.order_id
left join clean.sellers s    on s.seller_id = mi.main_seller_id
left join payment_totals pt  on pt.order_id = o.order_id
left join main_payment mp    on mp.order_id = o.order_id
left join clean.order_reviews r on r.order_id = o.order_id
where o.is_delivered;


-- -----------------------------------------------------------------------------
-- b. analysis.v_customers: one row per customer_unique_id with at least one
-- delivered order. The first order is found across the FULL history
-- (metrics.md metric 6); the analysis window is applied afterwards via the
-- in_window_cohort flag.
-- -----------------------------------------------------------------------------
create or replace view analysis.v_customers as
-- Built with window functions only (no join of the orders back to the first
-- order): every order row gets its customer's totals attached, then we keep
-- the first-order row. An earlier version joined two CTEs to each other and
-- was very slow, because PostgreSQL cannot estimate CTE row counts and chose a
-- nested-loop join (every order compared with every customer).
with ranked as (
    select v.*,
           -- Number each customer's delivered orders in time order.
           -- Ties on the same timestamp are broken by order_id so rn = 1 is unique.
           row_number() over (partition by customer_unique_id
                              order by order_purchase_timestamp, order_id) as rn,
           -- The first purchase DATE, copied onto every one of the customer's rows.
           min(purchase_date) over (partition by customer_unique_id) as first_date,
           -- 1 for the first order of each calendar day, so summing it counts distinct days.
           row_number() over (partition by customer_unique_id, purchase_date
                              order by order_purchase_timestamp, order_id) as rn_in_day
    from analysis.v_orders v
),
with_totals as (
    -- A window with only PARTITION BY (no ORDER BY) covers all the customer's
    -- rows, so these work like GROUP BY totals but keep every row.
    select r.*,
           count(*) over w                                                  as n_delivered_orders,
           sum(case when rn_in_day = 1 then 1 else 0 end) over w            as n_distinct_purchase_dates,
           -- Orders on the same calendar day as the first one (incl. the first).
           sum(case when purchase_date = first_date then 1 else 0 end) over w as n_orders_on_first_date,
           -- The first LATER calendar date with a delivered order (metrics.md metric 4).
           -- Same-day extra orders are ignored, so this is NULL for one-timers.
           min(case when purchase_date > first_date then purchase_date end) over w as second_purchase_date,
           sum(product_value) over w                                        as total_product_value,
           max(purchase_date) over w                                        as last_purchase_date
    from ranked r
    window w as (partition by customer_unique_id)
),
first_order as (
    -- Keep one row per customer: the first delivered order, now carrying the totals.
    select *
    from with_totals
    where rn = 1
)
select
    f.customer_unique_id,
    f.order_id                                         as first_order_id,
    f.purchase_date                                    as first_purchase_date,
    f.purchase_month                                   as cohort_month,      -- acquisition cohort
    -- First delivered order inside the analysis window (metrics.md metric 11).
    f.purchase_date between date '2017-01-01' and date '2018-08-31' as in_window_cohort,
    -- 180-day follow-up possible: 2018-03-04 + 180 days = 2018-08-31 (metrics.md metric 5).
    (f.purchase_date between date '2017-01-01' and date '2018-03-04') as eligible_180d,
    -- Attributes OF THE FIRST ORDER (what the customer experienced first).
    f.customer_state                                   as first_state,
    f.main_category                                    as first_main_category,
    f.order_value                                      as first_order_value,
    f.freight_share                                    as first_freight_share,
    f.is_late                                          as first_is_late,
    f.delay_days                                       as first_delay_days,
    f.delivery_days                                    as first_delivery_days,
    f.review_score                                     as first_review_score,
    f.n_delivered_orders::int                          as n_delivered_orders,
    f.n_distinct_purchase_dates::int                   as n_distinct_purchase_dates,
    f.n_orders_on_first_date::int                      as n_orders_on_first_date,
    f.second_purchase_date,
    f.second_purchase_date - f.purchase_date           as days_to_second,    -- integer days; NULL for one-timers
    -- Came back on a later calendar day, at any time.
    f.second_purchase_date is not null                 as is_repeat_lifetime,
    -- Came back on a later day within 180 days. NULL (not false) for customers
    -- who are not eligible, so they can never be counted as "did not return"
    -- just because we could not watch them for 180 days (right-censoring).
    case when f.purchase_date between date '2017-01-01' and date '2018-03-04'
         then coalesce(f.second_purchase_date - f.purchase_date <= 180, false)
    end                                                as is_repeat_180d,
    -- More than one delivered order, but all on one day: looks like a repeater
    -- only because of a split basket.
    (f.n_delivered_orders >= 2 and f.n_distinct_purchase_dates = 1) as same_day_only_repeater,
    f.total_product_value,
    f.last_purchase_date,
    -- ---- Added in Phase 4B (at the END): more attributes OF THE FIRST ORDER ----
    f.seller_state                                     as first_seller_state,
    f.is_same_state                                    as first_is_same_state,
    f.max_installments                                 as first_max_installments,
    f.delay_bucket                                     as first_delay_bucket,
    f.delivery_speed_bucket                            as first_delivery_speed_bucket,
    f.freight_share_band                               as first_freight_share_band,
    f.installment_band                                 as first_installment_band,
    f.order_value_band                                 as first_order_value_band
from first_order f;


-- -----------------------------------------------------------------------------
-- c. analysis.v_customer_rfm: Recency / Frequency / Monetary for every
-- in-window-cohort customer. Snapshot date 2018-09-01 = the day after the
-- analysis window ends ("today" for the analysis).
--
-- Why frequency is a flag, not a 1-5 score: about 97-98% of customers have a
-- single purchase date. Five equal-sized frequency buckets would put customers
-- with exactly the same frequency (1) into different buckets purely by the
-- tie-break, which means nothing. So F is split into 'repeat' vs 'one-time'.
--
-- NTILE(5) splits the ordered rows into 5 groups of (almost) equal size.
-- Customers with the same recency or monetary value can land in neighbouring
-- groups at a boundary; customer_unique_id is added to the ORDER BY so the
-- split is at least the same on every run.
-- -----------------------------------------------------------------------------
create or replace view analysis.v_customer_rfm as
with base as (
    select customer_unique_id,
           cohort_month,
           first_purchase_date,
           last_purchase_date,
           n_distinct_purchase_dates,
           date '2018-09-01' - last_purchase_date     as recency_days,  -- days since last purchase (date - date = integer)
           total_product_value                        as monetary       -- product revenue only (metrics.md metric 3)
    from analysis.v_customers
    where in_window_cohort
),
scored as (
    select b.*,
           -- Longest ago first, so the most recent customers end in group 5.
           ntile(5) over (order by recency_days desc, customer_unique_id) as r_score,
           -- Lowest spend first, so the highest spenders end in group 5.
           ntile(5) over (order by monetary, customer_unique_id)          as m_score,
           case when n_distinct_purchase_dates >= 2 then 'repeat' else 'one-time' end as f_flag
    from base b
)
select s.*,
       -- Segment mapping (docs/metrics.md). For one-timers, r 4-5 and r 1-2 are
       -- covered explicitly, so "Middle one-timers" is exactly r_score = 3.
       case
           when f_flag = 'repeat'   and r_score >= 4 and m_score >= 4 then 'Champions'
           when f_flag = 'repeat'                                       then 'Loyal repeaters'
           when r_score >= 4 and m_score >= 4                           then 'Promising high-value one-timers'
           when r_score >= 4 and m_score <= 3                           then 'Recent low-value one-timers'
           when r_score <= 2 and m_score >= 4                           then 'Lapsed high-value one-timers'
           when r_score <= 2 and m_score <= 3                           then 'Lapsed low-value one-timers'
           else 'Middle one-timers'
       end as segment
from scored s;
