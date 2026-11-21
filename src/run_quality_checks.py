"""Run sql/03_quality_checks.sql and report the results.

Run from the repo root:
    .venv\\Scripts\\python -m src.run_quality_checks

Prints one line per check, saves the table to outputs/phase3_quality_checks.csv
and exits with code 1 if any check failed (so a script or CI step would stop).
"""

import pandas as pd
from sqlalchemy import text

from src.db import REPO_ROOT, get_engine

SQL_FILE = REPO_ROOT / "sql" / "03_quality_checks.sql"
OUTPUT_FILE = REPO_ROOT / "outputs" / "phase3_quality_checks.csv"


def main() -> None:
    try:
        engine = get_engine()
        with engine.connect() as conn:
            results = pd.read_sql(text(SQL_FILE.read_text(encoding="utf-8")), conn)
    except RuntimeError as err:
        print(f"Setup problem: {err}")
        raise SystemExit(1)
    except Exception as err:
        # Only the error type: connection errors can mention host and user.
        print(f"Quality checks could not run ({type(err).__name__}). "
              "Has src.load_to_postgres been run?")
        raise SystemExit(1)

    OUTPUT_FILE.parent.mkdir(exist_ok=True)
    results.to_csv(OUTPUT_FILE, index=False)

    with pd.option_context("display.max_rows", None, "display.width", 200):
        print(results.to_string(index=False))

    n_failed = int((~results["passed"]).sum())
    print(f"\n{len(results) - n_failed} of {len(results)} checks passed. "
          f"Saved to {OUTPUT_FILE.relative_to(REPO_ROOT)}")
    if n_failed:
        print("FAILED checks:")
        print(results.loc[~results["passed"], ["check_name", "expected", "actual"]]
              .to_string(index=False))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
