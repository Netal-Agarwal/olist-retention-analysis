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

---
---

## Part B: delivery, reviews, pricing/freight and prioritisation

Files:
- `sql/04_base_views.sql`: new columns at the **end** of `v_orders` (main seller, seller state, same-state flag, five buckets/bands) and matching `first_*` columns at the end of `v_customers`.
- `sql/07_delivery_reviews.sql` (11 queries), `sql/08_pricing_freight.sql` (7) and `sql/09_prioritisation.sql` (5), run with `src.run_analysis` into `outputs/phase4/`.
- `sql/03_quality_checks.sql` section 8: 10 reconciliation checks. 62 of 62 pass, also after a loader re-run, and all nine 4A CSVs are byte-identical afterwards.

---

## 1. CASE bucketing, defined once in the view
```sql
case
    when o.order_delivered_customer_date is null then null
    when <delay> <= 0  then '1 early/on time'
    when <delay> <= 3  then '2 1-3 days late'
    when <delay> <= 7  then '3 4-7 days late'
    when <delay> <= 14 then '4 8-14 days late'
    else '5 15+ days late'
end as delay_bucket
```
- CASE checks lines top to bottom and stops at the first true one, so each line needs only its upper edge, and an order can never fall into two buckets.
- The number prefix ("1 ", "2 ", …) makes the labels sort in the right order as text, in a CSV or in Power BI.
- Putting the bucket in the **view** means every query, the quality checks and later Power BI use the same edges. The checks prove the buckets cover everything: 96,470 orders have a delay bucket, which is 96,478 delivered orders minus the 8 with no delivery date.
- A trap we hit: comparing text labels with `>` compares characters. `'1 early/on time' > '1'` is **true**, because the longer string sorts after its prefix. The check uses `left(delay_bucket, 1) <> '1'` instead.

## 2. Safe division with NULLIF, and the integer-division trap
- `x / nullif(y, 0)`: if `y` is 0, NULLIF turns it into NULL, and `x / NULL` is NULL instead of a "division by zero" error. For example, a seller whose orders all lack a delivery date gets a NULL late %, not a crash.
- **Integer division** truncates. In PostgreSQL, `62 / 3928` = **0** and `100 * 62 / 3928` = **1**, while `100.0 * 62 / 3928` = 1.58. (We ran these three in the database; the numbers are late-first repeaters and late-first customers from `q07_07`.) That is why every rate in these files starts with `100.0 *`: one decimal value makes the whole calculation decimal.

## 3. ROW_NUMBER vs RANK vs DENSE_RANK
For tied values, the three functions number rows differently:

| Function | Ties | Gap after a tie | Used for |
|---|---|---|---|
| `row_number()` | different numbers (tie-break decides) | n/a | "exactly 20 rows": `q09_02` top 20 sellers, tie-break orders then seller_id |
| `rank()` | same number | yes (1, 2, 2, 4) | `q09_01` state priority |
| `dense_rank()` | same number | no (1, 2, 2, 3) | when you want "the 3rd distinct value" |

Real example from `q09_01`: BA and RS both have an opportunity of 0.9 extra repeaters, so both get rank **5**, and PR comes next with rank **7**. With `dense_rank()` PR would be 6. With `row_number()` one of BA/RS would arbitrarily become 6.

## 4. HAVING thresholds: why small samples mislead
`having count(*) >= 300` keeps only groups big enough to read. Even then, the **late** cells inside categories are small. In `q07_09`, pet_shop has 46 late-first customers with 3 repeaters, a 6.52% rate that looks *better* than its on-time 2.79%. One repeater fewer would make it 4.35%, and two fewer 2.17%. With rates near 2%, a few people swing everything, so we always show n next to each rate, and Phase 5 adds confidence intervals.

## 5. Confounding and stratified comparison
A **confounder** is a third factor linked to both things you are comparing. Product category could be one: some categories are rebought often (pet food) and might also arrive late more or less often. A raw late-vs-on-time comparison would then partly measure category mix.

A **stratified** comparison compares like with like, here late vs on-time *within each category*, and then averages the gaps. `q07_11` weights each category's gap by its number of late customers:

| | Gap, on time − late (percentage points) |
|---|---|
| Crude, all eligible customers | 0.43 |
| Crude, the 24 covered categories | 0.37 |
| Within-category (weighted) | 0.38 |

Within categories the gap barely moves (0.37 → 0.38), so category mix does **not** explain it. Late is worse in 16 of the 24 categories, but every late cell has only 0–10 repeaters.

## 6. Correlation is not causation
Everything in Part B is an **association**. Customers whose first order arrived late repeat less (1.58% vs 2.01%), but that doesn't prove lateness causes it. Late orders may differ in other ways, for example remote states, bulky products or peak season (late % was 18.96% for March 2018 purchases vs 1.16% for June 2018). Part B can't rule those out. Phase 5 tests whether the gaps are larger than chance and controls for some of these factors. That is why the estimates in `q09` are labelled **ESTIMATE** and state "assumes lateness causes the gap".

---

## Results (Part B)

**Delivery overview** (`q07_01`, 96,211 in-window delivered orders, 96,203 with a delivery date): 93.21% on time, 6.79% late (6,531). Median delivery 10.21 days, P90 23.06 days. Late orders are a median 7 days late.

**Same vs cross state** (`q07_03`):

| | Orders | Late % | Median delivery days | Eligible customers | 180d repeat |
|---|---|---|---|---|---|
| Same state | 34,609 | 4.51 | 6.52 | 18,776 | 2.18% (409) |
| Cross state | 61,602 | 8.07 | 12.78 | 37,412 | 1.88% (703) |

**Reviews by delay** (`q07_06`, reviewed orders):

| Delay bucket | Reviewed orders | Mean score | Median | % 1–2 stars |
|---|---|---|---|---|
| Early / on time | 89,182 | 4.29 | 5 | 9.25 |
| 1–3 days late | 1,851 | 3.29 | 4 | 32.14 |
| 4–7 days late | 1,748 | 2.10 | 1 | 67.68 |
| 8–14 days late | 1,446 | 1.67 | 1 | 80.15 |
| 15+ days late | 1,333 | 1.72 | 1 | 78.32 |

**Repeat by first order** (eligible customers, 180-day rate):
- On time 2.01% (1,050 of 52,258) vs late 1.58% (62 of 3,928) (`q07_07`). By delay bucket: 1.83% (1–3 days), 1.36% (4–7), 2.14% (8–14), 1.03% (15+). The buckets have only 889–1,039 customers each, so the pattern isn't smooth.
- By first review (`q07_08`): 5 stars 2.12% (32,248), 4 stars 1.83%, 3 stars 1.94%, 2 stars 1.51% (1,788), 1 star 1.71% (5,658), no review 1.20% (417).
- By delivery speed (`q07_10`): ≤7 days 2.20% (11,716) falling steadily to 1.33% for >30 days (3,155).

**Sellers** (`q07_05`): 417 sellers have ≥ 50 in-window orders. The worst 10% by late % (42 sellers) have 6.73% of those sellers' orders but 15.14% of their late orders (11.42% of all in-window late orders). The top 20 sellers by late orders account for 24.58% of all late orders (`q09_02`).

**Freight** (`q08_01`): median freight share 18.33% (p25 11.66%, p75 27.57%); median freight R$17.17. By freight-share band, 1–2 star reviews only rise from 12.32% (<10%) to 13.95% (≥40%) (`q08_04`). 180d repeat is flat, 1.82–2.19% with no trend (`q08_05`).

**Estimates** (labelled ESTIMATE, assumptions in the CSVs):
- Late delivery (`q09_04`): 3,928 late-first customers × 0.43 pp = **16.9 extra repeaters**, × median second-visit value R$89.90 = **R$1,521.45** of product revenue over the 180-day horizon of the eligible cohort.
- Second-purchase campaign (`q09_05`), 14,533 Promising high-value one-timers: 1% → 145.3 repeaters / R$13,065.17; 2% → 290.7 / R$26,130.33; 5% → 726.7 / R$65,325.84 (assumed conversion rates, before campaign cost).

What it means: late delivery is strongly linked to **reviews** (1–2 stars go from 9.25% to about 80%), but only weakly to **repeat buying** (2.01% vs 1.58%). Even customers who gave 5 stars and got their parcel on time repeat at only about 2%. So fixing lateness alone is unlikely to fix retention. Its measured link is small and only affects the ~7% of first orders that arrive late. The bigger lever looks like actively driving a second purchase. All of this is to be tested in Phase 5.

---

## Interview questions, Part B (with model answers)

**1. Does late delivery hurt Olist?**
It clearly hurts satisfaction: the share of 1–2 star reviews goes from 9.25% for on-time orders to 67.68% at 4–7 days late and 80.15% at 8–14 days. The link to repeat buying is much smaller. Customers whose first order was late repeat at 1.58% within 180 days, against 2.01% for on time, a 0.43-point gap. That's an association; Phase 5 tests whether it's more than chance.

**2. How did you make sure product category wasn't driving the late-vs-on-time difference?**
I stratified: I compared late vs on time within each of the 24 categories with ≥ 300 eligible customers, then took a weighted average of the gaps (weights = late customers). The within-category gap is 0.38 points, against a crude 0.37 on the same customers, so category mix doesn't explain it. The per-category late cells are small, so I show n everywhere.

**3. Is distance the problem?**
Partly for delivery. Orders shipped within the customer's state arrive in a median 6.52 days with 4.51% late, against 12.78 days and 8.07% late across states. Same-state first-order customers repeat at 2.18% vs 1.88%. The states with the most late deliveries (MA 17.53%, CE 13.83%, BA 12.17%) are mostly in the north-east, far from where nearly all of the top-20 late sellers are based (SP). But that's still correlation; same-state orders also differ in other ways.

**4. Where should Olist fix delivery first?**
By late orders, sellers are concentrated. The 42 worst sellers (10% of those with ≥ 50 orders) handle 6.73% of those sellers' orders but cause 15.14% of their late orders, and the top 20 sellers by late orders cause 24.58% of all late orders. By state, the opportunity measure ranks RJ first (1,057 late-first customers, 12.14% late), then SP, MG, SC and BA. RJ ranks high because it combines volume with a high late rate.

**5. What would fixing late delivery be worth?**
As an ESTIMATE: 3,928 late-first customers × the 0.43-point gap ≈ 16.9 extra repeat customers. At the median second-visit value of R$89.90, that's about R$1,521 of product revenue for the eligible cohort. It assumes lateness causes the gap. It's small, which is itself a finding: the business case for delivery is satisfaction and reputation, not mainly retention.

**6. Why RANK in one query and ROW_NUMBER in another?**
For the state ranking, ties should share a place: BA and RS both have 0.9 and both rank 5, so the next state is 7. For "top 20 sellers" I need exactly 20 rows, so ROW_NUMBER with an explicit tie-break (orders, then seller_id) makes the cut deterministic. DENSE_RANK would number without gaps (5, 5, 6).

**7. Why do you write `100.0 *` and `NULLIF`?**
Integer division truncates. In this database `100 * 62 / 3928` returns 1, but `100.0 * 62 / 3928` returns 1.58. NULLIF(denominator, 0) turns a zero denominator into NULL, so a group with no qualifying rows gives an empty rate instead of crashing the query.

**8. Does freight cost matter?**
Less than expected. The median order spends 18.33% of the bill on freight, and up to 27.69% in MA. But 1–2 star reviews only rise from 12.32% to 13.95% across freight-share bands, and the 180-day repeat rate is flat (1.82–2.19%) with no clear direction. On this data, freight share doesn't look like a main reason for low repeat buying.
