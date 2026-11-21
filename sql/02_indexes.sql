-- =============================================================================
-- 02_indexes.sql
-- Purpose : add indexes on the columns later analyses join and filter on most.
-- Business question: none directly; makes the Phase 4 retention, delivery and
--           review queries fast.
-- Tables  : clean.orders, clean.customers, clean.order_items, clean.sellers
--
-- Run after 01_schema.sql (src/load_to_postgres.py runs both in one transaction).
-- 01_schema.sql recreates the tables, which also removes old indexes, so plain
-- CREATE INDEX is safe on every run.
--
-- What an index is: a sorted lookup structure (a B-tree) next to the table,
-- like the index at the back of a book. Instead of reading every row to find
-- "orders of customer X", Postgres jumps straight to the matching rows.
-- What it costs: disk space, and every INSERT/UPDATE/COPY must also update the
-- index, so writes get slower. That is why we index only columns we really use.
--
-- Already indexed by primary keys (Postgres builds a unique index for each PK):
--   customers(customer_id), sellers(seller_id), products(product_id),
--   geolocation(geolocation_zip_code_prefix), orders(order_id),
--   order_items(order_id, order_item_id), order_payments(order_id, payment_sequential),
--   order_reviews(order_id).
-- A multi-column index also serves lookups on its FIRST column alone, so
-- order_items.order_id and order_payments.order_id need no extra index.
-- =============================================================================

-- Join orders -> customers (orders.customer_id = customers.customer_id) starting
-- from the orders side, e.g. "all orders of these customers".
create index orders_customer_id_idx on clean.orders (customer_id);

-- Every customer-level metric groups or joins by the real person
-- (customer_unique_id): repeat rate, first order, cohorts.
create index customers_customer_unique_id_idx on clean.customers (customer_unique_id);

-- Filtering by date range (analysis window, cohort months, 180-day follow-up)
-- and sorting orders by purchase time to find each customer's first order.
create index orders_purchase_timestamp_idx on clean.orders (order_purchase_timestamp);

-- Join items -> products (category analysis).
create index order_items_product_id_idx on clean.order_items (product_id);

-- Join items -> sellers (seller performance, seller location).
create index order_items_seller_id_idx on clean.order_items (seller_id);

-- Join customers -> geolocation by zip prefix (customer region / distance).
create index customers_zip_code_prefix_idx on clean.customers (customer_zip_code_prefix);

-- Join sellers -> geolocation by zip prefix (seller region / distance).
create index sellers_zip_code_prefix_idx on clean.sellers (seller_zip_code_prefix);
