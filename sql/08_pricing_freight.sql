-- =============================================================================
-- 08_pricing_freight.sql
-- Purpose : how much customers pay for shipping and for the order, and whether
--           cost is associated with bad reviews or with not coming back.
-- Business question: is expensive freight (relative to the order) or the size
--           / payment structure of the first order linked to lower repeat buying?
-- Tables  : analysis.v_orders, analysis.v_customers
--
-- Format: named queries (-- name: <query_name>), run by src/run_analysis.py.
-- Order-level queries use in-window delivered orders; repeat queries use the
-- 180-day rate on eligible customers, grouped by the FIRST order's band.
-- Bands are defined once in analysis.v_orders (sql/04_base_views.sql) and
-- docs/metrics.md. Money values are skewed, so medians/quartiles are used.
-- =============================================================================


-- name: q08_01_freight_share_overview
-- Business question: how big a part of the bill is shipping, typically?
select count(*)                                                       as orders,
       round((percentile_cont(0.25) within group (order by freight_share))::numeric, 4)    as p25_freight_share,
       round((percentile_cont(0.50) within group (order by freight_share))::numeric, 4)    as median_freight_share,
       round((percentile_cont(0.75) within group (order by freight_share))::numeric, 4)    as p75_freight_share,
       round((percentile_cont(0.25) within group (order by freight_value))::numeric, 2)    as p25_freight_value,
       round((percentile_cont(0.50) within group (order by freight_value))::numeric, 2)    as median_freight_value,
       round((percentile_cont(0.75) within group (order by freight_value))::numeric, 2)    as p75_freight_value
from analysis.v_orders
where in_analysis_window;


-- name: q08_02_by_category
-- Business question: in which product categories is shipping a big share of
-- the bill? (Categories with >= 300 in-window orders.)
select main_category,
       count(*)                                                       as orders,
       round((percentile_cont(0.5) within group (order by order_value))::numeric, 2)       as median_order_value,
       round((percentile_cont(0.5) within group (order by freight_share))::numeric, 4)     as median_freight_share
from analysis.v_orders
where in_analysis_window
group by main_category
having count(*) >= 300
order by median_freight_share desc, main_category;


-- name: q08_03_by_state
-- Business question: do customers in some states pay much more for shipping?
-- (States with >= 500 in-window orders.)
select customer_state,
       count(*)                                                       as orders,
       round((percentile_cont(0.5) within group (order by freight_value))::numeric, 2)     as median_freight_value,
       round((percentile_cont(0.5) within group (order by freight_share))::numeric, 4)     as median_freight_share
from analysis.v_orders
where in_analysis_window
group by customer_state
having count(*) >= 500
order by median_freight_share desc, customer_state;


-- name: q08_04_reviews_by_freight_band
-- Business question: are customers who paid a high share of the bill in
-- freight less happy? (Reviewed in-window orders; mean shown alongside the
-- coarse 1-5 median, as in q07_06.)
select freight_share_band,
       count(*)                                                       as reviewed_orders,
       percentile_cont(0.5) within group (order by review_score)      as median_score,
       round(avg(review_score), 2)                                    as mean_score,
       round(100.0 * count(*) filter (where review_score <= 2) / count(*), 2) as pct_1_2_star
from analysis.v_orders
where in_analysis_window
  and review_score is not null
group by freight_share_band
order by freight_share_band;


-- name: q08_05_repeat_by_freight_band
-- Business question: do customers whose first order had expensive freight
-- (relative to the order) come back less?
select first_freight_share_band,
       count(*)                                                       as eligible_customers,
       count(*) filter (where is_repeat_180d)                         as repeaters_180d,
       round(100.0 * count(*) filter (where is_repeat_180d) / count(*), 2) as repeat_rate_180d_pct
from analysis.v_customers
where eligible_180d
group by first_freight_share_band
order by first_freight_share_band;


-- name: q08_06_installments
-- Business question: how do customers split payments, and is paying in many
-- instalments on the first order linked to coming back?
-- Two grains (orders, first-order customers) aggregated separately, then
-- joined on the band. installment_band is NULL only for the order with no
-- payment row; it is shown as 'no payment'.
with order_level as (
    select coalesce(installment_band, '9 no payment')                 as band,
           count(*)                                                   as orders,
           round((percentile_cont(0.5) within group (order by order_value))::numeric, 2)   as median_order_value
    from analysis.v_orders
    where in_analysis_window
    group by 1
),
customer_level as (
    select coalesce(first_installment_band, '9 no payment')           as band,
           count(*)                                                   as eligible_customers,
           count(*) filter (where is_repeat_180d)                     as repeaters_180d
    from analysis.v_customers
    where eligible_180d
    group by 1
)
select coalesce(o.band, c.band)                                       as installment_band,
       o.orders,
       o.median_order_value,
       c.eligible_customers,
       c.repeaters_180d,
       round(100.0 * c.repeaters_180d / nullif(c.eligible_customers, 0), 2) as repeat_rate_180d_pct
from order_level o
full join customer_level c on c.band = o.band
order by 1;


-- name: q08_07_repeat_by_order_value
-- Business question: do customers with a bigger first order come back more?
-- Bands (product + freight, R$): <50, 50-100, 100-200, 200-500, >=500. Round
-- numbers a business reader can use, chosen around the eligible first-order
-- quartiles (p25 R$61.58, median R$103.73, p75 R$174.42) with a top band for
-- large baskets; the n per band is in this query's output (docs/metrics.md).
select first_order_value_band,
       count(*)                                                       as eligible_customers,
       round((percentile_cont(0.5) within group (order by first_order_value))::numeric, 2) as median_first_order_value,
       count(*) filter (where is_repeat_180d)                         as repeaters_180d,
       round(100.0 * count(*) filter (where is_repeat_180d) / count(*), 2) as repeat_rate_180d_pct
from analysis.v_customers
where eligible_180d
group by first_order_value_band
order by first_order_value_band;
