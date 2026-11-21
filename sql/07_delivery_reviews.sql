-- =============================================================================
-- 07_delivery_reviews.sql
-- Purpose : delivery performance, its link to review scores, and whether the
--           first-order experience is associated with coming back.
-- Business question: is slow or late delivery (often caused by distance)
--           associated with bad reviews and with fewer repeat customers?
-- Tables  : analysis.v_orders, analysis.v_customers
--
-- Format: named queries (-- name: <query_name>), run by src/run_analysis.py.
-- Rules (docs/metrics.md):
--   * order-level queries: delivered orders purchased in the analysis window
--     (in_analysis_window);
--   * repeat queries: 180-day repeat rate on eligible customers only
--     (eligible_180d), grouped by attributes OF THE FIRST ORDER;
--   * late = delivery DATE after estimated DATE; orders with no delivery date
--     (8 delivered orders) are excluded from late/delay figures, so late %
--     uses count(is_late) (non-NULL rows) as the denominator;
--   * every rate is shown next to its n;
--   * 100.0 * ... forces decimal division (integer / integer would truncate);
--     NULLIF(x, 0) turns a zero denominator into NULL instead of an error.
-- These are associations, not proof of cause (Phase 5 tests them).
-- =============================================================================


-- name: q07_01_delivery_overview
-- Business question: how reliable is Olist's delivery overall?
-- Ordered-set aggregates (PERCENTILE_CONT) accept FILTER too: the last column
-- is the median delay of late orders only.
select
    count(*)                                                        as orders,
    count(is_late)                                                  as orders_with_delivery_date,
    count(*) filter (where not is_late)                             as on_time_orders,
    count(*) filter (where is_late)                                 as late_orders,
    round(100.0 * count(*) filter (where not is_late) / nullif(count(is_late), 0), 2) as on_time_pct,
    round(100.0 * count(*) filter (where is_late)     / nullif(count(is_late), 0), 2) as late_pct,
    round((percentile_cont(0.5) within group (order by delivery_days))::numeric, 2)      as median_delivery_days,
    round((percentile_cont(0.9) within group (order by delivery_days))::numeric, 2)      as p90_delivery_days,
    round((percentile_cont(0.5) within group (order by delay_days) filter (where is_late))::numeric, 2) as median_delay_days_late_orders
from analysis.v_orders
where in_analysis_window;


-- name: q07_02_by_state
-- Business question: which customer states get late or slow deliveries?
-- Only states with >= 500 in-window orders (docs/metrics.md minimum sizes).
select customer_state,
       count(*)                                                     as orders,
       count(is_late)                                               as orders_with_delivery_date,
       round(100.0 * count(*) filter (where is_late) / nullif(count(is_late), 0), 2) as late_pct,
       round((percentile_cont(0.5) within group (order by delivery_days))::numeric, 2)   as median_delivery_days
from analysis.v_orders
where in_analysis_window
group by customer_state
having count(*) >= 500
order by late_pct desc, customer_state;


-- name: q07_03_same_vs_cross_state
-- Business question: are orders shipped within the customer's own state faster
-- and more reliable, and do those customers come back more?
-- Order level and customer level have different grains, so each is
-- aggregated in its own CTE and the two are joined on the group.
with order_level as (
    select is_same_state,
           count(*)                                                 as orders,
           count(is_late)                                           as orders_with_delivery_date,
           round(100.0 * count(*) filter (where is_late) / nullif(count(is_late), 0), 2) as late_pct,
           round((percentile_cont(0.5) within group (order by delivery_days))::numeric, 2) as median_delivery_days
    from analysis.v_orders
    where in_analysis_window
    group by is_same_state
),
customer_level as (
    select first_is_same_state,
           count(*)                                                 as eligible_customers,
           count(*) filter (where is_repeat_180d)                   as repeaters_180d,
           round(100.0 * count(*) filter (where is_repeat_180d) / count(*), 2) as repeat_rate_180d_pct
    from analysis.v_customers
    where eligible_180d
    group by first_is_same_state
)
select case when o.is_same_state then 'same state' else 'cross state' end as seller_vs_customer,
       o.orders, o.orders_with_delivery_date, o.late_pct, o.median_delivery_days,
       c.eligible_customers, c.repeaters_180d, c.repeat_rate_180d_pct
from order_level o
left join customer_level c on c.first_is_same_state = o.is_same_state
order by o.is_same_state desc;


-- name: q07_04_monthly_late_trend
-- Business question: did delivery reliability change over time (e.g. around
-- peak season)?
select purchase_month,
       count(*)                                                     as orders,
       count(is_late)                                               as orders_with_delivery_date,
       round(100.0 * count(*) filter (where is_late) / nullif(count(is_late), 0), 2) as late_pct,
       round((percentile_cont(0.5) within group (order by delivery_days))::numeric, 2)   as median_delivery_days
from analysis.v_orders
where in_analysis_window
group by purchase_month
order by purchase_month;


-- name: q07_05_sellers
-- Business question: are late deliveries spread across all sellers, or
-- concentrated in a small group Olist could act on?
-- Orders are attributed to their main seller (seller of the highest-priced
-- item). Only sellers with >= 50 in-window orders, so a seller's late % is not
-- based on a handful of orders. "Worst 10%" = the ceil(10%) sellers with the
-- highest late %; ROW_NUMBER with tie-breaks picks exactly that many.
with seller_stats as (
    select main_seller_id,
           count(*)                                    as orders,
           count(is_late)                              as orders_with_delivery_date,
           count(*) filter (where is_late)             as late_orders
    from analysis.v_orders
    where in_analysis_window
    group by main_seller_id
    having count(*) >= 50
),
ranked as (
    select s.*,
           100.0 * late_orders / nullif(orders_with_delivery_date, 0) as late_pct,
           row_number() over (order by 1.0 * late_orders / nullif(orders_with_delivery_date, 0) desc,
                                       late_orders desc, main_seller_id) as worst_rank,
           count(*) over ()                            as n_sellers
    from seller_stats s
),
all_late as (
    select count(*) filter (where is_late) as all_late_orders
    from analysis.v_orders
    where in_analysis_window
)
select max(r.n_sellers)                                             as qualifying_sellers,
       sum(r.orders)                                                as qualifying_seller_orders,
       round((percentile_cont(0.5) within group (order by r.late_pct))::numeric, 2) as median_seller_late_pct,
       round((percentile_cont(0.9) within group (order by r.late_pct))::numeric, 2) as p90_seller_late_pct,
       ceil(0.1 * max(r.n_sellers))                                 as worst_10pct_sellers,
       sum(r.late_orders) filter (where r.worst_rank <= ceil(0.1 * r.n_sellers)) as worst_10pct_late_orders,
       sum(r.late_orders)                                           as qualifying_seller_late_orders,
       max(a.all_late_orders)                                       as all_in_window_late_orders,
       round(100.0 * sum(r.late_orders) filter (where r.worst_rank <= ceil(0.1 * r.n_sellers))
             / sum(r.late_orders), 2)                               as worst_10pct_share_of_qualifying_late_pct,
       round(100.0 * sum(r.late_orders) filter (where r.worst_rank <= ceil(0.1 * r.n_sellers))
             / max(a.all_late_orders), 2)                           as worst_10pct_share_of_all_late_pct,
       round(100.0 * sum(r.orders) filter (where r.worst_rank <= ceil(0.1 * r.n_sellers))
             / sum(r.orders), 2)                                    as worst_10pct_share_of_qualifying_orders_pct
from ranked r
cross join all_late a;


-- name: q07_06_reviews_by_delay
-- Business question: how much do review scores drop as deliveries get later?
-- Reviewed in-window orders with a delivery date only. Scores take only the
-- values 1-5, so the median is coarse (it jumps between whole numbers); the
-- mean and the % of 1-2 star reviews show the change more finely.
select delay_bucket,
       count(*)                                                     as reviewed_orders,
       round(100.0 * count(*) filter (where review_score = 1) / count(*), 2) as pct_score_1,
       round(100.0 * count(*) filter (where review_score = 2) / count(*), 2) as pct_score_2,
       round(100.0 * count(*) filter (where review_score = 3) / count(*), 2) as pct_score_3,
       round(100.0 * count(*) filter (where review_score = 4) / count(*), 2) as pct_score_4,
       round(100.0 * count(*) filter (where review_score = 5) / count(*), 2) as pct_score_5,
       percentile_cont(0.5) within group (order by review_score)    as median_score,
       round(avg(review_score), 2)                                  as mean_score,
       round(100.0 * count(*) filter (where review_score <= 2) / count(*), 2) as pct_1_2_star
from analysis.v_orders
where in_analysis_window
  and review_score is not null
  and delay_bucket is not null
group by delay_bucket
order by delay_bucket;


-- name: q07_07_repeat_by_first_order_late
-- Business question: do customers whose first order arrived late come back
-- less often than those whose first order arrived on time?
-- Two breakdowns stacked with UNION ALL: on time vs late, then by delay bucket.
-- The 2 eligible customers with no delivery date appear as 'no delivery date'.
with by_late as (
    select 'on time vs late'::text                                  as breakdown,
           case when first_is_late then '2 late'
                when not first_is_late then '1 on time'
                else '9 no delivery date' end                       as first_order_group,
           count(*)                                                 as eligible_customers,
           count(*) filter (where is_repeat_180d)                   as repeaters_180d
    from analysis.v_customers
    where eligible_180d
    group by 1, 2
),
by_bucket as (
    select 'delay bucket'::text,
           coalesce(first_delay_bucket, '9 no delivery date'),
           count(*),
           count(*) filter (where is_repeat_180d)
    from analysis.v_customers
    where eligible_180d
    group by 1, 2
)
select breakdown, first_order_group, eligible_customers, repeaters_180d,
       round(100.0 * repeaters_180d / eligible_customers, 2)        as repeat_rate_180d_pct
from (select * from by_late union all select * from by_bucket) u
order by breakdown desc, first_order_group;


-- name: q07_08_repeat_by_first_review
-- Business question: does the review a customer gave their first order
-- predict whether they come back? ('no review' kept as its own group.)
select coalesce(first_review_score::text, 'no review')              as first_review_score,
       count(*)                                                     as eligible_customers,
       count(*) filter (where is_repeat_180d)                       as repeaters_180d,
       round(100.0 * count(*) filter (where is_repeat_180d) / count(*), 2) as repeat_rate_180d_pct
from analysis.v_customers
where eligible_180d
group by 1
order by 1;


-- name: q07_09_repeat_late_within_category
-- Business question: is the late-vs-on-time repeat gap still there when we
-- compare customers who bought the SAME kind of product?
-- Why: categories differ both in how often people naturally rebuy (pet food vs
-- a sofa) and possibly in how often they arrive late. A raw late-vs-on-time
-- comparison could just reflect category mix (confounding). Comparing within
-- each category removes that particular effect.
-- Categories with >= 300 eligible customers. Late cells are small (often
-- 20-40 customers with 0-2 repeaters), so read gaps together with late_n.
-- gap_pp = on-time rate - late rate, in percentage points (positive = late is worse).
with cells as (
    select first_main_category                                      as main_category,
           count(*)                                                 as eligible_customers,
           count(*) filter (where not first_is_late)                as on_time_n,
           count(*) filter (where not first_is_late and is_repeat_180d) as on_time_repeaters,
           count(*) filter (where first_is_late)                    as late_n,
           count(*) filter (where first_is_late and is_repeat_180d) as late_repeaters
    from analysis.v_customers
    where eligible_180d
    group by first_main_category
    having count(*) >= 300
)
select main_category,
       eligible_customers,
       on_time_n,
       on_time_repeaters,
       round(100.0 * on_time_repeaters / nullif(on_time_n, 0), 2)   as on_time_rate_pct,
       late_n,
       late_repeaters,
       round(100.0 * late_repeaters / nullif(late_n, 0), 2)         as late_rate_pct,
       round(100.0 * on_time_repeaters / nullif(on_time_n, 0)
           - 100.0 * late_repeaters / nullif(late_n, 0), 2)         as gap_pp
from cells
order by gap_pp desc nulls last, main_category;


-- name: q07_10_repeat_by_delivery_speed
-- Business question: do customers whose first order arrived faster come back more?
select coalesce(first_delivery_speed_bucket, '9 no delivery date')  as first_delivery_speed,
       count(*)                                                     as eligible_customers,
       count(*) filter (where is_repeat_180d)                       as repeaters_180d,
       round(100.0 * count(*) filter (where is_repeat_180d) / count(*), 2) as repeat_rate_180d_pct
from analysis.v_customers
where eligible_180d
group by 1
order by 1;


-- name: q07_11_late_gap_category_summary
-- Business question: after allowing for product category, how big is the
-- late-vs-on-time repeat gap?
-- crude gap      = on-time rate - late rate over all eligible customers (no adjustment).
-- crude (covered)= the same, but only for customers in the categories of q07_09,
--                  so it is comparable with the within-category gap.
-- within-category gap = average of the per-category gaps, each weighted by the
--                  category's number of late customers (a simple stratified
--                  comparison: "compare like with like, then average").
-- If the within-category gap is close to the crude gap, category mix does not
-- explain the difference; if it shrinks a lot, category was a confounder.
with cells as (
    select first_main_category,
           count(*)                                                 as eligible_customers,
           count(*) filter (where not first_is_late)                as on_time_n,
           count(*) filter (where not first_is_late and is_repeat_180d) as on_time_repeaters,
           count(*) filter (where first_is_late)                    as late_n,
           count(*) filter (where first_is_late and is_repeat_180d) as late_repeaters
    from analysis.v_customers
    where eligible_180d
    group by first_main_category
    having count(*) >= 300
),
gaps as (
    select *,
           100.0 * on_time_repeaters / nullif(on_time_n, 0)
         - 100.0 * late_repeaters   / nullif(late_n, 0)             as gap_pp
    from cells
),
overall as (
    select count(*)                                                 as all_eligible,
           100.0 * count(*) filter (where not first_is_late and is_repeat_180d)
                 / count(*) filter (where not first_is_late)
         - 100.0 * count(*) filter (where first_is_late and is_repeat_180d)
                 / count(*) filter (where first_is_late)            as crude_gap_pp
    from analysis.v_customers
    where eligible_180d
)
select count(*)                                                     as categories,
       count(*) filter (where gap_pp > 0)                           as categories_late_worse,
       count(*) filter (where gap_pp <= 0)                          as categories_late_not_worse,
       sum(eligible_customers)                                      as customers_covered,
       round(100.0 * sum(eligible_customers) / max(o.all_eligible), 2) as pct_eligible_covered,
       sum(late_n)                                                  as late_customers_covered,
       round(max(o.crude_gap_pp), 2)                                as crude_gap_pp_all,
       round(100.0 * sum(on_time_repeaters) / sum(on_time_n)
           - 100.0 * sum(late_repeaters) / sum(late_n), 2)          as crude_gap_pp_covered,
       round(sum(gap_pp * late_n) / sum(late_n), 2)                 as within_category_gap_pp
from gaps
cross join overall o;
