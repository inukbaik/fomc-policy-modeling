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
| RQ3 | Can the meeting decision (cut / hold / hike) be predicted? | multinomial logit, elastic net, RF, XGBoost, expanding-window evaluation | Inuk |

Note: inside the notebook the object names are swapped (`data_rq2` holds the RQ1
data, `data_rq1` the RQ2 data). Don't "fix" one without the other.

## Layout

| File | What it does |
|---|---|
| `data_acq.Rmd` | Scrapes FOMC meeting dates from federalreserve.gov and pulls DFEDTAR/DFEDTARL/DFEDTARU via `quantmod`; writes `fomc_target_1982_2026M03_meeting_rows.csv`. Not currently used by the analysis. |
| `variable_acquisition.Rmd` | Pulls the monthly FRED panel through the FRED API (needs `FRED_KEY`); writes `fred_raw_monthly_dataset.csv` / `fed_funds_raw.csv` and `WTISPLC.csv`. |
| `fomc_policy_analysis.Rmd` | Cleaning, feature engineering, EDA, RQ1–RQ3. Reads `fed_funds_raw.csv`, `WTISPLC.csv`, `fed_meetings.csv`. |
| `fed_meetings.csv` | Meeting dates + scheduled flag. **No script in the repo produces it** (dates look like meeting start dates). |
| `reports/`, `figures/` | Original PDFs and plots. Git-ignored, local only. |

All `*.csv` files are git-ignored. Data is fetched, not committed.

## Running

- R 4.6. Render a notebook with `Rscript -e 'rmarkdown::render("fomc_policy_analysis.Rmd")'`.
- Acquisition needs a FRED API key: `cp .env.example .env`, then set `FRED_KEY`.
- The RQ3 expanding-window loop refits four tuned models per fold and takes a while.
  Run long renders in the background.
- `xgboost` 3.x is installed locally; its R API changed from 1.x. Check version
  differences before touching XGBoost code.

## Rules

- **Never commit secrets.** `.env` holds `FRED_KEY` and stays ignored. Never print
  the key or put it in a URL that gets logged or rendered.
- **Don't commit data.** Some FRED series (ICE BofA `BAMLH0A0HYM2`) carry
  redistribution limits. Fetch at build time.
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
| Static vs. reproducible / refreshed report | open | Reproducible pipeline that re-renders on a schedule (after each FOMC meeting), not a live server app |
| Output format | open | Quarto (`.qmd`) rendered to HTML, published with GitHub Pages; keep PDF export available |
| Time-series extension of RQ3 | open | Meeting-level dynamic models (ordered probit with lagged decision, autoregressive conditional hazard) plus a monthly rate-path model (VAR / BVAR / local projections). Data is too small for deep sequence models |
| Fixes to teammates' RQ1/RQ2 | approved | Teammates agreed to public MIT release and to changes, marked as Inuk's |
| Narrative structure | open | One headline question (predicting FOMC decisions), with RQ1/RQ2 as supporting sections |
