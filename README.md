# How Does the Fed Set Rates, and Can We Predict Its Next Move?

Modeling Federal Open Market Committee (FOMC) policy decisions (cut, hold
or hike) from economic and market data, with a fair, look-ahead-free
comparison of model families.

**Read the report:** <https://inukbaik.github.io/fomc-policy-modeling/>

## Findings

- Across 126 scheduled FOMC meetings (December 2010 to September 2026),
  each predicted only from information available before it, the best
  models reach a macro-F1 of about 0.71, against 0.65 for simply
  repeating the last decision. No model beats that rule by a margin the
  bootstrap can separate from luck.
- What makes the models competitive is information about the Fed itself
  (its previous decision, where rates are, what markets expect), not
  lagged economic data. With economic data alone, every model lost to
  "same as last meeting".
- A two-step hazard model with six inputs fixed in advance ("will they
  move?", then "which way?") matches the best tuned machine-learning
  model.
- Training on all meetings since 1986 clearly beats a rolling 15-year
  window for five of six models.

Numbers are from the current data pull; FRED revisions can shift them
slightly. The site computes them on every build.

## What's inside

| Chapter | Question | Methods |
|---|---|---|
| The data | What goes in? | FRED series and the FOMC calendar, cleaning, publication delays |
| The rule (RQ1) | How does the target relate to the economy, and has that changed? | Regression, rolling coefficients, structural breaks |
| The regimes (RQ2) | Do macro conditions fall into distinct regimes? | PCA, k-means |
| The prediction (RQ3) | How do model families compare at predicting the next decision? | Multinomial logit, elastic net, random forest, XGBoost, ordered probit, hazard model; expanding-window evaluation with block bootstrap |

Methods that keep the comparison honest:

- **No look-ahead:** every predictor was published before the meeting
  (publication delays per series); models train only on earlier meetings.
- **Time-ordered everything:** expanding-window evaluation, tuning on the
  last block of each training window, no random cross-validation.
- **A score that can't be gamed by always predicting "hold":** macro-F1
  where a class that is never predicted counts as zero.
- **Baselines:** always hold, same as last meeting, and a 2-year-yield
  market signal.

## Reproduce

Requires R 4.6, [Quarto](https://quarto.org) and a free
[FRED API key](https://fred.stlouisfed.org/docs/api/api_key.html).

```bash
Rscript -e 'renv::restore()'      # install pinned package versions
cp .env.example .env              # then set FRED_KEY in .env
Rscript R/acquire_data.R          # fetch data into data/ (about a minute)
quarto render                     # build the site into _site/ (~2 min first time)
```

Data is fetched at build time and never committed (some FRED series have
redistribution limits).

| Path | Contents |
|---|---|
| `R/acquire_data.R` | Scrapes the FOMC calendar and pulls FRED series |
| `R/settings.R`, `R/prepare_data.R` | Shared settings and data preparation |
| `index.qmd`, `data.qmd`, `rule.qmd`, `regimes.qmd`, `prediction.qmd`, `changes.qmd` | Site pages |
| `renv.lock` | Pinned package versions |

## History and credits

This started as a graduate course group project (April 2026). The
original submission is preserved as the tag
[`v1.0-course-submission`](https://github.com/inukbaik/fomc-policy-modeling/tree/v1.0-course-submission).
The rule and the regimes are the course-project teammates' original
chapters, kept as submitted with notes on known limitations. The data
pipeline and the prediction chapter were rebuilt and extended by Inuk
Baik; the site's [What changed](https://inukbaik.github.io/fomc-policy-modeling/changes.html)
page lists every change and its effect.

## License

MIT. See [LICENSE](LICENSE).
