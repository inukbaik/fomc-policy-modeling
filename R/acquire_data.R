# Data acquisition: FOMC meeting calendar + FRED series.
#
# Run from the project root:   Rscript R/acquire_data.R
# Needs FRED_KEY in .env (copy .env.example).
#
# Writes to data/ (git-ignored):
#   fomc_meetings.csv     one row per FOMC event (meetings, calls, votes)
#   fed_target_daily.csv  daily fed funds target (point target, then range midpoint)
#   macro_monthly.csv     monthly panel used by the analysis
#   market_daily.csv      daily market series (market-signal baseline, RQ3)

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
  library(tidyr)
  library(lubridate)
  library(readr)
  library(rvest)
  library(fredr)
})

# ---- Config ------------------------------------------------------------------

START_DATE <- as.Date("1982-01-01")
OUT_DIR    <- "data"

# Date when the Fed switched from a point target to a target range.
RANGE_START <- as.Date("2008-12-16")

# Series already published monthly.
MONTHLY_SERIES <- c(
  "PCEPI", "PCEPILFE",               # PCE price index, headline and core
  "MICH",                            # Michigan 1-year inflation expectations
  "UNRATE", "PAYEMS",                # unemployment rate, payrolls
  "JTSJOL", "JTSQUR",                # JOLTS openings, quits rate
  "INDPRO", "HOUST", "RRSFS",
  "WTISPLC"                          # WTI spot price (monthly, longer history)
)

# Daily or weekly series, averaged to monthly by FRED.
AVERAGED_SERIES <- c(
  "T5YIE",                           # 5-year breakeven inflation
  "DGS3MO", "DGS2", "DGS10", "T10Y3M",
  "BAA10Y",                          # Baa corporate minus 10y Treasury spread
  # BAMLH0A0HYM2 (ICE BofA high-yield spread) dropped: FRED now serves only
  # ~3 years of it under ICE licensing, so it can't support the 1986+ sample.
  "ANFCI",                           # Chicago Fed adjusted financial conditions
  "DTWEXBGS"                         # broad dollar index
)

# Daily series kept at daily frequency, so a meeting can use the value on
# the day before it starts.
DAILY_SERIES <- c("DGS2")                # 2-year Treasury yield

# Not fetched: PCEC96 (real consumption, starts 2007) and DCOILWTICO (daily WTI,
# starts 1986). WTISPLC covers oil with a longer history.

# ---- FRED --------------------------------------------------------------------

set_fred_key <- function(env_file = ".env") {
  if (file.exists(env_file)) readRenviron(env_file)
  key <- Sys.getenv("FRED_KEY")
  if (key == "") stop("FRED_KEY not set. Copy .env.example to .env and add your key.")
  fredr_set_key(key)
}

fetch_series <- function(id, start = START_DATE, monthly_avg = FALSE) {
  obs <- fredr(series_id = id, observation_start = start) %>%
    filter(!is.na(value)) %>%
    select(date, value)
  # Average locally rather than with FRED's aggregation_method = "avg":
  # FRED rounds the result to 2 decimals and buckets weekly series differently.
  if (monthly_avg) {
    obs <- obs %>%
      group_by(date = floor_date(date, "month")) %>%
      summarise(value = mean(value), .groups = "drop")
  }
  rename(obs, !!id := value)
}

build_target_daily <- function() {
  point <- fetch_series("DFEDTAR") %>% rename(target = DFEDTAR)
  lower <- fetch_series("DFEDTARL", start = RANGE_START) %>% rename(lower = DFEDTARL)
  upper <- fetch_series("DFEDTARU", start = RANGE_START) %>% rename(upper = DFEDTARU)

  range <- inner_join(lower, upper, by = "date") %>%
    mutate(target = (lower + upper) / 2)

  bind_rows(
    point %>% filter(date < RANGE_START),
    range %>% filter(date >= RANGE_START)
  ) %>%
    arrange(date) %>%
    select(date, ff_target = target, lower, upper)
}

build_macro_monthly <- function(target_daily) {
  target_monthly <- target_daily %>%
    arrange(date) %>%
    mutate(changed = coalesce(ff_target != lag(ff_target), FALSE)) %>%
    group_by(date = floor_date(date, "month")) %>%
    summarise(
      ff_target     = mean(ff_target),
      policy_change = any(changed),
      .groups = "drop"
    )

  monthly  <- map(MONTHLY_SERIES, fetch_series)
  averaged <- map(AVERAGED_SERIES, fetch_series, monthly_avg = TRUE)

  reduce(c(list(target_monthly), monthly, averaged), full_join, by = "date") %>%
    filter(date >= floor_date(min(target_daily$date), "month")) %>%
    arrange(date)
}

build_market_daily <- function() {
  map(DAILY_SERIES, fetch_series) %>%
    reduce(full_join, by = "date") %>%
    arrange(date)
}

# ---- FOMC meeting calendar ---------------------------------------------------
#
# Two sources on federalreserve.gov:
#   - historical pages (one per year, published with a ~5-year lag)
#   - the current calendar page (recent years, plus scheduled future meetings)
#
# Each event is classified as:
#   scheduled            regular meeting on the published calendar
#   unscheduled_meeting  marked "(unscheduled)"
#   conference_call      intermeeting call (unscheduled)
#   notation_vote        written vote, no meeting
#   cancelled            listed but not held

classify_event <- function(text) {
  t <- str_to_lower(text)
  case_when(
    str_detect(t, "cancel")          ~ "cancelled",
    str_detect(t, "notation vote")   ~ "notation_vote",
    str_detect(t, "conference call") ~ "conference_call",
    str_detect(t, "unscheduled")     ~ "unscheduled_meeting",
    TRUE                             ~ "scheduled"
  )
}

# "February 1-2", "June 30-July 1", "May 18" -> start and end dates.
parse_day_range <- function(month_day, year) {
  parts <- str_split_fixed(str_squish(month_day), "-", 2)
  start <- parts[, 1]
  end   <- ifelse(parts[, 2] == "", start, parts[, 2])
  start_month <- str_extract(start, "^[A-Za-z]+")
  # End part may be just a day ("2") or month + day ("July 1").
  end <- ifelse(str_detect(end, "^[A-Za-z]"), end, paste(start_month, end))
  tibble(
    start_date = mdy(paste(start, year), quiet = TRUE),
    end_date   = mdy(paste(end, year), quiet = TRUE)
  )
}

scrape_historical_year <- function(year) {
  url <- sprintf("https://www.federalreserve.gov/monetarypolicy/fomchistorical%d.htm", year)
  headings <- read_html(url) %>%
    html_elements("h5") %>%
    html_text(trim = TRUE) %>%
    str_squish()
  headings <- headings[str_detect(headings, sprintf("- %d$", year))]
  if (length(headings) == 0) return(NULL)

  # Date text is everything before the first "(", "Meeting" or "Conference Call".
  date_text <- headings %>%
    str_remove(sprintf("\\s*-\\s*%d$", year)) %>%
    str_remove("\\s*(\\(|Meeting|Conference Call).*$")

  # A few headings list several calls on one line, e.g. the October 1987 crash:
  # "October 21, 22, 23, ... and 30 Conference Calls". Split into one row per day.
  events <- tibble(date_text, raw = headings) %>%
    mutate(date_text = map(date_text, function(d) {
      if (!str_detect(d, ",")) return(d)
      month <- str_extract(d, "^[A-Za-z]+")
      paste(month, str_extract_all(d, "\\d{1,2}")[[1]])
    })) %>%
    unnest(date_text)

  bind_cols(parse_day_range(events$date_text, year), tibble(raw = events$raw)) %>%
    mutate(type = classify_event(raw), source = "historical")
}

scrape_calendar_page <- function() {
  pg <- read_html("https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm")
  panels <- html_elements(pg, ".panel.panel-default")

  map_dfr(panels, function(p) {
    year <- html_element(p, ".panel-heading") %>%
      html_text(trim = TRUE) %>%
      str_extract("\\d{4}") %>%
      as.integer()
    rows <- html_elements(p, ".fomc-meeting")
    month <- rows %>% html_element(".fomc-meeting__month") %>% html_text(trim = TRUE) %>% str_squish()
    day   <- rows %>% html_element(".fomc-meeting__date")  %>% html_text(trim = TRUE) %>% str_squish()

    # "Apr/May" + "30-1" -> "April 30-May 1"; "17-18*" -> SEP meeting.
    months   <- str_split_fixed(month, "/", 2)
    days     <- str_extract(day, "^[0-9]+(-[0-9]+)?")
    day_from <- str_extract(days, "^[0-9]+")
    day_to   <- str_extract(days, "(?<=-)[0-9]+")
    end_mon  <- ifelse(months[, 2] == "", months[, 1], months[, 2])
    md <- ifelse(
      is.na(day_to),
      paste(months[, 1], day_from),
      paste0(months[, 1], " ", day_from, "-", end_mon, " ", day_to)
    )
    # Short month names ("Apr") parse fine with mdy().
    bind_cols(parse_day_range(md, year), tibble(raw = paste(month, day))) %>%
      mutate(
        type   = classify_event(raw),
        has_sep = str_detect(day, "\\*"),
        source = "calendar"
      )
  })
}

build_meetings <- function() {
  calendar <- scrape_calendar_page()
  first_calendar_year <- min(year(calendar$start_date), na.rm = TRUE)

  historical <- map_dfr(year(START_DATE):(first_calendar_year - 1), function(y) {
    Sys.sleep(0.5)  # be polite to federalreserve.gov
    scrape_historical_year(y)
  })

  meetings <- bind_rows(historical, calendar) %>%
    mutate(is_scheduled = type == "scheduled") %>%
    select(start_date, decision_date = end_date, type, is_scheduled, has_sep, source, raw) %>%
    arrange(start_date) %>%
    distinct(start_date, type, .keep_all = TRUE)

  bad <- filter(meetings, is.na(start_date) | is.na(decision_date))
  if (nrow(bad) > 0) {
    print(bad)
    stop("Could not parse ", nrow(bad), " FOMC event date(s); see rows above.")
  }
  meetings
}

# ---- Main --------------------------------------------------------------------

main <- function() {
  dir.create(OUT_DIR, showWarnings = FALSE)
  set_fred_key()

  message("Scraping FOMC calendar...")
  meetings <- build_meetings()
  write_csv(meetings, file.path(OUT_DIR, "fomc_meetings.csv"))

  message("Fetching fed funds target...")
  target_daily <- build_target_daily()
  write_csv(target_daily, file.path(OUT_DIR, "fed_target_daily.csv"))

  message("Fetching macro series...")
  macro <- build_macro_monthly(target_daily)
  write_csv(macro, file.path(OUT_DIR, "macro_monthly.csv"))

  message("Fetching daily market series...")
  market <- build_market_daily()
  write_csv(market, file.path(OUT_DIR, "market_daily.csv"))

  message(sprintf(
    "Done: %d FOMC events (%s to %s), %d target days, %d months x %d columns.",
    nrow(meetings), min(meetings$start_date), max(meetings$start_date),
    nrow(target_daily), nrow(macro), ncol(macro)
  ))
}

if (sys.nframe() == 0) main()
