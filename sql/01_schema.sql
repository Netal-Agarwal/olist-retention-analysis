-- =============================================================================
-- 01_schema.sql
-- Purpose : create the `clean` schema and its 8 tables for the cleaned Olist
--           data (the CSVs in data/processed/, built by notebooks/02_cleaning.ipynb).
-- Business question: none directly. This gives every later SQL analysis a
--           trusted, typed and key-checked copy of the data, so questions like
--           "why do customers buy only once?" are answered on correct data.
-- Tables  : clean.customers, clean.sellers, clean.products, clean.geolocation,
--           clean.orders, clean.order_items, clean.order_payments, clean.order_reviews
--
-- Re-runnable: it drops and recreates ONLY tables inside the `clean` schema.
-- It never drops the `public` schema, any other schema, or any database.
-- Run it in the `olist` database only (src/load_to_postgres.py runs it for you).
-- =============================================================================

-- A schema is a named folder inside the database. Keeping the cleaned tables
-- in `clean` separates them from anything in `public` and from later reporting
-- views.
create schema if not exists clean;

-- -----------------------------------------------------------------------------
-- Drop old copies, children first.
-- A child table (e.g. order_items) points at its parents (orders, products,
-- sellers) through foreign keys, so a parent cannot be dropped while a child
-- still points at it. Reverse dependency order avoids that.
-- No CASCADE on purpose: if something unexpected depends on a table (a view,
-- say), the drop fails loudly instead of silently deleting that object too.
-- -----------------------------------------------------------------------------
drop table if exists clean.order_reviews;
drop table if exists clean.order_payments;
drop table if exists clean.order_items;
drop table if exists clean.orders;
drop table if exists clean.geolocation;
drop table if exists clean.products;
drop table if exists clean.sellers;
drop table if exists clean.customers;

-- -----------------------------------------------------------------------------
-- Type choices used throughout
--   text             IDs, zip prefixes, cities, states, categories, statuses.
--                    Zip prefixes are text so '09790' keeps its leading zero.
--   timestamp        every date/time column (no time zone in the source data).
--                    Date-only values such as '2017-10-18' load as midnight.
--   numeric(10,2)    money: exact decimals, so 0.10 + 0.20 is exactly 0.30.
--   integer          true whole numbers (counters, scores, grams, cm).
--   double precision latitude/longitude only (measurements, not money).
--   boolean          every is_ / in_ / flag_ column ('True'/'False' in the CSVs).
-- -----------------------------------------------------------------------------

-- One row per customer_id. Olist creates a new customer_id for every order;
-- the real person is customer_unique_id (not unique here, by design).
create table clean.customers (
    customer_id                 text    not null,
    customer_unique_id          text    not null,
    customer_zip_code_prefix    text    not null,
    customer_city               text    not null,
    customer_state              text    not null,
    flag_zip_not_in_geolocation boolean not null,
    constraint customers_pkey primary key (customer_id),
    -- A zip prefix is exactly 5 digits (profiling: every value has length 5).
    constraint customers_zip_5_digits check (customer_zip_code_prefix ~ '^[0-9]{5}$')
);

-- One row per seller.
create table clean.sellers (
    seller_id                   text    not null,
    seller_zip_code_prefix      text    not null,
    seller_city                 text    not null,
    seller_state                text    not null,
    flag_zip_not_in_geolocation boolean not null,
    constraint sellers_pkey primary key (seller_id),
    constraint sellers_zip_5_digits check (seller_zip_code_prefix ~ '^[0-9]{5}$')
);

-- NOTE on geolocation and foreign keys:
-- There is deliberately NO foreign key from customers or sellers to geolocation.
-- A foreign key would reject any customer or seller whose zip prefix is missing
-- from geolocation, and 279 customers and 7 sellers have no matching prefix
-- (flag_zip_not_in_geolocation). Those are real customers and sellers, so we
-- keep them; geolocation is an optional lookup ("where is this zip?"), not a
-- parent that every row must have. Analyses use a LEFT JOIN to it.

-- One row per product. The 7 size/text attributes are whole numbers; pandas
-- wrote them as '40.0' because they contain blanks. The loader turns '40.0'
-- into '40' (and fails on anything like '40.5'), so integer is the right type.
create table clean.products (
    product_id                 text    not null,
    category_name_english      text    not null,  -- 'unknown' when the raw category was empty
    product_name_length        integer,           -- blank for 610 products
    product_description_length integer,           -- blank for 610 products
    product_photos_qty         integer,           -- blank for 610 products
    product_weight_g           integer,           -- blank for 2 products
    product_length_cm          integer,
    product_height_cm          integer,
    product_width_cm           integer,
    flag_missing_category      boolean not null,
    flag_zero_weight           boolean not null,
    flag_missing_dimensions    boolean not null,
    constraint products_pkey primary key (product_id)
);

-- One row per zip prefix (Phase 2 reduced ~1M coordinate points to 19,010 prefixes).
create table clean.geolocation (
    geolocation_zip_code_prefix text             not null,
    geolocation_lat             double precision not null,  -- median latitude of the cleaned points
    geolocation_lng             double precision not null,  -- median longitude
    geolocation_city            text             not null,  -- most common city for the prefix
    geolocation_state           text             not null,
    n_points                    integer          not null,  -- points the median was taken from
    constraint geolocation_pkey primary key (geolocation_zip_code_prefix),
    constraint geolocation_zip_5_digits check (geolocation_zip_code_prefix ~ '^[0-9]{5}$')
);

-- One row per order. Dates that Phase 2 left empty stay NULL (never guessed).
create table clean.orders (
    order_id                             text      not null,
    customer_id                          text      not null,
    order_status                         text      not null,
    order_purchase_timestamp             timestamp not null,
    order_approved_at                    timestamp,  -- blank for 160 orders
    order_delivered_carrier_date         timestamp,  -- blank for 1,783 orders
    order_delivered_customer_date        timestamp,  -- blank for 2,965 orders
    order_estimated_delivery_date        timestamp not null,  -- date only in the source, stored as midnight
    is_delivered                         boolean   not null,
    in_analysis_window                   boolean   not null,
    flag_delivered_missing_customer_date boolean   not null,
    flag_carrier_before_approval         boolean   not null,
    flag_carrier_before_purchase         boolean   not null,
    flag_delivery_before_carrier         boolean   not null,
    flag_cancelled_with_delivery_date    boolean   not null,
    flag_no_items                        boolean   not null,
    flag_no_payment                      boolean   not null,
    flag_payment_mismatch                boolean   not null,
    constraint orders_pkey primary key (order_id),
    -- Every order must belong to a customer that exists.
    constraint orders_customer_fkey foreign key (customer_id)
        references clean.customers (customer_id)
);

-- One row per item in an order. Freight is per item, so sum it per order
-- before joining to other order-level tables.
create table clean.order_items (
    order_id               text          not null,
    order_item_id          integer       not null,  -- 1, 2, 3 ... inside the order
    product_id             text          not null,
    seller_id              text          not null,
    shipping_limit_date    timestamp     not null,
    price                  numeric(10,2) not null,
    freight_value          numeric(10,2) not null,
    flag_price_above_p99   boolean       not null,
    flag_freight_above_p99 boolean       not null,
    flag_zero_freight      boolean       not null,
    -- The pair (order, item number) identifies one item line.
    constraint order_items_pkey primary key (order_id, order_item_id),
    constraint order_items_order_fkey   foreign key (order_id)   references clean.orders (order_id),
    constraint order_items_product_fkey foreign key (product_id) references clean.products (product_id),
    constraint order_items_seller_fkey  foreign key (seller_id)  references clean.sellers (seller_id),
    constraint order_items_price_not_negative   check (price >= 0),
    constraint order_items_freight_not_negative check (freight_value >= 0)
);

-- One row per payment method used in an order (an order can have several).
create table clean.order_payments (
    order_id                      text          not null,
    payment_sequential            integer       not null,
    payment_type                  text          not null,
    payment_installments          integer       not null,  -- 0 in 2 rows (kept as in the source)
    payment_value                 numeric(10,2) not null,
    flag_zero_value               boolean       not null,
    flag_payment_type_not_defined boolean       not null,
    constraint order_payments_pkey primary key (order_id, payment_sequential),
    constraint order_payments_order_fkey foreign key (order_id) references clean.orders (order_id),
    constraint order_payments_value_not_negative        check (payment_value >= 0),
    constraint order_payments_installments_not_negative check (payment_installments >= 0)
);

-- One review per order (Phase 2 kept the latest answered one).
-- review_id is NOT unique: 578 rows share a review_id with another order on
-- purpose, so the primary key is order_id.
create table clean.order_reviews (
    review_id               text      not null,
    order_id                text      not null,
    review_score            integer   not null,
    review_comment_title    text,      -- optional, mostly blank
    review_comment_message  text,      -- optional, mostly blank
    review_creation_date    timestamp not null,
    review_answer_timestamp timestamp not null,
    n_raw_reviews           integer   not null,  -- how many raw review rows the order had
    flag_multiple_reviews   boolean   not null,
    constraint order_reviews_pkey primary key (order_id),
    constraint order_reviews_order_fkey foreign key (order_id) references clean.orders (order_id),
    constraint order_reviews_score_1_to_5 check (review_score between 1 and 5)
);
