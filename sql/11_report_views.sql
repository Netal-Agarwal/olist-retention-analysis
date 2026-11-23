-- =============================================================================
-- 11_report_views.sql
-- Purpose : the reporting layer for Power BI (schema `report`). A star schema
--           (one fact table + dimension tables) plus small pre-aggregated
--           views for logic that is risky to rebuild in DAX (right-censoring,
--           confidence intervals, excess-bad-review baselines, medians).
-- Business question: none new. This file only RESHAPES the Phase 4/5 results
--           so the dashboard shows exactly the same numbers. Every agg_* view
--           copies the logic of the query named in its comment; the quality
--           checks in sql/03_quality_checks.sql (section 10) prove they match.
-- Tables  : analysis.v_orders, analysis.v_customers, analysis.v_customer_rfm
--           (sql/04_base_views.sql); clean.products, clean.sellers.
--
-- Re-runnable: CREATE OR REPLACE VIEW. Run after 04_base_views.sql (the report
-- views read the analysis views). src/create_views.py runs both files and
-- drops the views in reverse dependency order (report first, no CASCADE).
-- Run it in the `olist` database only.
--
-- Naming: fact_* = one row per event (an order); dim_* = one row per thing
-- you filter or group by (a customer, a day, a category, a seller, a state);
-- agg_* = finished result tables that Power BI shows as they are.
-- =============================================================================

create schema if not exists report;


-- =============================================================================
-- STAR SCHEMA
-- =============================================================================

-- -----------------------------------------------------------------------------
-- report.fact_orders: one row per delivered order purchased INSIDE the
-- analysis window (2017-01-01 .. 2018-08-31, metrics.md metric 11).
-- Expected 96,211 rows (outputs/phase4/q07_01_delivery_overview.csv, orders).
-- Orders outside the window are left out so that no dashboard visual can
-- accidentally include the sparse 2016 months.
-- -----------------------------------------------------------------------------
create or replace view report.fact_orders as
with ranked as (
    -- Number each customer's delivered orders in time order over the FULL
    -- history (before the window filter), with exactly the ordering that
    -- analysis.v_customers uses for its first order (timestamp, then
    -- order_id). rn = 1 is therefore the customer's first_order_id.
    -- Done with a window function instead of joining analysis.v_customers:
    -- PostgreSQL cannot estimate that view's row count and picked a very
    -- slow nested-loop join. A quality check confirms the result
    -- (first orders in the fact = 93,094 in-window cohort customers).
    select v.*,
           row_number() over (partition by customer_unique_id
                              order by order_purchase_timestamp, order_id) as rn
    from analysis.v_orders v
)
select
    o.order_id,
    o.customer_unique_id,                         -- the real person (metric 1)
    o.purchase_date,                              -- joins to report.dim_date
    o.customer_state,                             -- joins to report.dim_state
    o.main_seller_id,                             -- joins to report.dim_seller (metric 18)
    o.seller_state,
    o.is_same_state                               as same_state,
    o.main_category,                              -- joins to report.dim_category (metric 12)
    o.product_value,                              -- product revenue (metric 3)
    o.freight_value,
    o.order_value,                                -- product + freight
    o.freight_share,                              -- metric 9
    o.n_items,
    o.delivery_days,                              -- metric 8; NULL with no delivery date
    o.delay_days,                                 -- metric 7; NULL with no delivery date
    o.is_late,                                    -- metric 7; NULL with no delivery date
    -- The bucket labels in analysis.v_orders start with a number ('1 early/on
    -- time') so they sort correctly in SQL. Power BI sorts with a separate
    -- sort column instead, so the label drops the 2-character prefix and the
    -- number goes into *_sort.
    substring(o.delay_bucket from 3)              as delay_bucket,
    left(o.delay_bucket, 1)::int                  as delay_bucket_sort,
    substring(o.delivery_speed_bucket from 3)     as delivery_speed_bucket,
    left(o.delivery_speed_bucket, 1)::int         as delivery_speed_bucket_sort,
    o.review_score,                               -- NULL when no review (never 0)
    o.review_score is not null                    as has_review,
    -- Bad review = 1 or 2 stars (metric 25). NULL (not false) when there is no
    -- review, so "no review" can never be counted as "not bad".
    o.review_score <= 2                           as is_bad_review,
    -- The customer's first delivered order across the FULL history (metric 6).
    -- An in-window order of a customer who first bought in 2016 is not a first order.
    o.rn = 1                                      as is_first_order
from ranked o
where o.in_analysis_window;


-- -----------------------------------------------------------------------------
-- report.dim_customer: one row per customer_unique_id with a delivered order
-- (93,358). Includes the 264 customers whose first order is before the window
-- so every fact row finds its customer; use in_window_cohort to restrict
-- customer metrics to the 93,094 cohort customers (metric 6 and 11).
-- -----------------------------------------------------------------------------
create or replace view report.dim_customer as
-- Why "stack and collapse" instead of a JOIN: the natural query is
--   v_customers LEFT JOIN v_customer_rfm USING (customer_unique_id).
-- PostgreSQL badly underestimates how many rows these two views return, so it
-- chose a nested-loop join (every customer compared with every customer) and
-- a simple count ran for more than 15 minutes. Instead we STACK the two views
-- (UNION ALL: customer facts on one row, RFM scores on another row, each with
-- NULLs for the other's columns) and COLLAPSE them to one row per customer
-- with GROUP BY. max() / bool_or() ignore NULLs, so each column takes the one
-- real value it has. This reuses both views unchanged and needs only one
-- hash aggregate. Customers outside the cohort have no RFM row, so their RFM
-- columns stay NULL (metric 16 covers in-window cohort customers only).
with stacked as (
    select customer_unique_id,
           in_window_cohort, eligible_180d, is_repeat_180d, is_repeat_lifetime,
           cohort_month, first_state, first_main_category, first_is_late,
           first_review_score, n_delivered_orders, total_product_value,
           null::int  as r_score, null::int as m_score,
           null::text as f_flag,  null::text as segment
    from analysis.v_customers
    union all
    select customer_unique_id,
           null, null, null, null,
           null, null, null, null,
           null, null, null,
           r_score, m_score, f_flag, segment
    from analysis.v_customer_rfm
),
customers as (
    select customer_unique_id,
           bool_or(in_window_cohort)    as in_window_cohort,
           bool_or(eligible_180d)       as eligible_180d,      -- first order 2017-01-01 .. 2018-03-04 (metric 5)
           bool_or(is_repeat_180d)      as is_repeat_180d,     -- stays NULL when not eligible (right-censoring)
           bool_or(is_repeat_lifetime)  as is_repeat_lifetime, -- later-date delivered order (metric 4)
           max(cohort_month)            as cohort_month,
           max(first_state)             as first_state,
           max(first_main_category)     as first_main_category,
           bool_or(first_is_late)       as first_is_late,
           max(first_review_score)      as first_review_score,
           max(n_delivered_orders)      as n_delivered_orders,
           max(total_product_value)     as total_product_value,
           max(r_score)                 as r_score,
           max(m_score)                 as m_score,
           max(f_flag)                  as f_flag,
           max(segment)                 as segment
    from stacked
    group by customer_unique_id
)
select
    customer_unique_id,
    in_window_cohort,
    eligible_180d,
    is_repeat_180d,
    is_repeat_lifetime,
    cohort_month,
    first_state,
    first_main_category,
    first_is_late,
    first_review_score,
    -- A readable label for the first review, with 'No review' as its own group
    -- (as in q07_08), and a sort column so 1..5 stars come before 'No review'.
    case when first_review_score is null then 'No review'
         when first_review_score = 1     then '1 star'
         else first_review_score || ' stars' end             as first_review_label,
    coalesce(first_review_score, 6)                           as first_review_sort,
    n_delivered_orders,
    total_product_value,
    r_score,
    m_score,
    f_flag,
    segment
from customers;


-- -----------------------------------------------------------------------------
-- report.dim_date: one row per calendar day of the analysis window,
-- 2017-01-01 .. 2018-08-31 (608 days, metric 11). fact_orders only holds
-- in-window orders, so this covers every purchase date in it (a quality check
-- proves it). A continuous calendar (no missing days) is what Power BI's
-- "Mark as date table" requires.
-- -----------------------------------------------------------------------------
create or replace view report.dim_date as
with days as (
    -- generate_series makes one row per day between the two bounds.
    select gs::date as date
    from generate_series(date '2017-01-01', date '2018-08-31', interval '1 day') as gs
)
select
    date,
    extract(year from date)::int                             as year,
    extract(quarter from date)::int                          as quarter,
    extract(month from date)::int                            as month_number,
    to_char(date, 'FMMonth')                                 as month_name,    -- 'January'; sort by month_number
    to_char(date, 'YYYY-MM')                                 as year_month,    -- '2017-01'; sorts correctly as text
    date_trunc('month', date)::date                          as month_start,
    to_char(date, 'FMDay')                                   as weekday,       -- 'Monday'; sort by weekday_number
    extract(isodow from date)::int                           as weekday_number, -- 1 = Monday .. 7 = Sunday
    date between date '2017-01-01' and date '2018-08-31'     as in_analysis_window
from days;


-- -----------------------------------------------------------------------------
-- report.dim_category: one row per product category (English name), including
-- 'unknown' for products with no category (metric 12).
-- -----------------------------------------------------------------------------
create or replace view report.dim_category as
select distinct category_name_english as main_category
from clean.products;


-- -----------------------------------------------------------------------------
-- report.dim_seller: one row per seller (3,095).
-- -----------------------------------------------------------------------------
create or replace view report.dim_seller as
select seller_id,
       seller_state,
       seller_city
from clean.sellers;


-- -----------------------------------------------------------------------------
-- report.dim_state: the 27 Brazilian federative units (26 states + the Federal
-- District, DF) with their name and IBGE macro-region. Written out as a small
-- inline table (VALUES) because the Olist data only has the 2-letter codes.
-- -----------------------------------------------------------------------------
create or replace view report.dim_state as
select state_code, state_name, region
from (values
    ('AC', 'Acre',                'North'),
    ('AP', 'Amapá',               'North'),
    ('AM', 'Amazonas',            'North'),
    ('PA', 'Pará',                'North'),
    ('RO', 'Rondônia',            'North'),
    ('RR', 'Roraima',             'North'),
    ('TO', 'Tocantins',           'North'),
    ('AL', 'Alagoas',             'Northeast'),
    ('BA', 'Bahia',               'Northeast'),
    ('CE', 'Ceará',               'Northeast'),
    ('MA', 'Maranhão',            'Northeast'),
    ('PB', 'Paraíba',             'Northeast'),
    ('PE', 'Pernambuco',          'Northeast'),
    ('PI', 'Piauí',               'Northeast'),
    ('RN', 'Rio Grande do Norte', 'Northeast'),
    ('SE', 'Sergipe',             'Northeast'),
    ('DF', 'Distrito Federal',    'Center-West'),
    ('GO', 'Goiás',               'Center-West'),
    ('MT', 'Mato Grosso',         'Center-West'),
    ('MS', 'Mato Grosso do Sul',  'Center-West'),
    ('ES', 'Espírito Santo',      'Southeast'),
    ('MG', 'Minas Gerais',        'Southeast'),
    ('RJ', 'Rio de Janeiro',      'Southeast'),
    ('SP', 'São Paulo',           'Southeast'),
    ('PR', 'Paraná',              'South'),
    ('RS', 'Rio Grande do Sul',   'South'),
    ('SC', 'Santa Catarina',      'South')
) as s(state_code, state_name, region);


-- =============================================================================
-- PRE-AGGREGATED VIEWS
-- Each one reproduces a Phase 4/5 query (named in its comment). They are not
-- related to the star schema in Power BI; visuals use them directly.
--
-- Wilson 95% confidence interval (metric 27), used for single rates below.
-- With k successes out of n, p = k / n and z = 1.959964:
--   centre     = p + z^2 / (2n)
--   half-width = z * sqrt( p(1-p)/n + z^2/(4n^2) )
--   bounds     = (centre -/+ half-width) / (1 + z^2/n)
-- This is the same formula statsmodels uses (proportion_confint, method
-- "wilson") in notebooks/03_statistical_tests.ipynb. Unlike "p +/- 1.96 x SE"
-- it never goes below 0%, which matters for rates around 2%.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- report.agg_cohort_retention: q05_03_cohort_retention (sql/05_retention.sql),
-- same logic, plus cohort_label for the matrix rows. 20 cohorts x 13 months =
-- 260 cells; 78 are censored and stay NULL (unknown, not 0).
-- -----------------------------------------------------------------------------
create or replace view report.agg_cohort_retention as
with cohorts as (
    select cohort_month, count(*) as cohort_size
    from analysis.v_customers
    where in_window_cohort
    group by cohort_month
),
returns as (
    -- Every later-date delivered order of a cohort customer, with its month offset.
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
    select cohort_month, month_number::int as month_number,
           count(distinct customer_unique_id) as customers_returning
    from returns
    where month_number <= 12
    group by cohort_month, month_number
),
grid as (
    -- Every cohort x month 0..12, so censored cells still appear (as NULL).
    select c.cohort_month, k.month_number, c.cohort_size
    from cohorts c
    cross join generate_series(0, 12) as k(month_number)
)
select g.cohort_month,
       to_char(g.cohort_month, 'YYYY-MM')               as cohort_label,
       g.month_number,
       g.cohort_size,
       case when g.cohort_month + g.month_number * interval '1 month' <= date '2018-08-01'
            then coalesce(r.customers_returning, 0) end as customers_returning,
       case when g.cohort_month + g.month_number * interval '1 month' <= date '2018-08-01'
            then round(100.0 * coalesce(r.customers_returning, 0) / g.cohort_size, 2) end as retention_pct
from grid g
left join returning_counts r
       on r.cohort_month = g.cohort_month and r.month_number = g.month_number;


-- -----------------------------------------------------------------------------
-- report.agg_time_to_second: the 5 bucket rows of q05_02_time_to_second, with
-- the quartiles of days_to_second repeated on every row (so a card can show
-- the median without a second table). Population: in-window cohort repeaters
-- (2,004). Right-censored: biased towards short gaps (metric 14).
-- -----------------------------------------------------------------------------
create or replace view report.agg_time_to_second as
with repeaters as (
    select days_to_second
    from analysis.v_customers
    where in_window_cohort and is_repeat_lifetime
),
bucketed as (
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
    select sort_order, label,
           count(*) as customers,
           round(100.0 * count(*) / sum(count(*)) over (), 2) as pct
    from bucketed
    group by sort_order, label
),
stats as (
    select percentile_cont(0.25) within group (order by days_to_second)::numeric as p25_days,
           percentile_cont(0.50) within group (order by days_to_second)::numeric as median_days,
           percentile_cont(0.75) within group (order by days_to_second)::numeric as p75_days,
           count(*)                                                              as repeaters
    from repeaters
)
select b.sort_order, b.label, b.customers, b.pct,
       s.repeaters, s.p25_days, s.median_days, s.p75_days
from buckets b
cross join stats s;


-- -----------------------------------------------------------------------------
-- report.agg_repeat_by_review: q07_08_repeat_by_first_review (180-day repeat
-- rate by the review score of the first order), plus a sort column and the
-- Wilson 95% CI. Population: 180-day eligible customers (56,188).
-- -----------------------------------------------------------------------------
create or replace view report.agg_repeat_by_review as
with groups as (
    select coalesce(first_review_score::text, 'no review')     as first_review_score,
           coalesce(first_review_score, 6)                      as sort_order,
           count(*)                                             as eligible_customers,
           count(*) filter (where is_repeat_180d)               as repeaters_180d
    from analysis.v_customers
    where eligible_180d
    group by 1, 2
),
rates as (
    select g.*,
           1.0 * repeaters_180d / eligible_customers            as p,
           1.959964::numeric                                    as z,
           eligible_customers::numeric                          as n   -- numeric, so the formula stays exact (round() needs numeric)
    from groups g
)
select first_review_score,
       case when sort_order = 6 then 'No review'
            when sort_order = 1 then '1 star'
            else sort_order || ' stars' end                     as review_label,
       sort_order,
       eligible_customers,
       repeaters_180d,
       round(100 * p, 2)                                        as repeat_rate_180d_pct,
       round(100 * (p + z^2 / (2 * n)
                    - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)))
                 / (1 + z^2 / n), 2)           as ci_low_pct,
       round(100 * (p + z^2 / (2 * n)
                    + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)))
                 / (1 + z^2 / n), 2)           as ci_high_pct
from rates;


-- -----------------------------------------------------------------------------
-- report.agg_repeat_by_category: q05_05_repeat_by_category (first-order main
-- category, >= 300 eligible customers, metric 17), plus the Wilson 95% CI.
-- Claim 11: only differences with non-overlapping CIs should be read.
-- -----------------------------------------------------------------------------
create or replace view report.agg_repeat_by_category as
with groups as (
    select first_main_category                                  as main_category,
           count(*)                                             as eligible_customers,
           count(*) filter (where is_repeat_180d)               as repeaters_180d
    from analysis.v_customers
    where eligible_180d
    group by first_main_category
    having count(*) >= 300
),
rates as (
    select g.*,
           1.0 * repeaters_180d / eligible_customers            as p,
           1.959964::numeric                                    as z,
           eligible_customers::numeric                          as n   -- numeric, so the formula stays exact (round() needs numeric)
    from groups g
)
select main_category,
       eligible_customers,
       repeaters_180d,
       round(100 * p, 2)                                        as repeat_rate_180d_pct,
       round(100 * (p + z^2 / (2 * n)
                    - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)))
                 / (1 + z^2 / n), 2)           as ci_low_pct,
       round(100 * (p + z^2 / (2 * n)
                    + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)))
                 / (1 + z^2 / n), 2)           as ci_high_pct
from rates;


-- -----------------------------------------------------------------------------
-- report.agg_bad_review_by_delay: q07_06_reviews_by_delay (reviewed in-window
-- orders with a delivery date, by delay bucket), plus the bad-review count,
-- its Wilson 95% CI, a display label and a sort column.
-- bad_review_rate_pct equals q07_06's pct_1_2_star.
-- -----------------------------------------------------------------------------
create or replace view report.agg_bad_review_by_delay as
with groups as (
    select delay_bucket,
           count(*)                                                     as reviewed_orders,
           count(*) filter (where review_score <= 2)                    as bad_reviews,
           round(100.0 * count(*) filter (where review_score = 1) / count(*), 2) as pct_score_1,
           round(100.0 * count(*) filter (where review_score = 2) / count(*), 2) as pct_score_2,
           round(100.0 * count(*) filter (where review_score = 3) / count(*), 2) as pct_score_3,
           round(100.0 * count(*) filter (where review_score = 4) / count(*), 2) as pct_score_4,
           round(100.0 * count(*) filter (where review_score = 5) / count(*), 2) as pct_score_5,
           round(avg(review_score), 2)                                  as mean_score
    from analysis.v_orders
    where in_analysis_window
      and review_score is not null
      and delay_bucket is not null
    group by delay_bucket
),
rates as (
    select g.*,
           1.0 * bad_reviews / reviewed_orders                          as p,
           1.959964::numeric                                            as z,
           reviewed_orders::numeric                                     as n
    from groups g
)
select substring(delay_bucket from 3)                                   as delay_bucket,
       left(delay_bucket, 1)::int                                       as delay_bucket_sort,
       left(delay_bucket, 1) <> '1'                                     as is_late,
       reviewed_orders,
       bad_reviews,
       round(100 * p, 2)                                                as bad_review_rate_pct,
       round(100 * (p + z^2 / (2 * n)
                    - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)))
                 / (1 + z^2 / n), 2)                      as ci_low_pct,
       round(100 * (p + z^2 / (2 * n)
                    + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)))
                 / (1 + z^2 / n), 2)                      as ci_high_pct,
       pct_score_1, pct_score_2, pct_score_3, pct_score_4, pct_score_5,
       mean_score
from rates;


-- -----------------------------------------------------------------------------
-- report.agg_excess_bad_reviews_state: q10_02_excess_bad_reviews_by_state
-- (sql/10_review_impact.sql), same logic and rounding, plus the state name
-- and region from report.dim_state. ESTIMATE (metric 26).
-- -----------------------------------------------------------------------------
create or replace view report.agg_excess_bad_reviews_state as
with reviewed as (
    select customer_state,
           is_late,
           review_score <= 2                                        as is_bad
    from analysis.v_orders
    where in_analysis_window
      and review_score is not null
      and is_late is not null
),
national as (
    -- National excess (same formula as q10_05): the common base for shares.
    select count(*) filter (where is_late and is_bad)
         - count(*) filter (where is_late)
           * (1.0 * count(*) filter (where not is_late and is_bad)
                  / count(*) filter (where not is_late))            as national_excess
    from reviewed
),
group_stats as (
    select customer_state                                           as state,
           count(*)                                                 as reviewed_orders,
           count(*) filter (where not is_late)                      as on_time_reviewed,
           count(*) filter (where is_late)                          as late_reviewed,
           count(*) filter (where not is_late and is_bad)           as on_time_bad,
           count(*) filter (where is_late and is_bad)               as late_bad
    from reviewed
    group by customer_state
    having count(*) >= 500
),
excess as (
    select s.*,
           1.0 * on_time_bad / nullif(on_time_reviewed, 0)          as on_time_rate,
           1.0 * late_bad    / nullif(late_reviewed, 0)             as late_rate,
           late_reviewed * (1.0 * on_time_bad / nullif(on_time_reviewed, 0)) as expected_late_bad
    from group_stats s
),
ranked as (
    select e.*,
           late_bad - expected_late_bad                             as excess_bad,
           rank() over (order by late_bad - expected_late_bad desc nulls last) as excess_rank
    from excess e
)
select r.excess_rank,
       r.state,
       ds.state_name,
       ds.region,
       r.reviewed_orders,
       r.late_reviewed                                              as late_reviewed_orders,
       round(100.0 * r.late_reviewed / r.reviewed_orders, 2)        as late_reviewed_pct,
       round(100 * r.on_time_rate, 2)                               as on_time_bad_review_rate_pct,
       round(100 * r.late_rate, 2)                                  as late_bad_review_rate_pct,
       r.late_bad                                                   as late_bad_reviews,
       round(r.expected_late_bad, 1)                                as expected_late_bad_reviews,
       round(r.excess_bad, 1)                                       as excess_bad_reviews,
       round(100 * r.excess_bad / n.national_excess, 2)             as share_of_national_excess_pct,
       round(100 * sum(r.excess_bad) over (order by r.excess_rank, r.state) / n.national_excess, 2)
                                                                    as cumulative_share_of_national_excess_pct,
       round(100 * r.excess_bad / sum(r.excess_bad) over (), 2)     as share_of_shown_states_excess_pct,
       'ESTIMATE'::text                                             as label,
       'excess = bad reviews on late orders - late reviewed orders x the state''s on-time bad-review rate; '
       || 'assumes late orders would otherwise have been reviewed like on-time ones (association, not proven cause); '
       || 'reviewed in-window delivered orders with a delivery date; shares use the national excess (q10_05)'::text
                                                                    as assumptions
from ranked r
cross join national n
left join report.dim_state ds on ds.state_code = r.state;


-- -----------------------------------------------------------------------------
-- report.agg_excess_bad_reviews_seller: q10_03_excess_bad_reviews_by_seller,
-- same logic: shares over ALL 411 qualifying sellers (>= 50 reviewed orders),
-- then the top 20 kept. ESTIMATE (metric 26). Claim 4 is only PARTLY
-- supported: concentration is real but moderate.
-- -----------------------------------------------------------------------------
create or replace view report.agg_excess_bad_reviews_seller as
with reviewed as (
    select main_seller_id,
           seller_state,
           is_late,
           review_score <= 2                                        as is_bad
    from analysis.v_orders
    where in_analysis_window
      and review_score is not null
      and is_late is not null
),
national as (
    select count(*) filter (where is_late and is_bad)
         - count(*) filter (where is_late)
           * (1.0 * count(*) filter (where not is_late and is_bad)
                  / count(*) filter (where not is_late))            as national_excess
    from reviewed
),
group_stats as (
    select main_seller_id,
           max(seller_state)                                        as seller_state,
           count(*)                                                 as reviewed_orders,
           count(*) filter (where not is_late)                      as on_time_reviewed,
           count(*) filter (where is_late)                          as late_reviewed,
           count(*) filter (where not is_late and is_bad)           as on_time_bad,
           count(*) filter (where is_late and is_bad)               as late_bad
    from reviewed
    group by main_seller_id
    having count(*) >= 50
),
excess as (
    select s.*,
           1.0 * on_time_bad / nullif(on_time_reviewed, 0)          as on_time_rate,
           1.0 * late_bad    / nullif(late_reviewed, 0)             as late_rate,
           late_reviewed * (1.0 * on_time_bad / nullif(on_time_reviewed, 0)) as expected_late_bad
    from group_stats s
),
ranked as (
    select e.*,
           late_bad - expected_late_bad                             as excess_bad,
           row_number() over (order by late_bad - expected_late_bad desc nulls last,
                                       late_reviewed desc, main_seller_id) as excess_rank,
           count(*) over ()                                         as qualifying_sellers
    from excess e
),
with_shares as (
    -- Window sums run over all qualifying sellers, BEFORE the top-20 filter.
    select r.*,
           sum(r.excess_bad) over (order by r.excess_rank)          as cumulative_excess,
           sum(r.excess_bad) over ()                                as all_sellers_excess
    from ranked r
)
select w.excess_rank,
       w.main_seller_id,
       -- Seller ids are 32-character hashes; a short label fits a table column.
       'Seller ' || left(w.main_seller_id, 8)                       as seller_label,
       w.seller_state,
       w.qualifying_sellers,
       w.reviewed_orders,
       w.late_reviewed                                              as late_reviewed_orders,
       round(100.0 * w.late_reviewed / w.reviewed_orders, 2)        as late_reviewed_pct,
       round(100 * w.on_time_rate, 2)                               as on_time_bad_review_rate_pct,
       round(100 * w.late_rate, 2)                                  as late_bad_review_rate_pct,
       w.late_bad                                                   as late_bad_reviews,
       round(w.expected_late_bad, 1)                                as expected_late_bad_reviews,
       round(w.excess_bad, 1)                                       as excess_bad_reviews,
       round(100 * w.excess_bad / n.national_excess, 2)             as share_of_national_excess_pct,
       round(100 * w.cumulative_excess / n.national_excess, 2)      as cumulative_share_of_national_excess_pct,
       round(100 * w.excess_bad / w.all_sellers_excess, 2)          as share_of_qualifying_sellers_excess_pct,
       'ESTIMATE'::text                                             as label,
       'excess = bad reviews on late orders - late reviewed orders x the seller''s on-time bad-review rate; '
       || 'assumes late orders would otherwise have been reviewed like the seller''s on-time ones (association); '
       || 'main-seller attribution; sellers with >= 50 reviewed orders; shares use the national excess (q10_05)'::text
                                                                    as assumptions
from with_shares w
cross join national n
where w.excess_rank <= 20;


-- -----------------------------------------------------------------------------
-- report.agg_excess_bad_reviews_route: q10_04_excess_bad_reviews_by_route,
-- same logic: seller state -> customer state routes with >= 200 reviewed
-- orders (48 routes), top 15 kept. ESTIMATE (metric 26).
-- -----------------------------------------------------------------------------
create or replace view report.agg_excess_bad_reviews_route as
with reviewed as (
    select seller_state || ' -> ' || customer_state                 as route,
           is_same_state,
           is_late,
           review_score <= 2                                        as is_bad
    from analysis.v_orders
    where in_analysis_window
      and review_score is not null
      and is_late is not null
),
national as (
    select count(*) filter (where is_late and is_bad)
         - count(*) filter (where is_late)
           * (1.0 * count(*) filter (where not is_late and is_bad)
                  / count(*) filter (where not is_late))            as national_excess
    from reviewed
),
group_stats as (
    select route,
           bool_and(is_same_state)                                  as is_same_state,
           count(*)                                                 as reviewed_orders,
           count(*) filter (where not is_late)                      as on_time_reviewed,
           count(*) filter (where is_late)                          as late_reviewed,
           count(*) filter (where not is_late and is_bad)           as on_time_bad,
           count(*) filter (where is_late and is_bad)               as late_bad
    from reviewed
    group by route
    having count(*) >= 200
),
excess as (
    select s.*,
           1.0 * on_time_bad / nullif(on_time_reviewed, 0)          as on_time_rate,
           1.0 * late_bad    / nullif(late_reviewed, 0)             as late_rate,
           late_reviewed * (1.0 * on_time_bad / nullif(on_time_reviewed, 0)) as expected_late_bad
    from group_stats s
),
ranked as (
    select e.*,
           late_bad - expected_late_bad                             as excess_bad,
           row_number() over (order by late_bad - expected_late_bad desc nulls last,
                                       late_reviewed desc, route)   as excess_rank,
           count(*) over ()                                         as qualifying_routes
    from excess e
),
with_shares as (
    select r.*,
           sum(r.excess_bad) over (order by r.excess_rank)          as cumulative_excess,
           sum(r.excess_bad) over ()                                as all_routes_excess
    from ranked r
)
select w.excess_rank,
       w.route,
       w.is_same_state,
       w.qualifying_routes,
       w.reviewed_orders,
       w.late_reviewed                                              as late_reviewed_orders,
       round(100.0 * w.late_reviewed / w.reviewed_orders, 2)        as late_reviewed_pct,
       round(100 * w.on_time_rate, 2)                               as on_time_bad_review_rate_pct,
       round(100 * w.late_rate, 2)                                  as late_bad_review_rate_pct,
       w.late_bad                                                   as late_bad_reviews,
       round(w.expected_late_bad, 1)                                as expected_late_bad_reviews,
       round(w.excess_bad, 1)                                       as excess_bad_reviews,
       round(100 * w.excess_bad / n.national_excess, 2)             as share_of_national_excess_pct,
       round(100 * w.cumulative_excess / n.national_excess, 2)      as cumulative_share_of_national_excess_pct,
       round(100 * w.excess_bad / w.all_routes_excess, 2)           as share_of_qualifying_routes_excess_pct,
       'ESTIMATE'::text                                             as label,
       'excess = bad reviews on late orders - late reviewed orders x the route''s on-time bad-review rate; '
       || 'assumes late orders would otherwise have been reviewed like the route''s on-time ones (association); '
       || 'routes with >= 200 reviewed orders; shares use the national excess (q10_05)'::text
                                                                    as assumptions
from with_shares w
cross join national n
where w.excess_rank <= 15;


-- -----------------------------------------------------------------------------
-- report.agg_campaign_baseline: ONE row with the two inputs of the
-- second-purchase campaign estimate in q09_05 (sql/09_prioritisation.sql):
-- the size of the "Promising high-value one-timers" segment and the median
-- second-visit product value (metric 22). The conversion rate is NOT here: it
-- is an assumption the dashboard user picks with a What-if parameter.
-- -----------------------------------------------------------------------------
create or replace view report.agg_campaign_baseline as
with segment as (
    select count(*) as segment_customers
    from analysis.v_customer_rfm
    where segment = 'Promising high-value one-timers'
),
second_visits as (
    -- Everything a 180-day repeater bought on their second purchase date.
    select c.customer_unique_id,
           sum(o.product_value)                                         as second_visit_product_value
    from analysis.v_customers c
    join analysis.v_orders o
      on o.customer_unique_id = c.customer_unique_id
     and o.purchase_date = c.second_purchase_date
    where c.eligible_180d and c.is_repeat_180d
    group by c.customer_unique_id
),
second_visit_median as (
    select count(*)                                                     as n_second_visits,
           round((percentile_cont(0.5) within group (order by second_visit_product_value))::numeric, 2) as median_second_visit_value
    from second_visits
)
select 'ESTIMATE'::text                                                 as label,
       'Promising high-value one-timers'::text                          as segment,
       s.segment_customers,
       m.n_second_visits,
       m.median_second_visit_value,
       'conversion rate is an assumption, not measured; one second visit per converted '
       || 'customer at the median second-visit product value of all 180d repeaters '
       || '(not specific to high-value customers); product revenue only; campaign cost not included'::text
                                                                        as assumptions
from segment s
cross join second_visit_median m;
