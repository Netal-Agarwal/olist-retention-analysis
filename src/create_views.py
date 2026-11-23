"""Create (or refresh) the analysis.* and report.* views.

Run from the repo root:
    .venv\\Scripts\\python -m src.create_views

Runs sql/04_base_views.sql (analysis.*) and then sql/11_report_views.sql
(report.*, the Power BI layer, which reads the analysis views) in ONE
transaction (all or nothing) and prints how many rows each view returns.
The loader (src.load_to_postgres) reuses drop_views() and create_views() so a
full reload also rebuilds every view.
"""

from __future__ import annotations

import sys

from src.db import REPO_ROOT, get_engine

# Files run in this order: the report views are built on the analysis views.
VIEWS_SQL = [
    REPO_ROOT / "sql" / "04_base_views.sql",
    REPO_ROOT / "sql" / "11_report_views.sql",
]

# Dependency order for dropping: a view must be dropped before the views it is
# built on. So all report views go first (they read the analysis views), and
# inside each schema the children go before their parents:
#   report.agg_excess_bad_reviews_state reads report.dim_state,
#   analysis.v_customer_rfm reads v_customers, which reads v_orders.
VIEWS_DROP_ORDER = [
    "report.agg_campaign_baseline",
    "report.agg_excess_bad_reviews_route",
    "report.agg_excess_bad_reviews_seller",
    "report.agg_excess_bad_reviews_state",
    "report.agg_bad_review_by_delay",
    "report.agg_repeat_by_category",
    "report.agg_repeat_by_review",
    "report.agg_time_to_second",
    "report.agg_cohort_retention",
    "report.dim_date",
    "report.dim_state",
    "report.dim_seller",
    "report.dim_category",
    "report.dim_customer",
    "report.fact_orders",
    "analysis.v_customer_rfm",
    "analysis.v_customers",
    "analysis.v_orders",
]


def drop_views(cur) -> None:
    """Drop the report and analysis views, children first. No CASCADE on
    purpose: if something else depends on a view, the drop fails loudly.
    (DROP VIEW IF EXISTS only gives a notice if the schema does not exist yet.)"""
    for view in VIEWS_DROP_ORDER:
        cur.execute(f"drop view if exists {view}")


def create_views(cur) -> None:
    """Run the view SQL files in order on an open cursor (the caller commits)."""
    for sql_file in VIEWS_SQL:
        cur.execute(sql_file.read_text(encoding="utf-8"))


def print_view_counts(cur) -> None:
    """Print the row count of every view, parents first."""
    print(f"{'view':<40}{'rows':>10}")
    for view in reversed(VIEWS_DROP_ORDER):
        cur.execute(f"select count(*) from {view}")
        print(f"{view:<40}{cur.fetchone()[0]:>10,}")


def main() -> None:
    try:
        conn = get_engine().raw_connection()
    except RuntimeError as err:
        print(f"Setup problem: {err}")
        raise SystemExit(1)
    except Exception as err:
        # Connection errors can mention host and user, so print only the type.
        print(f"Could not connect ({type(err).__name__}). Run src.test_connection for help.")
        raise SystemExit(1)

    try:
        cur = conn.cursor()
        cur.execute("select current_database()")
        if cur.fetchone()[0] != "olist":
            raise RuntimeError("Connected to the wrong database; expected 'olist'.")

        create_views(cur)
        print("Ran " + ", ".join(f"sql/{f.name}" for f in VIEWS_SQL) + "\n")
        print_view_counts(cur)
        conn.commit()
        print("\nViews committed.")
    except Exception as err:
        conn.rollback()
        # Server messages describe the SQL/data, so they are safe to show. For
        # other errors show only our own messages, never connection details.
        detail = getattr(err, "pgerror", None) or (str(err) if isinstance(err, RuntimeError) else "")
        print(f"Creating views failed ({type(err).__name__}). Nothing was changed.\n"
              f"{detail.strip()}", file=sys.stderr)
        raise SystemExit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
