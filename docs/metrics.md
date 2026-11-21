# Metric definitions

> Final as of Phase 2 (2026-11-20); metrics 12–17 added in Phase 4A and 18–24 in Phase 4B (2026-11-21), implemented in `sql/04_base_views.sql` and `sql/05_` … `sql/09_*.sql`. Definitions are based on `notebooks/01_data_profiling.ipynb` and implemented in `notebooks/02_cleaning.ipynb`.
> This file is the single source of truth for metric definitions. Any change must also be logged in `docs/decisions_log.md`.

Table names follow the processed files in `data/processed/` (`orders`, `order_items`, `customers`, `order_reviews`, ...). See `docs/data_dictionary.md`.

---

## 1. Customer
**Definition:** a customer is a `customer_unique_id`.
**In plain English:** Olist creates a new `customer_id` for every order, so we use `customer_unique_id` to recognise the same person across orders.
**Columns used:** `customers.customer_id`, `customers.customer_unique_id`, `orders.customer_id`

## 2. Delivered order
**Definition:** an order with `order_status = 'delivered'` (`orders.is_delivered = True`). Used for delivery, review and retention metrics.
**In plain English:** only orders that actually reached the customer count; cancelled or unavailable orders are analysed separately.
**Columns used:** `orders.order_id`, `orders.order_status`, `orders.is_delivered`

## 3. Product revenue and freight revenue
**Definition:** product revenue = sum of `order_items.price`; freight revenue = sum of `order_items.freight_value`. `payment_value` is not used as revenue.
**In plain English:** revenue is what the items cost plus, separately, what shipping cost — taken from the item lines, not from payments (payments include instalments/vouchers and can have several rows per order).
**Columns used:** `order_items.order_id`, `order_items.price`, `order_items.freight_value`

## 4. Repeat customer (lifetime)
**Definition:** a customer who has a delivered order on a **later calendar date** than their first delivered order (metric 6). Additional delivered orders placed on the same calendar date as the first order do **not** count as a repeat. Population: customers whose first delivered order is inside the analysis window (metric 11).
**In plain English:** someone who came back on another day and bought again. A second order placed the same day is the same shopping trip (for example a basket split into two orders), not a return visit.
**Columns used:** `customers.customer_unique_id`, `orders.order_id`, `orders.is_delivered`, `orders.order_purchase_timestamp` (as a calendar date)

## 5. Repeat within 180 days
**Definition:** the customer has a delivered order on a later calendar date than their first delivered order **and** no more than 180 calendar days after it. Only customers whose first delivered order (metric 6) is inside the analysis window **and on or before 2018-03-04** are included (2018-03-04 + 180 days = 2018-08-31, the last day of the window). Same-day additional orders do not count (as in metric 4).
**In plain English:** did they come back within six months? We only judge customers we could watch for a full six months, so recent customers are not unfairly counted as "never returned" (right-censoring).
**Columns used:** `customers.customer_unique_id`, `orders.is_delivered`, `orders.order_purchase_timestamp`

## 6. First delivered order and acquisition cohort
**Definition:** a customer's first delivered order is their earliest delivered order by `order_purchase_timestamp` across the **full history** (all dates, including outside the analysis window). The acquisition cohort is the calendar month of that order. The analysis window is applied **after** this: only cohorts inside the window are analysed.
**In plain English:** we find when each person really first bought before filtering dates. Otherwise someone who first bought in 2016 and again in 2017 would wrongly look like a new 2017 customer.
**Columns used:** `customers.customer_unique_id`, `orders.is_delivered`, `orders.order_purchase_timestamp`

## 7. Late delivery and delay days
**Definition:** an order is late when `order_delivered_customer_date` is later than `order_estimated_delivery_date`, compared at date level. Delay days = difference in days between the two. Delivered orders with no customer delivery date (`flag_delivered_missing_customer_date`) are excluded from this metric.
**In plain English:** the parcel arrived after the date Olist promised; delay days says by how much.
**Columns used:** `orders.order_delivered_customer_date`, `orders.order_estimated_delivery_date`

## 8. Delivery time
**Definition:** days between `order_purchase_timestamp` and `order_delivered_customer_date`, for delivered orders with a customer delivery date. Step timings (approval → carrier → customer) exclude orders flagged `flag_carrier_before_approval`, `flag_carrier_before_purchase` or `flag_delivery_before_carrier`.
**In plain English:** how long the customer waited from clicking "buy" to receiving the order.
**Columns used:** `orders.order_purchase_timestamp`, `orders.order_delivered_customer_date`

## 9. Freight share
**Definition:** `freight_value / (price + freight_value)`, computed at order level.
**In plain English:** what fraction of the total the customer paid went on shipping. Items are summed per order first, then the ratio is taken.
**Columns used:** `order_items.order_id`, `order_items.price`, `order_items.freight_value`

## 10. Review score per order
**Definition:** one review per order. Keep the review with the latest `review_answer_timestamp`; if tied, the latest `review_creation_date`; if still tied, the highest `review_id`. Repeated `review_id`s on different orders are kept (each is a valid review–order link). Orders with no review have no score (empty, never 0).
**In plain English:** some orders have more than one review row; we keep the one the customer answered last so each order counts once.
**Columns used:** `order_reviews.order_id`, `order_reviews.review_id`, `order_reviews.review_score`, `order_reviews.review_creation_date`, `order_reviews.review_answer_timestamp`

## 11. Analysis window
**Definition:** orders with `order_purchase_timestamp` from 2017-01-01 00:00:00 to 2018-08-31 23:59:59 inclusive (`orders.in_analysis_window = True`). Cohorts use the first delivered order date (metric 6).
**In plain English:** the date range we trust. 2016 is sparse (2016-11 has no orders), and September–October 2018 hold only 20 orders, none of them delivered (the end of the data extract).
**Columns used:** `orders.order_purchase_timestamp`

## 12. Main category of an order
**Definition:** the `category_name_english` of the order's highest-priced item; ties on price go to the lowest `order_item_id`. `'unknown'` when that product has no category.
**In plain English:** an order can mix categories; we label it by what the customer spent most on.
**Columns used:** `order_items.order_id`, `order_items.price`, `order_items.order_item_id`, `products.category_name_english`
**Implemented in:** `analysis.v_orders.main_category` (`sql/04_base_views.sql`).

## 13. Main payment type of an order
**Definition:** the `payment_type` of the order's largest `payment_value`; ties go to the lowest `payment_sequential`. Rows with `payment_type = 'not_defined'` are ignored (NULL if nothing else is left).
**In plain English:** how the customer mainly paid.
**Columns used:** `order_payments.order_id`, `payment_type`, `payment_value`, `payment_sequential`

## 14. Time to second purchase
**Definition:** `second_purchase_date − first_purchase_date` in whole days, where the second purchase date is the first **later calendar date** with a delivered order (metric 4). Only defined for repeaters. Reported in buckets (≤30, 31–90, 91–180, 181–365, >365 days) with median and quartiles.
**In plain English:** how long returning customers took to come back.
**Caveat:** right-censored. Late cohorts can only show short gaps, so the distribution is biased towards short values.

## 15. Monthly cohort retention
**Definition:** for each cohort month (metric 6, in-window cohorts) and month number k = 0…12, `retention_pct` = distinct cohort customers with a delivered order on a later calendar date than their first, whose purchase falls in calendar month (cohort month + k), ÷ cohort size. k is a calendar-month offset, so k = 0 means "returned later in the same calendar month". A cell is NULL (not 0) when cohort month + k is after 2018-08 (the month is not fully observed).
**In plain English:** of the people who first bought in a given month, what % came back in each following month — only shown where we can actually see that month.
**Summaries:** pooled (sum returning ÷ sum cohort size) and median-of-cohorts over observed cells only (`q05_07_cohort_retention_summary`).

## 16. RFM (recency, frequency, monetary)
**Population:** in-window cohort customers (metric 6 and 11): 93,094.
**Snapshot date:** 2018-09-01 (the day after the analysis window ends).
- **Recency** `recency_days` = 2018-09-01 − last delivered purchase date (whole days).
- **Monetary** `monetary` = the customer's total product revenue (sum of `price` over all delivered orders, metric 3; freight excluded).
- **Frequency** `f_flag` = `'repeat'` if the customer has delivered orders on ≥ 2 distinct calendar dates, else `'one-time'`. A 1–5 frequency score is not used: 97.85% of the population has one purchase date (`q05_01_headline`), so quintiles of frequency would only split identical values by an arbitrary tie-break.
- **Scores:** `r_score = NTILE(5)` ordered by recency_days descending (most recent = 5); `m_score = NTILE(5)` ordered by monetary ascending (highest = 5). Ties are ordered by `customer_unique_id` so scores are reproducible; customers with equal values can still fall either side of a quintile boundary.

**Segment mapping** (first match wins):

| Segment | Rule |
|---|---|
| Champions | repeat, r ≥ 4, m ≥ 4 |
| Loyal repeaters | repeat, any other score |
| Promising high-value one-timers | one-time, r ≥ 4, m ≥ 4 |
| Recent low-value one-timers | one-time, r ≥ 4, m ≤ 3 |
| Lapsed high-value one-timers | one-time, r ≤ 2, m ≥ 4 |
| Lapsed low-value one-timers | one-time, r ≤ 2, m ≤ 3 |
| Middle one-timers | one-time, r = 3 (everything else) |

**In plain English:** sort customers by how recently they bought and how much they spent, split each into five equal groups, and label groups by what Olist would do with them (keep, win back, nurture).

## 17. Minimum sample sizes for breakdowns
**Definition:** 180-day repeat rates by first-order state are shown only for states with ≥ 500 eligible customers; by first-order main category only for categories with ≥ 300 eligible customers.
**In plain English:** with a ~2% repeat rate, a group of 100 customers has only ~2 repeaters, so one person more or less swings the rate by a full percentage point. The thresholds keep each rate based on at least a few repeaters. They are rules of thumb, not a statistical test (tests follow in Phase 5).
**Added in Phase 4B:** sellers need ≥ 50 in-window delivered orders (main-seller attribution, metric 18) before their late % is shown or ranked.

## 18. Main seller, seller state and same-state orders
**Definition:** `main_seller_id` = the seller of the order's highest-priced item (same tie rule as metric 12); `seller_state` = that seller's state; `is_same_state` = `seller_state = customer_state`. Orders with several sellers (1,275 delivered orders) are attributed to the main seller only.
**In plain English:** who mainly shipped the order and whether it stayed within the customer's state, a rough proxy for short distance.

## 19. Buckets and bands
All defined once as columns of `analysis.v_orders` (and copied as `first_*` columns for the first order in `analysis.v_customers`). Labels start with a number so they sort correctly. CASE takes the first matching line, so ranges never overlap.

| Column | Based on | Bands |
|---|---|---|
| `delay_bucket` | `delay_days` (date level, metric 7) | `1 early/on time` (≤ 0), `2 1-3 days late`, `3 4-7`, `4 8-14`, `5 15+`; NULL with no delivery date |
| `delivery_speed_bucket` | purchase → delivery time (decimal days) | `1 <=7 days`, `2 8-14` (> 7 to 14), `3 15-21` (> 14 to 21), `4 22-30` (> 21 to 30), `5 >30`; NULL with no delivery date |
| `freight_share_band` | freight ÷ (product + freight), unrounded (metric 9) | `1 <10%`, `2 10-20%`, `3 20-30%`, `4 30-40%`, `5 >=40%` (lower edge included) |
| `installment_band` | `max_installments` | `1 0-1` (0 instalments = single payment), `2 2-3`, `3 4-6`, `4 7-10`, `5 >10`; NULL with no payment row (1 order) |
| `order_value_band` | `order_value` (product + freight, R$) | `1 <50`, `2 50-100`, `3 100-200`, `4 200-500`, `5 >=500` |

Order-value bands are round numbers around the eligible first-order quartiles (p25 R$61.58, median R$103.73, p75 R$174.42), with a top band for large baskets. Eligible first orders per band: 9,714 / 17,301 / 17,958 / 8,926 / 2,289 (`q08_07`).

## 20. Late % and on-time %
**Definition:** late % = late orders ÷ orders with a customer delivery date (`count(is_late)`), × 100. On-time % = 100 − late %. Orders with no delivery date are excluded from both the numerator and the denominator.

## 21. Seller late concentration
**Definition:** among sellers with ≥ 50 in-window orders, rank by late % (ties: more late orders first, then `seller_id`). The worst 10% = the top ceil(10% × number of sellers). Their late orders are reported as a share of all late orders from qualifying sellers, and as a share of all in-window late orders.

## 22. Second-visit product value
**Definition:** for an eligible customer who repeated within 180 days (metric 5), the sum of `product_value` over all their delivered orders on `second_purchase_date`. The median over all 1,112 such customers is R$89.90 (`q09_04`).
**In plain English:** what a customer typically spends when they come back the first time. Used as the revenue per extra repeat customer in estimates.

## 23. State opportunity measure (ESTIMATE)
**Definition:** per state (≥ 500 eligible customers): eligible customers whose first order was late × (national 180-day repeat rate of on-time first orders − national rate of late first orders). States are ranked by it with `RANK()`.
**In plain English:** how many extra repeat customers the state would have if its late first orders had repeated like on-time ones.
**Assumptions:** the gap is caused by lateness (untested; Phase 5); the national gap applies in every state (state-level late cells are too small for their own gap).

## 24. Impact estimates (ESTIMATE)
- **Late delivery (`q09_04`):** extra repeaters = late-first eligible customers × (on-time rate − late rate); extra product revenue = extra repeaters × median second-visit product value (metric 22). Assumes the gap is caused by lateness; 180-day horizon; eligible customers only; one second visit per extra repeater; product revenue, not margin.
- **Second-purchase campaign (`q09_05`):** extra repeaters = customers in "Promising high-value one-timers" × assumed conversion rate (1%, 2%, 5%); extra product revenue = × median second-visit product value. The conversion rates are assumptions, not measured. The median value is from all repeaters, not only high-value ones. Campaign cost is not included.

---

## Flag columns
All flags are True/False. Rows are never deleted for these issues; each analysis decides whether to exclude flagged rows.

| Table | Column | True when |
|---|---|---|
| orders | `is_delivered` | `order_status = 'delivered'` |
| orders | `in_analysis_window` | purchase is between 2017-01-01 and 2018-08-31 |
| orders | `flag_delivered_missing_customer_date` | delivered, but `order_delivered_customer_date` is empty |
| orders | `flag_carrier_before_approval` | carrier date earlier than approval |
| orders | `flag_carrier_before_purchase` | carrier date earlier than purchase |
| orders | `flag_delivery_before_carrier` | customer delivery earlier than carrier date |
| orders | `flag_cancelled_with_delivery_date` | status `canceled` but has a customer delivery date |
| orders | `flag_no_items` | the order has no `order_items` rows |
| orders | `flag_no_payment` | the order has no `order_payments` rows |
| orders | `flag_payment_mismatch` | order-level sum of `payment_value` differs from sum of price + freight by more than R$0.01 |
| order_items | `flag_price_above_p99` | price above the 99th percentile of all items |
| order_items | `flag_freight_above_p99` | freight above the 99th percentile of all items |
| order_items | `flag_zero_freight` | `freight_value = 0` |
| order_payments | `flag_zero_value` | `payment_value = 0` |
| order_payments | `flag_payment_type_not_defined` | `payment_type = 'not_defined'` (excluded from payment-type analysis) |
| order_reviews | `flag_multiple_reviews` | the order had more than one raw review row (see also `n_raw_reviews`) |
| products | `flag_missing_category` | raw category was empty (`category_name_english = 'unknown'`) |
| products | `flag_zero_weight` | `product_weight_g = 0` |
| products | `flag_missing_dimensions` | any of weight/length/height/width is empty |
| customers | `flag_zip_not_in_geolocation` | zip prefix has no row in processed `geolocation` |
| sellers | `flag_zip_not_in_geolocation` | zip prefix has no row in processed `geolocation` |
