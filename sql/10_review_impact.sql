-- =============================================================================
-- 10_review_impact.sql
-- Purpose : size how many bad reviews go with late delivery, and where
--           (customer state, seller, seller -> customer route) they come from.
-- Business question: delivery reliability as a REPUTATION lever. How many
--           extra 1-2 star reviews come with late orders, and which states,
--           sellers and routes account for most of them?
-- Tables  : analysis.v_orders
--
-- Format: named queries (-- name: <query_name>), run by src/run_analysis.py
-- (results go to outputs/phase5/).
-- Rules (docs/metrics.md):
--   * population = delivered orders purchased in the analysis window that
--     have a review AND a delivery date (so on time / late is known);
--   * bad review = review_score 1 or 2 (metric 25);
--   * excess bad reviews (metric 26, ESTIMATE) =
--         bad reviews on late orders
--       - late reviewed orders x the group's ON-TIME bad-review rate.
--     In words: "how many more bad reviews the late orders got than they
--     would have if they had been reviewed like that group's on-time orders".
--     It assumes lateness causes the difference; it is an association.
--   * shares use the NATIONAL excess (q10_05) as the base, so every query is
--     on the same scale. A second share uses the sum over the groups shown.
--     The two differ: small groups are left out, and each group uses its own
--     on-time baseline, so group excesses do not add up to the national one.
--     A group can have NEGATIVE excess, so cumulative shares can pass 100%.
-- Every estimate row has label = 'ESTIMATE' and an `assumptions` column.
-- =============================================================================


-- name: q10_01_bad_review_gap
-- Business question: how much more often do late orders get a 1-2 star review?
-- Three rows: on time, late, and all. The gap and ratio compare each row with
-- the on-time row (so the on-time row shows 0 and 1).
with reviewed as (
    -- One row per reviewed, in-window delivered order with a delivery date.
    select is_late,
           review_score <= 2                                        as is_bad
    from analysis.v_orders
    where in_analysis_window
      and review_score is not null
      and is_late is not null
),
groups as (
    select case when is_late then '2 late' else '1 on time' end     as delivery_group,
           count(*)                                                 as reviewed_orders,
           count(*) filter (where is_bad)                           as bad_reviews
    from reviewed
    group by 1
    union all
    select '3 all', count(*), count(*) filter (where is_bad)
    from reviewed
),
on_time as (
    -- The on-time rate, used as the baseline for the gap and the ratio.
    select 100.0 * bad_reviews / reviewed_orders                    as on_time_rate_pct
    from groups
    where delivery_group = '1 on time'
)
select g.delivery_group,
       g.reviewed_orders,
       g.bad_reviews,
       round(100.0 * g.bad_reviews / g.reviewed_orders, 2)          as bad_review_rate_pct,
       round(100.0 * g.bad_reviews / g.reviewed_orders - o.on_time_rate_pct, 2) as gap_vs_on_time_pp,
       round(100.0 * g.bad_reviews / g.reviewed_orders / o.on_time_rate_pct, 2) as ratio_vs_on_time
from groups g
cross join on_time o
order by g.delivery_group;


-- name: q10_02_excess_bad_reviews_by_state
-- Business question: in which customer states do late deliveries add the most
-- bad reviews? States with >= 500 reviewed orders. Each state's late orders
-- are compared with that state's OWN on-time bad-review rate, so a state where
-- customers are generally harsher is not blamed for that.
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
           -- Bad reviews we would expect on the late orders at the on-time rate.
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
       r.reviewed_orders,
       r.late_reviewed                                              as late_reviewed_orders,
       round(100.0 * r.late_reviewed / r.reviewed_orders, 2)        as late_reviewed_pct,
       round(100 * r.on_time_rate, 2)                               as on_time_bad_review_rate_pct,
       round(100 * r.late_rate, 2)                                  as late_bad_review_rate_pct,
       r.late_bad                                                   as late_bad_reviews,
       round(r.expected_late_bad, 1)                                as expected_late_bad_reviews,
       round(r.excess_bad, 1)                                       as excess_bad_reviews,
       round(100 * r.excess_bad / n.national_excess, 2)             as share_of_national_excess_pct,
       -- Running total in rank order (state name breaks ties).
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
order by r.excess_rank, r.state;


-- name: q10_03_excess_bad_reviews_by_seller
-- Business question: which sellers' late deliveries add the most bad reviews?
-- Sellers with >= 50 reviewed orders (main-seller attribution, metric 18).
-- Shares are computed over ALL qualifying sellers first, then the top 20 by
-- excess are kept. ROW_NUMBER gives exactly 20 rows (ties: more late reviewed
-- orders first, then seller_id).
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
           max(seller_state)                                        as seller_state,  -- one state per seller
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
where w.excess_rank <= 20
order by w.excess_rank;


-- name: q10_04_excess_bad_reviews_by_route
-- Business question: which seller-state -> customer-state routes add the most
-- bad reviews through late delivery? Routes with >= 200 reviewed orders; top 15.
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
           bool_and(is_same_state)                                  as is_same_state,  -- same value on every row of a route
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
where w.excess_rank <= 15
order by w.excess_rank;


-- name: q10_05_excess_total
-- Business question (ESTIMATE): across Olist, how many bad reviews are
-- "extra" because orders arrived late, and what share of all bad reviews is that?
with reviewed as (
    select is_late,
           review_score <= 2                                        as is_bad
    from analysis.v_orders
    where in_analysis_window
      and review_score is not null
      and is_late is not null
),
totals as (
    select count(*)                                                 as reviewed_orders,
           count(*) filter (where is_bad)                           as bad_reviews,
           count(*) filter (where not is_late)                      as on_time_reviewed,
           count(*) filter (where not is_late and is_bad)           as on_time_bad,
           count(*) filter (where is_late)                          as late_reviewed,
           count(*) filter (where is_late and is_bad)               as late_bad
    from reviewed
),
calc as (
    select t.*,
           1.0 * on_time_bad / on_time_reviewed                     as on_time_rate,
           late_reviewed * (1.0 * on_time_bad / on_time_reviewed)   as expected_late_bad
    from totals t
)
select 'ESTIMATE'::text                                             as label,
       reviewed_orders,
       bad_reviews,
       round(100.0 * bad_reviews / reviewed_orders, 2)              as bad_review_rate_pct,
       late_reviewed                                                as late_reviewed_orders,
       late_bad                                                     as late_bad_reviews,
       round(100 * on_time_rate, 2)                                 as on_time_bad_review_rate_pct,
       round(expected_late_bad, 1)                                  as expected_late_bad_reviews,
       round(late_bad - expected_late_bad, 1)                       as excess_bad_reviews,
       round(100 * (late_bad - expected_late_bad) / bad_reviews, 2) as excess_share_of_all_bad_reviews_pct,
       round(100 * (late_bad - expected_late_bad) / late_bad, 2)    as excess_share_of_late_bad_reviews_pct,
       'excess = bad reviews on late orders - late reviewed orders x national on-time bad-review rate; '
       || 'assumes late orders would otherwise have been reviewed like on-time ones (association, not proven cause); '
       || 'reviewed in-window delivered orders with a delivery date only; bad review = score 1-2'::text
                                                                    as assumptions
from calc;
