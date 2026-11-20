# Olist Retention Analysis

> **Work in progress** — Phase 1 (project scaffold) of 9.

## Business problem
Olist is a Brazilian e-commerce marketplace. Almost all of its customers buy only once. This project asks **why customers don't come back, and what Olist should fix first** — looking at delivery speed and reliability, freight cost, review scores and product mix, using the public Olist dataset from Kaggle (orders from 2016–2018).

## Planned stack
- **PostgreSQL 17** — local database `olist`; core analysis in SQL
- **Python 3.11** — pandas for cleaning, scipy/statsmodels for statistical tests, matplotlib/seaborn for charts, Jupyter notebooks
- **Power BI Desktop** — final dashboard

## Repository layout
| Folder | Contents |
|--------|----------|
| `data/raw/` | Original Kaggle CSVs (not committed) |
| `data/processed/` | Cleaned data produced by code (not committed) |
| `sql/` | Numbered SQL scripts |
| `notebooks/` | Numbered Jupyter notebooks |
| `src/` | Reusable Python code (DB connection in `src/db.py`) |
| `outputs/` | Exported result tables (CSV) |
| `dashboard/` | Power BI file |
| `reports/` | Findings memo |
| `docs/` | Metric definitions, decisions log, learning notes |

## Setup
1. `py -3.11 -m venv .venv`
2. `.venv\Scripts\python.exe -m pip install -r requirements.txt`
3. Copy `.env.example` to `.env` and fill in your PostgreSQL password.
4. `.venv\Scripts\python.exe -m src.test_connection`
