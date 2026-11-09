# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## Project

Modeling the Federal Funds target and FOMC policy decisions from macroeconomic
and financial indicators. It started as a graduate course group project
(Inuk Baik, Asal Delkhosh, Zihong Xiong, submitted 2026-04-22) and is being
turned into a portfolio project by Inuk Baik.

Don't name the course, course number, or group number in any tracked file,
commit message, or tag. Refer to it as "the course project".

The original submission has three research questions in `fomc_policy_analysis.Rmd`:

| Section | Question | Method | Owner |
|---|---|---|---|
| RQ1 | How does the target relate to macro variables, and is that stable over time? | OLS, rolling coefficients, Bai-Perron breakpoints, Chow tests | teammate |
| RQ2 | Can macro conditions be grouped into regimes? | PCA + k-means | teammate |
| RQ3 | Using only pre-meeting information, how do model families compare at predicting cut / hold / hike? (A fair comparison, not a race for the best forecast.) | multinomial logit, elastic net, RF, XGBoost, expanding-window evaluation | Inuk |

Note: inside the notebook the object names are swapped (`data_rq2` holds the RQ1
data, `data_rq1` the RQ2 data). Don't "fix" one without the other.

## Layout

| File | What it does |
|---|---|
| `R/acquire_data.R` | Scrapes the FOMC calendar from federalreserve.gov (`rvest`) and pulls FRED series (`fredr`). Writes the four files in `data/`. |
| `data/fomc_meetings.csv` | One row per FOMC event: `start_date`, `decision_date`, `type` (scheduled, unscheduled_meeting, conference_call, notation_vote, cancelled), `is_scheduled`, `has_sep`. Includes future scheduled meetings. |
| `data/fed_target_daily.csv` | Daily target: DFEDTAR until 2008-12-15, then the midpoint of DFEDTARL/DFEDTARU (`lower`, `upper` kept). Use this for meeting-level labels. |
| `data/macro_monthly.csv` | Monthly panel: monthly-average target, `policy_change`, monthly FRED series, and daily/weekly series averaged locally. |
| `data/market_daily.csv` | Daily market series kept daily (`DGS2`), for the RQ3 market-signal baseline. |
| `fomc_policy_analysis.Rmd` | Cleaning, feature engineering, EDA, RQ1–RQ3. Reads `data/macro_monthly.csv` and `data/fomc_meetings.csv`. |
| `reports/`, `figures/` | Original PDFs and plots. Git-ignored, local only. |

All `*.csv` files are git-ignored. Data is fetched, not committed. The
original acquisition notebooks (`data_acq.Rmd`, `variable_acquisition.Rmd`) and
the old root-level CSVs belong to tag `v1.0-course-submission`.

## Running

- R 4.6. Packages are pinned with renv. After cloning, run
  `Rscript -e 'renv::restore()'` once. After adding a package, run
  `renv::snapshot()` and commit `renv.lock`.
- renv quirk: `recipes` (a caret dependency, from CRAN) has a `biocViews`
  field, so renv mistakes it for Bioconductor and `renv::snapshot()` aborts.
  Snapshot with `force = TRUE`, then put it back as CRAN:
  `renv::record(list(recipes = list(Package = "recipes", Version = "<ver>", Source = "Repository", Repository = "CRAN")))`,
  and delete any top-level `"Bioconductor"` block from `renv.lock`.
  `renv::status()` still lists `recipes` as out of sync; that's harmless.
- Fetch data: `Rscript R/acquire_data.R` (about a minute). Needs a FRED API key:
  `cp .env.example .env`, then set `FRED_KEY`. The script stops if any FOMC
  heading fails to parse.
- Render a notebook with `Rscript -e 'rmarkdown::render("fomc_policy_analysis.Rmd")'`.
  rmarkdown doesn't find Quarto's bundled pandoc on its own; set
  `RSTUDIO_PANDOC=/Applications/quarto/bin/tools/aarch64` for the command.
- **Don't run the full notebook just to check a change.** The two slow RQ3
  chunks (`rq3-holdout`, `rq3-rolling`, ~2.5 of ~3 min) are cached by knitr
  and keyed on `rq3_inputs_hash` (data, settings, tuning/metric functions,
  package versions). Renders re-run them only when one of those changes.
  The cache lives in `fomc_policy_analysis_cache/` (git-ignored). Delete it to
  force a full re-run.
- For checks outside RQ3, run only the part you changed: `knitr::purl()` the
  notebook and source up to the section you need.
- Run anything that re-fits the RQ3 models in the background.
- `xgboost` 3.x is installed locally; its R API changed from 1.x. Check version
  differences before touching XGBoost code.

## Rules

- **Never commit secrets.** `.env` holds `FRED_KEY` and stays ignored. Never print
  the key or put it in a URL that gets logged or rendered.
- **Don't commit data.** Some FRED series carry redistribution limits. Fetch at
  build time. ICE BofA series (e.g. `BAMLH0A0HYM2`) are limited to ~3 years on
  FRED, so don't use them.
- **FRED data gets revised.** Re-fetching changes past values (PCE, JOLTS,
  payrolls; ANFCI is re-estimated weekly), so results can shift slightly
  between pulls.
- **No look-ahead.** Any predictor for meeting *t* must be information available
  before meeting *t*. Respect release lags (PCE for month m comes out near the end
  of month m+1) and prefer real-time vintages (ALFRED) once the pipeline supports them.
- **Time-ordered evaluation only.** No random CV splits on time-series data,
  including inside `cv.glmnet` (pass `foldid`).
- **Don't hardcode positions or dates derived from the data** (for example
  `df$date[c(198, 274, 387)]`). Compute them, so the report survives a data refresh.
- Keep the original submission reproducible. It is tagged `v1.0-course-submission`
  (commit `2b1f27f`). Improvements go on top of it, not in place of its history.
- Credit teammates for their sections in any published output.

## Analysis decisions

Settled choices that code changes must respect. The notebook text explains
each one to readers; keep the two in sync.

- **RQ3 unit = one scheduled FOMC meeting** (decided 2026-11-08). Conference
  calls and unscheduled meetings are excluded because (1) they react to sudden
  shocks that lagged monthly data can't see, so every model misses them for
  the same reason and they only add noise to the comparison; (2) whether an
  emergency call happens is itself a stress signal, which changes what is
  being predicted; (3) scheduled meetings happen on known dates, matching the
  question of comparing models on each regular decision. Emergency moves stay
  in the target series and may become a predictor later.
- **RQ3 label = target `LABEL_WINDOW_DAYS` (2) days after the decision minus
  target the day before the meeting starts**, from `data/fed_target_daily.csv`.
  Changes often take effect the next day, hence the window. Intermeeting moves
  by the Chair (26 of 150 changes since 1986, all 1986–1992) belong to no
  meeting and are not attributed to one. Never label from the monthly-average
  target: it mislabelled about 20% of meetings.
- **Breaks (RQ1) = 3 and k (RQ2) = 3 are settings**, not data-driven, until C4
  and C5 fix the methods (BIC hits its cap; silhouette is flat).
- **Missing values inside a series**: carry the last value forward, one month
  at most (no look-ahead).
- **RQ3 scoring** (decided 2026-11-08): macro-F1 where a class that occurs
  but is never predicted correctly scores F1 = 0 (never drop it with
  `na.rm`); ties broken by balanced accuracy (mean class recall). Rank on
  the pooled out-of-sample predictions of all expanding-window folds, with a
  moving-block bootstrap for intervals. The 80/20 split does not rank models.
  Tuning uses the same score.
- **RQ3 tuning is time-ordered everywhere**: every model, including elastic
  net's lambda, is tuned on the last block of its training window. No
  `cv.glmnet` random folds. Each model is fit from seed `RQ3_SEED + fold`.
- **RQ3 predictors = data published before the meeting starts**, using
  `RELEASE_DELAY_DAYS` (cautious approximations, until ALFRED in D3).
- **Class weights are a tuning setting** (user decision 2026-11-08): fixed
  inverse-frequency weights lowered macro-F1 for every model, so each model's
  validation block picks weighted or unweighted.
- **RQ3 baselines**: always hold, same as last meeting, and a 2-year-yield
  market signal. Models are judged against the best baseline.

## Git conventions

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <imperative summary, lowercase, no period, ≤ 72 chars>

<optional body: what and why, wrapped at 72>

<optional footer: BREAKING CHANGE: ..., Refs: #12>
```

Types:

| Type | Use for |
|---|---|
| `feat` | new analysis, model, feature, or report section |
| `fix` | bug fix (wrong label, leakage, broken code) |
| `data` | data acquisition or source changes |
| `refactor` | restructuring with no change in results |
| `perf` | faster runs with identical results |
| `docs` | README, CLAUDE.md, comments, narrative text |
| `style` | formatting only |
| `test` | tests and validation checks |
| `build` | renv, dependencies, render config |
| `ci` | GitHub Actions and scheduled jobs |
| `chore` | anything else (gitignore, housekeeping) |

Scopes: `acq`, `clean`, `features`, `eda`, `rq1`, `rq2`, `rq3`, `ts`, `report`, `pipeline`.

Examples:

```
fix(rq3): label decisions from meeting-date target, not monthly average
feat(ts): add ordered probit with lagged decision
data(acq): generate fed_meetings.csv from the scraper
build: add renv lockfile
```

Also:

- One logical change per commit. Separate a refactor from a result-changing fix.
- If a commit changes model results, say how in the body (old vs new metric).
- Branch names: `<type>/<short-description>`, e.g. `fix/rq3-labels`.
- Don't commit to `main` directly for non-trivial work. Use a branch and PR.

## Decisions

Status of the portfolio decisions. Update this when one is settled.

The full ordered task list lives in `TODO.md` (git-ignored, local only). Work
it top to bottom, one item at a time: bring the user only the current item,
and mark it done with a one-line outcome before moving on.

| Decision | Status | Current direction |
|---|---|---|
| Static vs. reproducible / refreshed report | decided | Reproducible: one command rebuilds everything from raw data; publishing is manual. Scheduled refresh and prediction tracker deferred (optional later) |
| Output format | decided | Quarto website on GitHub Pages: Home, The rule, The regimes, The prediction, Appendix. Code folded by default; `freeze` enabled for slow chunks |
| Time-series extension of RQ3 | open | Meeting-level dynamic models (ordered probit with lagged decision, autoregressive conditional hazard) plus a monthly rate-path model (VAR / BVAR / local projections). Data is too small for deep sequence models |
| Fixes to teammates' RQ1/RQ2 | approved | Teammates agreed to public MIT release and to changes, marked as Inuk's |
| Narrative structure | decided | Data science portfolio. One question, "How does the Fed set rates, and can we predict its next move?", in three connected chapters: the rule (RQ1), the regimes (RQ2), the prediction (RQ3, headline). RQ1 break dates set RQ3 training windows; RQ2 regime labels are an RQ3 feature, fit per fold on training data only |
