# Phase 4: Core SQL analysis

## Part A: base views, retention and RFM

Files:
- `sql/04_base_views.sql` creates schema `analysis` with three views: `v_orders`, `v_customers`, `v_customer_rfm`.
- `src/create_views.py` runs that file in one transaction. `src/load_to_postgres.py` now drops the views before the reload and recreates them afterwards.
- `sql/05_retention.sql` (7 queries) and `sql/06_rfm.sql` (2 queries) hold named SELECTs. `src/run_analysis.py` runs them read-only and saves `outputs/phase4/<query_name>.csv`.
- `sql/03_quality_checks.sql` section 7 has 8 new checks on the views (52 of 52 pass, before and after a full reload).

Every number below comes from those CSVs or from `outputs/phase3_quality_checks.csv`.

---

## 1. Views
A **view** is a saved SELECT with a name. `select * from analysis.v_orders` runs the stored query against the current `clean.*` tables. It stores no data, so it can never go stale.

Why bother? The tricky rules (delivered only, `customer_unique_id`, first order from the full history, a repeat must be on a later calendar date, the 180-day eligibility rule) are written **once**. Every retention query, every RFM query and later Power BI all read the same definitions. If a rule changes, you change one file.

Two practical consequences:
- `create or replace view` can add columns at the end but cannot remove or reorder them. To change a column list, drop the views first.
- A table cannot be dropped while a view depends on it (unless you use `CASCADE`, which we deliberately avoid). That is why the loader now drops the views first, children before parents (`v_customer_rfm` → `v_customers` → `v_orders`), and rebuilds them after the COPYs, all inside the same transaction.

## 2. CTEs (`with … as (…)`)
A CTE is a named step inside one query. `v_orders` is built from CTEs that each produce **one row per order**:
```sql
with items as (
    select order_id, sum(price) as product_value, sum(freight_value) as freight_value,
           count(*) as n_items, count(distinct seller_id) as n_sellers
    from clean.order_items
    group by order_id
), ...
```
This is the fix for the double-counting trap. If you joined `order_items` (several rows per order) straight to `order_payments` (also several rows per order), an order with 3 items and 2 payments would appear 3 × 2 = 6 times, and `sum(price)` would be six times too big. The quality check proves it didn't happen: `sum(v_orders.product_value)` equals the sum of `price` over delivered orders to the cent, R$13,221,498.11.

## 3. Window functions
A window function computes something across a group of rows **without collapsing them** (unlike GROUP BY). `over (partition by X order by Y)` means "for each X separately, in Y order".

**ROW_NUMBER**, which picks the first order (`v_customers`):
```sql
row_number() over (partition by customer_unique_id
                   order by order_purchase_timestamp, order_id) as rn
```
Each customer's orders are numbered 1, 2, 3… in time order, and `rn = 1` is the first order. `order_id` is a tie-breaker, so two orders with the same timestamp still get a fixed order.

**Aggregate OVER a partition** (COUNT/SUM/MIN/MAX OVER). With only `partition by` and no `order by`, the window is all of the customer's rows:
```sql
count(*) over w as n_delivered_orders,
min(case when purchase_date > first_date then purchase_date end) over w as second_purchase_date
...
window w as (partition by customer_unique_id)
```
Every order row gets its customer's totals, and we keep the `rn = 1` row. This is like GROUP BY plus a join back, but without the join. We rewrote the view this way because the first version joined two CTEs to each other. PostgreSQL has no row estimates for CTEs, so it chose a nested-loop join, and a simple count ran for over 2 minutes before we cancelled it.

**SUM OVER ()**: an empty window is the whole result, which gives "% of total" in one pass (`q06_01_segment_summary`):
```sql
round(100.0 * sum(monetary) / sum(sum(monetary)) over (), 2) as pct_revenue
```
The inner `sum(monetary)` is the GROUP BY total per segment, and the outer `sum(...) over ()` adds those up across all segments.

**NTILE(5)** splits the ordered rows into 5 equal-sized groups (quintiles):
```sql
ntile(5) over (order by recency_days desc, customer_unique_id) as r_score   -- most recent = 5
ntile(5) over (order by monetary, customer_unique_id)          as m_score   -- biggest spend = 5
```
Caveat: NTILE cuts by position, not value. Two customers with the same recency can land in groups 3 and 4 if the cut falls between them. The `customer_unique_id` tie-break doesn't remove that, but it makes the result the same on every run.

**LAG / LEAD** look at the previous or next row in the window. They are an alternative way to find the second purchase:
```sql
lead(purchase_date) over (partition by customer_unique_id order by purchase_date)
```
gives each order the next order's date. We didn't use it, because the next order may be on the **same** day, and that doesn't count as a repeat. `min(purchase_date) filter (where purchase_date > first_date)` says "first later calendar date" directly.

**DISTINCT ON** (PostgreSQL only) keeps the first row per group in the ORDER BY order. `v_orders` uses it for the main category and main payment type:
```sql
select distinct on (oi.order_id) oi.order_id, p.category_name_english as main_category
from clean.order_items oi join clean.products p on p.product_id = oi.product_id
order by oi.order_id, oi.price desc, oi.order_item_id
```
That reads as "per order, the most expensive item; ties go to the lowest item number". We first wrote it as `row_number() … where rn = 1`. That gives the same result, but the planner guessed `rn = 1` keeps ~0.5% of rows, and a filtered count on the view took over 60 seconds. With DISTINCT ON it takes 0.2 s, and all 9 output CSVs stayed byte-identical.

## 4. Dates: `::date`, DATE_TRUNC and date arithmetic
- `order_purchase_timestamp::date` drops the time of day. Repeats are judged on calendar dates.
- `date_trunc('month', ts)::date` gives the first day of the month (cohort month).
- `date - date` gives an **integer** number of days (`delay_days`, `days_to_second`, `recency_days = date '2018-09-01' - last_purchase_date`).
- `timestamp - timestamp` gives an **interval**. For `delivery_days` with decimals, `extract(epoch from interval)` gives seconds, and dividing by 86,400 gives days.
- Lateness compares **dates**: `delivered::date > estimated::date`. The estimate is stored as midnight, so a timestamp comparison would call a delivery at 10:00 on the promised day "late". Result: 6,534 late delivered orders, and 8 with no delivery date stay NULL.
- Month offset (q05_03): `(year*12 + month)` turns a month into one running number, so the difference between two of them is the number of months between them.

## 5. CASE buckets
`q05_02_time_to_second`:
```sql
case when days_to_second <= 30  then '<=30 days'
     when days_to_second <= 90  then '31-90 days'
     ...
     else '>365 days' end
```
CASE stops at the first true condition, so each line only needs its upper limit. The same idea maps R/M scores to segments in `v_customer_rfm` (first match wins).

## 6. COUNT(*) FILTER (WHERE …)
Counts only the rows that meet a condition, so many counts come out of one pass (`q05_01_headline`):
```sql
count(*) filter (where is_repeat_lifetime)   as lifetime_repeaters,
count(*) filter (where eligible_180d)        as eligible_180d_customers,
count(*) filter (where is_repeat_180d)       as repeaters_180d
```
It is the same as `sum(case when … then 1 else 0 end)`, but shorter and easier to read.

## 7. PERCENTILE_CONT
`percentile_cont(0.5) within group (order by days_to_second)` sorts the values and returns the median, interpolating between the two middle values when needed (which is why p25 is 22.75 days). We use medians because the values are skewed: a few very long gaps or very large baskets would pull a mean up.

## 8. HAVING and minimum sample sizes
`having count(*) >= 500` filters **groups** after GROUP BY, while WHERE filters rows before it. With a ~2% repeat rate, a state with 100 eligible customers has about 2 repeaters, and one person more or less moves its rate by a whole percentage point. So we show states with ≥ 500 and categories with ≥ 300 eligible customers (14 states and 24 categories qualify). Whether the differences are real is a Phase 5 question (statistical tests).

## 9. Right-censoring and the 180-day rule
The data stops on 2018-08-31. A customer who first bought on 2018-08-20 has had 11 days to come back. If they haven't yet, that is "not yet", not "never". Counting them as non-returners would drag the repeat rate down for every recent cohort.

Three places handle this:
- **180-day repeat rate**: only customers whose first purchase is on or before 2018-03-04 (+180 days = 2018-08-31), so everybody gets a full 180 days. `is_repeat_180d` is NULL (not false) for everyone else, so they can't be miscounted by accident.
- **Cohort table** (q05_03): a cell is NULL when cohort month + k is after 2018-08. There are 78 such cells (1 + 2 + … + 12 for the 2017-09 to 2018-08 cohorts).
- **Time to second purchase**: it can't be fully fixed, so it is stated as a caveat. Recent cohorts can only show short gaps.

---

## Results (Part A)

**Headline** (`q05_01_headline`, equal to Phase 2):

| Measure | Value |
|---|---|
| In-window cohort customers | 93,094 |
| One-time (no later-date order) | 97.85% |
| Lifetime repeaters | 2,004 (2.15%) |
| 180-day eligible customers | 56,188 |
| 180-day repeaters | 1,112 (1.98%) |
| Same-day-only "repeaters", lifetime / 180 days | 784 / 644 |

**Time to second purchase** (`q05_02`, 2,004 lifetime repeaters): ≤30 days 598 (29.84%), 31–90 days 507 (25.30%), 91–180 days 423 (21.11%), 181–365 days 398 (19.86%), >365 days 78 (3.89%). Quartiles: p25 22.75 days, median 74 days, p75 174 days.

**Cohort retention** (`q05_07`, observed cells only, pooled): month 0 0.37%, month 1 0.48%, month 2 0.34%, month 3 0.26%, then 0.16–0.26% in months 4–12. The highest single cell in any cohort is 0.72% (2017-10 cohort, month 1; `q05_03`).

**180-day repeat rate by state** (`q05_04`): highest MT 2.91%, ES 2.41%, SP 2.23%, RJ 2.06%, GO 1.93%; lowest CE 1.13%, PA 1.14%, SC 1.46%, PE 1.49%, BA 1.60%.

**By first-order category** (`q05_05`): highest fashion_bags_accessories 3.30%, pet_shop 2.99%, bed_bath_table 2.70%, sports_leisure 2.63%, furniture_decor 2.41%; lowest musical_instruments 0.92%, cool_stuff 1.04%, small_appliances 1.35%, consoles_games 1.36%, luggage_accessories 1.42%.

**RFM segments** (`q06_01`):

| Segment | Customers | % customers | % revenue | Median monetary (R$) | Median recency (days) |
|---|---|---|---|---|---|
| Lapsed high-value one-timers | 14,031 | 15.07 | 29.49 | 179.99 | 382 |
| Promising high-value one-timers | 14,533 | 15.61 | 29.48 | 177.67 | 96 |
| Middle one-timers | 18,245 | 19.60 | 18.19 | 87.00 | 221 |
| Lapsed low-value one-timers | 22,630 | 24.31 | 9.59 | 53.97 | 385 |
| Recent low-value one-timers | 21,651 | 23.26 | 9.12 | 52.00 | 93 |
| Champions | 831 | 0.89 | 2.08 | 240.00 | 89 |
| Loyal repeaters | 1,173 | 1.26 | 2.05 | 158.89 | 268 |

---

## Interview questions (with model answers)

**1. Why do you use `customer_unique_id`, and how did you check the SQL agrees with your Python work?**
Olist creates a new `customer_id` for every order, so counting it would make every customer look new. The real person is `customer_unique_id`. I built the SQL views independently and added quality checks that compare them with the Phase 2 notebook outputs: 93,094 cohort customers, 2,004 lifetime repeaters, 56,188 eligible, 1,112 180-day repeaters. All 52 checks pass, including after a full reload.

**2. What is right-censoring and how did you handle it?**
The data ends on 2018-08-31, so a customer who bought in August hasn't had time to return. Counting them as non-returners biases repeat rates down. For the 180-day rate I only include customers whose first purchase is on or before 2018-03-04, so all 56,188 have a full 180 days. In the cohort table, months we can't fully see are NULL rather than 0 (78 cells). The flag `is_repeat_180d` is NULL, not false, for ineligible customers.

**3. Why doesn't a second order on the same day count as a repeat?**
It's the same shopping trip, often a basket split into two orders. Counting it would turn 784 customers into "repeaters" who never came back. The lifetime rate would go from 2.15% to 2.99% (Phase 2), which overstates loyalty.

**4. How did you avoid double counting when joining items and payments?**
Both tables have several rows per order. I aggregated each to one row per order in its own CTE before joining. A quality check proves it: total product value in the view equals the sum of item prices over delivered orders, R$13,221,498.11, to the cent.

**5. Why did you change the standard RFM?**
97.85% of customers bought on only one date, so a 1–5 frequency score would just split identical values at random. I kept quintile scores for recency and monetary, made frequency a repeat/one-time flag, and defined 7 action-oriented segments. Repeaters (Champions plus Loyal) are only 2.15% of customers and 4.13% of revenue. Two high-value one-timer segments (lapsed and promising) together are 30.68% of customers and 58.97% of revenue, which is the pool a second-purchase campaign would target.

**6. ROW_NUMBER vs RANK vs NTILE vs DISTINCT ON: when do you use which?**
ROW_NUMBER gives a unique 1, 2, 3 per partition, which is right for "pick exactly one first order" with a tie-breaker. RANK gives tied rows the same number, so "first" could be two rows. NTILE(n) splits rows into n equal groups, as for the RFM quintiles. DISTINCT ON is PostgreSQL's shorthand for "first row per group". I used it for the main category and payment type because the planner estimates its row count correctly. The ROW_NUMBER version made a filtered query take over 60 seconds, against 0.2 s now.

**7. When do people who come back actually come back?**
Quickly, if at all. Of 2,004 lifetime repeaters, 29.84% return within 30 days and 55.14% within 90. The median gap is 74 days. In the cohort table, pooled month-1 retention is 0.48% and falls to 0.26% by month 3. This is biased short by censoring, but it suggests the first few weeks after delivery are the window for a retention action.

**8. Some states and categories repeat more. Can you say SP customers are more loyal than CE customers?**
Not yet. 2.23% (SP, 22,307 eligible) vs 1.13% (CE, 798 eligible) is a difference in the sample. With rates this low, small groups are noisy, which is why I set minimum group sizes (≥ 500 for states, ≥ 300 for categories). Whether the difference is statistically significant, and whether it's driven by something else such as delivery time, is tested in Phase 5.
