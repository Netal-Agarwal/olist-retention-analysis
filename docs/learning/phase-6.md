# Phase 6: Reporting layer for Power BI

> What was built: `sql/11_report_views.sql` (schema `report`: a star schema plus pre-aggregated views), `src/create_views.py` (now builds analysis and then report views), 50 new quality checks (section 10 of `sql/03_quality_checks.sql`, 114/114 pass), and the Power BI spec in `docs/powerbi/` (DAX measures, build guide, theme) plus `outputs/powerbi/claims_verdicts.csv`.

## Part A: concepts

### 1. Star schema
A model with one central **fact table** (things that happened, here orders) surrounded by **dimension tables** (the things you filter and group by: customer, day, category, seller, state). Drawn out, it looks like a star. Power BI's engine is optimised for it: filters travel from each small dimension to the one fact table, and measures stay simple.
*In this project:* `report.fact_orders` is in the middle, and `dim_customer`, `dim_date`, `dim_category`, `dim_seller` and `dim_state` point at it.

### 2. Fact vs dimension tables
- **Fact:** many rows, mostly numbers and keys. Each row is an event (`product_value`, `freight_value`, `delay_days`, `review_score`, plus keys such as `customer_unique_id`).
- **Dimension:** fewer rows, mostly descriptive text, **one row per key** (`dim_state`: 27 rows, `state_code` → name and region).
The quality checks prove every dimension key is unique and every fact key has a match ("orphans = 0"). Power BI's many-to-one relationships depend on both.

### 3. Grain
The grain is "what one row means". `fact_orders` = one delivered order in the window; `dim_customer` = one `customer_unique_id`; `agg_cohort_retention` = one cohort × month. Decide the grain first. Mixing grains (for example item rows in an order table) is how money gets double counted: the same trap as joining `order_items` before aggregating (CLAUDE.md data traps).

### 4. Why a date table
Power BI needs a continuous calendar (one row per day, no gaps) to do time grouping and time-intelligence functions reliably, and to sort months properly. `dim_date` has one row per day of the analysis window (608 days) with year, month, `year_month`, weekday and sort columns. It is marked as the date table in Power BI.

### 5. Import vs DirectQuery
- **Import:** Power BI copies the data into the .pbix at refresh time. Fast visuals; works offline; data is as fresh as the last refresh.
- **DirectQuery:** every visual sends SQL to the database live. Always current, but each click waits for PostgreSQL, and some DAX is limited.
We use **Import**: the data is a fixed historical extract, and our views are heavy (window functions over ~96k orders), so querying them live would be slow.

### 6. Relationships and filter direction
A relationship links a fact column to a dimension key (many-to-one). **Single direction** means filters flow only from the dimension to the fact. Choosing segment "Champions" in `dim_customer` filters their orders, but a date slicer does **not** filter `dim_customer`. That is why "Cohort Customers" stays 93,094 when someone filters a month: the month selects orders, not who the cohort is. Bi-directional filters would make that number move without anyone noticing.

### 7. DAX basics
- **Measure vs calculated column:** a calculated column is stored per row at refresh (like a SQL column). A measure is computed per visual cell at query time. Rates must be measures, because a rate is "sum of top ÷ sum of bottom" for whatever group the cell shows.
- **Filter context:** the set of filters active for one cell (visual row/column, slicers, page filters). The same measure gives 96,211 on an empty card and RJ's count in an RJ row.
- **CALCULATE:** evaluates an expression in a modified filter context. `CALCULATE([Bad Review Rate], fact_orders[is_late] == FALSE())` = the bad-review rate with "on time only" forced. A plain filter *replaces* an existing filter on the same column; `KEEPFILTERS` *intersects* with it.
- **DIVIDE:** `DIVIDE(a, b)` returns BLANK instead of an error when b is 0.
- **Blank booleans:** in DAX `BLANK() = FALSE()` is true, but `BLANK() == FALSE()` (strict) is false. Our blanks mean "unknown" (no delivery date, no review, not eligible), so all measures use `==`.
- **What-if parameter:** a one-column table of values (`GENERATESERIES(0.01, 0.10, 0.005)`) plus a slicer and a `SELECTEDVALUE` measure that reads the chosen value (default 2%). Measures multiply by it, so the campaign estimate updates as the slider moves.

## Part B: what each part of `sql/11_report_views.sql` does

| View | In plain English |
|---|---|
| `fact_orders` | Takes `analysis.v_orders`, keeps in-window orders, strips the number prefix from bucket labels into separate sort columns, adds `has_review`, `is_bad_review` (NULL when no review, so "no review" never counts as "not bad") and `is_first_order`. `is_first_order` numbers each customer's orders by time with `row_number()` and keeps number 1, using the same ordering as `v_customers`. |
| `dim_customer` | One row per customer with cohort and repeat flags, first-order attributes and RFM segment. Built by stacking `v_customers` and `v_customer_rfm` and collapsing per customer (`max` / `bool_or` ignore NULLs). The plain JOIN of the two views took over 15 minutes because PostgreSQL mis-estimated their sizes. |
| `dim_date` | `generate_series` makes one row per day from 2017-01-01 to 2018-08-31; `to_char` / `extract` give the calendar columns. |
| `dim_category`, `dim_seller`, `dim_state` | Simple lists. The states are typed in (VALUES), because the data only has 2-letter codes. |
| `agg_cohort_retention` | The q05_03 cohort grid; censored cells stay NULL so the heatmap shows them blank, not 0%. |
| `agg_time_to_second` | q05_02's buckets with the quartiles copied onto each row. |
| `agg_repeat_by_review`, `agg_repeat_by_category`, `agg_bad_review_by_delay` | The Phase 4 rates plus a 95% Wilson interval for error bars. The formula is written out in the file header; it matches statsmodels (checked against the notebook's 1.97–2.28 and 2.41–4.50). |
| `agg_excess_bad_reviews_*` | The Phase 5 q10_02–04 queries unchanged (each group vs its own on-time rate, minimum sizes, shares of the national 3,391.2). |
| `agg_campaign_baseline` | The two campaign inputs: 14,533 customers and the R$89.90 median second visit. The conversion rate comes from the What-if slider. |

**Why these checks?** Each report check compares the view with a published number (a CSV cell or a claims-evidence figure), so "the dashboard matches the analysis" is proven, not assumed. The excess total is compared in tenths: a tolerance of 0.05, which is the precision of the published 3,391.2.

## Part C: interview questions

**1. Why build a star schema instead of loading your analysis views straight into Power BI?**
The analysis views are wide and query-shaped. Power BI works best with one fact table and small dimensions, because every filter then has one path to the data. With a star schema the measures stay one-liners (`COUNTROWS(fact_orders)`) and the totals are easy to defend: no slicer applied gives exactly 96,211 orders, matching `q07_01`.

**2. What is the grain of your fact table, and why did you limit it to the analysis window?**
One delivered order purchased between 2017-01-01 and 2018-08-31. 2016 is sparse and Sep–Oct 2018 has no delivered orders. If the fact held them, any visual without a date filter would mix in unreliable months. Restricting the grain means the default view is always the trusted window.

**3. Why are some numbers pre-computed in SQL and not in DAX?**
Things that are easy to get subtly wrong: censored cohort cells must be blank, not 0%; Wilson intervals; ranked excess tables with minimum group sizes; a median. That SQL was already tested against the Phase 4/5 CSVs, so I reuse it. Simple ratios stay in DAX because they must respond to filters, for example the late rate by month.

**4. Explain filter context and CALCULATE with an example from your dashboard.**
"Bad Review Rate On Time" is `CALCULATE([Bad Review Rate], fact_orders[is_late] == FALSE())`. Whatever cell it sits in (a state, a month), CALCULATE adds "on time only" to that cell's filters. On an empty card it gives 9.25%. In the RJ row it gives RJ's own on-time rate, which is exactly the baseline the excess-bad-review estimate needs, so "Excess Bad Reviews" gives 905.4 for RJ, matching `q10_02`.

**5. Why single-direction relationships?**
So filters only go from dimensions to the fact. If `dim_date` could filter `dim_customer` through the fact, picking "2018-08" would shrink "Cohort Customers" to the customers who happened to order that month. The headline 93,094 would change without anyone choosing to change it.

**6. What went wrong while building the views, and how did you fix it?**
Joining `v_customers` to `v_customer_rfm` made a simple count run for more than 15 minutes. PostgreSQL could not estimate how many rows the views return, so it chose a nested loop (every customer compared with every customer). I cancelled it and rewrote the view to stack the two views and group by customer, which needs a single hash aggregate. A quality check proves all 7 segment sizes still match `q06_01`.

**7. How do you make sure the dashboard does not show unsupported claims?**
Every visual maps to a claim in `docs/claims_evidence.md` that is supported or supported as an estimate. State repeat-rate differences failed after Holm correction (p = 0.19), so there is no state repeat visual and no view for it. The claims table on page 4 shows that verdict as "Not supported", so readers can see it was tested. Estimates are labelled ESTIMATE with their assumptions.

**8. How does the What-if parameter work, and what are its limits?**
It is a table of conversion rates from 1% to 10% with a slider. `SELECTEDVALUE` reads the chosen rate (default 2%), and the measures compute 14,533 × rate extra repeaters × R$89.90. At 2% that is 290.7 customers and R$26,130.33, matching `q09_05`. The rate is an assumption, not measured; the value is product revenue, not margin; campaign cost is not included.
