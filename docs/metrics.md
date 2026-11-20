# Metric definitions

> **DRAFT — confirm after Phase 2 profiling.**
> This file is the single source of truth for metric definitions. Any change must also be logged in `docs/decisions_log.md`.

Table names follow the Olist Kaggle files (`orders`, `order_items`, `customers`, `order_reviews`, ...).

---

## 1. Customer
**Definition:** a customer is a `customer_unique_id`.
**In plain English:** Olist creates a new `customer_id` for every order, so we use `customer_unique_id` to recognise the same person across orders.
**Columns used:** `customers.customer_id`, `customers.customer_unique_id`, `orders.customer_id`

## 2. Delivered order
**Definition:** an order with `order_status = 'delivered'`. Used for delivery, review and retention metrics.
**In plain English:** only orders that actually reached the customer count; cancelled or unavailable orders are analysed separately.
**Columns used:** `orders.order_id`, `orders.order_status`

## 3. Product revenue and freight revenue
**Definition:** product revenue = sum of `order_items.price`; freight revenue = sum of `order_items.freight_value`. `payment_value` is not used as revenue.
**In plain English:** revenue is what the items cost plus, separately, what shipping cost — taken from the item lines, not from payments (payments include instalments/vouchers and can have several rows per order).
**Columns used:** `order_items.order_id`, `order_items.price`, `order_items.freight_value`

## 4. Repeat customer (lifetime)
**Definition:** a customer with 2 or more delivered orders.
**In plain English:** someone who came back and bought again at any point in the data.
**Columns used:** `customers.customer_unique_id`, `orders.order_id`, `orders.order_status`

## 5. Repeat within 180 days
**Definition:** the customer's second delivered order is within 180 days of their first. Only customers whose first delivered order is at least 180 days before the dataset's last purchase date are included.
**In plain English:** did they come back within six months? We only judge customers we could watch for a full six months, so recent customers are not unfairly counted as "never returned".
**Columns used:** `customers.customer_unique_id`, `orders.order_status`, `orders.order_purchase_timestamp`

## 6. Acquisition cohort
**Definition:** the month of the customer's first delivered order, by purchase timestamp.
**In plain English:** groups customers by the month they first bought, so we can compare how each group behaves over time.
**Columns used:** `customers.customer_unique_id`, `orders.order_status`, `orders.order_purchase_timestamp`

## 7. Late delivery and delay days
**Definition:** an order is late when `order_delivered_customer_date` is later than `order_estimated_delivery_date`, compared at date level. Delay days = difference in days between the two.
**In plain English:** the parcel arrived after the date Olist promised; delay days says by how much.
**Columns used:** `orders.order_delivered_customer_date`, `orders.order_estimated_delivery_date`

## 8. Delivery time
**Definition:** days between `order_purchase_timestamp` and `order_delivered_customer_date`.
**In plain English:** how long the customer waited from clicking "buy" to receiving the order.
**Columns used:** `orders.order_purchase_timestamp`, `orders.order_delivered_customer_date`

## 9. Freight share
**Definition:** `freight_value / (price + freight_value)`, computed at order level.
**In plain English:** what fraction of the total the customer paid went on shipping. Items are summed per order first, then the ratio is taken.
**Columns used:** `order_items.order_id`, `order_items.price`, `order_items.freight_value`

## 10. Review score per order
**Definition:** one review per order after deduplication, keeping the latest.
**In plain English:** some orders have more than one review row; we keep only the most recent so each order counts once. (Which timestamp defines "latest" is confirmed in Phase 2.)
**Columns used:** `order_reviews.order_id`, `order_reviews.review_id`, `order_reviews.review_score`, `order_reviews.review_creation_date`, `order_reviews.review_answer_timestamp`

## 11. Analysis window
**Definition:** TBD after Phase 2 (expected roughly Jan 2017 – Aug 2018).
**In plain English:** the date range we trust; 2016 and the final months of 2018 look sparse and will likely be excluded once profiling confirms it.
**Columns used:** `orders.order_purchase_timestamp`
