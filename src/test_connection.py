"""Quick check that Python can reach the olist database.

Run from the repo root:
    .venv\\Scripts\\python.exe -m src.test_connection
"""

from sqlalchemy import text

from src.db import get_engine


def main() -> None:
    try:
        engine = get_engine()
        # The connection opens here; "with" closes it again afterwards.
        with engine.connect() as conn:
            database, version = conn.execute(
                text("SELECT current_database(), version()")
            ).one()
    except RuntimeError as err:
        # Our own friendly messages from src/db.py (missing settings, wrong DB).
        print(f"Setup problem: {err}")
        raise SystemExit(1)
    except Exception as err:
        # Anything else is usually the server or the login. We print only the
        # error type, never the full message, so no connection details leak.
        print(f"Could not connect ({type(err).__name__}). Common causes:")
        print("  - wrong PGUSER or PGPASSWORD in .env")
        print("  - PostgreSQL service is not running")
        print("  - the 'olist' database has not been created yet")
        print("  - PGHOST or PGPORT is wrong")
        raise SystemExit(1)

    print(f"Database: {database}")
    print(f"Server:   {version}")
    print("Connection OK")


if __name__ == "__main__":
    main()
