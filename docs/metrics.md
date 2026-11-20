# Metric definitions

> Final as of Phase 2 (2026-11-20). Definitions are based on `notebooks/01_data_profiling.ipynb` and implemented in `notebooks/02_cleaning.ipynb`.
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
