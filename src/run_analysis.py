"""Run the named SELECT queries in one or more SQL files and save each result.

Run from the repo root:
    .venv\\Scripts\\python -m src.run_analysis sql/05_retention.sql sql/06_rfm.sql

Each query in a file starts with a marker line:
    -- name: <query_name>
Everything from one marker to the next is one query. Text before the first
marker (the file header) is ignored. Each result is saved to
outputs/phase4/<query_name>.csv (sql/05_ .. 09_) or outputs/phase5/<query_name>.csv
(sql/10_ and later), and the row count and first rows are printed.

Read-only: every query runs inside a transaction started with
SET TRANSACTION READ ONLY, so PostgreSQL itself refuses any statement that
would change data, and the transaction is rolled back at the end anyway.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pandas as pd
from sqlalchemy import text

from src.db import REPO_ROOT, get_engine

OUTPUTS = REPO_ROOT / "outputs"

# Which phase folder a SQL file's results go to, chosen by the file's number:
# 05-09 are the Phase 4 analysis files, 10 and later belong to Phase 5.
# Keeps Phase 4 results where they were and Phase 5 results apart.
PHASE5_FIRST_FILE_NUMBER = 10


def output_dir_for(sql_path: Path) -> Path:
    """outputs/phase4 for sql/05_..09_, outputs/phase5 for sql/10_ and later."""
    match = re.match(r"(\d+)_", sql_path.name)
    if match and int(match.group(1)) >= PHASE5_FIRST_FILE_NUMBER:
        return OUTPUTS / "phase5"
    return OUTPUTS / "phase4"

# A line that is exactly "-- name: something" (letters, digits, underscores).
# re.MULTILINE makes ^ and $ match at every line, not just the whole file.
NAME_MARKER = re.compile(r"^--\s*name:\s*(\w+)\s*$", re.MULTILINE)


def split_queries(sql_text: str, source: str) -> list[tuple[str, str]]:
    """Return [(name, sql), ...] in file order."""
    markers = list(NAME_MARKER.finditer(sql_text))
    if not markers:
        raise ValueError(f"{source}: no '-- name:' markers found.")
    queries = []
    for i, m in enumerate(markers):
        end = markers[i + 1].start() if i + 1 < len(markers) else len(sql_text)
        body = sql_text[m.end():end].strip()
        # Drop a trailing semicolon: we send one statement at a time.
        body = body.rstrip().rstrip(";").rstrip()
        # A body that is only comments has no SQL to run.
        code_lines = [ln for ln in body.splitlines()
                      if ln.strip() and not ln.strip().startswith("--")]
        if not code_lines:
            raise ValueError(f"{source}: query '{m.group(1)}' is empty.")
        queries.append((m.group(1), body))
    return queries


def main(paths: list[str]) -> None:
    if not paths:
        print("Usage: python -m src.run_analysis <file.sql> [<file.sql> ...]")
        raise SystemExit(1)

    # Collect every query first, so a bad file stops the run before anything is saved.
    # Each entry: (query name, sql, folder its CSV goes to).
    all_queries: list[tuple[str, str, Path]] = []
    for p in paths:
        path = (REPO_ROOT / p) if not Path(p).is_absolute() else Path(p)
        out_dir = output_dir_for(path)
        all_queries += [(name, sql, out_dir)
                        for name, sql in split_queries(path.read_text(encoding="utf-8"), p)]
    names = [n for n, _, _ in all_queries]
    duplicates = sorted({n for n in names if names.count(n) > 1})
    if duplicates:
        print(f"Duplicate query names: {duplicates}")
        raise SystemExit(1)

    try:
        engine = get_engine()
    except RuntimeError as err:
        print(f"Setup problem: {err}")
        raise SystemExit(1)

    with pd.option_context("display.width", 200, "display.max_columns", 20):
        for name, sql, out_dir in all_queries:
            try:
                with engine.connect() as conn:
                    # First statement of the transaction: make it read-only.
                    conn.execute(text("set transaction read only"))
                    df = pd.read_sql(text(sql), conn)
                    conn.rollback()
            except Exception as err:
                detail = getattr(getattr(err, "orig", None), "pgerror", None) or ""
                print(f"\nQuery {name} failed ({type(err).__name__}).\n{detail.strip()}",
                      file=sys.stderr)
                raise SystemExit(1)

            # pandas stores an integer column that contains NULLs as float
            # (2 -> 2.0). convert_dtypes() switches such columns back to a
            # nullable integer type, so the CSV shows 2 and an empty cell.
            df = df.convert_dtypes()
            out_dir.mkdir(parents=True, exist_ok=True)
            out = out_dir / f"{name}.csv"
            df.to_csv(out, index=False)
            print(f"\n=== {name}: {len(df):,} rows -> {out.relative_to(REPO_ROOT)}")
            print(df.head(10).to_string(index=False))


if __name__ == "__main__":
    main(sys.argv[1:])
