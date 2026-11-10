# Libraries and analysis settings shared by every page of the site.
# Pages source this file; index.qmd also displays it (knitr::read_chunk).

## ---- libraries ----
library(dplyr)
library(tidyr)
library(ggplot2)
library(glmnet)
library(tseries)
library(zoo)
library(cluster)
library(strucchange)
library(randomForest)
library(xgboost)
library(nnet)
library(purrr)
library(broom)
library(corrplot)
library(caret)
library(factoextra)

## ---- settings ----
SAMPLE_START    <- as.Date("1986-01-01")  # start of the modeling sample
MAX_GAP_FILL    <- 1                      # fill internal gaps up to this many months
BP_MAX_BREAKS   <- 5                      # most structural breaks the test considers (RQ1)
BP_N_BREAKS     <- 3                      # breaks used (RQ1); BIC picks the max here, see C4
K_RANGE         <- 2:8                    # cluster counts shown in diagnostics (RQ2)
K_CLUSTERS      <- 3                      # clusters used (RQ2); silhouette is flat, see C5
LABEL_WINDOW_DAYS <- 2                    # days after a decision to read the new target (RQ3)
# Days after the end of month m by which month m's value is published.
# Cautious approximations of the usual release calendar; series not listed
# (market data, Michigan survey, oil, the target itself) are known by the
# end of month m. Real release dates (ALFRED) will replace this later.
RELEASE_DELAY_DAYS <- c(
  UNRATE   = 10,  # Employment Situation, first Friday of m+1
  PAYEMS   = 10,
  INDPRO   = 18,  # industrial production, mid m+1
  HOUST    = 20,  # housing starts, around the 17th-19th of m+1
  PCEPILFE = 31,  # personal income and outlays, end of m+1
  PCEPI    = 31
)
ZLB_MAX_TARGET  <- 0.25                   # target at or below this = zero lower bound (RQ3 feature)
RQ3_START_TRAIN <- 200                    # meetings in the first training window
RQ3_STEP        <- 12                     # meetings per test block
RQ3_WEIGHT_OPTIONS <- c(FALSE, TRUE)      # tuning tries unweighted and inverse-frequency class weights (RQ3)
RQ3_SEED        <- 597                    # seed for model fitting and the bootstrap (RQ3)
RQ3_BOOT_REPS   <- 1000                   # bootstrap resamples for score intervals (RQ3)
RQ3_CORES       <- max(1, parallel::detectCores(logical = FALSE) - 2)  # parallel folds (1 on Windows)
RQ3_BOOT_BLOCK  <- 8                      # meetings per bootstrap block (~1 year)

# Events tested with Chow tests alongside the estimated break dates (RQ1)
CHOW_EVENT_DATES <- as.Date(c(
  "2001-09-01",  # 9/11
  "2008-01-01",  # start of 2008 easing
  "2008-11-01",  # zero lower bound reached
  "2020-03-01"   # COVID
))
