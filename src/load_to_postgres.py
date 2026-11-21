"""Load the 8 cleaned CSVs from data/processed/ into the `clean` schema.

Run from the repo root:
    .venv\\Scripts\\python -m src.load_to_postgres

What it does, all inside ONE database transaction (all or nothing):
  0. drops the analysis.* views (children first, no CASCADE). They read the
     clean.* tables, and 01_schema.sql drops those tables without CASCADE, so
     the views must go first or the table drop would fail.
  1. runs sql/01_schema.sql  (drop + recreate the clean.* tables)
  2. runs sql/02_indexes.sql (indexes on join/filter columns)
  3. for each table, in dependency order:
       - checks the CSV header matches the table's columns,
       - bulk-loads the file with PostgreSQL COPY,
       - prints how many rows are now in the table.
  4. recreates the analysis.* views by running sql/04_base_views.sql.
If anything fails, nothing is kept: the database looks exactly as before.

Why COPY instead of row-by-row INSERTs?
  An INSERT per row means ~100,000 separate statements for one table, each
  parsed, planned and sent over the connection on its own. COPY streams the
  whole file to the server in one command and the server parses it in bulk,
  which is typically 10-100x faster. It also reads the CSV format natively
  (quoted text with commas or line breaks inside, empty cells as NULL).

Why does load order matter?
  Foreign keys make the database refuse a child row whose parent is missing,
  e.g. an order_items row whose order_id is not in orders. So parents are
  loaded first (customers, sellers, products, geolocation), then orders, then
  the tables that point at orders.
"""

from __future__ import annotations

import csv
import io
import re
import sys
from pathlib import Path

from src.create_views import create_views, drop_views, print_view_counts
from src.db import REPO_ROOT, get_engine

SQL_DIR = REPO_ROOT / "sql"
PROCESSED_DIR = REPO_ROOT / "data" / "processed"
SCHEMA = "clean"

# Parents before children (see "Why does load order matter?" above).
LOAD_ORDER = [
    "customers",
    "sellers",
    "products",
    "geolocation",
    "orders",
    "order_items",
    "order_payments",
    "order_reviews",
]

# Whole-number columns that pandas wrote as floats ("40.0") because they
# contain blanks. Postgres will not put '40.0' into an integer column, so we
# convert them in memory before COPY. The CSV on disk is never changed.
FLOAT_WRITTEN_INTEGERS = {
    "products": [
        "product_name_length",
        "product_description_length",
        "product_photos_qty",
        "product_weight_g",
        "product_length_cm",
        "product_height_cm",
        "product_width_cm",
    ],
}

# Accept only a whole number followed by ".0" (e.g. "40.0", "-3.0").
# Anything else, like "40.5", is a real decimal and must stop the load
# rather than be silently rounded.
WHOLE_FLOAT = re.compile(r"^(-?\d+)\.0$")


class LoadError(Exception):
    """A problem we detected ourselves, with a plain-English message."""


def read_csv_header(path: Path) -> list[str]:
    """Return the column names from the first line of a CSV file."""
    with open(path, encoding="utf-8", newline="") as f:
        return next(csv.reader(f))


def table_columns(cur, table: str) -> list[str]:
    """Return the table's column names in their defined order."""
    cur.execute(
        """
        select column_name
        from information_schema.columns
        where table_schema = %s and table_name = %s
        order by ordinal_position
        """,
        (SCHEMA, table),
    )
    return [row[0] for row in cur.fetchall()]


def check_header(table: str, csv_cols: list[str], db_cols: list[str]) -> None:
    """Stop with a clear message if the CSV and the table disagree."""
    if csv_cols == db_cols:
        return
    missing = [c for c in db_cols if c not in csv_cols]
    extra = [c for c in csv_cols if c not in db_cols]
    lines = [f"Header mismatch for {SCHEMA}.{table}:"]
    if missing:
        lines.append(f"  columns in the table but not in the CSV: {missing}")
    if extra:
        lines.append(f"  columns in the CSV but not in the table: {extra}")
    if not missing and not extra:
        lines.append("  same columns but in a different order.")
        lines.append(f"  CSV:   {csv_cols}")
        lines.append(f"  table: {db_cols}")
    raise LoadError("\n".join(lines))


def whole_floats_to_int(path: Path, columns: list[str]) -> io.BytesIO:
    """Return the CSV as bytes with "40.0" -> "40" in the given columns.

    Blank cells stay blank (COPY turns them into NULL). Any value that is not
    blank and not of the form <digits>.0 raises LoadError with its location.
    """
    out = io.StringIO()
    # lineterminator="\n": COPY requires one consistent line ending.
    writer = csv.writer(out, lineterminator="\n")
    with open(path, encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        positions = [header.index(c) for c in columns]
        writer.writerow(header)
        # Line 1 is the header, so data starts on line 2.
        for line_no, row in enumerate(reader, start=2):
            for pos in positions:
                value = row[pos]
                if value == "":
                    continue
                match = WHOLE_FLOAT.match(value)
                if not match:
                    raise LoadError(
                        f"{path.name} line {line_no}, column {header[pos]}: "
                        f"value {value!r} is not a whole number written as 'N.0'. "
                        "Refusing to round it."
                    )
                row[pos] = match.group(1)
            writer.writerow(row)
    return io.BytesIO(out.getvalue().encode("utf-8"))


def copy_table(cur, table: str, columns: list[str], source) -> None:
    """Bulk-load one table from a binary file-like object with COPY."""
    column_list = ", ".join(columns)
    # FORMAT csv: understands quotes, commas and line breaks inside text.
    # HEADER true: skip the first line (we already checked it ourselves).
    # An unquoted empty cell becomes NULL, which is how pandas wrote blanks.
    sql = (
        f"copy {SCHEMA}.{table} ({column_list}) from stdin "
        "with (format csv, header true, encoding 'UTF8')"
    )
    cur.copy_expert(sql, source)


def main() -> None:
    try:
        engine = get_engine()
        # copy_expert is a psycopg2 feature, so we ask SQLAlchemy for the
        # underlying psycopg2 connection. It starts a transaction
        # automatically and keeps it open until commit() or rollback().
        conn = engine.raw_connection()
    except RuntimeError as err:
        print(f"Setup problem: {err}")
        raise SystemExit(1)
    except Exception as err:
        # Connection errors can mention host and user, so print only the type.
        print(f"Could not connect ({type(err).__name__}). Run src.test_connection for help.")
        raise SystemExit(1)

    current_step = "connecting"
    try:
        cur = conn.cursor()

        # Belt and braces on top of src/db.py: confirm which database we are in.
        cur.execute("select current_database()")
        if cur.fetchone()[0] != "olist":
            raise LoadError("Connected to the wrong database; expected 'olist'.")

        # Step 0: the views depend on clean.* tables, so drop them first.
        current_step = "dropping analysis views"
        drop_views(cur)
        print("Dropped analysis views (if they existed)")

        for sql_file in ["01_schema.sql", "02_indexes.sql"]:
            current_step = f"running sql/{sql_file}"
            cur.execute((SQL_DIR / sql_file).read_text(encoding="utf-8"))
            print(f"Ran sql/{sql_file}")

        print()
        print(f"{'table':<16}{'rows loaded':>12}")
        for table in LOAD_ORDER:
            current_step = f"loading {SCHEMA}.{table}"
            path = PROCESSED_DIR / f"{table}.csv"
            if not path.exists():
                raise LoadError(f"Missing file {path}. Re-run notebooks/02_cleaning.ipynb.")

            csv_cols = read_csv_header(path)
            db_cols = table_columns(cur, table)
            check_header(table, csv_cols, db_cols)

            if table in FLOAT_WRITTEN_INTEGERS:
                source = whole_floats_to_int(path, FLOAT_WRITTEN_INTEGERS[table])
                copy_table(cur, table, db_cols, source)
            else:
                with open(path, "rb") as f:
                    copy_table(cur, table, db_cols, f)

            cur.execute(f"select count(*) from {SCHEMA}.{table}")
            print(f"{table:<16}{cur.fetchone()[0]:>12,}")

        # Step 4: rebuild the views on top of the freshly loaded tables.
        current_step = "running sql/04_base_views.sql"
        create_views(cur)
        print("\nRan sql/04_base_views.sql")
        print_view_counts(cur)

        # Only now, with every step done, make the changes permanent.
        current_step = "committing"
        conn.commit()
        print("\nLoad committed. All 8 tables are in the clean schema; analysis views rebuilt.")

    except LoadError as err:
        conn.rollback()
        print(f"\nLoad stopped while {current_step}. Nothing was changed.\n{err}")
        raise SystemExit(1)
    except Exception as err:
        conn.rollback()
        # Server messages (e.g. a broken constraint) describe the data, not the
        # connection, so they are safe and useful to show.
        detail = getattr(err, "pgerror", None) or ""
        print(
            f"\nLoad failed while {current_step} ({type(err).__name__}). "
            f"Nothing was changed.\n{detail.strip()}",
            file=sys.stderr,
        )
        raise SystemExit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
