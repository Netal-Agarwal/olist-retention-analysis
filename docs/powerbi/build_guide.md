# Power BI build guide (Phase 7)

> Click-by-click, for Power BI Desktop on Windows. It builds a 4-page dashboard on the `report.*` views from `sql/11_report_views.sql`. Measures and their expected values are in `docs/powerbi/dax_measures.md`; keep that file open next to Power BI.
> **Rule for the whole build:** the dashboard shows only claims that `docs/claims_evidence.md` marks *supported* or *supported as an estimate*, and every number must match the checklist at the end of each page section. If a number does not match, fix the model before formatting anything.

Before you start, make sure the views exist and are correct:
```
.venv\Scripts\python -m src.create_views
.venv\Scripts\python -m src.run_quality_checks
```
Expect "114 of 114 checks passed".

---

## 1. Connect to PostgreSQL

1. Open Power BI Desktop → **Blank report**.
2. **Home → Get data → More…** → search "PostgreSQL" → **PostgreSQL database** → **Connect**.
3. **Server:** `localhost` (add `:5432` only if your server uses another port, e.g. `localhost:5433`). **Database:** `olist`. **Data Connectivity mode:** **Import**. Click **OK**.
   - *Import* copies the data into the .pbix file, so visuals are fast and work offline. *DirectQuery* would send a SQL query to PostgreSQL for every visual, every time. Our views are heavy (window functions), so that would be slow, and the data never changes.
4. The credentials dialog opens: choose the **Database** tab on the left (not Windows). Enter the PostgreSQL user name and password you use in `.env`, and leave "Select which level to apply these settings to" as `localhost;olist`. Click **Connect**.
5. **Common error: encryption / SSL.** A local PostgreSQL usually has no SSL certificate, and Power BI tries an encrypted connection first. You will see either:
   - a dialog "*Encryption Support — We were unable to connect to the data source using an encrypted connection…*" → click **OK** to connect without encryption; or
   - an error such as "*The remote certificate is invalid*" or "*SSL is not supported by the server*". Fix: **File → Options and settings → Data source settings** → select `localhost;olist` → **Edit Permissions…** → untick **Encrypt connections** → **OK** → **Close**, then repeat step 2.
   Turning off encryption is fine here only because the server is on your own machine (localhost). Never do this for a remote server.

## 2. Load the views

1. In the **Navigator**, expand `olist` → `report`. Tick these 15 views:
   `fact_orders`, `dim_customer`, `dim_date`, `dim_category`, `dim_seller`, `dim_state`, `agg_cohort_retention`, `agg_time_to_second`, `agg_repeat_by_review`, `agg_repeat_by_category`, `agg_bad_review_by_delay`, `agg_excess_bad_reviews_state`, `agg_excess_bad_reviews_seller`, `agg_excess_bad_reviews_route`, `agg_campaign_baseline`.
   Do not load anything from `clean` or `analysis`.
2. Click **Transform Data** (not Load). Power Query opens. For each query, rename it to drop the `report ` prefix: right-click the query → **Rename** → e.g. `fact_orders`.
3. Check the data types (icon left of each column header):
   - `fact_orders[purchase_date]`, `dim_date[date]`, `dim_date[month_start]`, `dim_customer[cohort_month]`, `agg_cohort_retention[cohort_month]`: **Date** (not Date/Time).
   - True/False columns (`is_late`, `has_review`, `is_bad_review`, `same_state`, `is_first_order`, `in_window_cohort`, `eligible_180d`, `is_repeat_180d`, `is_repeat_lifetime`, `first_is_late`, `in_analysis_window`): **True/False**. Empty cells must stay empty (`null`). Do **not** use "Replace values" on them: blank means "unknown", not false.
   - Money and rate columns: **Decimal number**.
4. Add the claims table: **Home → New Source → Text/CSV** → `outputs\powerbi\claims_verdicts.csv` → **OK**. Rename it `claims_verdicts`.
5. **Home → Close & Apply.** Wait for the load. `fact_orders` and `dim_customer` take the longest.
6. Check the row counts: **Table view** (left bar, grid icon), select a table, and the count is at the bottom left. Expected: fact_orders 96,211; dim_customer 93,358; dim_date 608; dim_category 74; dim_seller 3,095; dim_state 27; agg_cohort_retention 260; agg_time_to_second 5; agg_repeat_by_review 6; agg_repeat_by_category 24; agg_bad_review_by_delay 5; agg_excess_bad_reviews_state 17; _seller 20; _route 15; agg_campaign_baseline 1; claims_verdicts 12.

## 3. Model: relationships, date table, sorting, hiding

### 3a. Relationships
Open **Model view** (left bar, third icon). Power BI may have guessed some relationships: open **Home → Manage relationships**, delete any that are not in the table below, then create the missing ones with **New…**.

| From (many side) | To (one side) | Cardinality | Cross-filter direction | Active |
|---|---|---|---|---|
| `fact_orders[customer_unique_id]` | `dim_customer[customer_unique_id]` | Many to one (*:1) | Single | Yes |
| `fact_orders[purchase_date]` | `dim_date[date]` | Many to one | Single | Yes |
| `fact_orders[main_category]` | `dim_category[main_category]` | Many to one | Single | Yes |
| `fact_orders[main_seller_id]` | `dim_seller[seller_id]` | Many to one | Single | Yes |
| `fact_orders[customer_state]` | `dim_state[state_code]` | Many to one | Single | Yes |

All `agg_*` tables, `claims_verdicts` and the What-if table stay **unconnected**. They are finished result tables, and connecting them would let slicers filter them into numbers that match no output.

*Why single direction?* Filters flow from the dimension (one) to the fact (many): picking a segment in `dim_customer` filters its orders. The reverse (a date slicer filtering customers) would silently change customer counts. Bi-directional filters also make results harder to explain and can create ambiguous paths.

### 3b. Mark the date table
Select `dim_date` in the Fields pane → **Table tools → Mark as date table** → date column **date** → **OK**. Power BI checks that `date` is unique and has no gaps (the quality checks already prove both).

### 3c. Sort by column
Text labels sort alphabetically unless you tell Power BI otherwise. For each pair, go to **Table view**, select the label column, then **Column tools → Sort by column** → the sort column:

| Table | Label column | Sort by |
|---|---|---|
| fact_orders | delay_bucket | delay_bucket_sort |
| fact_orders | delivery_speed_bucket | delivery_speed_bucket_sort |
| dim_customer | first_review_label | first_review_sort |
| dim_date | month_name | month_number |
| dim_date | weekday | weekday_number |
| agg_time_to_second | label | sort_order |
| agg_repeat_by_review | review_label | sort_order |
| agg_bad_review_by_delay | delay_bucket | delay_bucket_sort |

### 3d. Hide technical columns
In the Fields pane, right-click → **Hide in report view** for: all `*_sort` / `sort_order` / `weekday_number` columns; `fact_orders[customer_unique_id]`, `[purchase_date]`, `[main_category]`, `[main_seller_id]`, `[customer_state]` (use the dimension columns instead, so filters always come from the "one" side); `dim_customer[customer_unique_id]`; every `assumptions` and `label` column in the `agg_*` tables; `agg_excess_bad_reviews_seller[main_seller_id]` (use `seller_label`).
Also set **Summarize by → Don't summarize** (Column tools) on ID-like number columns: `r_score`, `m_score`, `month_number`, `excess_rank`, `first_review_score`, `review_score`, `year`.

## 4. Measures table, measures, What-if, theme

1. **Home → Enter data** → leave the single empty column, name the table `_Measures` → **Load**.
2. Select `_Measures` → **Home → New measure**, paste one measure from `dax_measures.md`, press Enter, then set the format in **Measure tools** (Format, decimals). Repeat for measures 1-22. When the table has its first measure, delete the empty `Column1` (right-click → Delete). The table then shows a calculator icon and sorts to the top.
3. Group them: Model view → select measures → Properties pane → **Display folder**: `A Orders`, `B Reviews`, `C Customers`, `D Campaign`.
4. **What-if parameter:** **Modeling → New parameter → Numeric range**. Name `Campaign Conversion Rate`, Decimal number, Minimum `0.01`, Maximum `0.1`, Increment `0.005`, Default `0.02`, tick "Add slicer to this page" (do this while on page 4). Format the generated column and the `Campaign Conversion Rate Value` measure as Percentage, 1 decimal. Then add measures 20-22.
5. **Test every measure** before building pages: put each on a card on a scratch page and compare it with the "Expected" column. Delete the scratch page afterwards.
6. **Theme:** **View → Themes → Browse for themes** → `docs\powerbi\olist_theme.json`. Colours: slate blue `#4C6A85` = default/neutral; vermillion `#D55E00` = **only** for late or bad outcomes; greys for context. The pair stays distinguishable for the common colour-vision deficiencies (Okabe-Ito palette).

## 5. Page specs

General formatting: page size 16:9 (**Format page → Canvas settings**). Title text box at the top left (20 pt); a one-line subtitle stating population and window ("Delivered orders, Jan 2017 – Aug 2018"). Put a small grey footnote text box at the bottom of each page: "Source: Olist public dataset; definitions in docs/metrics.md. ESTIMATE = based on stated assumptions, association not proven cause."
Rename pages by double-clicking the tab.

### Page 1: Executive overview
**Title:** "Olist: almost nobody comes back, and late deliveries drive bad reviews"

| # | Visual | Fields | Filters | Title text | Formatting |
|---|---|---|---|---|---|
| 1 | Card | `One-time Customer %` | – | "Customers who never returned on a later day" | Largest card, top left; callout 28 pt |
| 2 | Card | `180-day Repeat Rate` | – | "Repeat within 180 days" | subtitle "of 56,188 customers with 180 days of follow-up" |
| 3 | Card | `Cohort Customers` | – | "New customers in window" | |
| 4 | Card | `Total Orders` | – | "Delivered orders" | |
| 5 | Card | `Product Revenue` | – | "Product revenue (excl. freight)" | display units: Millions, 2 decimals |
| 6 | Card | `Late Rate` | – | "Orders delivered late" | |
| 7 | Clustered column chart | Y: `Bad Review Rate On Time`, `Bad Review Rate Late` | – | "Bad reviews (1–2★): on time vs late" | data labels on; on-time column slate, late column vermillion (Format → Columns → per series) |
| 8 | Card | `Excess Bad Reviews` | – | "Excess bad reviews linked to lateness (ESTIMATE)" | 1 decimal |
| 9 | Card | `Excess Share of Bad Reviews` | – | "Share of all bad reviews (ESTIMATE)" | |
| 10 | Line and clustered column chart | X: `dim_date[year_month]`; Column y: `Total Orders`; Line y: `Product Revenue` | – | "Delivered orders and product revenue by month" | X axis type Categorical, sorted by year_month ascending (… → Sort axis → year_month, ascending) |
| 11 | Text box | – | – | "Two levers" | Two short bullets: **Lever 1, re-engage:** retention is structural; first-order factors explain about 1% of who returns (pseudo R² 0.011), so target "Promising high-value one-timers". **Lever 2, deliver on time:** late orders get bad reviews 62.42% of the time vs 9.25% on time. |

**Checklist, page 1**
- [ ] One-time 97.85% · 180-day repeat 1.98% · cohort customers 93,094
- [ ] Orders 96,211 · revenue R$13,181,027.13 (R$13.18M) · late rate 6.79%
- [ ] Bad-review rate on time 9.25% · late 62.42%
- [ ] Excess bad reviews 3,391.2 · share 27.73%
- [ ] Monthly chart: 2017-01 = 750 orders / R$111,798.36; 2017-11 (peak) = 7,289 / R$987,765.37; 2018-08 = 6,351 / R$838,576.64 (`q05_06`)

### Page 2: Retention
**Title:** "Retention is structural: about 2% return, whatever the first experience"

| # | Visual | Fields | Filters | Title text | Formatting |
|---|---|---|---|---|---|
| 1 | Matrix (cohort heatmap) | Rows: `agg_cohort_retention[cohort_label]`; Columns: `[month_number]`; Values: `[retention_pct]` (Sum; each cell has exactly one row) | – | "Monthly cohort retention: % of each cohort buying again in month k" | Format → Cell elements → **Background color** on → **fx** → Format style *Gradient*, based on Sum of retention_pct, Minimum lowest value `#F2F5F8`, Maximum highest value `#2F4558`; "How should we format empty values": **Don't format**. Turn row/column subtotals **off**. Values 2 decimals. Censored cells stay blank: that is correct, not missing data. Add a subtitle: "Blank = not yet observable (data ends Aug 2018). Month 0 = returned later in the same month." |
| 2 | Clustered column chart | X: `agg_time_to_second[label]`; Y: `[customers]` | – | "Time to second purchase (lifetime repeaters)" | data labels; subtitle "Right-censored: recent customers can only show short gaps" |
| 3 | Card | `agg_time_to_second[median_days]` (Max) | – | "Median days to 2nd purchase" | |
| 4 | Clustered column chart + error bars | X: `agg_repeat_by_review[review_label]`; Y: `[repeat_rate_180d_pct]` (Sum) | – | "180-day repeat by first review score: even 5★ customers rarely return" | **Analytics pane → Error bars** → on; Upper bound `ci_high_pct` (Max), Lower bound `ci_low_pct` (Max), Relationship *Absolute*; Bar style on. **Constant line** (Analytics → Y-axis constant line) at 1.98, label "all customers 1.98%". Tooltip: `eligible_customers` |
| 5 | Clustered bar chart + error bars | Y: `agg_repeat_by_category[main_category]`; X: `[repeat_rate_180d_pct]` | – | "180-day repeat by first-order category (≥ 300 customers)" | sort descending by rate; error bars from `ci_low_pct` / `ci_high_pct`; subtitle "Small effect; compare only bars whose intervals do not overlap" |
| 6 | Table | `dim_customer[segment]`, `Cohort Customers`, Sum of `dim_customer[total_product_value]` | visual filter: segment *is not blank* | "RFM segments (in-window cohort)" | conditional formatting: bold the row "Promising high-value one-timers"; revenue as currency |
| 7 | Text box | – | – | "Why 'structural'?" | "First-order factors (lateness, delivery time, freight share, value, category, state, review) explain about 1% of who returns: McFadden pseudo R² 0.011. Better delivery alone will not create loyalty; Olist needs active re-engagement." |

**Checklist, page 2**
- [ ] Heatmap: 20 rows × 13 columns; 78 blank cells (bottom-right triangle); 2017-01 month 0 = 0.28, 2017-11 month 1 = 0.57 (`q05_03`)
- [ ] Time to second: 598 / 507 / 423 / 398 / 78 customers; median 74 days (`q05_02`)
- [ ] Repeat by review: 1★ 1.71, 2★ 1.51, 3★ 1.94, 4★ 1.83, 5★ 2.12 (CI 1.97–2.28), No review 1.20 (`q07_08`, claim 6)
- [ ] Category: top fashion_bags_accessories 3.30 (CI 2.41–4.50), bottom musical_instruments 0.92; 24 bars (`q05_05`, claim 11)
- [ ] Segments: total 93,094; Promising high-value one-timers 14,533 / R$3,885,522.64; Champions 831; Loyal repeaters 1,173 (`q06_01`)

### Page 3: Delivery & reviews
**Title:** "Late delivery is a reputation problem: 62% of late orders get a bad review"

| # | Visual | Fields | Filters | Title text | Formatting |
|---|---|---|---|---|---|
| 1 | Clustered column chart + error bars | X: `agg_bad_review_by_delay[delay_bucket]`; Y: `[bad_review_rate_pct]` | – | "Bad-review rate (1–2★) by days late" | error bars from `ci_low_pct` / `ci_high_pct`; **Columns → fx → Rules** on `is_late`: True → `#D55E00`, False → `#4C6A85` (or set each column's colour by hand); data labels 1 decimal; tooltip `reviewed_orders`, `bad_reviews` |
| 2 | Clustered column chart | Y: `Bad Review Rate On Time`, `Bad Review Rate Late` | – | "On time vs late" | same colours as page 1 |
| 3 | Line chart | X: `dim_date[year_month]`; Y: `Late Rate` | – | "Late delivery rate by month" | line colour vermillion; markers on |
| 4 | Clustered column chart | X: `fact_orders[same_state]`; Y: `Late Rate` | – | "Late rate: same-state vs cross-state shipping" | rename axis labels in a text subtitle: "True = seller and customer in the same state"; subtitle "Same state is a rough proxy for distance" |
| 5 | Card ×2 | `Late Orders`; `Orders With Delivery Date` | – | "Late orders" / "Orders with a delivery date" | small, top right |

**Checklist, page 3**
- [ ] By delay bucket: early/on time 9.25 · 1-3 days late 32.14 · 4-7 67.68 · 8-14 80.15 · 15+ 78.32; reviewed orders 89,182 / 1,851 / 1,748 / 1,446 / 1,333 (`q07_06`)
- [ ] On time 9.25% vs late 62.42% (`q10_01`)
- [ ] Late rate 2017-01 = 2.93%, 2017-02 = 2.96%, 2017-03 = 4.56% (`q07_04`)
- [ ] Same state 4.51% · cross-state 8.07% (`q07_03`, claim 8)
- [ ] Late orders 6,531 of 96,203 (`q07_01`)

### Page 4: Where to act
**Title:** "Where to act: fix delivery on the SP→RJ corridor, re-engage high-value one-timers"

| # | Visual | Fields | Filters | Title text | Formatting |
|---|---|---|---|---|---|
| 1 | Clustered bar chart | Y: `agg_excess_bad_reviews_state[state_name]`; X: `[excess_bad_reviews]` | – | "Excess bad reviews by customer state (ESTIMATE)" | sort descending; bars vermillion; tooltip `share_of_national_excess_pct`, `late_reviewed_orders`; subtitle "States with ≥ 500 reviewed orders; each vs its own on-time rate" |
| 2 | Clustered bar chart | Y: `agg_excess_bad_reviews_route[route]`; X: `[excess_bad_reviews]` | – | "Top 15 seller→customer routes (ESTIMATE)" | sort descending; tooltip `share_of_national_excess_pct`, `is_same_state` |
| 3 | Table | `agg_excess_bad_reviews_seller[excess_rank]`, `[seller_label]`, `[seller_state]`, `[late_reviewed_pct]`, `[excess_bad_reviews]`, `[cumulative_share_of_national_excess_pct]` | – | "Top 20 sellers by excess bad reviews (ESTIMATE)" | sort by excess_rank ascending; data bars on excess_bad_reviews; subtitle "Partly supported: concentration is real but moderate" |
| 4 | Slicer | `Campaign Conversion Rate[Campaign Conversion Rate]` | – | "Assumed campaign conversion rate" | created by the What-if dialog; style *Single value* slider |
| 5 | Card ×3 | `Campaign Segment Customers`; `Campaign Extra Repeaters`; `Campaign Extra Revenue` | – | "Promising high-value one-timers" / "Extra repeat customers (ESTIMATE)" / "Extra product revenue (ESTIMATE)" | text box under them: "Conversion rate is an assumption. One second visit at the median R$89.90. Product revenue, not margin; campaign cost not included." |
| 6 | Table | `claims_verdicts[claim]`, `[verdict]`, `[key_number]`, `[caveat]` | – | "What the evidence supports" | sort by claim_id (add it then hide via width 0, or sort in the column header); conditional formatting on `verdict` (font colour: Supported → slate, Partly → grey, Not supported → vermillion); word wrap on |

The claims table lists all 12 verdicts, including "Not supported" for state differences in repeat rate. That row tells the reader the finding was *tested and rejected*; no visual on any page ranks states by repeat rate.

**Checklist, page 4**
- [ ] State: RJ 905.4 (26.70%), SP 815.0 (24.03%), MG 250.1; 17 bars (`q10_02`)
- [ ] Routes: SP→RJ 714.2 (21.06%), SP→SP 616.4 (18.18%), SP→MG 190.1; 15 bars (`q10_04`)
- [ ] Sellers: rank 1 = 85.7 (2.53%); cumulative share at rank 20 = 24.78% (`q10_03`)
- [ ] Campaign at 2%: 14,533 → 290.7 repeaters → R$26,130.33; at 1%: 145.3 / R$13,065.17; at 5%: 726.7 / R$65,325.84 (`q09_05`)
- [ ] Claims table: 12 rows

## 6. Save and export

1. Create the folder `dashboard\` in the repo if it does not exist.
2. **File → Save as** → `D:\Projects\olist-retention-analysis\dashboard\olist_retention.pbix`.
3. **PDF:** **File → Export → Export to PDF** → save as `dashboard\olist_retention.pdf` (one page per report page).
4. **PNG screenshots:** for each page, open it, press **Win + Shift + S**, drag over the canvas, click the notification, then **Save** (Ctrl+S) as `dashboard\page1_executive_overview.png`, `page2_retention.png`, `page3_delivery_reviews.png`, `page4_where_to_act.png`.
5. The .pbix contains a copy of the data (Import mode) but **no password**: credentials are stored in your Windows profile, not in the file. Still, check `git status` before committing and do not commit anything from `.env`.
