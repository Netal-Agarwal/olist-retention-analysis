# Phase 2 — Understanding and cleaning the data (pandas)

Two notebooks:
- `notebooks/01_data_profiling.ipynb` **measures** the nine raw CSVs and lists every data problem. It changes nothing.
- `notebooks/02_cleaning.ipynb` **applies** the approved rules and writes one cleaned CSV per table to `data/processed/`.

All numbers below come from those notebooks' outputs, `outputs/phase2_profile_summary.csv` and `outputs/phase2_cleaning_summary.csv`.

---

## 1. Why profile before cleaning?
If you write cleaning rules before looking, you guess. Profiling first gives every rule a measured reason ("547 orders have more than one review"), and every rule's impact can be checked afterwards (99,224 → 98,673 review rows). In an interview, being able to say *how many rows a rule touched and why* is what makes a cleaning step defensible.

## 2. pandas concepts used

### `read_csv` with `dtype` and `parse_dates`
```python
orders = pd.read_csv(RAW / "olist_orders_dataset.csv", parse_dates=ORDER_DATES)
customers = pd.read_csv(..., dtype={"customer_zip_code_prefix": str})
translation = pd.read_csv(..., encoding="utf-8-sig")
```
- `parse_dates` turns text like `2017-10-02 10:56:33` into real timestamps, so you can compare and subtract them. Left as text, `"2017-10-02" < "2017-9-30"` would compare letter by letter.
- `dtype=str` for zip prefixes: read as numbers, `"01037"` would become `1037` and stop matching other tables. Profiling confirmed every prefix is 5 characters.
- `encoding="utf-8-sig"` strips the invisible byte-order mark at the start of the translation file. Without it, the first column is called `﻿product_category_name` and joins fail.

### `value_counts`
Counts how often each value appears. `orders["order_status"].value_counts()` gave delivered 96,478, shipped 1,107, canceled 625, and so on. Divide by `len(orders)` for percentages.

### `groupby` / `agg`
"Split the rows into groups, calculate something per group, put the results together."
```python
delivered_cust.groupby("customer_unique_id")["order_id"].nunique()   # delivered orders per person
geo_step2.groupby("geolocation_zip_code_prefix").agg(
    geolocation_lat=("geolocation_lat", "median"), n_points=("geolocation_lat", "size"))
```
`agg` with `new_name=(column, function)` pairs makes several summaries in one go. This is the pandas version of SQL's `GROUP BY` with `COUNT/SUM/MEDIAN`.

### `merge`, and how merges duplicate rows
`merge` is SQL's `JOIN`. The danger is **one-to-many** joins: if an order has 2 item rows and 2 payment rows, joining items to payments on `order_id` gives 2 × 2 = 4 rows, and summing `payment_value` then double-counts money.
The fix used here: **aggregate each table to one row per order first**, then combine.
```python
paid_per_order = payments.groupby("order_id")["payment_value"].sum()
items_total_per_order = (items["price"] + items["freight_value"]).groupby(items["order_id"]).sum()
payment_gap = orders["order_id"].map(paid_per_order) - orders["order_id"].map(items_total_per_order)
```
`merge(..., validate="many_to_one")` is a safety net. pandas raises an error if the right-hand table has a duplicate key, instead of silently multiplying rows. It's used for the category translation and for attaching `customer_unique_id`.

### `duplicated` / `drop_duplicates`
- `df.duplicated()` marks rows identical to an earlier row in every column. Geolocation had 261,831 of them.
- `df.duplicated(subset=["review_id"])` checks only some columns. That's how key uniqueness was tested.
- `drop_duplicates(subset="order_id", keep="last")` keeps one row per order. Combined with a sort, it picks *which* row survives:
```python
reviews.sort_values(["order_id", "review_answer_timestamp", "review_creation_date", "review_id"]) \
       .drop_duplicates(subset="order_id", keep="last")
```
Sorting puts the wanted review (latest answer, then the tie-breakers) last inside each order, and `keep="last"` keeps it.

### Datetime arithmetic
- Subtracting two timestamps gives a duration (`Timedelta`): `.dt.days` gives whole days, `.dt.total_seconds() / 3600` gives hours.
- `.dt.normalize()` sets the time to midnight, giving the **calendar date**. It's used for the same-day rule.
- `.dt.to_period("M")` turns a timestamp into its month (`2017-11`). It's used for orders per month and cohorts.
- Comparing with an empty date (`NaT`) is always False. So `carrier_date < approved_at` never flags an order just because a date is missing; missing dates are counted separately.

### Copy-on-write in pandas 3
In pandas 3, a slice like `df[df.x > 0]` behaves as an independent copy. Editing it never changes the original, and the old `SettingWithCopyWarning` is gone. The cleaning notebook follows the safe style: it never edits in place and builds new tables with `assign()`:
```python
orders_clean = orders.assign(is_delivered=orders["order_status"].eq("delivered"), ...)
```
`orders` (the raw load) stays untouched, so every section can compare before and after.

## 3. Why flag instead of delete
Deleting a "bad" row silently changes every total built on top of it: orders, customers, revenue. Nobody reading the dashboard can see that it happened. A `flag_` column keeps every row and lets each analysis exclude rows **on purpose and visibly**. For example, the 1,359 orders with `flag_carrier_before_approval` are left out of the approval → carrier timing, but they still count as delivered orders for retention.
Only two tables change row count, and both are reduced to their intended grain, not filtered: reviews go to one row per order (−551 rows) and geolocation to one row per zip prefix (19,010 rows).

## 4. Why same-day orders are not repeats
A "repeat customer" should mean the customer **came back**. Some customers place two orders on the same day, for example when a basket is split across sellers. That is one shopping trip. Counting it would inflate loyalty:
- Lifetime: 2,788 customers have 2+ delivered orders, but only **2,004** came back on a later date. **784** were same-day only.
- So the lifetime repeat rate drops from 2.99% to **2.15%** (of 93,094 cohort customers).

## 5. Right-censoring in plain English
The data stops at the end of August 2018. A customer who first bought on 2018-08-20 had 11 days to come back; if they haven't, we don't know whether they never will or just haven't *yet*. Their story is "cut off" (censored) on the right-hand side of the timeline. Counting them as one-time buyers would make retention look worse than it is.
The fix is a **fixed follow-up window**: only judge customers we could watch for a full 180 days. The window ends 2018-08-31, so the first delivered order must be on or before **2018-03-04**. That leaves **56,188** customers for the 180-day metric.

## 6. First order from the full history (rule B)
To find each customer's *real* first order, search all dates **before** applying the analysis window. **10** customers who bought inside the window had actually first bought before 2017. Without this rule they would wrongly appear as new 2017 customers (93,104 "new" vs the correct 93,094).

## 7. What each notebook section does

**01_data_profiling**

| Section | What it does |
|---|---|
| 0 | Loads all tables and reports rows, dtypes, nulls, fully duplicated rows and key uniqueness. Reviews (`review_id`, `order_id`) and geolocation keys are not unique. |
| 1 | `customer_id` vs `customer_unique_id`: 99,441 vs 96,096. 97.00% of 93,358 people with a delivered order have exactly one. |
| 2–3 | Status mix; orders per month. Leads to the window 2017-01-01 → 2018-08-31. |
| 4 | Date checks: 8 delivered orders without a delivery date, 1,359 with carrier before approval, and so on. |
| 5 | Review duplicates and which date column should decide "latest". |
| 6–7 | Payments vs item totals (aggregated per order first); items per order. |
| 8–11 | Geolocation, products, price/freight outliers, referential integrity (all foreign keys resolve). |

**02_cleaning**

| Section | What it does |
|---|---|
| 1 | Orders: status/window flags, date-quality flags, payment mismatch (per-order sums compared with `.map`). |
| 2–3 | Items and payments: outlier and oddity flags; nothing removed. |
| 4 | Reviews reduced to one per order with sort + `drop_duplicates(keep="last")`, checked with `is_unique`. |
| 5 | Products: English categories with `validate="many_to_one"`, `'unknown'`, column renames. |
| 6–7 | Geolocation to one row per prefix (median lat/lng); customers/sellers flagged when the prefix has no coordinates. |
| 8 | Repeat rates with and without same-day orders; the rule-B count. |
| 9–10 | Writes the CSVs, re-reads them to confirm row counts, and builds the reconciliation table. |

---

## 8. Interview questions (with answers from this project)

**Q1. Why did you count customers with `customer_unique_id` and not `customer_id`?**
In Olist, `customer_id` is created per order: there are 99,441 of them, one per order, but only 96,096 real people (`customer_unique_id`). Counting `customer_id` would make every customer look like a one-time buyer by construction.

**Q2. What share of customers buy only once, and how did you make sure that number was fair?**
In profiling, 97.00% of the 93,358 customers with a delivered order had exactly one. For a fair repeat metric I used a 180-day follow-up window. Only customers whose first delivered order was on or before 2018-03-04 are judged, because the data ends 2018-08-31. Of those 56,188 customers, only 1.98% came back within 180 days.

**Q3. What is right-censoring and how did you handle it?**
Customers who joined near the end of the data haven't had time to return, so we can't tell "never" from "not yet". I handled it with a fixed 180-day follow-up and an eligibility cutoff (first order ≤ 2018-03-04), so every judged customer had the same chance to come back.

**Q4. Why don't same-day orders count as repeat purchases? What difference did it make?**
Two orders on the same day are one shopping trip, not a return visit. Applying that rule cut lifetime repeaters from 2,788 to 2,004 (2.99% → 2.15%). Within 180 days it cut them from 1,756 to 1,112 (3.13% → 1.98%). So 644 apparent 180-day repeaters were same-day only. Without the rule, the 180-day repeat rate would have been overstated by more than half (3.13% vs 1.98%).

**Q5. How did you avoid double counting when combining payments and items?**
Both tables have several rows per order (up to 29 payment rows and 21 items). I summed each to one value per order first and only then compared them. That comparison found 303 orders where payments and price + freight differ by more than R$0.01. Those are flagged, and revenue comes from item lines, not payments.

**Q6. The reviews table had duplicates. What rule did you use?**
547 orders had more than one review. I kept the review with the latest `review_answer_timestamp`, then latest `review_creation_date`, then highest `review_id` for ties. The answer timestamp is never empty, has a time of day, and had no ties, whereas the creation date tied in 157 orders. Separately, 789 `review_id`s were copied onto different orders. I kept those, because each review–order link is valid. Result: 99,224 → 98,673 rows, exactly one per order.

**Q7. Why did you flag problem rows instead of deleting them?**
Deleting changes totals invisibly. For example, 1,359 orders have a carrier date before approval. They're real delivered orders with a timestamp problem, so they stay in the retention numbers and are only excluded from the approval → carrier timing. Every flag count is in `outputs/phase2_cleaning_summary.csv`, so the impact is auditable.

**Q8. How did you choose the analysis window?**
From the monthly order counts. 2016 is sparse: 4 orders in September, 324 in October on only 10 days, none in November and 1 in December. September–October 2018 have 20 orders and none were delivered, which is the end of the extract. 2017-01-01 to 2018-08-31 keeps 99,092 of 99,441 orders (99.65%).
