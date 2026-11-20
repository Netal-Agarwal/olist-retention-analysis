# Data dictionary: raw Olist CSVs

Source: Olist Brazilian E-Commerce public dataset (Kaggle), 9 CSVs in `data/raw/` (never modified).
Row counts, types and issue counts come from `notebooks/01_data_profiling.ipynb` (pandas 3.1.1). Types are
shown as pandas loads them there: `str` = text, `datetime` = timestamp, `int`/`float` = number.

Profiling findings are summarised under "Known issues" for each table. Cleaning rules for them are decided in Phase 2 Step B.

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
