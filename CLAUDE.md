# Olist Retention Analysis — rules for Claude Code

## Project
Data Analyst portfolio project. Business question: why do almost all Olist customers buy only once, and what should Olist fix first?
Stack: PostgreSQL 17 (local, database `olist`), Python 3.11 + pandas, Power BI Desktop. OS: Windows.

## Owner context
The owner is learning SQL, statistics and Power BI while building this and must be able to defend every line in an interview. Favour clarity over cleverness. Explain non-obvious code in plain English.

## Hard rules
1. Never run `git commit`, `git push`, or any command that changes git history or remotes. When a good commit point is reached, say so and suggest a commit message; the owner commits and pushes.
2. Never read, print, or write real credentials. Credentials live only in `.env` (gitignored), which the owner fills in. Code reads them via python-dotenv. Keep `.env.example` up to date with variable names only.
3. Never modify anything in `data/raw/`.
4. Only ever connect to the `olist` database. Never run `DROP DATABASE`, and never touch other databases on the server.
5. At the start of each phase, propose a plan and wait for approval.
6. Never invent or estimate numbers in docs or reports. Every figure must come from a query or notebook output in this repo. Impact estimates must state their assumptions and be labelled as estimates.
7. Work directly in `D:\Projects\olist-retention-analysis` on `main`. Never use git worktrees or create branches.

## Conventions
- **SQL:** PostgreSQL dialect, lowercase snake_case, CTEs preferred over nested subqueries. Files in `sql/` are numbered (`01_`, `02_`, ...). Each file starts with a header comment (purpose, business question answered, tables used), and each non-trivial step has a plain-English comment.
- **Python:** notebooks in `notebooks/` (numbered), reusable code in `src/`. All DB access goes through `src/db.py`. Exported result tables go to `outputs/` as CSV. Use the `.venv` (Python 3.11, created with `py -3.11 -m venv .venv`).
- Run notebooks with `.venv\Scripts\python -m nbconvert --to notebook --execute --inplace <path>` on the 'Python 3.11 (olist .venv)' kernel; never `python -m jupyter nbconvert`.
- `docs/metrics.md` is the single source of truth for metric definitions. If a definition changes, update it and log the change in `docs/decisions_log.md`.

## Olist data traps (always respect)
- `customer_id` is generated per order; the real customer is `customer_unique_id`. All customer-level metrics use `customer_unique_id`.
- Repeat-purchase metrics are right-censored near the end of the data: use a fixed follow-up window (e.g. repeat within 180 days) and only include customers with enough follow-up time.
- 2016 and the final months of 2018 are sparse/incomplete; the analysis window is set in `docs/metrics.md` after profiling.
- `order_items` has one row per item (freight is per item) and `order_payments` can have multiple rows per order. Aggregate to order level before joining to avoid double counting.
- `order_reviews` contains duplicates; `geolocation` has many rows per zip prefix. Deduplicate before joining.
- Delivery and review analysis use delivered orders only; cancelled/unavailable orders are analysed separately.

## Documentation duties (every phase)
- `docs/learning/phase-N.md`: concepts used, what each important query or notebook cell does in plain English, and 5–8 likely interview questions with model answers grounded in this project.
- `docs/decisions_log.md`: append every assumption or cleaning decision (date, decision, reason, impact).

## Phases
1 Scaffold · 2 Understand + clean (Python) · 3 Database schema, load, quality checks · 4 Core SQL analysis · 5 Statistical tests · 6 Reporting views + DAX spec · 7 Power BI (owner builds) · 8 Findings memo + README · 9 Interview prep pack
