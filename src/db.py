"""Single entry point for connecting to the local PostgreSQL `olist` database.

Every notebook and script gets its database connection from get_engine(),
so the connection rules (credentials from .env, olist database only) live
in exactly one place.

Usage:
    from src.db import get_engine
    engine = get_engine()
    df = pd.read_sql("SELECT ...", engine)
"""

from pathlib import Path
import os

from dotenv import load_dotenv
from sqlalchemy import URL, create_engine
from sqlalchemy.engine import Engine

# The repo root is one folder above src/. We find it from this file's own
# location so the .env is found no matter where the code is run from
# (repo root, notebooks/ folder, an IDE, ...).
REPO_ROOT = Path(__file__).resolve().parent.parent
ENV_PATH = REPO_ROOT / ".env"

# The five settings we need. They are the standard PostgreSQL variable names.
REQUIRED_VARS = ["PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"]

# Hard rule 4 in CLAUDE.md: this project only ever talks to this database.
ALLOWED_DATABASE = "olist"


def get_engine() -> Engine:
    """Return a SQLAlchemy engine for the olist database.

    Creating the engine does not open a connection yet; the first query does.
    Raises RuntimeError with a plain-English message if a setting is missing
    or the database name is not 'olist'.
    """
    # Read .env into environment variables. Values already set in the
    # environment are not overwritten.
    load_dotenv(ENV_PATH)

    # Collect every missing or blank setting so the message lists them all
    # at once, instead of failing on the first one.
    settings = {name: os.getenv(name, "").strip() for name in REQUIRED_VARS}
    missing = [name for name, value in settings.items() if not value]
    if missing:
        raise RuntimeError(
            "Missing or empty database settings: "
            + ", ".join(missing)
            + f". Copy .env.example to .env in {REPO_ROOT} and fill them in."
        )

    # Refuse to connect anywhere except the project database.
    if settings["PGDATABASE"] != ALLOWED_DATABASE:
        raise RuntimeError(
            f"PGDATABASE is '{settings['PGDATABASE']}', but this project may only "
            f"connect to '{ALLOWED_DATABASE}'. Fix PGDATABASE in .env."
        )

    try:
        port = int(settings["PGPORT"])
    except ValueError:
        raise RuntimeError("PGPORT in .env must be a number, e.g. 5432.") from None

    # URL.create builds the connection address piece by piece. It escapes
    # special characters in the password (like @ or /) and hides the
    # password when the URL is printed, so it never leaks into logs.
    url = URL.create(
        drivername="postgresql+psycopg2",
        username=settings["PGUSER"],
        password=settings["PGPASSWORD"],
        host=settings["PGHOST"],
        port=port,
        database=settings["PGDATABASE"],
    )

    # pool_pre_ping checks a pooled connection is still alive before using it,
    # which avoids confusing errors after the laptop sleeps or Postgres restarts.
    return create_engine(url, pool_pre_ping=True)


def read_sql_readonly(sql: str, engine: Engine | None = None) -> "pd.DataFrame":
    """Run one SELECT inside a READ ONLY transaction and return a DataFrame.

    SET TRANSACTION READ ONLY makes PostgreSQL itself refuse any statement
    that would change data, and the transaction is rolled back afterwards.
    Same pattern as src/run_analysis.py, packaged for notebooks.
    """
    # Imported here so scripts that only need get_engine() do not load pandas.
    import pandas as pd
    from sqlalchemy import text

    engine = engine or get_engine()
    with engine.connect() as conn:
        conn.execute(text("set transaction read only"))  # first statement of the transaction
        df = pd.read_sql(text(sql), conn)
        conn.rollback()
    return df
