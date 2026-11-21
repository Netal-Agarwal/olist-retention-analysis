"""Create (or refresh) the analysis.* views from sql/04_base_views.sql.

Run from the repo root:
    .venv\\Scripts\\python -m src.create_views

Runs the SQL file in ONE transaction (all or nothing) and prints how many rows
each view returns. The loader (src.load_to_postgres) reuses drop_views() and
create_views() so a full reload also rebuilds the views.
"""

from __future__ import annotations

import sys

from src.db import REPO_ROOT, get_engine

VIEWS_SQL = REPO_ROOT / "sql" / "04_base_views.sql"

# Dependency order for dropping: a view must be dropped before the views it is
# built on (v_customer_rfm reads v_customers, which reads v_orders).
VIEWS_DROP_ORDER = [
    "analysis.v_customer_rfm",
    "analysis.v_customers",
    "analysis.v_orders",
]


def drop_views(cur) -> None:
    """Drop the analysis views, children first. No CASCADE on purpose:
    if something else depends on a view, the drop fails loudly."""
    for view in VIEWS_DROP_ORDER:
        cur.execute(f"drop view if exists {view}")


def create_views(cur) -> None:
    """Run sql/04_base_views.sql on an open cursor (the caller commits)."""
    cur.execute(VIEWS_SQL.read_text(encoding="utf-8"))


def print_view_counts(cur) -> None:
    print(f"{'view':<28}{'rows':>10}")
    for view in reversed(VIEWS_DROP_ORDER):
        cur.execute(f"select count(*) from {view}")
        print(f"{view:<28}{cur.fetchone()[0]:>10,}")


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
        print(f"Ran sql/{VIEWS_SQL.name}\n")
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
