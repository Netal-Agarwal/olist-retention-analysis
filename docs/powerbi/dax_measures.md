# DAX measures spec (Phase 6)

> For Phase 7. Every measure lives in one dedicated table, `_Measures`. The **Expected** column is the value the measure must show with **no slicers or filters applied**, taken from a Phase 4/5 output (file and column given). If your card shows something else, stop and check the model (relationships, filters, data types) before going on.
> The step-by-step clicks are in `docs/powerbi/build_guide.md`. Definitions follow `docs/metrics.md` (metric numbers in brackets).

## Before you start: four DAX ideas used below

**Measure vs calculated column.** A *calculated column* is computed once per row when the data is loaded and stored in the table (like a new SQL column). A *measure* is computed at query time, for whatever cell of a visual it sits in. Rates must be measures: a rate is "sum of the top ÷ sum of the bottom" for the current group, and you cannot store that per row.

**Filter context.** Every cell of a visual has a set of active filters: the row/column of the visual (for example "state = RJ"), slicers, page and report filters. A measure is evaluated *inside* that set. `COUNTROWS(fact_orders)` gives 96,211 on an empty card, but only RJ's orders in the RJ row of a table. Filters flow along relationships, from the "one" side (dimension) to the "many" side (fact). In this model a `dim_state` filter reaches `fact_orders`, but it never reaches `dim_customer`.

**CALCULATE.** `CALCULATE(<expression>, <filter>, ...)` evaluates the expression in a *modified* filter context. A filter like `fact_orders[is_late] == TRUE()` *replaces* any existing filter on that same column, while filters on other columns are kept. `KEEPFILTERS(...)` *intersects* with the existing filter instead of replacing it. That matters in the review measures below.

**DIVIDE.** `DIVIDE(a, b)` is `a / b` but returns BLANK instead of an error when `b` is 0 or blank (for example a state with no late orders).

**Two traps in this model, and how the measures avoid them**
1. *Blank booleans.* `is_late` is blank for the 8 orders with no delivery date, `is_bad_review` is blank for orders without a review and `is_repeat_180d` is blank for non-eligible customers. In DAX, `BLANK() = FALSE()` is **TRUE** (blank is treated as false). The strict operator `==` does not do that: `BLANK() == FALSE()` is FALSE. So the measures always use `==` with booleans.
2. *Inner filters overriding outer ones.* `[Reviewed Orders]` has its own filter on `is_late` (not blank). If `[Bad Review Rate On Time]` then calls it with `is_late == FALSE()`, a plain inner filter on the same column would replace the outer one and the "on time" part would be lost. Wrapping the inner filter in `KEEPFILTERS` makes the two combine.

## Measures

Format column: `%` means "Percentage, 2 decimals"; `#,0` means "Whole number, thousands separator"; `R$` means "Currency, 2 decimals".

### A. Orders and delivery (table `fact_orders`, in-window delivered orders)

| # | Measure | DAX | Format | Plain English | Used on | Expected (source) |
|---|---|---|---|---|---|---|
| 1 | Total Orders | `Total Orders = COUNTROWS ( fact_orders )` | #,0 | Number of delivered orders in the filter context. | P1 card; P1 monthly chart | **96,211** (`q07_01` orders) |
| 2 | Product Revenue | `Product Revenue = SUM ( fact_orders[product_value] )` | R$ | Product revenue: item prices, freight excluded [3]. | P1 card; P1 monthly chart | **R$13,181,027.13** (sum of `q05_06` product_revenue) |
| 3 | Orders With Delivery Date | `Orders With Delivery Date = CALCULATE ( COUNTROWS ( fact_orders ), KEEPFILTERS ( NOT ISBLANK ( fact_orders[is_late] ) ) )` | #,0 | Orders we can judge as on time or late (the denominator of Late Rate) [20]. | helper | **96,203** (`q07_01` orders_with_delivery_date) |
| 4 | Late Orders | `Late Orders = CALCULATE ( COUNTROWS ( fact_orders ), fact_orders[is_late] == TRUE () )` | #,0 | Orders delivered on a later day than promised [7]. | helper | **6,531** (`q07_01` late_orders) |
| 5 | Late Rate | `Late Rate = DIVIDE ( [Late Orders], [Orders With Delivery Date] )` | % | Share of orders with a delivery date that arrived late [20]. | P1 card; P3 monthly line; P3 same vs cross state | **6.79%** (`q07_01` late_pct) |

The same-state vs cross-state check on P3: put `fact_orders[same_state]` on the axis. Late Rate shows **4.51%** same state and **8.07%** cross-state (`q07_03` late_pct).

### B. Reviews (table `fact_orders`; population = reviewed orders with a delivery date [25])

| # | Measure | DAX | Format | Plain English | Used on | Expected (source) |
|---|---|---|---|---|---|---|
| 6 | Reviewed Orders | `Reviewed Orders = CALCULATE ( COUNTROWS ( fact_orders ), KEEPFILTERS ( fact_orders[has_review] == TRUE () ), KEEPFILTERS ( NOT ISBLANK ( fact_orders[is_late] ) ) )` | #,0 | Reviewed orders whose on-time/late status is known. | helper | **95,560** (`q10_01` 3 all) |
| 7 | Bad Reviews | `Bad Reviews = CALCULATE ( COUNTROWS ( fact_orders ), KEEPFILTERS ( fact_orders[is_bad_review] == TRUE () ), KEEPFILTERS ( NOT ISBLANK ( fact_orders[is_late] ) ) )` | #,0 | 1-2 star reviews in the same population. | helper | **12,228** (`q10_01` 3 all) |
| 8 | Bad Review Rate | `Bad Review Rate = DIVIDE ( [Bad Reviews], [Reviewed Orders] )` | % | Share of reviewed orders with 1-2 stars. | P3 | **12.80%** (`q10_01` 3 all) |
| 9 | Bad Review Rate On Time | `Bad Review Rate On Time = CALCULATE ( [Bad Review Rate], fact_orders[is_late] == FALSE () )` | % | The same rate for on-time orders only. CALCULATE replaces any filter on `is_late` with "false"; the KEEPFILTERS inside measures 6-7 keep "not blank" as well. | P1 card; P3 comparison | **9.25%** (`q10_01` 1 on time: 8,247 / 89,182) |
| 10 | Bad Review Rate Late | `Bad Review Rate Late = CALCULATE ( [Bad Review Rate], fact_orders[is_late] == TRUE () )` | % | The same rate for late orders. | P1 card; P3 comparison | **62.42%** (`q10_01` 2 late: 3,981 / 6,378) |
| 11 | Excess Bad Reviews | see below | #,0.0 | ESTIMATE [26]: bad reviews on late orders minus what they would have had at the on-time rate. | P1 card; P4 | **3,391.2** (`q10_05` excess_bad_reviews) |
| 12 | Excess Share of Bad Reviews | `Excess Share of Bad Reviews = DIVIDE ( [Excess Bad Reviews], [Bad Reviews] )` | % | ESTIMATE: the share of all bad reviews that the lateness "adds". | P1 card | **27.73%** (`q10_05` excess_share_of_all_bad_reviews_pct) |

```dax
Excess Bad Reviews =
-- ESTIMATE (docs/metrics.md metric 26). VAR stores an intermediate result,
-- so each piece is computed once and the formula reads top to bottom.
VAR LateBad      = CALCULATE ( [Bad Reviews],     fact_orders[is_late] == TRUE () )
VAR LateReviewed = CALCULATE ( [Reviewed Orders], fact_orders[is_late] == TRUE () )
VAR OnTimeRate   = [Bad Review Rate On Time]
RETURN
    LateBad - LateReviewed * OnTimeRate
```
**Filter context note:** the measure uses the on-time rate *of the current filter context*. In a row for state RJ it compares RJ's late orders with RJ's own on-time rate, which is exactly metric 26's "group's own baseline". So with a `dim_state[state_code] = RJ` filter it shows **905.4** (`q10_02` RJ), and with SP **815.0**. The *shares* and the minimum-size rules (states ≥ 500, sellers ≥ 50, routes ≥ 200 reviewed orders) are not in the measure. For the P4 rankings use the `agg_excess_bad_reviews_*` tables, which have them.

### C. Customers and retention (table `dim_customer`)
These measures count customers, not orders, so they read `dim_customer`. They react to `dim_customer` columns (segment, first-order state, first review label). They do **not** react to `dim_date`, `dim_state` or `dim_category`, because those filter only `fact_orders`, and the relationship filters in one direction (dimension → fact). That is deliberate: "cohort customers" must not change when someone moves a date slicer, which only selects orders.

| # | Measure | DAX | Format | Plain English | Used on | Expected (source) |
|---|---|---|---|---|---|---|
| 13 | Cohort Customers | `Cohort Customers = CALCULATE ( COUNTROWS ( dim_customer ), dim_customer[in_window_cohort] == TRUE () )` | #,0 | Customers whose first delivered order is in the window [6, 11]. | P1 card; P2 | **93,094** (`q05_01` cohort_customers) |
| 14 | Lifetime Repeaters | `Lifetime Repeaters = CALCULATE ( [Cohort Customers], dim_customer[is_repeat_lifetime] == TRUE () )` | #,0 | Cohort customers who bought again on a later day [4]. | helper | **2,004** (`q05_01` lifetime_repeaters) |
| 15 | Lifetime Repeat Rate | `Lifetime Repeat Rate = DIVIDE ( [Lifetime Repeaters], [Cohort Customers] )` | % | Share of cohort customers who ever came back (not censoring-safe: see 18). | P2 card | **2.15%** (`q05_01` lifetime_repeat_rate_pct) |
| 16 | One-time Customer % | `One-time Customer % = 1 - [Lifetime Repeat Rate]` | % | Share of cohort customers who never returned on a later day. | P1 headline card | **97.85%** (`q05_01` one_time_pct) |
| 17 | Eligible 180d Customers | `Eligible 180d Customers = CALCULATE ( COUNTROWS ( dim_customer ), dim_customer[eligible_180d] == TRUE () )` | #,0 | Customers we could watch for a full 180 days (first order up to 2018-03-04) [5]. | helper | **56,188** (`q05_01` eligible_180d_customers) |
| 18 | 180-day Repeaters | `180-day Repeaters = CALCULATE ( COUNTROWS ( dim_customer ), dim_customer[is_repeat_180d] == TRUE () )` | #,0 | Eligible customers who came back within 180 days. `==` keeps the blank (not eligible) customers out. | helper | **1,112** (`q05_01` repeaters_180d) |
| 19 | 180-day Repeat Rate | `180-day Repeat Rate = DIVIDE ( [180-day Repeaters], [Eligible 180d Customers] )` | % | The headline, censoring-safe retention rate [5]. | P1 card; P2 card | **1.98%** (`q05_01` repeat_rate_180d_pct) |

### D. What-if: second-purchase campaign (ESTIMATE, metric 24)

**Parameter.** Modeling → New parameter → Numeric range. Name `Campaign Conversion Rate`, data type Decimal number, minimum 0.01, maximum 0.10, increment 0.005, default 0.02, "Add slicer to this page" ticked. Power BI creates a one-column table and this measure for you:
```dax
Campaign Conversion Rate = GENERATESERIES ( 0.01, 0.10, 0.005 )          -- the table (19 values)
Campaign Conversion Rate Value = SELECTEDVALUE ( 'Campaign Conversion Rate'[Campaign Conversion Rate], 0.02 )
```
`SELECTEDVALUE` returns the value picked on the slider, or 0.02 (the default) if nothing or several values are selected. Format the column and the measure as Percentage, 1 decimal.

| # | Measure | DAX | Format | Plain English | Used on | Expected at 2% (source) |
|---|---|---|---|---|---|---|
| 20 | Campaign Segment Customers | `Campaign Segment Customers = SUM ( agg_campaign_baseline[segment_customers] )` | #,0 | Size of "Promising high-value one-timers" (one-row table, so SUM just reads the value). | P4 card | **14,533** (`q09_05` segment_customers) |
| 21 | Campaign Extra Repeaters | `Campaign Extra Repeaters = [Campaign Segment Customers] * [Campaign Conversion Rate Value]` | #,0.0 | ESTIMATE: customers who would make a second purchase if the campaign converted that share. | P4 card | **290.7** (`q09_05`, 2% row) |
| 22 | Campaign Extra Revenue | `Campaign Extra Revenue = [Campaign Extra Repeaters] * SUM ( agg_campaign_baseline[median_second_visit_value] )` | R$ | ESTIMATE: extra product revenue at the median second-visit value R$89.90 (metric 22). | P4 card | **R$26,130.33** (`q09_05`, 2% row) |

More check points (same source): at **1%**, 145.3 and R$13,065.17; at **5%**, 726.7 and R$65,325.84. The conversion rate is an assumption, campaign cost is not included and the value is product revenue, not margin. The P4 cards must say "ESTIMATE".

## Measures deliberately NOT built
- **Repeat rate by customer state:** claim 10 is not supported (Holm p = 0.19). Showing a state ranking would invite a wrong decision.
- **Late-delivery revenue impact (`q09_04`, R$1,521.45):** it rests on the late vs on-time repeat gap, which is not significant (claim 5). It is described in the memo, not shown as a dashboard number.
- **Rates with confidence intervals** (by review score, category, delay bucket): Wilson CIs are awkward in DAX and easy to get wrong, so they are pre-computed in the `agg_*` views. Visuals use those columns directly.
- **Cohort retention:** censored cells must stay blank. That logic lives in `agg_cohort_retention`; recomputing it in DAX would risk turning unknown cells into 0%.
