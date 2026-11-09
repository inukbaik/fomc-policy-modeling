# Load, clean and build features for the monthly panel (df_clean, df_final).
# Every page sources this file after R/settings.R. index.qmd displays each
# section next to its explanation (knitr::read_chunk), so the code lives
# only here. Printed values are shown on the index page only.

## ---- load ----
set.seed(597)
# Produced by R/acquire_data.R
df_raw <- read.csv("data/macro_monthly.csv")

dim(df_raw)
colnames(df_raw)
head(df_raw)

## ---- fix-types ----
df_clean <- df_raw %>%
  mutate(date = as.Date(date))

## ---- sample-end ----
# Sample end: the last month in which every series has been published.
# Series are released with different delays, so later months are incomplete.
series_cols <- setdiff(names(df_clean), "date")

last_obs <- sapply(series_cols, function(col) {
  max(df_clean$date[!is.na(df_clean[[col]])])
})
SAMPLE_END <- as.Date(min(last_obs))

sort(as.Date(last_obs))  # last available month per series

df_clean <- df_clean %>%
  filter(date <= SAMPLE_END)

## ---- fill-gaps ----
# Fill short gaps inside a series (e.g. October 2025, when the government
# shutdown stopped some releases) by carrying the last value forward.
# Carrying forward never uses later data, so it adds no look-ahead.
# Leading NAs (before a series starts) are left alone.
before <- df_clean

df_clean <- df_clean %>%
  arrange(date) %>%
  mutate(across(
    all_of(series_cols),
    ~ zoo::na.locf(.x, na.rm = FALSE, maxgap = MAX_GAP_FILL)
  ))

filled <- map_dfr(series_cols, function(col) {
  idx <- which(is.na(before[[col]]) & !is.na(df_clean[[col]]))
  tibble(series = col, date = before$date[idx], filled_with = df_clean[[col]][idx])
})
filled

## ---- derived ----
df_clean <- df_clean %>%
  arrange(date) %>%
  mutate(
    core_pce_yoy      = 100 * (PCEPILFE / lag(PCEPILFE, 12) - 1),
    unrate_lag1       = lag(UNRATE, 1),
    payems_yoy        = 100 * (PAYEMS / lag(PAYEMS, 12) - 1),
    term_spread_10y_3m = DGS10 - DGS3MO,
    inflation_gap     = core_pce_yoy - 2
  )

## ---- fomc-counts ----
# Produced by R/acquire_data.R. Keep meetings and conference calls; drop
# notation votes and the cancelled March 2020 meeting. `date` is the first day
# of the meeting, as in the original fed_meetings.csv.
fomc_meetings <- read.csv("data/fomc_meetings.csv") %>%
  filter(!type %in% c("cancelled", "notation_vote")) %>%
  mutate(date = as.Date(start_date))

fomc_monthly <- fomc_meetings %>%
  mutate(month = as.Date(format(date, "%Y-%m-01"))) %>%
  group_by(month) %>%
  summarise(
    fomc_meetings    = n(),
    fomc_scheduled   = sum(is_scheduled, na.rm = TRUE),
    fomc_unscheduled = sum(!is_scheduled, na.rm = TRUE),
    .groups = "drop"
  )

df_clean <- df_clean %>%
  mutate(month = as.Date(format(date, "%Y-%m-01"))) %>%
  left_join(fomc_monthly, by = "month") %>%
  mutate(
    fomc_meetings    = dplyr::coalesce(fomc_meetings, 0),
    fomc_scheduled   = dplyr::coalesce(fomc_scheduled, 0),
    fomc_unscheduled = dplyr::coalesce(fomc_unscheduled, 0)
  )

## ---- fomc-timing ----
fomc_dates <- fomc_meetings %>%
  arrange(date)

df_clean <- df_clean %>%
  rowwise() %>%
  mutate(
    days_since_last_fomc = as.numeric(date - max(fomc_dates$date[fomc_dates$date < date]))
  ) %>%
  ungroup() %>%
  select(-month)

## ---- final ----
df_final <- df_clean %>%
  filter(date >= SAMPLE_START)
