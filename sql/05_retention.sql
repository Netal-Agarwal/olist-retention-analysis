-- =============================================================================
-- 05_retention.sql
-- Purpose : retention analysis on the analysis.* views (sql/04_base_views.sql).
-- Business question: how few customers come back, how fast do the ones who
--           return come back, and does it differ by cohort, state or category?
-- Tables  : analysis.v_customers, analysis.v_orders
--
-- Format: several separate SELECT queries. Each starts with a line
--   -- name: <query_name>
-- src/run_analysis.py splits the file on those lines, runs each query
-- read-only and saves outputs/phase4/<query_name>.csv. Each query can also be
-- copied into pgAdmin and run on its own.
--
-- Rules (docs/metrics.md): delivered orders only; customer = customer_unique_id;
-- repeat = delivered order on a LATER calendar date than the first; 180-day
-- metrics only on customers whose first order is on or before 2018-03-04.
-- =============================================================================


-- name: q05_01_headline
-- Business question: what share of new customers ever buys again, and within
-- 180 days? Must equal Phase 2 (outputs/phase2_cleaning_summary.csv):
-- 93,094 / 2,004 (2.15%) / 56,188 / 1,112 (1.98%) / 784 / 644.
-- COUNT(*) FILTER (WHERE ...) counts only the rows that meet the condition,
-- so many different counts come out of one pass over the table.
select
    count(*)                                                      as cohort_customers,
    round(100.0 * count(*) filter (where not is_repeat_lifetime) / count(*), 2) as one_time_pct,
    count(*) filter (where is_repeat_lifetime)                    as lifetime_repeaters,
    round(100.0 * count(*) filter (where is_repeat_lifetime) / count(*), 2)     as lifetime_repeat_rate_pct,
    count(*) filter (where eligible_180d)                         as eligible_180d_customers,
    count(*) filter (where is_repeat_180d)                        as repeaters_180d,
    round(100.0 * count(*) filter (where is_repeat_180d)
          / count(*) filter (where eligible_180d), 2)             as repeat_rate_180d_pct,
    -- Lifetime: more than one delivered order but no later-date order
    -- (all extra orders on the first day = a split basket, not a return).
    count(*) filter (where n_delivered_orders >= 2 and not is_repeat_lifetime) as same_day_only_lifetime,
    -- 180 days (Phase 2 definition): eligible, has an extra order on the first
    -- day, but no later-date order within 180 days.
    count(*) filter (where eligible_180d and n_orders_on_first_date >= 2
                       and not is_repeat_180d)                    as same_day_only_180d
from analysis.v_customers
where in_window_cohort;


-- name: q05_02_time_to_second
-- Business question: when customers do come back, how long do they take?
-- Population: in-window cohort customers who repeated (lifetime).
-- Caveat (right-censoring): a customer acquired in mid-2018 can only show a
-- short gap, because the data ends on 2018-08-31. Gaps here are therefore
-- biased towards short values; use it for the shape, not as a precise forecast.
with repeaters as (
    select days_to_second
    from analysis.v_customers
    where in_window_cohort and is_repeat_lifetime
),
bucketed as (
    -- CASE checks the conditions top to bottom and stops at the first match,
    -- so each line only needs its upper limit.
    select case when days_to_second <= 30  then 1
                when days_to_second <= 90  then 2
                when days_to_second <= 180 then 3
                when days_to_second <= 365 then 4
                else 5 end as sort_order,
           case when days_to_second <= 30  then '<=30 days'
                when days_to_second <= 90  then '31-90 days'
                when days_to_second <= 180 then '91-180 days'
                when days_to_second <= 365 then '181-365 days'
                else '>365 days' end as label
    from repeaters
),
buckets as (
    select 'bucket'::text as row_type, sort_order, label,
           count(*) as customers,
           -- SUM(...) OVER () = the total across all buckets, without collapsing rows.
           round(100.0 * count(*) / sum(count(*)) over (), 2) as pct,
           null::numeric as days
    from bucketed
    group by sort_order, label
),
stats as (
    -- PERCENTILE_CONT(p) sorts the values and returns the value at position p,
    -- interpolating between neighbours when needed. 0.5 = median.
    select percentile_cont(0.25) within group (order by days_to_second) as p25,
           percentile_cont(0.50) within group (order by days_to_second) as p50,
           percentile_cont(0.75) within group (order by days_to_second) as p75,
           count(*) as n
    from repeaters
)
select * from buckets
union all select 'stat', 6, 'p25 (days)',    n, null, p25::numeric from stats
union all select 'stat', 7, 'median (days)', n, null, p50::numeric from stats
union all select 'stat', 8, 'p75 (days)',    n, null, p75::numeric from stats
order by sort_order;


-- name: q05_03_cohort_retention
-- Business question: of the customers acquired in a month, what % come back
-- (a delivered order on a later calendar date) in each of the next 12 months?
-- month_number = calendar months between the purchase month and the cohort
-- month. Month 0 = came back later in the SAME calendar month (so it is not
-- 100%: first orders are not counted as returns).
-- Right-censoring: the data ends on 2018-08-31. For a cohort, month k is only
-- fully observed if cohort_month + k months <= 2018-08-01. Later cells are
-- left NULL (unknown), not 0, because those customers may still return in
-- months we cannot see. Treating them as 0 would make recent cohorts look worse.
with cohorts as (
    select cohort_month, count(*) as cohort_size
    from analysis.v_customers
    where in_window_cohort
    group by cohort_month
),
returns as (
    -- Every later-date delivered order of a cohort customer, with its month offset.
    -- (year*12 + month) turns a month into one running number, so the
    -- difference of two of them is the number of months between them.
    select c.customer_unique_id,
           c.cohort_month,
           (extract(year from o.purchase_month) * 12 + extract(month from o.purchase_month))
         - (extract(year from c.cohort_month)  * 12 + extract(month from c.cohort_month)) as month_number
    from analysis.v_customers c
    join analysis.v_orders o on o.customer_unique_id = c.customer_unique_id
    where c.in_window_cohort
      and o.purchase_date > c.first_purchase_date   -- later calendar date only
),
returning_counts as (
    -- A customer with two orders in the same month counts once (DISTINCT).
    select cohort_month, month_number::int as month_number,
           count(distinct customer_unique_id) as customers_returning
    from returns
    where month_number <= 12
    group by cohort_month, month_number
),
grid as (
    -- Every cohort x month 0..12, so missing and censored cells still appear.
    select c.cohort_month, k.month_number, c.cohort_size
    from cohorts c
    cross join generate_series(0, 12) as k(month_number)
)
select g.cohort_month,
       g.month_number,
       g.cohort_size,
       case when g.cohort_month + g.month_number * interval '1 month' <= date '2018-08-01'
            then coalesce(r.customers_returning, 0) end as customers_returning,
       case when g.cohort_month + g.month_number * interval '1 month' <= date '2018-08-01'
            then round(100.0 * coalesce(r.customers_returning, 0) / g.cohort_size, 2) end as retention_pct
from grid g
left join returning_counts r
       on r.cohort_month = g.cohort_month and r.month_number = g.month_number
order by g.cohort_month, g.month_number;


-- name: q05_04_repeat_by_state
-- Business question: does the 180-day repeat rate differ by the state of the
-- first order? Only states with >= 500 eligible customers, so a rate is not
-- driven by a handful of people (docs/metrics.md, minimum sample sizes).
-- HAVING filters groups after GROUP BY (WHERE filters rows before it).
select first_state                                         as state,
       count(*)                                            as eligible_customers,
       count(*) filter (where is_repeat_180d)              as repeaters_180d,
       round(100.0 * count(*) filter (where is_repeat_180d) / count(*), 2) as repeat_rate_180d_pct
from analysis.v_customers
where eligible_180d
group by first_state
having count(*) >= 500
order by repeat_rate_180d_pct desc, state;


-- name: q05_05_repeat_by_category
-- Business question: does the 180-day repeat rate differ by the main category
-- of the first order? Only categories with >= 300 eligible customers.
select first_main_category                                 as main_category,
       count(*)                                            as eligible_customers,
       count(*) filter (where is_repeat_180d)              as repeaters_180d,
       round(100.0 * count(*) filter (where is_repeat_180d) / count(*), 2) as repeat_rate_180d_pct
from analysis.v_customers
where eligible_180d
group by first_main_category
having count(*) >= 300
order by repeat_rate_180d_pct desc, main_category;


-- name: q05_06_monthly_trend
-- Business question: how did volume, new-customer acquisition and product
-- revenue develop month by month inside the analysis window?
with orders_by_month as (
    select purchase_month,
           count(*)           as delivered_orders,
           sum(product_value) as product_revenue
    from analysis.v_orders
    where in_analysis_window
    group by purchase_month
),
new_customers as (
    select cohort_month, count(*) as new_customers
    from analysis.v_customers
    where in_window_cohort
    group by cohort_month
)
select o.purchase_month,
       o.delivered_orders,
       coalesce(n.new_customers, 0) as new_customers,
       o.product_revenue
from orders_by_month o
left join new_customers n on n.cohort_month = o.purchase_month
order by o.purchase_month;


-- name: q05_07_cohort_retention_summary
-- Business question: what is TYPICAL month-k retention across cohorts?
-- Two summaries per month_number, using only fully observed (non-censored)
-- cells, i.e. cohort_month + k months <= 2018-08-01:
--   pooled_retention_pct = all returning customers / all cohort customers
--                          (big cohorts weigh more)
--   median_cohort_retention_pct = median of the per-cohort percentages
--                          (every cohort counts once)
-- The cell logic repeats q05_03 so this query can run on its own.
with cohorts as (
    select cohort_month, count(*) as cohort_size
    from analysis.v_customers
    where in_window_cohort
    group by cohort_month
),
returns as (
    select c.customer_unique_id,
           c.cohort_month,
           ((extract(year from o.purchase_month) * 12 + extract(month from o.purchase_month))
          - (extract(year from c.cohort_month)  * 12 + extract(month from c.cohort_month)))::int as month_number
    from analysis.v_customers c
    join analysis.v_orders o on o.customer_unique_id = c.customer_unique_id
    where c.in_window_cohort
      and o.purchase_date > c.first_purchase_date
),
returning_counts as (
    -- Count each cohort x month once (GROUP BY), then join; this is much
    -- faster than a subquery that re-scans `returns` for every cell.
    select cohort_month, month_number,
           count(distinct customer_unique_id) as customers_returning
    from returns
    where month_number <= 12
    group by cohort_month, month_number
),
cells as (
    select c.cohort_month, k.month_number, c.cohort_size,
           coalesce(rc.customers_returning, 0) as customers_returning
    from cohorts c
    cross join generate_series(0, 12) as k(month_number)
    left join returning_counts rc
           on rc.cohort_month = c.cohort_month and rc.month_number = k.month_number
    -- keep only fully observed cells
    where c.cohort_month + k.month_number * interval '1 month' <= date '2018-08-01'
)
select month_number,
       count(*)                                                    as cohorts_observed,
       sum(cohort_size)                                            as customers_observed,
       sum(customers_returning)                                    as customers_returning,
       round(100.0 * sum(customers_returning) / sum(cohort_size), 2) as pooled_retention_pct,
       round((percentile_cont(0.5) within group
              (order by 100.0 * customers_returning / cohort_size))::numeric, 2) as median_cohort_retention_pct
from cells
group by month_number
order by month_number;
