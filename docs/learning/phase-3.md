# Phase 3: Database schema, load and quality checks (PostgreSQL)

Files:
- `sql/01_schema.sql` creates the schema `clean` and its 8 tables, with types, keys and checks.
- `sql/02_indexes.sql` adds indexes on the main join and filter columns.
- `src/load_to_postgres.py` runs both SQL files, then bulk-loads the 8 CSVs from `data/processed/` with COPY, all in one transaction.
- `sql/03_quality_checks.sql` + `src/run_quality_checks.py` run 44 checks and save `outputs/phase3_quality_checks.csv`.

All numbers below come from the loader output, `outputs/phase3_quality_checks.csv` (44 of 44 passed) and the Phase 2 outputs.

---

## 1. Schemas
A **schema** is a named folder inside one database. Tables are addressed as `schema.table`, e.g. `clean.orders`.
- `public` is the default schema every database has. We leave it alone.
- `clean` holds the cleaned data. Later phases can add other schemas (for example reporting views) without mixing them up.
- `create schema if not exists clean;` does nothing if the schema already exists, so the script can be run again.

The re-run safety rule: `01_schema.sql` only ever runs `drop table if exists clean.<table>`. It never drops a schema or a database. It also uses no `CASCADE`, so if something unexpected depends on a table, the drop fails loudly instead of quietly deleting that object too.

## 2. CREATE TABLE and data types
```sql
create table clean.order_items (
    order_id      text          not null,
    order_item_id integer       not null,
    price         numeric(10,2) not null,
    ...
);
```
Each column gets a type, and the database refuses values that don't fit. That's the point: wrong data fails at load time instead of producing a wrong number months later.

| Type | Used for | Why |
|---|---|---|
| `text` | IDs, zip prefixes, cities, categories, statuses | IDs aren't numbers you do maths on. Zip prefixes must keep their leading zero (`09790`); stored as an integer it would become `9790` and stop matching. |
| `timestamp` | every date/time column | Lets you compare and subtract dates. Date-only values (`order_estimated_delivery_date`) are stored as midnight. |
| `numeric(10,2)` | price, freight, payment | Exact decimal money (up to 8 digits before the point, 2 after). |
| `integer` | counters, scores, grams, cm | True whole numbers. |
| `double precision` | latitude / longitude | Measurements, where tiny rounding doesn't matter. |
| `boolean` | `is_`, `in_`, `flag_` columns | True/False. The CSV's `True`/`False` load directly. |

`not null` means "this column must always have a value". Columns that Phase 2 deliberately left empty (missing delivery dates, review comments, product sizes) are allowed to be NULL.

**Why numeric beats float for money.** `float`/`double precision` stores numbers in binary, and most decimal amounts (like 0.10) have no exact binary form. They're stored as a very close approximation, so `0.1 + 0.2` gives `0.30000000000000004`. Over 112,650 item rows these tiny errors add up, and a sum like "total revenue = 13,591,643.70" might not come out exactly. `numeric` stores decimal digits exactly, so sums of money are exact. Our spot check confirmed the database sum of `price` (13,591,643.70) and of `payment_value` (16,008,872.12) equal the pandas sums of the CSVs.

**CHECK constraints** add simple rules on top of types: zip prefixes must be exactly 5 digits (`~ '^[0-9]{5}$'`), `review_score between 1 and 5`, price/freight/payment `>= 0`.

**The "500.0" problem.** In `products`, 7 whole-number columns (e.g. `product_weight_g`) were written by pandas as `225.0`, because a pandas integer column with blanks becomes a float column. Postgres refuses `'225.0'` for an `integer` column. The loader converts these values in memory: a value must be blank (becomes NULL) or look exactly like `<digits>.0`, which becomes `<digits>`. Anything else, such as `225.5`, stops the load. No value can be silently rounded. The CSV on disk is not changed. The spot check confirmed the result: 610 NULL name lengths and 2 NULL weights (same as the CSV blanks) and the same total weight (75,007,492 g) in the CSV and the database.

## 3. Primary keys vs foreign keys
- A **primary key** (PK) says "these columns identify exactly one row". The database refuses duplicates and NULLs there.
  - Single column: `orders(order_id)`, `customers(customer_id)`, `products(product_id)`, `sellers(seller_id)`, `geolocation(geolocation_zip_code_prefix)`.
  - Composite (two columns together): `order_items(order_id, order_item_id)` and `order_payments(order_id, payment_sequential)`. One order has many items, but each (order, item number) pair is unique.
  - `order_reviews(order_id)`: Phase 2 reduced reviews to one per order. `review_id` can't be the key, because 578 rows share a `review_id` with another order on purpose.
- A **foreign key** (FK) says "this value must exist as a key in another table". `orders.customer_id → customers.customer_id` means no order can point at a customer that doesn't exist.
  - FKs here: orders → customers; order_items → orders, products, sellers; order_payments → orders; order_reviews → orders.
  - **No FK to geolocation.** 279 customers and 7 sellers have a zip prefix with no geolocation row. An FK would reject those real customers and sellers. Geolocation is an optional lookup, so analyses `LEFT JOIN` to it.

In one sentence: a PK protects a table from duplicates; an FK protects the links *between* tables.

## 4. Why load order matters
Because of foreign keys, a child row can only be inserted if its parent already exists. If `order_items` were loaded before `orders`, the very first item row would fail with "violates foreign key constraint". So the loader goes parents first:

customers, sellers, products, geolocation → orders → order_items, order_payments, order_reviews.

Dropping works the other way round (children first), which is why `01_schema.sql` drops `order_reviews` first and `customers` last.

The whole load runs in **one transaction**. Postgres can even roll back `create table` and `drop table`, so if anything fails, the database ends up exactly as it was before the run. There's never a half-loaded state.

## 5. COPY
```python
cur.copy_expert(
    "copy clean.orders (order_id, ...) from stdin "
    "with (format csv, header true, encoding 'UTF8')",
    file,
)
```
- `INSERT` row by row would send 112,650 separate statements for `order_items`, each parsed and planned on its own. `COPY` streams the whole file in one command, and the server parses it in bulk. That's much faster.
- `format csv` understands quoted text. 3,818 review messages contain line breaks inside quotes, and all 3,818 arrived intact.
- An unquoted empty cell becomes NULL, which is how pandas wrote blanks.
- `header true` skips the header line. Before each COPY, the loader compares that header with the table's columns from `information_schema.columns` and stops with a clear message if they differ. That catches a renamed or reordered column before it can load into the wrong place.

Rows loaded: customers 99,441 · sellers 3,095 · products 32,951 · geolocation 19,010 · orders 99,441 · order_items 112,650 · order_payments 103,886 · order_reviews 98,673. These match the Phase 2 processed counts.

## 6. Indexes
An index is a sorted lookup structure kept next to a table, like the index at the back of a book. Without one, finding "all orders of customer X" means reading every row (a *sequential scan*). With one, Postgres jumps to the matching rows.

- **Speeds up:** joins (`orders.customer_id`, `order_items.product_id`, `order_items.seller_id`, zip prefixes), grouping and lookups by person (`customers.customer_unique_id`), and date filters/sorts (`orders.order_purchase_timestamp` for the analysis window and first-order logic).
- **Costs:** disk space, and every insert/update/COPY must also update each index, so writes get slower. That's why only columns that are really used get one.
- **Free indexes:** every primary key automatically gets a unique index. A composite index also serves its *first* column, so `order_items(order_id, order_item_id)` already covers lookups by `order_items.order_id`.

## 7. LEFT JOIN ... IS NULL for orphans
An **orphan** is a child row whose parent is missing, e.g. an item whose `order_id` isn't in `orders`.
```sql
select count(*)
from clean.order_items oi
left join clean.orders o on o.order_id = oi.order_id
where o.order_id is null;
```
`LEFT JOIN` keeps every item row. Where no order matches, the order's columns come back NULL, so `where o.order_id is null` keeps exactly the unmatched rows. All 6 orphan checks returned 0. That's guaranteed here by the FKs, but the pattern is how you audit a database that has no FKs.
The same pattern found the 279 customers and 7 sellers whose zip prefix has no geolocation row, matching their `flag_zip_not_in_geolocation` counts.

## 8. GROUP BY / HAVING
`GROUP BY` puts rows into groups and computes one result per group. `WHERE` filters rows *before* grouping; `HAVING` filters groups *after* grouping.
```sql
select order_id
from clean.order_reviews
group by order_id
having count(*) > 1;   -- orders with more than one review
```
This returned no rows, which proves "one review per order". You can't write `where count(*) > 1`, because `WHERE` runs before the counts exist.

## 9. INNER vs LEFT JOIN
- `INNER JOIN` keeps only rows that match on both sides.
- `LEFT JOIN` keeps every row from the left table, with NULLs where the right side has no match.

Example: 99,441 orders, 98,673 reviews. `orders INNER JOIN order_reviews` gives 98,673 rows. `orders LEFT JOIN order_reviews` gives 99,441 rows, of which 768 have a NULL score (orders with no review, Phase 2 profiling). Choosing the wrong join silently changes what a metric covers. An average review score is fine with an inner join; "share of orders that got a review" needs a left join.

---

## 10. Try it yourself in pgAdmin
Open pgAdmin → your server → Databases → `olist` → right-click → **Query Tool**. Paste a query and press F5.

**1. How many orders are in each status?**
```sql
select order_status, count(*) as n_orders
from clean.orders
group by order_status
order by n_orders desc;
```
One row per status. `delivered` should be 96,478, and the others (shipped, canceled, unavailable, …) are the orders analysed separately.

**2. How many real customers placed more than one order?**
```sql
select count(*) as customers_with_2plus_orders
from (
    select c.customer_unique_id
    from clean.orders o
    join clean.customers c on c.customer_id = o.customer_id
    group by c.customer_unique_id
    having count(*) > 1
) as multi;
```
Joining orders to customers swaps the per-order `customer_id` for the real person. `HAVING` keeps people with 2+ orders (any status, same-day included). Compare it with the 96,096 distinct people: it's a small fraction, which is the project's whole question.

**3. Which 10 categories sell the most items?**
```sql
select p.category_name_english, count(*) as items_sold
from clean.order_items oi
join clean.products p on p.product_id = oi.product_id
group by p.category_name_english
order by items_sold desc
limit 10;
```
Each `order_items` row is one item, so `count(*)` counts items, not orders.

**4. What is the distribution of review scores?**
```sql
select review_score, count(*) as n_reviews,
       round(100.0 * count(*) / sum(count(*)) over (), 2) as pct
from clean.order_reviews
group by review_score
order by review_score;
```
Five rows (1 to 5) whose `pct` adds up to 100. `sum(count(*)) over ()` is the grand total, so each score's share can be calculated in the same query.

**5. How many orders have no review? (INNER vs LEFT JOIN)**
```sql
select count(*)             as orders_left_join,
       count(r.order_id)    as orders_with_review,
       count(*) - count(r.order_id) as orders_without_review
from clean.orders o
left join clean.order_reviews r on r.order_id = o.order_id;
```
Expect 99,441, 98,673 and 768. `count(column)` skips NULLs, so it counts only the orders that matched a review.

**6. What is the average delivery time in days for delivered orders, per year?**
```sql
select extract(year from order_purchase_timestamp) as purchase_year,
       count(*) as n_orders,
       round(avg(extract(epoch from order_delivered_customer_date - order_purchase_timestamp) / 86400)::numeric, 1) as avg_days
from clean.orders
where is_delivered
  and order_delivered_customer_date is not null
group by purchase_year
order by purchase_year;
```
Subtracting two timestamps gives an interval. `extract(epoch …)` turns it into seconds, and `/ 86400` turns that into days. The 8 delivered orders without a delivery date are excluded, as `docs/metrics.md` (metric 8) requires.

---

## 11. Interview questions (with answers from this project)

**Q1. Why did you load the cleaned data into PostgreSQL when you already had it in pandas?**
So the database enforces the rules permanently: types, primary keys, foreign keys and checks. Any later query, dashboard or colleague gets data that can't contain duplicate orders or items pointing at non-existent orders. SQL is also what the Phase 4 analysis and Power BI use.

**Q2. Why is the primary key of `order_reviews` `order_id` and not `review_id`?**
After Phase 2's one-review-per-order rule, `order_id` is unique (98,673 rows). `review_id` isn't: 578 rows share a `review_id` with another order. The raw data copied identical reviews onto different orders, and each link is valid. A key must be unique, so `order_id` it is.

**Q3. Why is there no foreign key from customers to geolocation?**
279 customers and 7 sellers have a zip prefix with no geolocation row. A foreign key would reject them, and they're real customers with real orders. Geolocation is an optional lookup, so I use a `LEFT JOIN` and the `flag_zip_not_in_geolocation` column tells you who has no coordinates.

**Q4. How did you handle integer columns that pandas wrote as `225.0`?**
They're whole numbers with some blanks, so pandas stored them as floats. I typed them `integer` and had the loader convert `225.0` to `225`, but only when the decimal part is exactly `.0`. Any other value stops the load, so nothing is rounded silently. The NULL counts (610 and 2) and the total weight match the CSV.

**Q5. How do you know the load is complete and correct?**
44 automated checks, all passed: 8 row counts, delivered orders (96,478), distinct real customers (96,096), one review per order, 6 orphan checks, the 279/7 geolocation gaps, all 21 flag counts, no negative money and no delivery before purchase. Every expected value is copied from a Phase 2 output and cited in the SQL. On top of that, a spot check compared sums of price and payments between the database and the CSVs.

**Q6. Why COPY instead of `to_sql` or INSERTs?**
COPY streams the file in one command and is far faster than one INSERT per row. More importantly, it loads into tables I defined myself (exact types, keys, constraints), whereas `pandas.to_sql` would create its own tables with guessed types, for example float for money and bigint for zip prefixes, which loses the leading zeros.

**Q7. What happens if the load fails halfway?**
Nothing is kept. The schema script, the indexes and all 8 COPYs run in one transaction, and Postgres rolls back DDL too. Either all 8 tables are fully loaded or the database is unchanged. I also re-ran the loader to prove it's re-runnable.

**Q8. Why use indexes, and why not index every column?**
Indexes make joins and filters fast, e.g. `customers.customer_unique_id` for every customer-level metric and `orders.order_purchase_timestamp` for the analysis window. Each index costs disk space and slows every write, so I indexed only columns the analysis actually joins or filters on. Primary keys are indexed automatically.
