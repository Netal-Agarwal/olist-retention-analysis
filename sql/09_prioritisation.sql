-- =============================================================================
-- 09_prioritisation.sql
-- Purpose : rank where Olist should act first (states, sellers, categories)
--           and size two impacts as clearly labelled ESTIMATES.
-- Business question: what should Olist fix first to get more customers to
--           buy a second time, and roughly how much could it be worth?
-- Tables  : analysis.v_orders, analysis.v_customers, analysis.v_customer_rfm
--
-- Format: named queries (-- name: <query_name>), run by src/run_analysis.py.
-- Every estimate row has label = 'ESTIMATE' and an `assumptions` column.
-- Estimates rest on ASSOCIATIONS from 07/08; they assume the gap is caused by
-- the factor, which Phase 5 tests. They are not forecasts.
--
-- Shared definition, "second-visit product value": for an eligible customer who
-- repeated within 180 days, the product value (sum of price) of all delivered
-- orders on their second purchase date. It matches the date-based repeat rule
-- (a visit = a calendar day). Its MEDIAN is used as the revenue per extra
-- repeat customer (docs/metrics.md).
-- =============================================================================


-- name: q09_01_state_priority
-- Business question: in which states would fixing late first deliveries
-- matter most?
-- opportunity_repeaters_estimate = late-first-order eligible customers in the
-- state x (national on-time repeat rate - national late repeat rate).
-- "If this state's late first orders had repeated like on-time ones, how many
-- more repeaters?" It uses the NATIONAL gap (state-level late cells are too
-- small to give a stable gap of their own).
-- RANK() gives tied values the same rank and then skips (1, 2, 2, 4).
with national as (
    select 100.0 * count(*) filter (where not first_is_late and is_repeat_180d)
                 / count(*) filter (where not first_is_late)            as on_time_rate_pct,
           100.0 * count(*) filter (where first_is_late and is_repeat_180d)
                 / count(*) filter (where first_is_late)                as late_rate_pct
    from analysis.v_customers
    where eligible_180d
),
customers_by_state as (
    select first_state                                                  as state,
           count(*)                                                     as eligible_customers,
           count(*) filter (where is_repeat_180d)                       as repeaters_180d,
           count(*) filter (where first_is_late)                        as late_first_order_customers
    from analysis.v_customers
    where eligible_180d
    group by first_state
    having count(*) >= 500
),
orders_by_state as (
    select customer_state                                               as state,
           count(*)                                                     as orders,
           round(100.0 * count(*) filter (where is_late) / nullif(count(is_late), 0), 2) as late_pct,
           round((percentile_cont(0.5) within group (order by delivery_days))::numeric, 2)   as median_delivery_days,
           sum(product_value)                                           as product_revenue
    from analysis.v_orders
    where in_analysis_window
    group by customer_state
),
scored as (
    select c.state,
           o.orders,
           o.late_pct,
           o.median_delivery_days,
           o.product_revenue,
           c.eligible_customers,
           c.repeaters_180d,
           round(100.0 * c.repeaters_180d / c.eligible_customers, 2)    as repeat_rate_180d_pct,
           c.late_first_order_customers,
           round(n.on_time_rate_pct, 2)                                 as national_on_time_rate_pct,
           round(n.late_rate_pct, 2)                                    as national_late_rate_pct,
           round(c.late_first_order_customers * (n.on_time_rate_pct - n.late_rate_pct) / 100, 1)
                                                                        as opportunity_repeaters_estimate
    from customers_by_state c
    join orders_by_state o on o.state = c.state
    cross join national n
)
select rank() over (order by opportunity_repeaters_estimate desc)       as priority_rank,
       s.*,
       'ESTIMATE'::text                                                 as label,
       'late-first eligible customers x national (on-time - late) 180d repeat rate; '
       || 'assumes lateness causes the gap (Phase 5 tests this)'::text  as assumptions
from scored s
order by priority_rank, state;


-- name: q09_02_seller_priority
-- Business question: which sellers cause the most late deliveries?
-- Top 20 sellers (>= 50 in-window orders, main-seller attribution) by number
-- of late orders. ROW_NUMBER (not RANK) so exactly 20 rows come back even if
-- two sellers tie; ties are broken by orders, then seller_id.
with seller_stats as (
    select main_seller_id,
           max(seller_state)                                            as seller_state,
           count(*)                                                     as orders,
           count(is_late)                                               as orders_with_delivery_date,
           count(*) filter (where is_late)                              as late_orders,
           sum(product_value)                                           as product_revenue
    from analysis.v_orders
    where in_analysis_window
    group by main_seller_id
    having count(*) >= 50
),
all_late as (
    select count(*) filter (where is_late) as all_late_orders
    from analysis.v_orders
    where in_analysis_window
),
ranked as (
    select s.*,
           row_number() over (order by late_orders desc, orders desc, main_seller_id) as late_orders_rank
    from seller_stats s
)
select r.late_orders_rank,
       r.main_seller_id,
       r.seller_state,
       r.orders,
       r.late_orders,
       round(100.0 * r.late_orders / nullif(r.orders_with_delivery_date, 0), 2) as late_pct,
       r.product_revenue,
       round(100.0 * r.late_orders / a.all_late_orders, 2)              as share_of_all_late_pct,
       -- Running total: share of all late orders covered by the top N so far.
       round(100.0 * sum(r.late_orders) over (order by r.late_orders_rank) / a.all_late_orders, 2)
                                                                        as cumulative_share_of_all_late_pct
from ranked r
cross join all_late a
where r.late_orders_rank <= 20
order by r.late_orders_rank;


-- name: q09_03_category_priority
-- Business question: which product categories combine late delivery, low
-- repeat buying and high revenue? (Categories with >= 300 eligible customers.)
with customers_by_category as (
    select first_main_category                                          as main_category,
           count(*)                                                     as eligible_customers,
           count(*) filter (where is_repeat_180d)                       as repeaters_180d
    from analysis.v_customers
    where eligible_180d
    group by first_main_category
    having count(*) >= 300
),
orders_by_category as (
    select main_category,
           count(*)                                                     as orders,
           round(100.0 * count(*) filter (where is_late) / nullif(count(is_late), 0), 2) as late_pct,
           sum(product_value)                                           as product_revenue
    from analysis.v_orders
    where in_analysis_window
    group by main_category
)
select c.main_category,
       o.orders,
       o.late_pct,
       o.product_revenue,
       c.eligible_customers,
       c.repeaters_180d,
       round(100.0 * c.repeaters_180d / c.eligible_customers, 2)        as repeat_rate_180d_pct
from customers_by_category c
join orders_by_category o on o.main_category = c.main_category
order by o.product_revenue desc;


-- name: q09_04_impact_late_delivery
-- Business question (ESTIMATE): if customers whose first order arrived late
-- had come back at the on-time rate, how many extra repeat customers and how
-- much extra product revenue would that be?
with rates as (
    select count(*) filter (where first_is_late)                        as late_first_customers,
           100.0 * count(*) filter (where not first_is_late and is_repeat_180d)
                 / count(*) filter (where not first_is_late)            as on_time_rate_pct,
           100.0 * count(*) filter (where first_is_late and is_repeat_180d)
                 / count(*) filter (where first_is_late)                as late_rate_pct
    from analysis.v_customers
    where eligible_180d
),
second_visits as (
    -- Product value of the second visit of each 180-day repeater.
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
       r.late_first_customers,
       round(r.on_time_rate_pct, 2)                                     as on_time_rate_pct,
       round(r.late_rate_pct, 2)                                        as late_rate_pct,
       round(r.on_time_rate_pct - r.late_rate_pct, 2)                   as gap_pp,
       round(r.late_first_customers * (r.on_time_rate_pct - r.late_rate_pct) / 100, 1) as extra_repeaters_estimate,
       m.n_second_visits,
       round(m.median_second_visit_value::numeric, 2)                   as median_second_visit_value,
       round((r.late_first_customers * (r.on_time_rate_pct - r.late_rate_pct) / 100
              * m.median_second_visit_value)::numeric, 2)               as extra_product_revenue_estimate,
       'assumes the late-vs-on-time gap is caused by lateness (untested; Phase 5); '
       || '180-day horizon, 180d-eligible customers only (2017-01-01..2018-03-04 first orders); '
       || 'one second visit per extra repeater at the median second-visit product value; '
       || 'product revenue only (no freight, no margin)'::text          as assumptions
from rates r
cross join second_visit_median m;


-- name: q09_05_impact_second_purchase_campaign
-- Business question (ESTIMATE): if a second-purchase campaign converted part
-- of the "Promising high-value one-timers" segment, how many extra repeat
-- customers and how much product revenue could that be?
-- Sensitivity table: the conversion rates 1%, 2%, 5% are ASSUMPTIONS, not
-- measured. VALUES (...) builds a small inline table of them.
with segment as (
    select count(*) as segment_customers
    from analysis.v_customer_rfm
    where segment = 'Promising high-value one-timers'
),
second_visits as (
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
       s.segment_customers,
       r.assumed_conversion_pct,
       round(s.segment_customers * r.assumed_conversion_pct / 100, 1)   as extra_repeaters_estimate,
       m.n_second_visits,
       round(m.median_second_visit_value::numeric, 2)                   as median_second_visit_value,
       round((s.segment_customers * r.assumed_conversion_pct / 100
              * m.median_second_visit_value)::numeric, 2)               as extra_product_revenue_estimate,
       'conversion rate is an assumption, not measured; one second visit per converted '
       || 'customer at the median second-visit product value of all 180d repeaters '
       || '(not specific to high-value customers); product revenue only; campaign cost not included'::text
                                                                        as assumptions
from segment s
cross join second_visit_median m
cross join (values (1.0), (2.0), (5.0)) as r(assumed_conversion_pct)
order by r.assumed_conversion_pct;
