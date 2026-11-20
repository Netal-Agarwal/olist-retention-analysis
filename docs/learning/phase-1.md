# Phase 1 — Project scaffold: what I set up and why

## 1. Virtual environments
A virtual environment (`.venv/`) is a private copy of Python with its own installed packages, living inside the project folder.

- **Why:** different projects need different package versions. Without a venv, installing pandas for one project could break another.
- **Why Python 3.11:** this machine's default `py` is 3.14, which some data libraries may not fully support yet. `py -3.11 -m venv .venv` picks 3.11 explicitly.
- **How it is used:** I call `.venv\Scripts\python.exe` directly instead of "activating" the venv. That avoids PowerShell's script-execution policy blocking `Activate.ps1`.
- **`requirements.txt`** lists the packages with minimum versions, so anyone can rebuild the same environment with one command.
- `.venv/` is gitignored: it is large and machine-specific. The recipe (`requirements.txt`) is committed instead.

## 2. Secrets: `.env`, `.env.example` and `.gitignore`
- The database password lives only in `.env`, a small text file of `NAME=value` lines.
- `.gitignore` tells git to never track `.env`, so it can't be pushed to GitHub by accident. Anything pushed to a public repo can be copied by bots within minutes, and deleting it later does not remove it from history.
- `.env.example` has the same variable names with no real values. It is committed so others know which settings to fill in.
- Python reads `.env` with **python-dotenv** (`load_dotenv`), which turns those lines into environment variables.

## 3. Raw vs processed data
- `data/raw/` holds the original Kaggle CSVs, untouched. Never edited (hard rule 3).
- `data/processed/` holds cleaned outputs that code produces.
- **Why:** if a cleaning step is wrong, I can delete processed files and rebuild from raw. Raw is the evidence; it must stay identical to the source.
- Both folders' contents are gitignored (the files are large and downloadable from Kaggle); a `.gitkeep` file keeps the empty folders in git.

## 4. What a SQLAlchemy engine is
An **engine** is Python's "address book + connection manager" for a database. It knows where the database is and how to log in, and it keeps a small pool of open connections to reuse. Creating it does not connect yet — the first query does.

pandas can use it directly: `pd.read_sql("SELECT ...", engine)`.

### Walk-through of `src/db.py`
1. **Find the repo root** from the file's own location (`Path(__file__).resolve().parent.parent`), so `.env` is found whether code runs from the repo root or from `notebooks/`.
2. **`load_dotenv(ENV_PATH)`** reads `.env` into environment variables.
3. **Check all five settings** (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`). Every missing or blank one is listed in a single friendly error that points to `.env.example`.
4. **Refuse any database except `olist`** — this enforces hard rule 4 in code, not just in writing.
5. **Check the port is a number.**
6. **`URL.create(...)`** builds the connection address safely: special characters in the password are escaped, and the password is hidden if the URL is printed.
7. **`create_engine(url, pool_pre_ping=True)`** — `pool_pre_ping` tests a reused connection before using it, avoiding errors after sleep or a Postgres restart.

`src/test_connection.py` uses the engine to run `SELECT current_database(), version()` and prints "Connection OK". If it fails, it lists common causes without printing any connection details.

## 5. Likely interview questions

**Q1. Why did you use a virtual environment?**
A: To isolate this project's packages and Python version (3.11) from everything else on my machine, and so `requirements.txt` can rebuild the exact setup anywhere.

**Q2. How do you keep database credentials out of your code and GitHub?**
A: They live only in a `.env` file that is gitignored. Code reads them with python-dotenv. I commit a `.env.example` with variable names only so others know what to set.

**Q3. Why keep raw and processed data separate?**
A: Raw data is the untouched source of truth. All cleaning is done by code into `data/processed/`, so any mistake can be fixed by rerunning from raw, and every change is reproducible.

**Q4. What does your `get_engine()` function do, and why have one?**
A: It loads credentials from `.env`, checks they're all present, refuses any database other than `olist`, and returns a SQLAlchemy engine. Having one function means every notebook connects the same way and the safety rules live in one place.

**Q5. Why use `URL.create` instead of building the connection string with an f-string?**
A: An f-string breaks if the password contains characters like `@` or `/`, and printing it would expose the password. `URL.create` escapes those characters and masks the password when printed.

**Q6. Why is `customer_unique_id` your customer key and not `customer_id`?**
A: In Olist, `customer_id` is created per order, so one person can have many. Counting `customer_id` would make almost everyone look like a one-time buyer — exactly the metric this project studies — so it would bias the main result.
