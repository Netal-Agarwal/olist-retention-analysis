# Phase 5: Review-impact SQL and statistical tests

**Files:** `sql/10_review_impact.sql`, `notebooks/03_statistical_tests.ipynb` (built by `notebooks/build_03_statistical_tests.py`), `outputs/phase5/`, `reports/figures/`, `docs/claims_evidence.md`.

**Business question:** Phase 4 suggested two levers. (1) Retention is structural, so Olist needs active re-engagement. (2) Delivery reliability is a reputation lever. Phase 5 asks: do these claims survive a proper statistical test, and how many bad reviews does lateness account for?

---

## Part A: the review-impact SQL (`sql/10_review_impact.sql`)

**Bad review** = score 1 or 2. **Excess bad reviews** compares what happened with what we would expect:

> excess = bad reviews on late orders − (late reviewed orders × the group's on-time bad-review rate)

Example (Olist overall, `q10_05`): 6,378 late reviewed orders. At the on-time rate of 9.25% we would expect 589.8 bad reviews; they actually got 3,981. Excess = 3,391.2, which is 27.73% of all 12,228 bad reviews.

**Why each group's own baseline?** Customers in some states (or of some sellers) are harsher in general. Using the group's own on-time rate means we only count the *extra* badness that goes with lateness. Consequence: group excesses do not add up to the national total, and a group can be negative. That is why the shares use the national excess as one common base.

**SQL patterns used:** the same `reviewed` CTE at the start of every query (one population definition); `count(*) filter (where …)` to count several subgroups in one pass; `nullif(x, 0)` against division by zero; `rank()` for states (ties share a rank) and `row_number()` for sellers and routes (exactly 20 / 15 rows); `sum(...) over (order by rank)` for a running cumulative share; window sums computed **before** the top-20 filter, so shares use all qualifying sellers.

**Quality checks:** two new checks recompute the reviewed and bad-review counts straight from `clean.orders` ⋈ `clean.order_reviews`. They confirm that on-time + late = all (95,560 and 12,228), so no order is lost or counted twice. 64/64 checks pass.

---

## Part B: statistics concepts, each tied to the notebook

### 1. Hypothesis testing
We start from a **null hypothesis (H0)**: "no difference" (e.g. late and on-time customers repeat at the same rate). A test asks: *if H0 were true, how surprising would data like ours be?* If very surprising (p < alpha = 0.05), we **reject H0**. If not, we **fail to reject H0**, which is not the same as proving H0. **Two-sided** means we would count a difference in either direction as evidence; we did not decide the direction in advance. *(Every section of the notebook states its H0.)*

### 2. p-value
The probability of getting a difference at least as big as ours **if H0 were true**. It is **not** the probability that H0 is true, and it says nothing about how big or important the effect is. *(§2: p = 0.062 for late vs repeat, just above 0.05.)*

### 3. Confidence intervals (CI)
A 95% CI is a range of plausible values for the true effect. If we repeated the study many times, 95% of such intervals would contain the true value. A CI that includes 0 (for a difference) or 1 (for a ratio) matches "not significant". Its **width** shows precision. *(§2: difference −0.43 pp, CI −0.80 to +0.02, which includes 0 but also allows a fairly large drop.)* Methods: **Wilson** for one rate and **Newcombe** for a difference. Both stay sensible near 0% (our repeat rates are ~2%), where the textbook "± 1.96 × SE" can give negative limits.

### 4. Effect size vs significance
With 95,560 orders, even trivial differences become "significant". With 62 late repeaters, real differences can fail to. So we always report **how big**: a difference in percentage points, a relative risk, an odds ratio, Cramér's V or a rank-biserial r. *(§8: the category differences are highly significant, p = 4.8e-07, but Cramér's V is only 0.037: real, yet small.)*

### 5. Statistical power and minimum detectable effect (MDE)
**Power** = the chance a test detects an effect *if it is real*. It depends on effect size, sample size and alpha. **MDE** = the smallest true effect detectable with 80% power. *(§4: MDE ≈ 0.60 pp; the observed gap is 0.43 pp; power for that gap was 50%.)* So "not significant" here means "a big effect is unlikely; a small one is possible". It never simply means "no effect". We used **Cohen's h** (an arcsine transform of the rates) because statsmodels' power functions for proportions work on that scale.

### 6. Chi-square test of independence
For counts in a table (e.g. late/on-time × bad/not bad). It compares observed counts with the counts expected if the two variables were unrelated. It needs reasonably large expected counts (rule of thumb ≥ 5; our smallest was 6.5). We skipped **Yates' correction** because it only matters for small counts. *(§1 T1: chi-square 15,080; §5, §8.)*

### 7. Two-proportion z-test
Compares two rates using a normal approximation and the pooled rate under H0. Same idea as a 2×2 chi-square (for 2×2, z² = chi-square without correction). *(§2, §6a.)*

### 8. Fisher's exact test
Calculates the exact probability of the 2×2 table from the fixed row and column totals, with no normal approximation. It is useful when a cell is small. *(§2: 62 late repeaters; Fisher p = 0.065 agrees with z-test p = 0.062, so the approximation was fine.)*

### 9. Cochran–Mantel–Haenszel (CMH)
Tests an association **within strata** (here, product categories) and pools them into one **Mantel–Haenszel odds ratio**. It controls for a **confounder** by comparing like with like. **Zero cells:** the MH OR is Σ(ad/n) / Σ(bc/n), so a category with 0 late repeaters still contributes and no continuity correction is needed. **Breslow–Day** tests whether the OR is the same in every stratum. *(§3: MH OR 0.808 vs crude 0.814, so category was not confounding; Breslow–Day p = 0.905.)*

### 10. Mann–Whitney U
Compares two groups' distributions by ranks, not means. It suits skewed data like delivery days (a long tail of very slow orders would pull a mean around). Effect size: **rank-biserial r** = 2U/(n₁n₂) − 1. *(§6: medians 12.78 vs 6.52 days; r = 0.597; a random cross-state order is slower than a random same-state one about 80% of the time.)*

### 11. Multiple comparisons and Holm
Run 15 tests at alpha 0.05 and the chance of at least one false positive is far above 5%. **Holm** sorts p-values and compares the smallest with 0.05/15, the next with 0.05/14, and so on, stopping at the first failure. It controls the family-wise error rate like Bonferroni but rejects more often when effects are real. *(§9: the review-score trend p = 0.012 becomes 0.12; state differences p = 0.021 become 0.19; neither survives.)* The same logic applies when reading top/bottom-10 lists: some groups are extreme by chance.

### 12. Logistic regression and odds ratios
For a yes/no outcome. It models the **log-odds** of the outcome as a straight-line combination of predictors. exp(coefficient) = **odds ratio**: how the odds change per one unit, **holding the other predictors fixed**. Odds = p / (1 − p). At 2% rates, odds and probabilities are almost equal, so OR ≈ relative risk. **McFadden pseudo R²** compares the model's fit with an intercept-only model. Values of 0.2–0.4 are considered good fit; ours is 0.011, meaning the predictors barely help predict who comes back. *(§7: freight share OR 1.13 per +10 pp; delivery time OR 0.892 per extra week; is_late not significant.)* **Collinearity:** is_late and delivery_days correlate at 0.63, so is_late's OR means "late vs on time at the same delivery time". VIFs under 2.1 show the estimates are still stable.

### 13. Mediators vs confounders
- A **confounder** causes both the factor and the outcome (e.g. category might affect both lateness and rebuying). You **should** adjust for it.
- A **mediator** sits on the path from factor to outcome: late → bad review → no return. Adjusting for it **removes part of the effect** you are trying to measure.
So Model A (no review) gives the total association of lateness, and Model B (with review) gives what is left after the review. *(§7: is_late OR 1.14 → 1.20 and review block LR p = 0.223, so no sign of mediation.)*

### 14. Correlation vs causation
Every result here is an association in observational data. Late orders differ from on-time orders in other ways (route, seller, product size, season), and we cannot rule out all of them. Strong, dose-response patterns (the bad-review rate climbs with each delay bucket) make a causal reading of lateness → bad reviews plausible. Only an experiment (e.g. randomly upgrading shipping for some orders) would prove it.

---

## Results summary (from `outputs/phase5/test_results.csv` and `q10_*`)

| Finding | Number |
|---|---|
| Bad-review rate late vs on time | 62.42% vs 9.25% (gap 53.17 pp, CI 51.96–54.37; RR 6.75) |
| Excess bad reviews (ESTIMATE) | 3,391.2 = 27.73% of all bad reviews |
| Top states by excess | RJ 905.4 (26.70%), SP 815.0 (24.03%) |
| Top route by excess | SP → RJ 714.2 (21.06%) |
| 180d repeat late vs on time | 1.58% vs 2.01%, diff −0.43 pp (CI −0.80 to +0.02), p = 0.062 |
| Within categories (CMH) | MH OR 0.808 (0.621–1.051), p = 0.111 |
| Power for observed gap / MDE | 50% / about 0.60 pp |
| 5★ customers' 180d repeat | 2.12% (CI 1.97–2.28) |
| Cross vs same state late rate | 8.07% vs 4.51% (diff 3.55 pp); median days 12.78 vs 6.52 |
| Logistic is_late OR (A / B) | 1.14 (0.81–1.60) / 1.20 (0.84–1.71) |
| Pseudo R² (A / B) | 0.011 / 0.012 |
| Significant after Holm | 5 of 15 tests |

---

## Interview questions (with model answers)

**1. Your late customers repeated at 1.58% vs 2.01%. Why don't you say lateness hurts retention?**
The gap is −0.43 points with a 95% CI from −0.80 to +0.02, and p = 0.062 (Fisher 0.065). So it is not significant at 0.05. Within product categories, the Mantel–Haenszel odds ratio was 0.808 with a CI crossing 1, and in the logistic regression lateness was not significant either. I don't say "no effect", though: the power analysis showed only 50% power for a gap that size. My honest statement is that a large effect is unlikely, and that even the full observed gap would be worth only about 17 extra repeaters (the Phase 4 estimate).

**2. What is the difference between "not significant" and "no effect"?**
Not significant means the data are compatible with no effect. It does not show the effect is zero. Here the minimum detectable gap at 80% power was about 0.60 points, while the observed gap was 0.43, so a real effect of that size would be missed half the time. That is why I report the confidence interval: it shows which effect sizes are still plausible.

**3. How much do late deliveries hurt reviews?**
Late orders got 1–2 stars 62.42% of the time vs 9.25% on time: 6.75 times as often, with a CI of 6.56 to 6.94. Even 1–3 days late gives 32%. I estimated about 3,391 excess bad reviews, 27.73% of all bad reviews in the window. That assumes late orders would otherwise have been reviewed like on-time ones, so it is labelled as an estimate.

**4. Why did you use a Mantel–Haenszel test?**
Category could be a confounder: pet food is rebought more than furniture, and categories may differ in how often they arrive late. CMH compares late and on-time customers within each category and pools the result. The pooled odds ratio (0.808) was almost the same as the crude one (0.814), so category mix was not distorting the comparison. Categories with zero late repeaters still count, because the MH estimator is a ratio of sums across strata.

**5. You ran 15 tests. How did you handle multiple comparisons?**
I applied the Holm correction across the whole family. It's less strict than Bonferroni but still controls the chance of any false positive. Two results that looked significant on their own did not survive: the review-score trend went from 0.012 to 0.12, and state differences went from 0.021 to 0.19. Five tests stayed significant: lateness and bad reviews, cross-state lateness and delivery time, freight share in the model, and category differences.

**6. Your logistic regression has a pseudo R² of 0.011. Isn't that a bad model?**
For prediction, yes. For the business question, it's the finding. Everything we know about the first order (lateness, speed, freight, value, category, state, review) explains almost none of who comes back. That supports the claim that low retention is structural, not caused by a bad first experience, so the lever is active re-engagement rather than fixing the first order.

**7. Why did you fit the model with and without the review score?**
The review sits between lateness and repeating: late → bad review → maybe no return. That makes it a mediator, not a confounder. Controlling for a mediator removes part of the effect you want to measure. So Model A gives the total association of lateness, and Model B shows what's left after the review. The lateness odds ratio barely moved (1.14 to 1.20) and the review terms together were not significant (LR p = 0.223), so there was no sign of a lateness effect running through reviews.

**8. Freight share came out significant. Does that mean high shipping costs matter?**
Not in the way people expect. The odds ratio was 1.13 per +10 points of freight share, which is positive: holding order value, category and state fixed, a higher freight share went with slightly more repeat buying. The raw rates by freight band were flat (1.82–2.19%). So there's no evidence that freight deters customers. The positive adjusted link probably reflects what kind of basket it is, and I wouldn't use it to justify raising freight.
