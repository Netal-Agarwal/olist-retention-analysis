"""Build notebooks/03_statistical_tests.ipynb from the cell texts below.

Why a builder script: the notebook has ~50 cells; keeping them as plain text
here makes them easy to review and diff. Run from the repo root:
    .venv\\Scripts\\python notebooks/build_03_statistical_tests.py
then execute the notebook with nbconvert (see CLAUDE.md).
The "What this means for the business" cells (BUSINESS below) are written
only from the executed output.
"""

from pathlib import Path

import nbformat as nbf

NB_PATH = Path(__file__).resolve().parent / "03_statistical_tests.ipynb"

PLACEHOLDER = "_To be written from the executed output._"

# "What this means for the business" text per section, written from the output.
BUSINESS = {
    "t1": """\
- Late orders got a 1–2 star review **62.42%** of the time vs **9.25%** for on-time orders: a gap of **53.17 percentage points** (95% CI 51.96 to 54.37). Late orders are **6.75 times** as likely to get a bad review (95% CI 6.56 to 6.94). The chi-square test gives p ≈ 0 (it prints as 0 because it is too small to store). Chance cannot explain a gap this size.
- The damage starts early: even **1–3 days late** gives a 32.14% bad-review rate (CI 30.06–34.31), about 3.5 times the on-time rate. At **4–7 days** it is 67.68%, and at 8+ days it is about 80%. The CIs of neighbouring buckets do not overlap up to 8–14 days, so each extra step of delay is a real step down in reviews.
- Sizing (q10_05, ESTIMATE): late orders received about **3,391 more bad reviews** than the on-time rate would predict, **27.73% of all bad reviews** in the window. This is the reputation lever, and it is supported.""",
    "t2": """\
- Customers whose first order was late repeated at **1.58%** vs **2.01%** for on time: a difference of **−0.43 points** (95% CI −0.80 to +0.02), relative risk 0.79 (CI 0.61 to 1.01).
- z-test **p = 0.062**; Fisher's exact test **p = 0.065**, so the small count (62 late repeaters) is not distorting the result. At alpha 0.05 we **cannot reject** "no difference".
- The CI runs from "late customers repeat 0.80 points less" to "0.02 points more". So the data rule out a large effect but cannot tell a small effect from none (section 4). Either way the possible size is small next to the 98% of customers who never return.""",
    "t3": """\
- Comparing customers within the same first-order category (24 categories, 51,936 customers), the pooled Mantel–Haenszel odds ratio is **0.808** (95% CI 0.621 to 1.051), CMH **p = 0.111**. The crude odds ratio over the same strata is 0.814, almost identical, so **product category does not explain** the small late-vs-on-time gap. It is neither hiding a big effect nor creating a fake one.
- Breslow–Day **p = 0.905**: no evidence that the odds ratio differs between categories. With only 62 late repeaters spread over 24 categories (2 categories have none), this test has little power, so "no evidence of difference" is not "proven the same".
- Same conclusion as section 2: after adjustment, the lateness–repeat link is small and not statistically significant.""",
    "t4": """\
- With 3,928 late and 52,258 on-time customers, alpha 0.05 and 80% power, the smallest gap we could reliably detect is **about 0.60 points** (late rate 1.41% vs 2.01% on time). The observed gap is **0.43 points**, below that.
- The power to detect a true gap of 0.43 points was only **50%**: a coin flip. To reach 80% power for a gap that size, we would need about **7,980 late customers** (and about 106,000 on time), roughly twice the data.
- **Why "not significant" ≠ "no effect":** a test can only see effects bigger than its noise. Here a real 0.43-point effect would be missed half the time. What we *can* say is that a large effect (0.6+ points) is unlikely. Even at the full observed gap, Phase 4 sized it at only **16.9 extra repeaters** (q09_04, ESTIMATE). So lateness is not where the retention problem comes from, whether or not this small effect is real.""",
    "t5": """\
- 180-day repeat by first review score: 1.71% (1 star), 1.51% (2), 1.94% (3), 1.83% (4), **2.12% (5 stars, 95% CI 1.97–2.28)**. No-review customers: 1.20% (CI 0.51–2.78, n = 417).
- Chi-square across the 5 scores: **p = 0.074**, Cramér's V = 0.012 (very weak). The trend test finds a slight upward slope: **odds ratio 1.064 per extra star** (CI 1.014–1.117, p = 0.012). After the Holm correction for the 15 tests, that p becomes 0.12, so the trend is not significant once we account for the number of tests run.
- The business point: **even customers who gave 5 stars came back only 2.12% of the time.** Satisfaction does not turn into repeat buying on its own, which is the core of the "structural" story and the case for active re-engagement.""",
    "t6": """\
- Cross-state orders were late **8.07%** of the time vs **4.51%** for same-state: a gap of **3.55 points** (95% CI 3.24 to 3.86), 1.79 times the rate (CI 1.69–1.89), p ≈ 4e-98.
- Median delivery time: **12.78 days** cross-state vs **6.52 days** same-state. Rank-biserial r = **0.597**: a random cross-state order is slower than a random same-state order about **80%** of the time (P = 0.798). This is a large effect, not just a significant one.
- Shipping across states (our rough proxy for distance) goes with slower and less reliable delivery. This supports routing and seller-location fixes for the reputation lever, but "same state" is only a proxy for distance and the data are observational.""",
    "t7": """\
- **Lateness:** in Model A the is_late odds ratio is **1.14** (CI 0.81–1.60, p = 0.458). This compares late with on-time orders that took the *same* number of days, because delivery_days is also in the model (correlation 0.63). Without delivery_days the odds ratio is **0.79** (CI 0.61–1.03, p = 0.080). Neither is significant. **Delivery time** itself is: odds ratio **0.892 per extra week** (CI 0.828–0.960). Speed may matter a little; the late flag adds nothing beyond it.
- **Review as mediator:** adding the review score (Model B) barely changes is_late (1.14 → 1.20), and the review block adds nothing significant (likelihood-ratio p = 0.223). We see no sign that a lateness effect on repeat runs through the review.
- **Freight share:** odds ratio **1.13 per +10 points of freight share** (CI 1.05–1.21), significant even after Holm (p = 0.011). The direction is *positive*: holding order value, category and state fixed, a higher freight share goes with slightly *more* repeat buying. Phase 4's flat bivariate rates (q08_05) agree that freight does **not** deter repeat buying. The positive adjusted link is probably about basket type (small, cheap, shipped items) rather than freight itself; it is not a lever to raise freight.
- **Explained share:** McFadden pseudo R² is **0.011** (Model A) and 0.012 (Model B). Everything we know about the first order (lateness, speed, freight, value, category, state, review) barely predicts who comes back. This supports the "structural" story: the reason most customers do not return is not in the first-order experience we can measure.
- **Checks:** both models converged; 2 rows dropped (no delivery date); VIFs are all below 2.1, so collinearity does not make the estimates unstable, but is_late must be read as "at equal delivery time".""",
    "t8": """\
- **States** (14 with ≥ 500 eligible customers): repeat rates range from 1.13% (CE) to 2.91% (MT), chi-square p = 0.021. After the Holm correction, p = 0.19, so it is **not significant**, and Cramér's V is 0.022. Most state CIs overlap, so state rankings of repeat rate should not drive decisions.
- **Categories** (24 with ≥ 300): from 0.92% (musical_instruments) to **3.30% (fashion_bags_accessories, CI 2.41–4.50)**, p = 4.8e-07 (Holm 5.8e-06), Cramér's V = 0.037. **Category differences are real but small** in absolute terms. The clearest contrasts are where the CIs do not overlap, e.g. fashion_bags_accessories 3.30% (2.41–4.50) or bed_bath_table 2.70% (2.30–3.16) vs cool_stuff 1.04% (0.72–1.51) and computers_accessories 1.52% (1.18–1.96).
- For re-engagement this suggests targeting by category (what people bought) rather than by state.""",
    "t9": """\
- **Significant after Holm (5 of 15):** late → more bad reviews (T1); cross-state → later and slower (T6a, T6b); freight share (positive, T7b); category differences in repeat (T8b).
- **Not significant:** every test of lateness → repeat buying (T2a, T2b, T3a, T7a, T7c), the review score → repeat (T5a, T5b, T7d), and state differences (T8a).
- **The two levers hold up:** delivery reliability is a strong, well-measured **reputation** lever. Repeat buying is low almost regardless of the first-order experience (pseudo R² 0.011; 5-star customers repeat at 2.12%), so the **retention** lever is active re-engagement, ideally targeted by category. One caveat: the study had only 50% power for a lateness → repeat effect the size observed, so we can rule out a large effect but not a small one.""",
}

cells: list[tuple[str, str]] = []


def md(text: str) -> None:
    cells.append(("md", text.strip("\n")))


def code(text: str) -> None:
    cells.append(("code", text.strip("\n")))


def business(key: str) -> None:
    md("**What this means for the business**\n\n" + BUSINESS[key])


# =============================================================================
md("""
# 03 — Statistical tests (Phase 5)

**Business question.** Phase 4 suggested a "two levers" story:
1. **Retention is structural.** Almost nobody comes back (1.98% within 180 days), whatever happened on their first order, so the lever is *active re-engagement*.
2. **Delivery reliability is a reputation lever.** Late orders get far more 1–2 star reviews, but lateness only weakly goes with fewer repeat purchases.

This notebook checks whether each part of that story holds up statistically. Results are reported as they come out.

**Conventions (docs/metrics.md, metric 27)**
- Significance level **alpha = 0.05**. All tests are **two-sided** (we do not assume the direction in advance).
- We report **effect sizes and 95% confidence intervals**, not only p-values. A p-value only says whether a difference is distinguishable from zero; the effect size and CI say how big it is and how precisely we know it.
- CIs: Wilson for a single rate; Newcombe for a difference of two rates; log method for a relative risk; Wald CIs (from the model's standard errors) for logistic-regression odds ratios.
- Many tests are run, so the summary (section 9) adds **Holm-adjusted p-values**.
- Populations follow docs/metrics.md: order-level tests use in-window delivered orders with a delivery date; customer-level tests use 180-day-eligible customers (first delivered order 2017-01-01 … 2018-03-04), grouped by their **first** order.
- Data comes from the `analysis` views through `src/db.py`, inside a **read-only transaction**.
- These are observational data: a significant association is **not proof of cause**.
""")

md("## 0. Setup")
code("""
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import scipy
from scipy import stats
import statsmodels
import statsmodels.api as sm
import statsmodels.formula.api as smf
from statsmodels.stats.contingency_tables import StratifiedTable
from statsmodels.stats.multitest import multipletests
from statsmodels.stats.outliers_influence import variance_inflation_factor
from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import (confint_proportions_2indep, proportion_confint,
                                          proportion_effectsize, proportions_ztest)
import matplotlib
matplotlib.use("Agg")          # draw to files only (no window), works under nbconvert
import matplotlib.pyplot as plt

print("Python:", sys.executable)
print("pandas", pd.__version__, "| scipy", scipy.__version__, "| statsmodels", statsmodels.__version__)
assert ".venv" in sys.prefix, "Not running on the project .venv - select the 'Python 3.11 (olist .venv)' kernel."

REPO_ROOT = Path.cwd().parent if Path.cwd().name == "notebooks" else Path.cwd()
sys.path.insert(0, str(REPO_ROOT))      # so `src` can be imported from the notebooks/ folder
from src.db import get_engine, read_sql_readonly

OUT5 = REPO_ROOT / "outputs" / "phase5"
FIG = REPO_ROOT / "reports" / "figures"
OUT5.mkdir(parents=True, exist_ok=True)
FIG.mkdir(parents=True, exist_ok=True)

ALPHA = 0.05            # significance level
MIN_STATE = 500         # eligible customers per state (docs/metrics.md metric 17)
MIN_CATEGORY = 300      # eligible customers per category (metric 17)
pd.set_option("display.width", 200)
pd.set_option("display.max_columns", 30)
""")

md("""
### Helper functions
Small wrappers so every section reports results the same way.
- `wilson_ci(k, n)`: 95% CI for one rate. Wilson behaves well for rates near 0% (ours are ~2%), where the simple "± 1.96 × SE" interval can go below zero.
- `compare_two(k1, n1, k2, n2)`: compares rate 1 with rate 2. It returns the difference (Newcombe CI), the relative risk (log CI) and a pooled two-proportion z-test.
- `cramers_v`: an effect size for a chi-square table, from 0 (no association) to 1.
- `add_result`: stores one row for the summary table in section 9.
""")
code("""
def wilson_ci(k, n):
    lo, hi = proportion_confint(k, n, alpha=ALPHA, method="wilson")
    return lo, hi


def compare_two(k1, n1, k2, n2):
    \"\"\"Group 1 vs group 2: difference (1 - 2), relative risk (1 / 2) and z-test.\"\"\"
    p1, p2 = k1 / n1, k2 / n2
    d_lo, d_hi = confint_proportions_2indep(k1, n1, k2, n2, method="newcomb", compare="diff", alpha=ALPHA)
    r_lo, r_hi = confint_proportions_2indep(k1, n1, k2, n2, method="log", compare="ratio", alpha=ALPHA)
    z, p = proportions_ztest([k1, k2], [n1, n2])          # pooled-variance z-test, two-sided
    return {"rate_1_pct": 100 * p1, "rate_2_pct": 100 * p2,
            "diff_pp": 100 * (p1 - p2), "diff_ci_pp": (100 * d_lo, 100 * d_hi),
            "relative_risk": p1 / p2, "rr_ci": (r_lo, r_hi),
            "z": z, "p_value": p, "n": n1 + n2}


def cramers_v(chi2, n, shape):
    return np.sqrt(chi2 / (n * (min(shape) - 1)))


def show(d):
    \"\"\"Print a result dict one item per line, rounding numbers.\"\"\"
    for k, v in d.items():
        if isinstance(v, tuple):
            v = "(" + ", ".join(f"{x:.4g}" for x in v) + ")"
        elif isinstance(v, (float, np.floating)):
            v = f"{v:.4g}"
        print(f"  {k:<28} {v}")


RESULTS = []   # one dict per hypothesis test, for the summary in section 9


def add_result(test_id, test, question, n, effect_measure, effect, ci, p_value):
    RESULTS.append({"test_id": test_id, "test": test, "question": question, "n": int(n),
                    "effect_measure": effect_measure, "effect": effect,
                    "ci_low": ci[0] if ci else np.nan, "ci_high": ci[1] if ci else np.nan,
                    "p_value": p_value})
""")

md("""
### Load data (read-only)
Two pulls, only the needed columns:
1. **Orders**: in-window delivered orders with a delivery date (so on time / late is known).
2. **Customers**: 180-day-eligible customers, with attributes of their first delivered order.

Numeric columns are cast to `float8` in SQL, because PostgreSQL `numeric` arrives in Python as `Decimal`, which statistics libraries do not accept.
""")
code("""
engine = get_engine()

orders = read_sql_readonly(\"\"\"
    select order_id,
           is_late,
           delay_bucket,
           review_score::float8   as review_score,     -- NULL = no review
           is_same_state,
           delivery_days::float8  as delivery_days
    from analysis.v_orders
    where in_analysis_window
      and is_late is not null
\"\"\", engine)

cust = read_sql_readonly(\"\"\"
    select customer_unique_id,
           is_repeat_180d,
           first_is_late,
           first_delay_bucket,
           first_delivery_days::float8  as first_delivery_days,
           first_freight_share::float8  as first_freight_share,
           first_order_value::float8    as first_order_value,
           first_main_category,
           first_state,
           first_review_score::float8   as first_review_score
    from analysis.v_customers
    where eligible_180d
\"\"\", engine)

# Plain 0/1 columns (NaN for the 2 eligible customers with no delivery date).
cust["repeat"] = cust["is_repeat_180d"].astype(int)
cust["is_late"] = cust["first_is_late"].map({True: 1, False: 0}).astype(float)
orders["late"] = orders["is_late"].astype(int)
print(f"orders: {len(orders):,} rows | eligible customers: {len(cust):,} rows")
""")

md("""
### Sanity check against Phase 4
If these numbers did not match the Phase 4 CSVs, the pulls would be wrong and nothing below could be trusted.
""")
code("""
rev = orders[orders["review_score"].notna()].copy()
rev["bad"] = (rev["review_score"] <= 2).astype(int)
on_time_bad_pct = 100 * rev.loc[rev["late"] == 0, "bad"].mean()

c2 = cust[cust["is_late"].notna()]     # eligible customers whose first order has a delivery date
checks = {
    "eligible customers (56,188)": len(cust),
    "180d repeaters (1,112)": int(cust["repeat"].sum()),
    "on-time 180d repeat % (2.01)": round(100 * c2.loc[c2["is_late"] == 0, "repeat"].mean(), 2),
    "late 180d repeat % (1.58)": round(100 * c2.loc[c2["is_late"] == 1, "repeat"].mean(), 2),
    "late repeaters (62)": int(c2.loc[c2["is_late"] == 1, "repeat"].sum()),
    "orders with delivery date (96,203)": len(orders),
    "reviewed orders with delivery date (95,560)": len(rev),
    "on-time bad-review % (9.25)": round(on_time_bad_pct, 2),
}
for k, v in checks.items():
    print(f"  {k:<45} {v:,}" if isinstance(v, int) else f"  {k:<45} {v}")
assert checks["eligible customers (56,188)"] == 56188
assert checks["180d repeaters (1,112)"] == 1112
assert checks["late repeaters (62)"] == 62
assert checks["reviewed orders with delivery date (95,560)"] == 95560
assert checks["on-time bad-review % (9.25)"] == 9.25
""")

# =============================================================================
md("""
## 1. Late delivery vs bad reviews

**Question.** Do late orders get a 1–2 star review more often than on-time orders, and by how much?

**Null hypothesis (H0).** The bad-review rate is the same for late and on-time orders.

**Why this test.** Both variables are yes/no, so the data is a 2×2 table of counts, and the chi-square test of independence is the standard test for it. Every expected cell count is in the hundreds or more, so the chi-square approximation is reliable. We use it **without** Yates' continuity correction. That correction matters only for small counts, and with n ≈ 95,000 it would just make the test slightly conservative. Because a p-value alone says nothing about size, we also report the **difference in rates** (Newcombe 95% CI) and the **relative risk** (how many times more likely).

Population: in-window delivered orders with a delivery date and a review (95,560).
""")
code("""
tab1 = pd.crosstab(rev["late"].map({0: "on time", 1: "late"}), rev["bad"].map({0: "not bad", 1: "bad (1-2)"}))
tab1 = tab1.loc[["late", "on time"], ["bad (1-2)", "not bad"]]
print(tab1, "\\n")

chi2_1, p_chi2_1, dof_1, expected_1 = stats.chi2_contingency(tab1.values, correction=False)
print(f"smallest expected count: {expected_1.min():,.0f}")

k_late, n_late = tab1.loc["late"].iloc[0], tab1.loc["late"].sum()
k_on, n_on = tab1.loc["on time"].iloc[0], tab1.loc["on time"].sum()
t1 = compare_two(k_late, n_late, k_on, n_on)    # late minus on time
print("\\nLate (1) vs on time (2):")
show(t1)
print(f"  {'chi-square':<28} {chi2_1:,.1f} (df {dof_1}), p = {p_chi2_1:.3g}")

add_result("T1", "Chi-square 2x2 (late x bad review)",
           "Do late orders get more 1-2 star reviews?", n_late + n_on,
           "difference in bad-review rate, late - on time (pp)", t1["diff_pp"], t1["diff_ci_pp"], p_chi2_1)
""")
md("""
**Bad-review rate by delay bucket.** The same rate for each delay bucket, with Wilson 95% CIs, shows whether it rises steadily with the delay or jumps once an order is late at all.
""")
code("""
buckets = (rev.groupby("delay_bucket")["bad"].agg(reviewed_orders="size", bad_reviews="sum").reset_index())
buckets["bad_rate_pct"] = 100 * buckets["bad_reviews"] / buckets["reviewed_orders"]
ci = buckets.apply(lambda r: wilson_ci(r["bad_reviews"], r["reviewed_orders"]), axis=1)
buckets["ci_low_pct"] = [100 * lo for lo, _ in ci]
buckets["ci_high_pct"] = [100 * hi for _, hi in ci]
print(buckets.round(2).to_string(index=False))
""")
business("t1")

# =============================================================================
md("""
## 2. Late first delivery vs 180-day repeat

**Question.** Are customers whose first order arrived late less likely to buy again within 180 days?

**H0.** The 180-day repeat rate is the same for late and on-time first orders.

**Why this test.** We are comparing two proportions from independent groups, so we use the **two-proportion z-test** (pooled variance), with a Newcombe CI for the difference and the relative risk. The late group has only **62 repeaters**. The z-test relies on a normal approximation, so we also run **Fisher's exact test**, which computes the p-value exactly from the 2×2 table without that approximation. If the two tests agree, the small count is not distorting the result.

Population: 180-day-eligible customers whose first order has a delivery date (56,186; the 2 with no delivery date are excluded).
""")
code("""
g = c2.groupby("is_late")["repeat"].agg(["sum", "size"])
rep_late, n_late_c = int(g.loc[1, "sum"]), int(g.loc[1, "size"])
rep_on, n_on_c = int(g.loc[0, "sum"]), int(g.loc[0, "size"])
print(f"late:    {rep_late} repeaters of {n_late_c:,}")
print(f"on time: {rep_on:,} repeaters of {n_on_c:,}\\n")

t2 = compare_two(rep_late, n_late_c, rep_on, n_on_c)      # late minus on time
print("Late (1) vs on time (2):")
show(t2)

fisher_or, p_fisher = stats.fisher_exact([[rep_late, n_late_c - rep_late], [rep_on, n_on_c - rep_on]])
print(f"  {'Fisher exact: odds ratio':<28} {fisher_or:.3f}, p = {p_fisher:.3g}")

add_result("T2a", "Two-proportion z-test (late x 180d repeat)",
           "Do late first orders repeat less within 180 days?", t2["n"],
           "difference in 180d repeat rate, late - on time (pp)", t2["diff_pp"], t2["diff_ci_pp"], t2["p_value"])
add_result("T2b", "Fisher's exact test (late x 180d repeat)",
           "Same question, exact test (only 62 late repeaters)", t2["n"],
           "odds ratio, late vs on time", fisher_or, None, p_fisher)
""")
business("t2")

# =============================================================================
md("""
## 3. Late vs repeat within product categories (Cochran–Mantel–Haenszel)

**Question.** Does the late-vs-on-time repeat gap survive when we compare customers who bought the **same kind of product**?

**H0.** Within categories, the odds of repeating are the same for late and on-time first orders (common odds ratio = 1).

**Why this test.** Category could be a **confounder**: some categories are rebought more often (pet food vs a sofa) and may also arrive late more or less often. The CMH test makes one 2×2 table per category and combines them into a **pooled Mantel–Haenszel odds ratio**, a "like with like" comparison. We also run the **Breslow–Day homogeneity test**, which asks whether the odds ratio differs between categories.

**Strata and zero cells.** Strata are first-order categories with ≥ 300 eligible customers (metric 17), as in `q07_09`. Many categories have **0 late repeaters**. The MH odds ratio is a ratio of sums across strata, Σ(a·d/n) / Σ(b·c/n). A stratum with a zero cell still counts: it adds zero to one sum and a positive amount to the other. So no continuity correction (adding 0.5 to cells) is needed, and none is applied. A stratum with an entirely empty row (no late customers, or no on-time customers) says nothing about the comparison and would be dropped; the code lists any. Small expected counts make Breslow–Day unreliable, so read it with care.
""")
code("""
cat_sizes = cust["first_main_category"].value_counts()
strata_cats = sorted(cat_sizes[cat_sizes >= MIN_CATEGORY].index)

tables, kept, dropped = [], [], []
for cat in strata_cats:
    d = c2[c2["first_main_category"] == cat]
    a = int(((d["is_late"] == 1) & (d["repeat"] == 1)).sum())   # late, repeat
    b = int(((d["is_late"] == 1) & (d["repeat"] == 0)).sum())   # late, no repeat
    c = int(((d["is_late"] == 0) & (d["repeat"] == 1)).sum())   # on time, repeat
    e = int(((d["is_late"] == 0) & (d["repeat"] == 0)).sum())   # on time, no repeat
    if a + b == 0 or c + e == 0:
        dropped.append(cat)
        continue
    tables.append(np.array([[a, b], [c, e]], dtype=float))
    kept.append({"category": cat, "late_n": a + b, "late_repeaters": a, "on_time_n": c + e, "on_time_repeaters": c})

kept = pd.DataFrame(kept)
print(f"categories with >= {MIN_CATEGORY} eligible customers: {len(strata_cats)}; used as strata: {len(kept)}; dropped (empty row): {dropped}")
print(f"strata with 0 late repeaters: {(kept['late_repeaters'] == 0).sum()}")
print(f"customers covered: {int((kept['late_n'] + kept['on_time_n']).sum()):,}\\n")

st = StratifiedTable(tables)
mh_or = st.oddsratio_pooled
mh_ci = st.oddsratio_pooled_confint(alpha=ALPHA)
null_test = st.test_null_odds(correction=False)
homog_test = st.test_equal_odds(adjust=False)

crude = np.array(tables).sum(axis=0)
crude_or = (crude[0, 0] * crude[1, 1]) / (crude[0, 1] * crude[1, 0])
print(f"crude odds ratio (strata pooled into one table): {crude_or:.3f}")
print(f"Mantel-Haenszel pooled odds ratio:               {mh_or:.3f}  95% CI ({mh_ci[0]:.3f}, {mh_ci[1]:.3f})")
print(f"CMH test of OR = 1:          chi2 = {null_test.statistic:.3f}, p = {null_test.pvalue:.3g}")
print(f"Breslow-Day homogeneity:     chi2 = {homog_test.statistic:.3f}, p = {homog_test.pvalue:.3g} (df {len(tables) - 1})")

n_cmh = int((kept["late_n"] + kept["on_time_n"]).sum())
add_result("T3a", "Cochran-Mantel-Haenszel (late x repeat, by category)",
           "Does the late-repeat link hold within categories?", n_cmh,
           "MH pooled odds ratio, late vs on time", mh_or, tuple(mh_ci), null_test.pvalue)
add_result("T3b", "Breslow-Day homogeneity of odds ratios",
           "Does the late-repeat odds ratio differ between categories?", n_cmh,
           "chi-square statistic", homog_test.statistic, None, homog_test.pvalue)
""")
business("t3")

# =============================================================================
md("""
## 4. Power analysis: how big a gap could we have detected?

**Question.** With these group sizes (3,928 late vs 52,258 on time), alpha 0.05 and 80% power, what is the **smallest** gap in 180-day repeat rate we could reliably detect? And what was the chance of detecting a true gap the size of the one we observed (2.01% vs 1.58%)?

**Why.** "Not significant" can mean two things: there is no real effect, *or* the study was too small to see it. Power analysis tells them apart. **Power** = the chance a test finds an effect of a given size if that effect is real. The **minimum detectable effect (MDE)** is the smallest true effect the test would catch 80% of the time.

**Method.** For two proportions, statsmodels measures the effect with **Cohen's h** = 2·asin(√p₁) − 2·asin(√p₂). This transformation keeps the variance stable, so the same h is equally hard to detect at any baseline rate. We solve for h at 80% power, then convert it back into a late-group repeat rate, starting from the on-time baseline. This is not a hypothesis test, so it is not part of the Holm family.
""")
code("""
p_on = rep_on / n_on_c
p_late = rep_late / n_late_c
ratio = n_on_c / n_late_c                  # size of group 2 relative to group 1 (group 1 = late)
power_calc = NormalIndPower()

h_mde = power_calc.solve_power(effect_size=None, nobs1=n_late_c, alpha=ALPHA, power=0.80,
                               ratio=ratio, alternative="two-sided")
# Back from h to a rate: p_late = sin(asin(sqrt(p_on)) -/+ h/2)^2
p_late_lower = np.sin(np.arcsin(np.sqrt(p_on)) - h_mde / 2) ** 2
p_late_upper = np.sin(np.arcsin(np.sqrt(p_on)) + h_mde / 2) ** 2

h_obs = abs(proportion_effectsize(p_on, p_late))
power_obs = power_calc.power(effect_size=h_obs, nobs1=n_late_c, alpha=ALPHA, ratio=ratio,
                             alternative="two-sided")
n_late_needed = power_calc.solve_power(effect_size=h_obs, nobs1=None, alpha=ALPHA, power=0.80,
                                       ratio=ratio, alternative="two-sided")

power_df = pd.DataFrame([{
    "late_n": n_late_c, "on_time_n": n_on_c, "on_time_rate_pct": 100 * p_on, "late_rate_pct": 100 * p_late,
    "observed_gap_pp": 100 * (p_on - p_late), "observed_cohens_h": h_obs,
    "alpha": ALPHA, "target_power": 0.80, "mde_cohens_h": h_mde,
    "mde_late_rate_if_lower_pct": 100 * p_late_lower, "mde_gap_lower_pp": 100 * (p_on - p_late_lower),
    "mde_late_rate_if_higher_pct": 100 * p_late_upper, "mde_gap_higher_pp": 100 * (p_late_upper - p_on),
    "power_for_observed_gap": power_obs,
    "late_n_needed_for_80pct_power_same_ratio": n_late_needed,
    "on_time_n_needed_same_ratio": n_late_needed * ratio,
}])
show(power_df.iloc[0].to_dict())
power_df.round(4).to_csv(OUT5 / "power_analysis.csv", index=False)
""")
business("t4")

# =============================================================================
md("""
## 5. First review score vs 180-day repeat

**Question.** Do customers who gave their first order a better review come back more often?

**H0.** The 180-day repeat rate is the same for all five review scores.

**Why these tests.** A **chi-square test** on the 5×2 table (score × repeated) asks whether *any* score differs; it ignores that the scores are ordered. A **logistic regression with the score as a number** (1–5) asks a more specific question: is there a *trend*, with each extra star going with higher odds of repeating? It reports one odds ratio per star. Customers with **no review** (417) cannot sit on the 1–5 scale, so they are shown separately and left out of both tests.
""")
code("""
r5 = cust.copy()
r5["score"] = r5["first_review_score"].map(lambda s: "no review" if pd.isna(s) else str(int(s)))
by_score = r5.groupby("score")["repeat"].agg(eligible_customers="size", repeaters="sum").reset_index()
by_score["repeat_rate_pct"] = 100 * by_score["repeaters"] / by_score["eligible_customers"]
ci = by_score.apply(lambda r: wilson_ci(r["repeaters"], r["eligible_customers"]), axis=1)
by_score["ci_low_pct"] = [100 * lo for lo, _ in ci]
by_score["ci_high_pct"] = [100 * hi for _, hi in ci]
print(by_score.round(2).to_string(index=False), "\\n")

scored = r5[r5["score"] != "no review"]
tab5 = pd.crosstab(scored["score"], scored["repeat"])
chi2_5, p_5, dof_5, exp_5 = stats.chi2_contingency(tab5.values, correction=False)
v_5 = cramers_v(chi2_5, tab5.values.sum(), tab5.shape)
print(f"chi-square (scores 1-5): {chi2_5:.2f} (df {dof_5}), p = {p_5:.3g}, Cramer's V = {v_5:.4f}, "
      f"smallest expected count {exp_5.min():.1f}")

trend = smf.logit("repeat ~ first_review_score", data=scored).fit(disp=0)
or_star = np.exp(trend.params["first_review_score"])
or_star_ci = tuple(np.exp(trend.conf_int(alpha=ALPHA).loc["first_review_score"]))
p_trend = trend.pvalues["first_review_score"]
print(f"trend: odds ratio per extra star = {or_star:.3f}, 95% CI ({or_star_ci[0]:.3f}, {or_star_ci[1]:.3f}), "
      f"p = {p_trend:.3g}, n = {int(trend.nobs):,}, converged = {trend.mle_retvals['converged']}")

add_result("T5a", "Chi-square 5x2 (review score x 180d repeat)",
           "Does the 180d repeat rate differ by first review score?", tab5.values.sum(),
           "Cramer's V", v_5, None, p_5)
add_result("T5b", "Logistic trend (score as number)",
           "Does each extra review star go with higher repeat odds?", trend.nobs,
           "odds ratio per extra star", or_star, or_star_ci, p_trend)
""")
business("t5")

# =============================================================================
md("""
## 6. Cross-state vs same-state orders: lateness and delivery time

**Question.** Are orders shipped to another state late more often, and do they take longer to arrive? (Same state is a rough stand-in for short distance.)

**H0 (a).** The late rate is the same for cross-state and same-state orders. **H0 (b).** Delivery times have the same distribution in both groups.

**Why these tests.** (a) Two proportions, so the **two-proportion z-test** with a Newcombe CI. (b) Delivery days are strongly right-skewed (a long tail of very slow orders), so instead of a t-test on means we use **Mann–Whitney U**, which compares ranks and is not pulled around by the tail. Its effect size is the **rank-biserial correlation** r = 2·U/(n₁·n₂) − 1. It runs from −1 to 1; for example, r = 0.4 means that if you pick one cross-state and one same-state order at random, the cross-state one is slower 70% of the time and faster 30% of the time (0.70 − 0.30 = 0.4). We also report both medians.

Population: in-window delivered orders with a delivery date (all of them, reviewed or not).
""")
code("""
cross = orders[~orders["is_same_state"]]
same = orders[orders["is_same_state"]]
t6a = compare_two(int(cross["late"].sum()), len(cross), int(same["late"].sum()), len(same))   # cross minus same
print(f"cross-state: {len(cross):,} orders | same-state: {len(same):,} orders")
print("Late rate, cross (1) vs same (2):")
show(t6a)

mw = stats.mannwhitneyu(cross["delivery_days"], same["delivery_days"], alternative="two-sided")
u_cross = mw.statistic                        # U for the first sample (cross-state)
n1, n2 = len(cross), len(same)
rank_biserial = 2 * u_cross / (n1 * n2) - 1   # > 0: cross-state orders tend to take longer
prob_cross_slower = u_cross / (n1 * n2)       # chance a random cross order is slower than a random same order (ties count half)
print(f"\\nDelivery days: median cross = {cross['delivery_days'].median():.2f}, median same = {same['delivery_days'].median():.2f}")
print(f"Mann-Whitney U = {u_cross:,.0f}, p = {mw.pvalue:.3g}, rank-biserial r = {rank_biserial:.3f}, "
      f"P(cross slower) = {prob_cross_slower:.3f}")

add_result("T6a", "Two-proportion z-test (cross vs same state x late)",
           "Are cross-state orders late more often?", t6a["n"],
           "difference in late rate, cross - same (pp)", t6a["diff_pp"], t6a["diff_ci_pp"], t6a["p_value"])
add_result("T6b", "Mann-Whitney U (delivery days, cross vs same state)",
           "Do cross-state orders take longer to arrive?", n1 + n2,
           "rank-biserial correlation (cross slower > 0)", rank_biserial, None, mw.pvalue)
""")
business("t6")

# =============================================================================
md("""
## 7. Logistic regression: what goes with repeating, all at once?

**Question.** Once we allow for the other first-order attributes at the same time, is lateness (or anything else) associated with 180-day repeat buying? And how much of repeat buying do these attributes explain at all?

**Why logistic regression.** The outcome is yes/no (repeated or not), so ordinary linear regression would predict impossible values (below 0 or above 1). Logistic regression models the **log-odds** of repeating. Each coefficient, exponentiated, is an **odds ratio** (OR): how the odds of repeating change for a one-unit increase, *holding the other variables fixed*. OR = 1 means no association; below 1, lower odds; above 1, higher.

**Specification** (docs/decisions_log.md):
- `is_late` (0/1), `delivery_days` (purchase to delivery, days), `freight_share_10pp` (freight share × 10, so one unit = +10 percentage points of freight share, e.g. 15% → 25%), `log(order_value)`. The log is used because order value is very right-skewed, and a log unit is a *proportional* change (×2.72 in value).
- `category`: first-order main category if it has ≥ 300 eligible customers, else `other`. `state`: first-order state if it has ≥ 500 eligible customers, else `other`. Reference levels are the largest groups, so each category or state OR compares with a big, stable baseline.
- **Model A** leaves the review score out. **Model B** adds `review` (1–5 or `none`, reference 5 stars).

**Mediator, not confounder.** The review score sits *between* lateness and repeating: late → bad review → maybe no return. A **confounder** causes both the factor and the outcome, and adjusting for it removes bias. A **mediator** is part of the path, and adjusting for it removes part of the very effect we want to measure. So Model A shows the *total* association of lateness with repeating, and Model B shows what is left *after* the review. If is_late's OR moves towards 1 in Model B, part of any lateness association runs through the review.

**Checks.** Convergence (the fitting algorithm reached a solution); n used and dropped (rows with a missing value are dropped); McFadden pseudo-R², where 0 means the model predicts no better than the overall rate; collinearity between `is_late` and `delivery_days` (late orders are, by definition, mostly slow ones), shown as their correlation and as variance inflation factors (VIF).
""")
code("""
m = cust.copy()
cat_counts = m["first_main_category"].value_counts()
state_counts = m["first_state"].value_counts()
m["category"] = np.where(m["first_main_category"].map(cat_counts) >= MIN_CATEGORY, m["first_main_category"], "other")
m["state"] = np.where(m["first_state"].map(state_counts) >= MIN_STATE, m["first_state"], "other")
m["review"] = m["first_review_score"].map(lambda s: "none" if pd.isna(s) else str(int(s)))
m = m.rename(columns={"first_delivery_days": "delivery_days", "first_freight_share": "freight_share",
                      "first_order_value": "order_value"})
m["freight_share_10pp"] = m["freight_share"] * 10     # 1 unit = +10 percentage points of freight share

ref_cat = m["category"].value_counts().idxmax()
ref_state = m["state"].value_counts().idxmax()
print(f"category levels: {m['category'].nunique()} (reference '{ref_cat}'); "
      f"state levels: {m['state'].nunique()} (reference '{ref_state}')")

rhs_a = (f"is_late + delivery_days + freight_share_10pp + np.log(order_value)"
         f" + C(category, Treatment('{ref_cat}')) + C(state, Treatment('{ref_state}'))")
rhs_b = rhs_a + " + C(review, Treatment('5'))"


def fit_logit(rhs, label):
    res = smf.logit("repeat ~ " + rhs, data=m).fit(disp=0, maxiter=200)
    ci = np.exp(res.conf_int(alpha=ALPHA))
    table = pd.DataFrame({"term": res.params.index, "odds_ratio": np.exp(res.params.values),
                          "ci_low": ci[0].values, "ci_high": ci[1].values, "p_value": res.pvalues.values})
    print(f"{label}: n used = {int(res.nobs):,}, n dropped = {len(m) - int(res.nobs)}, "
          f"converged = {res.mle_retvals['converged']}, McFadden pseudo R2 = {res.prsquared:.4f}, "
          f"log-likelihood = {res.llf:.1f}")
    return res, table


res_a, or_a = fit_logit(rhs_a, "Model A (no review)")
res_b, or_b = fit_logit(rhs_b, "Model B (+ review)")
or_a.round(4).to_csv(OUT5 / "logit_model_a.csv", index=False)
or_b.round(4).to_csv(OUT5 / "logit_model_b.csv", index=False)
""")
md("Odds ratios for the main terms (the full tables, including every category and state, are saved to `outputs/phase5/logit_model_a.csv` and `logit_model_b.csv`):")
code("""
main_terms = ["is_late", "delivery_days", "freight_share_10pp", "np.log(order_value)"]
review_terms = [t for t in or_b["term"] if t.startswith("C(review")]
print("Model A")
print(or_a[or_a["term"].isin(main_terms)].round(4).to_string(index=False))
print("\\nModel B")
print(or_b[or_b["term"].isin(main_terms + review_terms)].round(4).to_string(index=False))

# Delivery time per extra WEEK is easier to picture than per day: OR(7 days) = exp(7 x coefficient).
week_or = np.exp(7 * res_a.params["delivery_days"])
week_ci = np.exp(7 * res_a.conf_int(alpha=ALPHA).loc["delivery_days"])
print(f"\\nModel A delivery time: odds ratio per +7 days = {week_or:.3f}, 95% CI ({week_ci[0]:.3f}, {week_ci[1]:.3f})")
""")
md("""
**Sensitivity: Model A without `delivery_days`.** With both `is_late` and `delivery_days` in the model, the is_late OR means "late vs on time *at the same delivery time*". That is a narrow comparison, because late orders are mostly slow ones. Dropping `delivery_days` gives the lateness association with everything else still adjusted. It is shown for interpretation only and is not part of the Holm family.
""")
code("""
rhs_a_no_days = rhs_a.replace("delivery_days + ", "")
res_a2, or_a2 = fit_logit(rhs_a_no_days, "Model A without delivery_days")
print(or_a2[or_a2["term"] == "is_late"].round(4).to_string(index=False))
""")
md("""
**Does adding the review improve the model?** A likelihood-ratio test compares Model B with Model A. Both use the same rows, because the review always has a level (`none` included). It asks whether the 5 review terms (1, 2, 3, 4 and none, each vs 5 stars) together add explanatory power.
""")
code("""
assert res_a.nobs == res_b.nobs
lr_stat = 2 * (res_b.llf - res_a.llf)
lr_df = int(res_b.df_model - res_a.df_model)
p_lr = stats.chi2.sf(lr_stat, lr_df)
print(f"LR test (review block): chi2 = {lr_stat:.2f}, df = {lr_df}, p = {p_lr:.3g}")
print(f"pseudo R2: Model A {res_a.prsquared:.4f} -> Model B {res_b.prsquared:.4f}")
""")
md("**Collinearity check.** How strongly do `is_late` and `delivery_days` move together, and how much does that inflate the uncertainty of their coefficients?")
code("""
used = m.dropna(subset=["is_late", "delivery_days", "freight_share", "order_value"])
print(f"correlation is_late vs delivery_days: {used['is_late'].corr(used['delivery_days']):.3f}")
X = sm.add_constant(pd.DataFrame({"is_late": used["is_late"], "delivery_days": used["delivery_days"],
                                  "freight_share": used["freight_share"],
                                  "log_order_value": np.log(used["order_value"])}))
vif = pd.DataFrame({"variable": X.columns[1:],
                    "VIF": [variance_inflation_factor(X.values, i) for i in range(1, X.shape[1])]})
print(vif.round(2).to_string(index=False))
print("(Rule of thumb: VIF above ~5-10 signals a collinearity problem.)")
""")
code("""
def or_row(table, term):
    return table.loc[table["term"] == term].iloc[0]


ra, rb = or_row(or_a, "is_late"), or_row(or_b, "is_late")
fa = or_row(or_a, "freight_share_10pp")
add_result("T7a", "Logistic Model A: is_late",
           "Is late first delivery linked to repeat, adjusting for other factors?", res_a.nobs,
           "odds ratio, late vs on time", ra["odds_ratio"], (ra["ci_low"], ra["ci_high"]), ra["p_value"])
add_result("T7b", "Logistic Model A: freight_share",
           "Is freight share linked to repeat, adjusting for other factors?", res_a.nobs,
           "odds ratio per +10 pp freight share", fa["odds_ratio"], (fa["ci_low"], fa["ci_high"]), fa["p_value"])
add_result("T7c", "Logistic Model B: is_late (+ review)",
           "Is lateness linked to repeat after allowing for the review?", res_b.nobs,
           "odds ratio, late vs on time", rb["odds_ratio"], (rb["ci_low"], rb["ci_high"]), rb["p_value"])
add_result("T7d", "Likelihood-ratio test: review block (Model B vs A)",
           "Does the first review score add to explaining repeat?", res_b.nobs,
           "chi-square statistic (df 5)", lr_stat, None, p_lr)
""")
business("t7")

# =============================================================================
md("""
## 8. Are the state and category differences in repeat buying real?

**Question.** Phase 4 listed 180-day repeat rates by state and by category. Are the differences bigger than chance alone would produce?

**H0.** The repeat rate is the same in every state (or every category).

**Why this test.** A **chi-square test** on the k×2 table (group × repeated) gives one overall answer for each breakdown. It uses only the groups that meet the size thresholds (states ≥ 500, categories ≥ 300). Effect size: Cramér's V.

**Multiple comparisons caution.** With 14 states and 24 categories, some groups will look high or low purely by chance. If you compared every pair at alpha 0.05 you would expect about 1 in 20 "significant" pairs even if nothing were going on. So a top-5 / bottom-5 list should be read with the CIs below: rates whose intervals overlap heavily are not reliably different, even if they rank far apart.
""")
code("""
def group_test(col, min_n, label, test_id):
    sizes = cust[col].value_counts()
    keep = sizes[sizes >= min_n].index
    d = cust[cust[col].isin(keep)]
    tab = pd.crosstab(d[col], d["repeat"])
    chi2, p, dof, exp = stats.chi2_contingency(tab.values, correction=False)
    v = cramers_v(chi2, tab.values.sum(), tab.shape)
    rates = d.groupby(col)["repeat"].agg(eligible_customers="size", repeaters="sum")
    rates["repeat_rate_pct"] = 100 * rates["repeaters"] / rates["eligible_customers"]
    ci = [wilson_ci(k, n) for k, n in zip(rates["repeaters"], rates["eligible_customers"])]
    rates["ci_low_pct"] = [100 * lo for lo, _ in ci]
    rates["ci_high_pct"] = [100 * hi for _, hi in ci]
    rates = rates.sort_values("repeat_rate_pct", ascending=False)
    print(f"{label}: {len(keep)} groups, n = {tab.values.sum():,}, chi2 = {chi2:.2f} (df {dof}), "
          f"p = {p:.3g}, Cramer's V = {v:.4f}, smallest expected count {exp.min():.1f}")
    print(f"  rates range {rates['repeat_rate_pct'].min():.2f}% - {rates['repeat_rate_pct'].max():.2f}%")
    add_result(test_id, f"Chi-square k x 2 ({label} x 180d repeat)",
               f"Do 180d repeat rates differ between {label}s?", tab.values.sum(), "Cramer's V", v, None, p)
    return rates


state_rates = group_test("first_state", MIN_STATE, "state", "T8a")
print(state_rates.round(2).to_string(), "\\n")
cat_rates = group_test("first_main_category", MIN_CATEGORY, "category", "T8b")
print(cat_rates.round(2).to_string())
""")
business("t8")

# =============================================================================
md("""
## 9. Summary of all tests

One row per hypothesis test. **Holm adjustment:** we ran several tests, so the chance of at least one false positive is above 5%. Holm's method sorts the p-values from smallest to largest and compares the smallest with alpha/m, the next with alpha/(m−1), and so on, stopping at the first that fails. It controls the family-wise error rate like Bonferroni but is less strict. The family is every row in this table; the power analysis (section 4) is not a test and is not included.

`conclusion` uses the Holm-adjusted p-value: "significant" = we reject H0 at alpha 0.05 after adjustment.
""")
code("""
summary = pd.DataFrame(RESULTS)
reject, p_holm, _, _ = multipletests(summary["p_value"], alpha=ALPHA, method="holm")
summary["p_holm"] = p_holm
summary["conclusion"] = np.where(reject, "significant (reject H0)", "not significant (cannot reject H0)")
summary_out = summary.copy()
for c in ["effect", "ci_low", "ci_high"]:
    summary_out[c] = summary_out[c].round(4)
summary_out["p_value"] = summary_out["p_value"].map(lambda p: float(f"{p:.3g}"))
summary_out["p_holm"] = summary_out["p_holm"].map(lambda p: float(f"{p:.3g}"))
summary_out.to_csv(OUT5 / "test_results.csv", index=False)
with pd.option_context("display.max_colwidth", 60):
    print(summary_out[["test_id", "test", "n", "effect_measure", "effect", "ci_low", "ci_high",
                       "p_value", "p_holm", "conclusion"]].to_string(index=False))
""")
business("t9")

# =============================================================================
md("""
## 10. Charts

Three simple charts for the report, saved as PNG to `reports/figures/`. Error bars are 95% CIs. Each title states the finding and the subtitle the population and n.
""")
code("""
INK, INK2, GRID, SURFACE = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"
BLUE, ORANGE = "#2a78d6", "#eb6834"
plt.rcParams.update({"font.size": 10, "axes.edgecolor": GRID, "axes.labelcolor": INK2,
                     "xtick.color": INK2, "ytick.color": INK2, "figure.facecolor": SURFACE,
                     "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE})


def style(ax):
    for side in ["top", "right", "left"]:
        ax.spines[side].set_visible(False)
    ax.tick_params(length=0)
    ax.set_axisbelow(True)


# --- Chart 1: bad-review rate by delay bucket ---
fig, ax = plt.subplots(figsize=(8, 4.8))
labels = [b.split(" ", 1)[1] for b in buckets["delay_bucket"]]
y = buckets["bad_rate_pct"].values
err = np.vstack([y - buckets["ci_low_pct"].values, buckets["ci_high_pct"].values - y])
ax.bar(labels, y, color=BLUE, width=0.6)
ax.errorbar(labels, y, yerr=err, fmt="none", ecolor=INK, elinewidth=1.2, capsize=4)
for i, (v, n) in enumerate(zip(y, buckets["reviewed_orders"])):
    ax.text(i, buckets["ci_high_pct"].iloc[i] + 1.5, f"{v:.1f}%", ha="center", color=INK, fontsize=10)
    ax.text(i, -6, f"n = {n:,}", ha="center", color=INK2, fontsize=8)
ax.set_ylim(-9, 100)
ax.set_yticks(range(0, 101, 20))
ax.yaxis.grid(True, color=GRID, linewidth=0.8)
ax.set_ylabel("Share of reviews that are 1-2 stars (%)")
ax.set_xlabel("Delivery vs promised date")
style(ax)
fig.suptitle("Late orders get far more 1-2 star reviews", x=0.02, ha="left", fontsize=13, color=INK, fontweight="bold")
ax.set_title(f"Reviewed in-window delivered orders, n = {len(rev):,}. Error bars: 95% Wilson CI.",
             loc="left", fontsize=9, color=INK2)
fig.tight_layout()
fig.savefig(FIG / "bad_review_rate_by_delay_bucket.png", dpi=150)
plt.close(fig)

# --- Chart 2: 180d repeat rate, on time vs late ---
fig, ax = plt.subplots(figsize=(6.5, 4.8))
grp = ["On-time first order", "Late first order"]
k = np.array([rep_on, rep_late]); n = np.array([n_on_c, n_late_c])
y = 100 * k / n
cis = [wilson_ci(a, b) for a, b in zip(k, n)]
err = np.vstack([y - [100 * lo for lo, _ in cis], [100 * hi for _, hi in cis] - y])
ax.bar(grp, y, color=[BLUE, ORANGE], width=0.5)
ax.errorbar(grp, y, yerr=err, fmt="none", ecolor=INK, elinewidth=1.2, capsize=4)
for i in range(2):
    ax.text(i, 100 * cis[i][1] + 0.08, f"{y[i]:.2f}%", ha="center", color=INK, fontsize=10)
    ax.text(i, -0.22, f"{k[i]:,} of {n[i]:,}", ha="center", color=INK2, fontsize=8)
ax.set_ylim(-0.35, 3)
ax.set_yticks([0, 0.5, 1, 1.5, 2, 2.5, 3])
ax.yaxis.grid(True, color=GRID, linewidth=0.8)
ax.set_ylabel("Bought again within 180 days (%)")
style(ax)
fig.suptitle("Repeat buying is low whether or not the first order was late", x=0.02, ha="left",
             fontsize=12, color=INK, fontweight="bold")
ax.set_title(f"180-day-eligible customers, n = {n.sum():,}. z-test p = {t2['p_value']:.2f}. Error bars: 95% Wilson CI.",
             loc="left", fontsize=9, color=INK2)
fig.tight_layout()
fig.savefig(FIG / "repeat_180d_on_time_vs_late.png", dpi=150)
plt.close(fig)

# --- Chart 3: Model A odds ratios (forest plot) ---
plot = or_a[or_a["term"] != "Intercept"].copy()


def nice(term):
    if term.startswith("C(category"):
        return "category: " + term.split("[T.")[1].rstrip("]")
    if term.startswith("C(state"):
        return "state: " + term.split("[T.")[1].rstrip("]")
    return {"is_late": "late first order (yes vs no)", "delivery_days": "delivery time (+1 day)",
            "freight_share_10pp": "freight share (+10 pp)",
            "np.log(order_value)": "log order value (+1 = x2.72 value)"}.get(term, term)


plot["label"] = plot["term"].map(nice)
plot["group"] = plot["term"].map(lambda t: 0 if not t.startswith("C(") else (1 if "category" in t else 2))
plot = plot.sort_values(["group", "odds_ratio"], ascending=[True, True]).reset_index(drop=True)
fig, ax = plt.subplots(figsize=(8, 0.28 * len(plot) + 1.6))
ypos = np.arange(len(plot))[::-1]
ax.hlines(ypos, plot["ci_low"], plot["ci_high"], color=BLUE, linewidth=2)
ax.plot(plot["odds_ratio"], ypos, "o", color=BLUE, markersize=6, markeredgecolor=SURFACE, markeredgewidth=1.5)
ax.axvline(1, color=INK2, linewidth=1, linestyle="--")
ax.set_xscale("log")
ax.set_xticks([0.1, 0.2, 0.5, 1, 2, 5])
ax.set_xticklabels(["0.1", "0.2", "0.5", "1", "2", "5"])
ax.minorticks_off()
ax.set_yticks(ypos)
ax.set_yticklabels(plot["label"], fontsize=8)
ax.xaxis.grid(True, color=GRID, linewidth=0.8)
ax.set_xlabel("Odds ratio for 180-day repeat (log scale; 1 = no association)")
style(ax)
fig.suptitle("Model A: first-order category matters more than lateness", x=0.02, ha="left", fontsize=12,
             color=INK, fontweight="bold")
ax.set_title(f"Logistic regression, 180-day-eligible customers, n = {int(res_a.nobs):,}; McFadden pseudo R2 = {res_a.prsquared:.3f}.\\n"
             f"Bars: 95% CI. Reference levels: category {ref_cat}, state {ref_state}.", loc="left", fontsize=8, color=INK2)
fig.tight_layout()
fig.savefig(FIG / "logit_model_a_odds_ratios.png", dpi=150)
plt.close(fig)

print(sorted(p.name for p in FIG.glob("*.png")))
""")


def build() -> None:
    nb = nbf.v4.new_notebook()
    nb.metadata = {
        "kernelspec": {"display_name": "Python 3.11 (olist .venv)", "language": "python", "name": "olist-venv"},
        "language_info": {"name": "python"},
    }
    nb.cells = [nbf.v4.new_markdown_cell(t) if kind == "md" else nbf.v4.new_code_cell(t)
                for kind, t in cells]
    nbf.write(nb, NB_PATH)
    print(f"wrote {NB_PATH} ({len(nb.cells)} cells)")


if __name__ == "__main__":
    build()
