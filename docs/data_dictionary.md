# Data dictionary: raw Olist CSVs

Source: Olist Brazilian E-Commerce public dataset (Kaggle), 9 CSVs in `data/raw/` (never modified).
Row counts, types and issue counts come from `notebooks/01_data_profiling.ipynb` (pandas 3.1.1). Types are
shown as pandas loads them there: `str` = text, `datetime` = timestamp, `int`/`float` = number.

Profiling findings are summarised under "Known issues" for each raw table. The cleaned versions are described under
[Processed tables](#processed-tables-dataprocessed) at the end. Cleaning rules are in `docs/decisions_log.md`, and metric definitions in `docs/metrics.md`.

---

## How the tables join

```
                        customers
                            │ customer_id (1 : 1, one customer_id per order)
                            │
                         orders ──────────────┬───────────────────┐
                            │ order_id        │ order_id          │ order_id
                            │ (1 : many)      │ (1 : many)        │ (1 : many)
                       order_items      order_payments      order_reviews
                        │         │
           product_id   │         │  seller_id
                        ▼         ▼
                    products    sellers
                        │
                        │ product_category_name
                        ▼
              category_translation

  customers.customer_zip_code_prefix ─┐
                                      ├──► geolocation.geolocation_zip_code_prefix  (MANY rows per prefix)
  sellers.seller_zip_code_prefix ─────┘
```

- To get the **real customer** for an order: `orders.customer_id → customers.customer_id → customers.customer_unique_id`.
- `order_items`, `order_payments` and `order_reviews` each have several rows per order. **Aggregate each to one row per order before joining them together**, or money and counts get multiplied.
- `geolocation` has many coordinate rows per zip prefix. Reduce it to one row per prefix before joining.

---

## orders (`olist_orders_dataset.csv`): 99,441 rows
**Grain:** one row per order. **Key:** `order_id` (unique). **Foreign key:** `customer_id → customers`.

| Column | Type | Meaning |
|---|---|---|
| `order_id` | str | Order identifier. |
| `customer_id` | str | Per-order customer identifier. **Not the person**: see `customers.customer_unique_id`. |
| `order_status` | str | delivered, shipped, canceled, unavailable, invoiced, processing, created, approved. |
| `order_purchase_timestamp` | datetime | When the customer placed the order. Used for months, cohorts and the analysis window. |
| `order_approved_at` | datetime | When the payment was approved. |
| `order_delivered_carrier_date` | datetime | When the seller handed the parcel to the carrier. |
| `order_delivered_customer_date` | datetime | When the customer received the parcel. |
| `order_estimated_delivery_date` | datetime | Delivery date promised to the customer at purchase (date only). |

**Known issues:** 96,478 delivered (97.02%). Nulls: 160 approval, 1,783 carrier and 2,965 customer-delivery dates. Among delivered orders, 8 lack a customer date, 14 lack an approval date and 2 lack a carrier date. 6 canceled orders have a customer delivery date. 1,359 orders have a carrier date before approval, 166 a carrier date before purchase, and 23 a customer delivery before the carrier date. 2016 is sparse (2016-11 has no orders) and 2018-09/10 hold only 20 orders, none delivered.

## customers (`olist_customers_dataset.csv`): 99,441 rows
**Grain:** one row per `customer_id` (so one row per order). **Key:** `customer_id` (unique).

| Column | Type | Meaning |
|---|---|---|
| `customer_id` | str | Per-order customer id; joins to `orders.customer_id`. |
| `customer_unique_id` | str | **The real person.** 96,096 distinct values. Use it for every customer-level metric. |
| `customer_zip_code_prefix` | str | First 5 digits of the zip code (kept as text so leading zeros survive). |
| `customer_city` | str | City name (lowercase, unaccented). |
| `customer_state` | str | Two-letter Brazilian state code. |

**Known issues:** 278 rows (157 prefixes) have a zip prefix that is not in `geolocation`.

## order_items (`olist_order_items_dataset.csv`): 112,650 rows
**Grain:** one row per item in an order (buying 2 units of a product = 2 rows). **Key:** `order_id + order_item_id` (unique).
**Foreign keys:** `order_id → orders`, `product_id → products`, `seller_id → sellers`.

| Column | Type | Meaning |
|---|---|---|
| `order_id` | str | Order the item belongs to. |
| `order_item_id` | int | Item counter inside the order (1, 2, 3, …). |
| `product_id` | str | Product sold. |
| `seller_id` | str | Seller who sold it. |
| `shipping_limit_date` | datetime | Deadline for the seller to hand the item to the carrier. |
| `price` | float | Item price in R$. |
| `freight_value` | float | Freight charged **for this item** in R$ (freight is split across items). |

**Known issues:** 775 orders have no items (mostly unavailable/canceled). Price is right-skewed (median R$74.99, max R$6,735.00). 383 items have zero freight.

## order_payments (`olist_order_payments_dataset.csv`): 103,886 rows
**Grain:** one row per payment method used in an order. **Key:** `order_id + payment_sequential` (unique). **Foreign key:** `order_id → orders`.

| Column | Type | Meaning |
|---|---|---|
| `order_id` | str | Order paid for. |
| `payment_sequential` | int | 1, 2, … when an order is paid with several methods/vouchers. |
| `payment_type` | str | credit_card, boleto (Brazilian bank slip), voucher, debit_card, not_defined. |
| `payment_installments` | int | Number of instalments chosen. |
| `payment_value` | float | Amount paid with this method in R$. |

**Known issues:** up to 29 rows per order. 9 zero-value rows, 3 `not_defined` rows, 2 rows with 0 instalments. 1 order has no payment. 303 orders' payments differ from price + freight by more than R$0.01.

## order_reviews (`olist_order_reviews_dataset.csv`): 99,224 rows
**Grain:** intended as one review per order, but it isn't. **Intended keys:** `review_id`, `order_id`. **Neither is unique.** **Foreign key:** `order_id → orders`.

| Column | Type | Meaning |
|---|---|---|
| `review_id` | str | Review identifier. |
| `order_id` | str | Order reviewed. |
| `review_score` | int | 1–5 satisfaction score. |
| `review_comment_title` | str | Optional title (88.34% blank). |
| `review_comment_message` | str | Optional comment (58.70% blank). |
| `review_creation_date` | datetime | When the satisfaction survey was sent (date only in almost all rows). |
| `review_answer_timestamp` | datetime | When the customer answered (full timestamp). |

**Known issues:** 789 review_ids are repeated across different orders (identical content). 547 orders have more than one review. 768 orders have no review.

## products (`olist_products_dataset.csv`): 32,951 rows
**Grain:** one row per product. **Key:** `product_id` (unique). **Foreign key:** `product_category_name → category_translation`.

| Column | Type | Meaning |
|---|---|---|
| `product_id` | str | Product identifier. |
| `product_category_name` | str | Category in Portuguese. |
| `product_name_lenght` | float | Number of characters in the product name (column name misspelled in the source). |
| `product_description_lenght` | float | Number of characters in the description (misspelled in the source). |
| `product_photos_qty` | float | Number of product photos. |
| `product_weight_g` | float | Weight in grams. |
| `product_length_cm` | float | Length in cm. |
| `product_height_cm` | float | Height in cm. |
| `product_width_cm` | float | Width in cm. |

**Known issues:** 610 products lack category, name length, description length and photo count (all the same rows). 2 lack size attributes and 4 weigh 0 g. 2 categories (`pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos`) have no translation.

## sellers (`olist_sellers_dataset.csv`): 3,095 rows
**Grain:** one row per seller. **Key:** `seller_id` (unique).

| Column | Type | Meaning |
|---|---|---|
| `seller_id` | str | Seller identifier. |
| `seller_zip_code_prefix` | str | First 5 digits of the seller's zip code. |
| `seller_city` | str | City. |
| `seller_state` | str | Two-letter state code. |

**Known issues:** 7 sellers have a zip prefix not in `geolocation`.

## geolocation (`olist_geolocation_dataset.csv`): 1,000,163 rows
**Grain:** one row per coordinate point. There are **many per zip prefix** (19,015 distinct prefixes, median 29 rows each). **Intended key:** `geolocation_zip_code_prefix`, not unique.

| Column | Type | Meaning |
|---|---|---|
| `geolocation_zip_code_prefix` | str | 5-digit zip prefix. |
| `geolocation_lat` | float | Latitude. |
| `geolocation_lng` | float | Longitude. |
| `geolocation_city` | str | City. |
| `geolocation_state` | str | State code. |

**Known issues:** 261,831 exact duplicate rows. 42 rows (21 prefixes) lie outside Brazil's rough bounding box.

## category_translation (`product_category_name_translation.csv`): 71 rows
**Grain:** one row per category. **Key:** `product_category_name` (unique).
File starts with a UTF-8 byte-order mark, so read it with `encoding="utf-8-sig"`.

| Column | Type | Meaning |
|---|---|---|
| `product_category_name` | str | Category in Portuguese (joins to `products`). |
| `product_category_name_english` | str | English category name. |

---

## Processed tables (`data/processed/`)

Produced by `notebooks/02_cleaning.ipynb` from `data/raw/` only. These files are gitignored; re-run the notebook to rebuild them.
Every raw column is kept unless stated otherwise. All `is_` / `in_` / `flag_` columns are True/False. Their exact meaning is defined in the "Flag columns" table in `docs/metrics.md`.
Only two tables change row count: `order_reviews` and `geolocation`.

| File | Grain | Rows (raw → processed) | Key | Added / changed columns |
|---|---|---|---|---|
| `orders.csv` | one row per order | 99,441 → 99,441 | `order_id` | `is_delivered`, `in_analysis_window`, `flag_delivered_missing_customer_date`, `flag_carrier_before_approval`, `flag_carrier_before_purchase`, `flag_delivery_before_carrier`, `flag_cancelled_with_delivery_date`, `flag_no_items`, `flag_no_payment`, `flag_payment_mismatch` |
| `customers.csv` | one row per `customer_id` (= per order) | 99,441 → 99,441 | `customer_id` | `flag_zip_not_in_geolocation` |
| `order_items.csv` | one row per item in an order | 112,650 → 112,650 | `order_id + order_item_id` | `flag_price_above_p99`, `flag_freight_above_p99`, `flag_zero_freight` |
| `order_payments.csv` | one row per payment method per order | 103,886 → 103,886 | `order_id + payment_sequential` | `flag_zero_value`, `flag_payment_type_not_defined` |
| `order_reviews.csv` | **one row per reviewed order** | 99,224 → 98,673 | `order_id` (now unique; `review_id` is still not unique) | `n_raw_reviews` (raw review rows the order had), `flag_multiple_reviews` |
| `products.csv` | one row per product | 32,951 → 32,951 | `product_id` | **`category_name_english`** replaces `product_category_name` (`'unknown'` when missing); `product_name_lenght` → `product_name_length`; `product_description_lenght` → `product_description_length`; `flag_missing_category`, `flag_zero_weight`, `flag_missing_dimensions` |
| `sellers.csv` | one row per seller | 3,095 → 3,095 | `seller_id` | `flag_zip_not_in_geolocation` |
| `geolocation.csv` | **one row per zip prefix** | 1,000,163 → 19,010 | `geolocation_zip_code_prefix` (unique) | `geolocation_lat` / `geolocation_lng` = median of the cleaned points; `geolocation_city` / `geolocation_state` = most common value; `n_points` = points used |

Notes:
- There is no separate translation file in `data/processed/`. English names live directly in `products.category_name_english`, including the two added translations (`pc_gamer`, `portable_kitchen_and_food_preparers`).
- Timestamps are written as `YYYY-MM-DD HH:MM:SS`. Columns where every value is midnight (e.g. `order_estimated_delivery_date`) are written as `YYYY-MM-DD`. Empty dates are blank cells. Booleans are written as `True` / `False`. Zip prefixes are written as 5-character text, so read them back as text (`dtype=str`) to keep leading zeros.
- Joins work as in the raw diagram above, except that `order_reviews` and `geolocation` can now be joined directly (one row per `order_id` / zip prefix). `order_items` and `order_payments` still need aggregating to order level first.

---

## PostgreSQL tables (`clean.*`)

Built by `sql/01_schema.sql` + `sql/02_indexes.sql` and loaded from `data/processed/` by `src/load_to_postgres.py` (Phase 3) into the `olist` database, schema `clean`. Column names and order are identical to the processed CSVs. The load is checked by `sql/03_quality_checks.sql` (results in `outputs/phase3_quality_checks.csv`).

**Type rules used for every table**

| Kind of column | PostgreSQL type |
|---|---|
| IDs, zip prefixes, city, state, status, payment type, category, review text | `text` |
| All dates and times (date-only values stored as midnight) | `timestamp` |
| `price`, `freight_value`, `payment_value` | `numeric(10,2)` |
| `order_item_id`, `payment_sequential`, `payment_installments`, `review_score`, `n_raw_reviews`, `n_points`, the 7 product size/text columns | `integer` |
| `geolocation_lat`, `geolocation_lng` | `double precision` |
| All `is_` / `in_` / `flag_` columns | `boolean` |

**Tables, keys and constraints** (rows = rows loaded)

| Table | Rows | Primary key | Foreign keys | Nullable columns | CHECK constraints | Extra indexes |
|---|---|---|---|---|---|---|
| `clean.customers` | 99,441 | `customer_id` | none | none | zip prefix is 5 digits | `customer_unique_id`, `customer_zip_code_prefix` |
| `clean.sellers` | 3,095 | `seller_id` | none | none | zip prefix is 5 digits | `seller_zip_code_prefix` |
| `clean.products` | 32,951 | `product_id` | none | the 7 size/text attributes | none | none |
| `clean.geolocation` | 19,010 | `geolocation_zip_code_prefix` | none | none | zip prefix is 5 digits | none |
| `clean.orders` | 99,441 | `order_id` | `customer_id → clean.customers` | `order_approved_at`, `order_delivered_carrier_date`, `order_delivered_customer_date` | none | `customer_id`, `order_purchase_timestamp` |
| `clean.order_items` | 112,650 | `order_id, order_item_id` | `order_id → clean.orders`, `product_id → clean.products`, `seller_id → clean.sellers` | none | `price >= 0`, `freight_value >= 0` | `product_id`, `seller_id` |
| `clean.order_payments` | 103,886 | `order_id, payment_sequential` | `order_id → clean.orders` | none | `payment_value >= 0`, `payment_installments >= 0` | none |
| `clean.order_reviews` | 98,673 | `order_id` (`review_id` is not unique) | `order_id → clean.orders` | `review_comment_title`, `review_comment_message` | `review_score` between 1 and 5 | none |

Notes:
- There is **no foreign key** from `customers` or `sellers` to `geolocation`: 279 customers and 7 sellers have a zip prefix with no geolocation row. Join to geolocation with a `LEFT JOIN`.
- The 7 product columns written as `N.0` in `products.csv` are loaded as integers (`225.0` → `225`). The loader stops if any value has a non-zero decimal part. See `docs/decisions_log.md`.
- `order_estimated_delivery_date` is a date in the source and is stored as a `timestamp` at midnight. Compare it at date level (`::date`) as `docs/metrics.md` metric 7 requires.

---

## Analysis views (`analysis.*`)

Built by `sql/04_base_views.sql` (Phase 4A), created by `src/create_views.py` and rebuilt by every `src/load_to_postgres.py` run. Views store no data; they are saved queries over `clean.*`. Metric rules are in `docs/metrics.md`. Row counts are checked in `sql/03_quality_checks.sql` section 7.

### `analysis.v_orders`: one row per delivered order (96,478 rows; key `order_id`)

| Column | Type | Meaning |
|---|---|---|
| `order_id`, `customer_id` | text | from `clean.orders` |
| `customer_unique_id`, `customer_state`, `customer_city` | text | from `clean.customers` via `customer_id` |
| `order_purchase_timestamp` | timestamp | purchase time |
| `purchase_date` | date | calendar day of purchase |
| `purchase_month` | date | first day of the purchase month |
| `in_analysis_window` | boolean | purchase in 2017-01-01..2018-08-31 |
| `order_approved_at`, `order_delivered_carrier_date`, `order_delivered_customer_date`, `order_estimated_delivery_date` | timestamp | as in `clean.orders` |
| `delivery_days` | numeric | purchase → customer delivery in days, 2 decimals; NULL for the 8 orders with no delivery date |
| `delay_days` | integer | delivery date − estimated date (negative = early); NULL if no delivery date |
| `is_late` | boolean | delivery date > estimated date (dates, not timestamps); NULL for 8 orders; true for 6,534 |
| `product_value`, `freight_value` | numeric | sum of item `price` / `freight_value` for the order |
| `order_value` | numeric | product + freight |
| `freight_share` | numeric | freight ÷ order_value, 4 decimals |
| `n_items`, `n_sellers` | bigint | item lines; distinct sellers |
| `main_category` | text | category of the highest-priced item (metrics.md 12) |
| `max_installments` | integer | largest instalment count among the order's payments |
| `main_payment_type` | text | type of the largest payment, `not_defined` ignored (metrics.md 13); NULL for 1 order |
| `review_score` | integer | 1–5; NULL for 646 delivered orders with no review |
| `flag_delivered_missing_customer_date`, `flag_carrier_before_approval`, `flag_carrier_before_purchase`, `flag_delivery_before_carrier`, `flag_payment_mismatch` | boolean | as in `clean.orders` |
| *Added in Phase 4B (end of the view):* | | |
| `main_seller_id` | text | seller of the highest-priced item (metrics.md 18) |
| `seller_state` | text | state of the main seller |
| `is_same_state` | boolean | seller_state = customer_state |
| `delay_bucket` | text | `1 early/on time` … `5 15+ days late`; NULL for 8 orders (metrics.md 19) |
| `delivery_speed_bucket` | text | `1 <=7 days` … `5 >30 days`; NULL for 8 orders |
| `freight_share_band` | text | `1 <10%` … `5 >=40%` |
| `installment_band` | text | `1 0-1` … `5 >10`; NULL for 1 order with no payment |
| `order_value_band` | text | `1 <50` … `5 >=500` (R$, product + freight) |

Every delivered order has at least one item (0 with NULL `product_value`), and so a main seller.

### `analysis.v_customers`: one row per `customer_unique_id` with a delivered order (93,358 rows)

| Column | Type | Meaning |
|---|---|---|
| `customer_unique_id` | text | the customer (key) |
| `first_order_id`, `first_purchase_date`, `cohort_month` | text / date / date | first delivered order over the full history (ties: timestamp, then order_id) |
| `in_window_cohort` | boolean | first purchase date in 2017-01-01..2018-08-31 (93,094 true) |
| `eligible_180d` | boolean | in window and first purchase date ≤ 2018-03-04 (56,188 true) |
| `first_state`, `first_main_category`, `first_order_value`, `first_freight_share`, `first_is_late`, `first_delay_days`, `first_delivery_days`, `first_review_score` | various | the same columns of the first order in `v_orders` |
| `n_delivered_orders` | integer | all delivered orders |
| `n_distinct_purchase_dates` | integer | distinct calendar days with a delivered order |
| `n_orders_on_first_date` | integer | delivered orders on the first purchase date (incl. the first) |
| `second_purchase_date` | date | first later calendar date with a delivered order; NULL for one-timers |
| `days_to_second` | integer | second − first purchase date |
| `is_repeat_lifetime` | boolean | has a later-date delivered order |
| `is_repeat_180d` | boolean | later-date order within 180 days; **NULL when not `eligible_180d`** |
| `same_day_only_repeater` | boolean | ≥ 2 delivered orders, all on one day |
| `total_product_value` | numeric | sum of product value over all delivered orders |
| `last_purchase_date` | date | latest delivered purchase date |
| *Added in Phase 4B (end of the view), all OF THE FIRST ORDER:* | | |
| `first_seller_state`, `first_is_same_state` | text / boolean | main seller's state; same state as the customer |
| `first_max_installments` | integer | largest instalment count |
| `first_delay_bucket`, `first_delivery_speed_bucket`, `first_freight_share_band`, `first_installment_band`, `first_order_value_band` | text | the `v_orders` buckets of the first order |

### `analysis.v_customer_rfm`: one row per in-window cohort customer (93,094 rows)

| Column | Type | Meaning |
|---|---|---|
| `customer_unique_id`, `cohort_month`, `first_purchase_date`, `last_purchase_date`, `n_distinct_purchase_dates` | | from `v_customers` |
| `recency_days` | integer | 2018-09-01 − last purchase date |
| `monetary` | numeric | `total_product_value` |
| `r_score`, `m_score` | integer | NTILE(5); 5 = most recent / highest spend |
| `f_flag` | text | `repeat` (≥ 2 purchase dates) or `one-time` |
| `segment` | text | one of 7 segments (metrics.md 16) |

---

## Reporting views (`report.*`)

Built by `sql/11_report_views.sql` (Phase 6) for Power BI, created by `src/create_views.py` after the analysis views and rebuilt by every `src/load_to_postgres.py` run. A star schema (one fact table, five dimensions) plus pre-aggregated result tables. Row counts and the match with Phase 4/5 outputs are checked in `sql/03_quality_checks.sql` section 10. Relationships and DAX: `docs/powerbi/`.

### `report.fact_orders`: one row per delivered order in the analysis window (96,211 rows; key `order_id`)

| Column | Type | Meaning |
|---|---|---|
| `order_id` | text | key |
| `customer_unique_id` | text | → `dim_customer` |
| `purchase_date` | date | → `dim_date` |
| `customer_state` | text | → `dim_state[state_code]` |
| `main_seller_id`, `seller_state` | text | → `dim_seller`; the main seller's state |
| `same_state` | boolean | seller state = customer state |
| `main_category` | text | → `dim_category` |
| `product_value`, `freight_value`, `order_value`, `freight_share` | numeric | as in `v_orders` (metrics 3, 9) |
| `n_items` | bigint | item lines |
| `delivery_days`, `delay_days`, `is_late` | numeric / integer / boolean | metrics 7–8; NULL for the 8 orders with no delivery date |
| `delay_bucket`, `delay_bucket_sort` | text / integer | e.g. `early/on time` (1) … `15+ days late` (5): the `v_orders` bucket without its number prefix, plus the number for sorting |
| `delivery_speed_bucket`, `delivery_speed_bucket_sort` | text / integer | `<=7 days` (1) … `>30 days` (5) |
| `review_score` | integer | 1–5; NULL with no review |
| `has_review` | boolean | review exists |
| `is_bad_review` | boolean | score 1–2 (metric 25); **NULL when no review** |
| `is_first_order` | boolean | the customer's first delivered order over the full history (93,094 true) |

### `report.dim_customer`: one row per `customer_unique_id` with a delivered order (93,358 rows)

| Column | Type | Meaning |
|---|---|---|
| `customer_unique_id` | text | key |
| `in_window_cohort`, `eligible_180d`, `is_repeat_180d`, `is_repeat_lifetime`, `cohort_month` | | from `v_customers` (`is_repeat_180d` NULL when not eligible) |
| `first_state`, `first_main_category`, `first_is_late`, `first_review_score` | | attributes of the first order |
| `first_review_label`, `first_review_sort` | text / integer | `1 star` … `5 stars` (1–5), `No review` (6) |
| `n_delivered_orders`, `total_product_value` | integer / numeric | from `v_customers` |
| `r_score`, `m_score`, `f_flag`, `segment` | | from `v_customer_rfm`; **NULL for the 264 customers outside the in-window cohort** |

### `report.dim_date`: one row per day, 2017-01-01 … 2018-08-31 (608 rows; key `date`)
`date`, `year`, `quarter`, `month_number`, `month_name` (`January`), `year_month` (`2017-01`), `month_start`, `weekday` (`Monday`), `weekday_number` (ISO, 1 = Monday), `in_analysis_window` (all true).

### `report.dim_category` (74 rows; key `main_category`)
Distinct `category_name_english` from `clean.products`, incl. `unknown`.

### `report.dim_seller` (3,095 rows; key `seller_id`)
`seller_id`, `seller_state`, `seller_city` from `clean.sellers`.

### `report.dim_state` (27 rows; key `state_code`)
`state_code` (UF), `state_name`, `region` (North, Northeast, Center-West, Southeast, South). Hard-coded list of the 26 states + DF.

### Pre-aggregated views (not related to the star schema in Power BI)

| View | Rows | Reproduces | Extra columns |
|---|---|---|---|
| `agg_cohort_retention` | 260 | `q05_03` (78 censored cells NULL) | `cohort_label` (`YYYY-MM`) |
| `agg_time_to_second` | 5 | `q05_02` bucket rows | `repeaters`, `p25_days`, `median_days`, `p75_days` on every row |
| `agg_repeat_by_review` | 6 | `q07_08` | `review_label`, `sort_order`, Wilson `ci_low_pct` / `ci_high_pct` |
| `agg_repeat_by_category` | 24 | `q05_05` | Wilson CI |
| `agg_bad_review_by_delay` | 5 | `q07_06` | `delay_bucket_sort`, `is_late`, `bad_reviews`, `bad_review_rate_pct` (= `pct_1_2_star`), Wilson CI (median_score dropped) |
| `agg_excess_bad_reviews_state` | 17 | `q10_02` | `state_name`, `region` |
| `agg_excess_bad_reviews_seller` | 20 | `q10_03` | `seller_label` (`Seller` + first 8 characters of the id) |
| `agg_excess_bad_reviews_route` | 15 | `q10_04` | – |
| `agg_campaign_baseline` | 1 | inputs of `q09_05` | `segment_customers` 14,533, `n_second_visits` 1,112, `median_second_visit_value` 89.90 |

CI columns are percentages with 2 decimals (95% Wilson interval, z = 1.959964).
