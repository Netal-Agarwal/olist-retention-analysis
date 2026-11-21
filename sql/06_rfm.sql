-- =============================================================================
-- 06_rfm.sql
-- Purpose : summarise the RFM segmentation in analysis.v_customer_rfm.
-- Business question: which groups of customers hold the revenue, and how big
--           is the pool of one-time buyers Olist could try to win back?
-- Tables  : analysis.v_customer_rfm (in-window cohort customers, snapshot 2018-09-01)
--
-- Format: named queries (-- name: <query_name>), run by src/run_analysis.py.
-- =============================================================================


-- name: q06_01_segment_summary
-- Business question: how many customers and how much product revenue sit in
-- each RFM segment, and what do typical members look like?
-- SUM(...) OVER () is a window total across all segments, so each row can be
-- divided by the grand total without a second query.
-- Medians, not means: spend and recency are skewed (a few very large orders).
select segment,
       count(*)                                                       as customers,
       round(100.0 * count(*) / sum(count(*)) over (), 2)             as pct_customers,
       sum(monetary)                                                  as product_revenue,
       round(100.0 * sum(monetary) / sum(sum(monetary)) over (), 2)   as pct_revenue,
       percentile_cont(0.5) within group (order by monetary)          as median_monetary,
       percentile_cont(0.5) within group (order by recency_days)      as median_recency_days
from analysis.v_customer_rfm
group by segment
order by product_revenue desc;


-- name: q06_02_rm_grid
-- Business question: how are customers spread across recency x monetary
-- scores, separately for repeaters and one-timers? (Long format: one row per
-- f_flag, r_score, m_score; pivot in Excel/Power BI for a 5x5 heatmap.)
select f_flag,
       r_score,
       m_score,
       count(*) as customers
from analysis.v_customer_rfm
group by f_flag, r_score, m_score
order by f_flag, r_score desc, m_score desc;
