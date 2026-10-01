###############################################################################
## MAU HYSTERESIS REPRODUCIBILITY PIPELINE
#
# Single continuous from-raw-data workflow.
#
# STRUCTURE
#   0. Configuration, packages, paths, constants and reusable utilities
#   1. Raw-data import and physical quality control
#   2. Rainfall/discharge event detection and accepted event register
#   3. WQ screening, event metrics, hysteresis and chemical-status analysis
#   4. Corrected Vaughan flushing index
#   5. Integrated response-pattern analysis (PAM, stability and controls)
#   6. Main-text and Supplementary figures/tables
#   7. Final reviewer harmonisation and publication-output audit
#
# General utilities are defined before the analysis; highly specialized figure
# helpers remain beside the figure they render. Analytical thresholds, event
# logic, table definitions, publication figure code and output names are retained.
#
# USER ACTION: edit PROJECT_DIR only.
#
# FINAL FIGURE NUMBERING USED BY THIS SCRIPT
# Main article: former Figure S3 -> Figure 3; former Figures 3-6 -> Figures 4-7.
# Supplementary: Figures S1-S2 unchanged; former Figures S4-S6 -> Figures S3-S5.
# No analytical calculations, thresholds, tables, or figure contents are changed
# by this renumbering.
###############################################################################


#Save the Entire Workspace
#save.image(file = "Mau_hysteresis_analysis_workspace.RData")
#
#restore all objects to your workspace only for an intentional saved-state workflow
#load("Mau_hysteresis_analysis_workspace.RData")  # intentionally disabled for raw-data reproducibility

#clear the environment
#rm(list = ls())
#Clear Console.
#cat("\014")
###############################################################################
# FINAL STATIC-REVIEW NOTES
# - Unconditional workspace restoration is disabled.
# - mgcv is included in dependency checks because mgcv::gam() is used later.
# - Figure 7 and Supplementary Figures S3-S5 use one authoritative C1-C3 palette:
#   C1 #1A365D, C2 #718096, C3 #63B3ED.
# - Figure S4 silhouette boxplots use explicit observed min/max whisker caps.
# - The final reviewer harmonization block at the end overwrites only requested
#   figure outputs; analytical calculations remain unchanged.
# - v4_16: stale-workspace/event-metric protection added; Figure 7a and S5
#   now take tDry/qStart from the current event register; S5 is fixed to four panels.

# 0. USER SETTINGS — PORTABLE PROJECT ROOT
PROJECT_DIR <- normalizePath(".", winslash = "/", mustWork = TRUE)

TZ_USE     <- "Africa/Nairobi"
LOCALE_TRY <- "English_Great Britain.1252"

# 0.1 REQUIRED PACKAGES

required_packages <- c(
  "zoo", "xts", "lubridate", "dplyr", "tidyr", "purrr", "tibble",
  "ggplot2", "scales", "png", "stringr", "patchwork",
  "cowplot", "cluster", "mgcv"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0L) {
  stop(
    "Install the missing package(s), restart R, and rerun the script:\n",
    paste0("  - ", missing_packages, collapse = "\n"),
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(zoo)
  library(xts)
  library(lubridate)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(tibble)
  library(ggplot2)
  library(scales)
  library(png)
  library(grid)
  library(stringr)
  library(patchwork)
  library(cowplot)
})

if ("package:plyr" %in% search()) {
  detach("package:plyr", unload = TRUE)
}

# 0.2 PROJECT AND OUTPUT DIRECTORIES

if (!dir.exists(PROJECT_DIR)) {
  stop("PROJECT_DIR does not exist: ", PROJECT_DIR, call. = FALSE)
}

WORKDIR <- normalizePath(PROJECT_DIR, winslash = "/", mustWork = TRUE)
BASE_DIR <- WORKDIR
setwd(WORKDIR)

try(Sys.setlocale(category = "LC_ALL", locale = LOCALE_TRY), silent = TRUE)
Sys.setenv(TZ = TZ_USE)

# Publication/reproducibility master folder.
REPRO_ROOT <- file.path(WORKDIR, "Mau_Hysteresis_Reproducibility")
DIR_CORE   <- file.path(REPRO_ROOT, "00_Core_Analysis")
DIR_MAIN   <- file.path(REPRO_ROOT, "01_Main_Article")
DIR_SUPP   <- file.path(REPRO_ROOT, "02_Supplementary_Information")
DIR_REPRO  <- file.path(REPRO_ROOT, "03_Reproducibility")

# Core-analysis outputs requested for reproducibility.
DIR_Q_EVENTS  <- file.path(DIR_CORE, "q_events")
DIR_WQ_RETURN <- file.path(DIR_CORE, "WQ_return")
DIR_WQ_RESP   <- file.path(DIR_CORE, "WQ_response")
DIR_WQ_HYST   <- file.path(DIR_CORE, "WQ_hysteresis")

DIR_Q_SITE <- c(
  NF  = file.path(DIR_Q_EVENTS, "NF_q_events"),
  SHA = file.path(DIR_Q_EVENTS, "SHA_q_events"),
  TTP = file.path(DIR_Q_EVENTS, "TTP_q_events")
)
DIR_RETURN_SITE <- c(
  NF  = file.path(DIR_WQ_RETURN, "NF_WQ_return"),
  SHA = file.path(DIR_WQ_RETURN, "SHA_WQ_return"),
  TTP = file.path(DIR_WQ_RETURN, "TTP_WQ_return")
)
DIR_RESP_SITE <- c(
  NF  = file.path(DIR_WQ_RESP, "NF_WQ_response"),
  SHA = file.path(DIR_WQ_RESP, "SHA_WQ_response"),
  TTP = file.path(DIR_WQ_RESP, "TTP_WQ_response")
)
DIR_HYST_SITE <- c(
  NF  = file.path(DIR_WQ_HYST, "NF_WQ_hysteresis"),
  SHA = file.path(DIR_WQ_HYST, "SHA_WQ_hysteresis"),
  TTP = file.path(DIR_WQ_HYST, "TTP_WQ_hysteresis")
)

# Main-article and Supplementary Information outputs.
DIR_MAIN_FIG     <- file.path(DIR_MAIN, "Figures")
DIR_MAIN_FIG_PNG <- file.path(DIR_MAIN_FIG, "PNG")
DIR_MAIN_FIG_ALT <- file.path(DIR_MAIN_FIG, "PDF_TIFF")
DIR_MAIN_TAB     <- file.path(DIR_MAIN, "Tables")

DIR_SUPP_FIG     <- file.path(DIR_SUPP, "Figures")
DIR_SUPP_FIG_PNG <- file.path(DIR_SUPP_FIG, "PNG")
DIR_SUPP_FIG_ALT <- file.path(DIR_SUPP_FIG, "PDF_TIFF")
DIR_SUPP_TAB     <- file.path(DIR_SUPP, "Tables")

# Intermediate analytical files needed only while the script runs are kept in
# the session temporary directory, so the publication tree remains clean.
DIR_REPRO_TMP <- file.path(tempdir(), "Mau_Hysteresis_Reproducibility_intermediate")
DIR_REPRO_TMP_FIG <- file.path(DIR_REPRO_TMP, "Figures")
DIR_REPRO_TMP_TAB <- file.path(DIR_REPRO_TMP, "Tables")

all_dirs <- c(
  REPRO_ROOT, DIR_CORE, DIR_MAIN, DIR_SUPP, DIR_REPRO,
  DIR_Q_EVENTS, DIR_WQ_RETURN, DIR_WQ_RESP, DIR_WQ_HYST,
  unname(DIR_Q_SITE), unname(DIR_RETURN_SITE), unname(DIR_RESP_SITE), unname(DIR_HYST_SITE),
  DIR_MAIN_FIG, DIR_MAIN_FIG_PNG, DIR_MAIN_FIG_ALT, DIR_MAIN_TAB,
  DIR_SUPP_FIG, DIR_SUPP_FIG_PNG, DIR_SUPP_FIG_ALT, DIR_SUPP_TAB,
  DIR_REPRO_TMP, DIR_REPRO_TMP_FIG, DIR_REPRO_TMP_TAB
)
invisible(lapply(all_dirs, dir.create, recursive = TRUE, showWarnings = FALSE))

# Compatibility aliases for retained analytical code.
DIR_EVENT_PLOTS  <- DIR_Q_EVENTS
DIR_PAPER        <- DIR_REPRO_TMP
DIR_PAPER_FIG    <- DIR_REPRO_TMP_FIG
DIR_PAPER_TAB    <- DIR_REPRO_TMP_TAB
DIR_OVERVIEW     <- DIR_REPRO_TMP
DIR_OVERVIEW_FIG <- DIR_REPRO_TMP_FIG
DIR_OVERVIEW_TAB <- DIR_REPRO_TMP_TAB
DIR_SEASON_YEAR  <- DIR_REPRO_TMP
DIR_HI_AP        <- DIR_REPRO_TMP_FIG
OUTDIR <- DIR_REPRO_TMP
FIGDIR <- DIR_REPRO_TMP_FIG
TABDIR <- DIR_REPRO_TMP_TAB

resolve_project_file <- function(filename, root = WORKDIR, required = TRUE) {
  direct <- file.path(root, filename)
  if (file.exists(direct)) {
    return(normalizePath(direct, winslash = "/", mustWork = TRUE))
  }

  hits <- list.files(
    root,
    pattern = paste0("^", gsub("\\.", "\\\\.", filename), "$"),
    recursive = TRUE,
    full.names = TRUE,
    ignore.case = TRUE
  )

  hits <- hits[file.exists(hits)]

  if (length(hits) > 0L) {
    info <- file.info(hits)
    selected <- hits[order(info$mtime, decreasing = TRUE, na.last = TRUE)][1]
    message(
      "Resolved ", filename, " to: ",
      normalizePath(selected, winslash = "/", mustWork = TRUE)
    )
    return(normalizePath(selected, winslash = "/", mustWork = TRUE))
  }

  if (required) {
    stop(
      "Required file not found: ", filename,
      "\nSearched under: ", root,
      call. = FALSE
    )
  }

  normalizePath(direct, winslash = "/", mustWork = FALSE)
}

DATA_CSV <- resolve_project_file("data_final.csv", WORKDIR, required = TRUE)

cat("\n=== COMPLETE PIPELINE INITIALIZATION ===\n")
cat("Project directory :", WORKDIR, "\n")
cat("Input data        :", DATA_CSV, "\n")
cat("Figure directory  :", DIR_PAPER_FIG, "\n")
cat("Table directory   :", DIR_PAPER_TAB, "\n\n")

# Event selection thresholds (author-agreed)
NF_minDry  <- 10; NF_minPeak  <- 1.20; NF_maxEnd  <- 0.10
SHA_minDry <-  8; SHA_minPeak <- 1.15; SHA_maxEnd <- 0.10
TTP_minDry <- 10; TTP_minPeak <- 1.20; TTP_maxEnd <- 0.15

# Return-to-baseline + response thresholds
resp_thresh <- 0.15
ret_thresh  <- 0.20

# WQ availability and authoritative pre-event baseline window
min_pts_basic <- 2L
min_pts_hyst  <- 10L
min_pts_limb  <- 4L
C0_start_offset_steps <- -6L
C0_end_offset_steps   <- -2L

# Sites + catchment areas (km2)
sites <- c("NF", "SHA", "TTP")
catchment_area_km2 <- c(NF = 35.9, SHA = 27.2, TTP = 33.3)

# API
API_days <- 21
API_k    <- 0.85

# Rainfall clustering
cluster_by_site <- TRUE
k_centers    <- 4
km_nstart    <- 50
km_seed      <- 123
scale_method <- "range"
km_features  <- c("Depth_mm", "Duration_h", "Intensity")
season_levels <- c("Short Rainy Season", "Hot Dry Season", "Long Rainy Season", "Cool Dry Season")
cluster_levels <- c("I","II","III","IV")

# Typical event window
pre_hours  <- 6
post_hours <- 24

# Helpers: parsing + numeric coercion
.parse_dt <- function(x, tz = TZ_USE) {
  if (inherits(x, "POSIXct")) return(with_tz(x, tz))
  if (inherits(x, "POSIXt"))  return(as.POSIXct(x, tz = tz))
  if (inherits(x, "Date"))    return(as.POSIXct(x, tz = tz))

  if (is.numeric(x)) {
    if (all(x > 20000 & x < 80000, na.rm = TRUE)) {
      return(suppressWarnings(as.POSIXct(x * 86400, origin = "1899-12-30", tz = tz)))
    }
    return(suppressWarnings(as.POSIXct(x, origin = "1970-01-01", tz = tz)))
  }

  xx <- trimws(as.character(x))
  xx[xx %in% c("", "NA", "NaN", "NULL")] <- NA_character_

  suppressWarnings(parse_date_time(
    xx,
    orders = c(
      "Ymd HMS", "Ymd HM", "Ymd",
      "Y-m-d H:M:S", "Y-m-d H:M", "Y-m-d",
      "Y/m/d H:M:S", "Y/m/d H:M", "Y/m/d",
      "d/m/Y H:M:S", "d/m/Y H:M", "d/m/Y",
      "m/d/Y H:M:S", "m/d/Y H:M", "m/d/Y",
      "d-m-Y H:M:S", "d-m-Y H:M", "d-m-Y",
      "m-d-Y H:M:S", "m-d-Y H:M", "m-d-Y"
    ),
    tz = tz
  ))
}

to_num <- function(x) {
  x <- as.character(x)
  x <- gsub(",", ".", x)
  x <- suppressWarnings(as.numeric(x))
  x[x %in% c(-9999, -999, -99)] <- NA
  x
}

get_dt_seconds <- function(dates) {
  if (length(dates) < 2) return(NA_real_)
  as.numeric(median(diff(dates)), units = "secs")
}

# Robust column detection
detect_q_col <- function(df_names, site) {
  cand <- c(paste0(site, ".wl.q"), paste0(site, "_wl.q"),
            paste0(site, ".q"),    paste0(site, "_q"))
  cand <- cand[cand %in% df_names]
  if (length(cand) > 0) return(cand[1])

  cand2 <- df_names[grepl(site, df_names, ignore.case = TRUE) &
                      grepl("\\.q$|_q$|\\.wl\\.q$|_wl\\.q$", df_names, ignore.case = TRUE)]
  if (length(cand2) > 0) return(cand2[1])

  NA_character_
}

detect_prec_col <- function(df_names, site) {
  cand <- c(paste0(site, ".prec"), paste0(site, "_prec"))
  cand <- cand[cand %in% df_names]
  if (length(cand) > 0) return(cand[1])

  cand2 <- df_names[grepl(site, df_names, ignore.case = TRUE) &
                      grepl("\\.prec$|_prec$|\\bprec\\b", df_names, ignore.case = TRUE)]
  if (length(cand2) > 0) return(cand2[1])

  NA_character_
}

detect_wq_col <- function(df_names, site, param) {
  param_rgx <- switch(
    param,
    NO3 = "(no3|nit|nitr)",
    DOC = "(doc)",
    EC  = "(ec|elc|cond|conduct|spc)",
    TSS = "(tss|ssc|turb)",
    "(no3|nit|nitr|doc|ec|elc|cond|conduct|spc|tss|ssc|turb)"
  )

  cand <- df_names[
    grepl(site, df_names, ignore.case = TRUE) &
      grepl(param_rgx, df_names, ignore.case = TRUE)
  ]

  cand <- cand[!grepl("\\.prec$|_prec$|\\bprec\\b|\\.wl\\.q$|_wl\\.q$|\\.q$|_q$",
                      cand, ignore.case = TRUE)]
  if (length(cand) == 0) return(NA_character_)

  cand_cal <- cand[grepl("\\.cal$|_cal$", cand, ignore.case = TRUE)]
  if (length(cand_cal) > 0) cand <- cand_cal

  pref <- cand[grepl(paste0("^", site, "\\."), cand, ignore.case = TRUE) |
                 grepl(paste0("^", site, "_"), cand, ignore.case = TRUE)]
  if (length(pref) > 0) cand <- pref

  cand[which.min(nchar(cand))]
}

# Baseline / response / HI helpers used downstream
# Authoritative C0: median of valid observations six to two 10-min timesteps
# before hydrograph onset.
calc_event_C0 <- function(df, col, tStart,
                          start_offset_steps = C0_start_offset_steps,
                          end_offset_steps = C0_end_offset_steps) {
  if (!is.data.frame(df) || !("date" %in% names(df)) ||
      !(col %in% names(df)) || length(tStart) != 1L || is.na(tStart)) {
    return(NA_real_)
  }
  idx0 <- which.min(abs(df$date - tStart))
  if (length(idx0) != 1L || !is.finite(idx0)) return(NA_real_)
  idx <- idx0 + seq.int(start_offset_steps, end_offset_steps)
  idx <- idx[idx >= 1L & idx < idx0 & idx <= nrow(df)]
  if (length(idx) == 0L) return(NA_real_)
  values <- to_num(df[[col]][idx])
  values <- values[is.finite(values)]
  if (length(values) == 0L) return(NA_real_)
  stats::median(values)
}

# Backward-compatible alias; pre_h is ignored intentionally.
get_C0 <- function(df, col, tStart, pre_h = NULL) {
  calc_event_C0(df = df, col = col, tStart = tStart)
}

calc_response <- function(values, baseline) {
  if (!is.finite(baseline) || baseline == 0) return(list(response = NA_real_, peak = NA_real_))
  peak_up   <- suppressWarnings(max(values, na.rm = TRUE))
  peak_down <- suppressWarnings(min(values, na.rm = TRUE))
  if (!is.finite(peak_up) && !is.finite(peak_down)) return(list(response = NA_real_, peak = NA_real_))

  dev_up   <- if (is.finite(peak_up))   abs(peak_up   - baseline) / abs(baseline) else -Inf
  dev_down <- if (is.finite(peak_down)) abs(peak_down - baseline) / abs(baseline) else -Inf

  list(
    response = max(dev_up, dev_down, na.rm = TRUE),
    peak     = ifelse(dev_up >= dev_down, peak_up, peak_down)
  )
}

calc_return_ratio <- function(end_value, baseline, peak_value) {
  if (!is.finite(end_value) || !is.finite(baseline) || !is.finite(peak_value)) return(NA_real_)
  denom <- abs(peak_value - baseline)
  if (!is.finite(denom) || denom == 0) return(NA_real_)
  abs(end_value - baseline) / denom
}

approx_unique_initial <- function(x, y, xout, rule = 2) {
  x <- suppressWarnings(as.numeric(x))
  y <- suppressWarnings(as.numeric(y))
  xout_num <- suppressWarnings(as.numeric(xout))

  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) == 0L) {
    return(list(x = xout, y = rep(NA_real_, length(xout_num))))
  }

  dat <- data.frame(x = x[ok], y = y[ok])
  dat <- stats::aggregate(y ~ x, data = dat, FUN = mean, na.rm = TRUE)
  dat <- dat[order(dat$x), , drop = FALSE]

  if (nrow(dat) == 1L) {
    return(list(x = xout, y = rep(dat$y[1], length(xout_num))))
  }

  out <- stats::approx(
    x = dat$x,
    y = dat$y,
    xout = xout_num,
    rule = rule,
    ties = "ordered"
  )
  out$x <- xout
  out
}

calc_HI_Lloyd <- function(Q, C, baseline = NA_real_,
                          k = seq(0.05, 0.95, by = 0.05),
                          min_points = min_pts_hyst,
                          min_limb_points = min_pts_limb) {
  Q <- suppressWarnings(as.numeric(Q))
  C <- suppressWarnings(as.numeric(C))
  k <- suppressWarnings(as.numeric(k))
  ok <- is.finite(Q) & is.finite(C)
  Q <- Q[ok]; C <- C[ok]
  if (length(Q) < min_points || length(k) == 0L || any(!is.finite(k))) return(NA_real_)
  i_peak <- which.max(Q)
  if (i_peak < min_limb_points || (length(Q) - i_peak + 1L) < min_limb_points) return(NA_real_)
  Qr <- Q[seq_len(i_peak)]; Cr <- C[seq_len(i_peak)]
  Qf <- Q[i_peak:length(Q)]; Cf <- C[i_peak:length(C)]
  if (length(unique(Qr)) < min_limb_points || length(unique(Qf)) < min_limb_points) return(NA_real_)
  Qlo <- max(min(Qr), min(Qf))
  Qhi <- min(max(Qr), max(Qf))
  Cmin <- min(C); Cmax <- max(C)
  if (!is.finite(Qlo) || !is.finite(Qhi) || Qhi <= Qlo ||
      !is.finite(Cmin) || !is.finite(Cmax) || Cmax <= Cmin) return(NA_real_)
  Qk <- Qlo + k * (Qhi - Qlo)
  Crk <- approx_unique_initial(Qr, Cr, xout = Qk, rule = 1)$y
  Cfk <- approx_unique_initial(Qf, Cf, xout = Qk, rule = 1)$y
  HIk <- (Crk - Cmin) / (Cmax - Cmin) - (Cfk - Cmin) / (Cmax - Cmin)
  if (sum(is.finite(HIk)) != length(k)) return(NA_real_)
  mean(HIk)
}

calc_HI_Zuecco <- function(Q, C) {
  ok <- is.finite(Q) & is.finite(C)
  Q <- Q[ok]
  C <- C[ok]

  if (length(Q) < 10L) return(NA_real_)

  i_peak <- which.max(Q)
  if (i_peak < 3L || i_peak > length(Q) - 3L) return(NA_real_)

  Qr <- Q[seq_len(i_peak)]
  Cr <- C[seq_len(i_peak)]
  Qf <- Q[i_peak:length(Q)]
  Cf <- C[i_peak:length(C)]

  if (length(unique(Qr)) < 2L || length(unique(Qf)) < 2L) {
    return(NA_real_)
  }

  Qref <- min(Qr, na.rm = TRUE) +
    0.5 * (max(Qr, na.rm = TRUE) - min(Qr, na.rm = TRUE))

  if (Qref < min(Qf, na.rm = TRUE) || Qref > max(Qf, na.rm = TRUE)) {
    return(NA_real_)
  }

  Cr_ref <- approx_unique_initial(Qr, Cr, xout = Qref, rule = 2)$y
  Cf_ref <- approx_unique_initial(Qf, Cf, xout = Qref, rule = 2)$y

  denom <- max(C, na.rm = TRUE) - min(C, na.rm = TRUE)
  if (!is.finite(denom) || denom == 0) return(NA_real_)

  as.numeric((Cr_ref - Cf_ref) / denom)
}

calc_API_GW <- function(df, prec_col, t0, n_days = 21, k = 0.85) {
  if (is.na(t0) || !(prec_col %in% names(df))) return(NA_real_)
  lags <- 0:(n_days - 1)
  P_lag <- vapply(lags, function(j) {
    sum(df[[prec_col]][df$date >= t0 - days(j + 1) & df$date < t0 - days(j)], na.rm = TRUE)
  }, numeric(1))
  sum(P_lag * k^lags, na.rm = TRUE)
}

calc_RB <- function(Q) {
  ok <- is.finite(Q)
  Q <- Q[ok]
  if (length(Q) < 3) return(NA_real_)
  sQ <- sum(Q, na.rm = TRUE)
  if (!is.finite(sQ) || sQ == 0) return(NA_real_)
  sum(abs(diff(Q)), na.rm = TRUE) / sQ
}

calc_recession_k <- function(dates, Q, t_peak) {
  ok <- is.finite(Q) & Q > 0 & !is.na(dates) & dates >= t_peak
  dates <- dates[ok]; Q <- Q[ok]
  if (length(Q) < 10) return(NA_real_)
  t_h <- as.numeric(difftime(dates, min(dates), units = "hours"))
  fit <- try(lm(log(Q) ~ t_h), silent = TRUE)
  if (inherits(fit, "try-error")) return(NA_real_)
  k <- -coef(fit)[2]
  if (!is.finite(k)) return(NA_real_)
  as.numeric(k)
}

calc_m_CQ <- function(Q, C) {
  ok <- is.finite(Q) & is.finite(C) & Q > 0 & C > 0
  Q <- Q[ok]; C <- C[ok]
  if (length(Q) < 10) return(c(m_rise = NA_real_, m_fall = NA_real_, m_mean = NA_real_))
  i_peak <- which.max(Q)
  if (i_peak < 3 || i_peak > length(Q) - 3) return(c(m_rise = NA_real_, m_fall = NA_real_, m_mean = NA_real_))
  Qr <- Q[1:i_peak]; Cr <- C[1:i_peak]
  Qf <- Q[i_peak:length(Q)]; Cf <- C[i_peak:length(C)]
  m_r <- try(coef(lm(log(Cr) ~ log(Qr)))[2], silent = TRUE)
  m_f <- try(coef(lm(log(Cf) ~ log(Qf)))[2], silent = TRUE)
  if (inherits(m_r, "try-error")) m_r <- NA_real_
  if (inherits(m_f, "try-error")) m_f <- NA_real_
  c(m_rise = as.numeric(m_r), m_fall = as.numeric(m_f), m_mean = mean(c(m_r, m_f), na.rm = TRUE))
}

calc_FI_peak <- function(C0, C_peak) {
  if (!is.finite(C0) || C0 == 0 || !is.finite(C_peak)) return(NA_real_)
  (C_peak - C0) / C0
}

calc_FI_mean <- function(C0, Cmean) {
  if (!is.finite(C0) || C0 == 0 || !is.finite(Cmean)) return(NA_real_)
  (Cmean - C0) / C0
}

drop_list_columns <- function(dat, context = "data frame") {
  if (!is.data.frame(dat)) return(dat)

  list_cols <- names(dat)[vapply(dat, is.list, logical(1))]
  if (length(list_cols) > 0L) {
    message(
      "Removing non-tabular list column(s) from ",
      context,
      ": ",
      paste(list_cols, collapse = ", ")
    )
    dat <- dat[, setdiff(names(dat), list_cols), drop = FALSE]
  }
  dat
}

write_csv_safe <- function(dat, file, row.names = FALSE, fileEncoding = "UTF-8") {
  dat <- drop_list_columns(dat, context = basename(file))
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    dat,
    file = file,
    row.names = row.names,
    fileEncoding = fileEncoding
  )
  invisible(file)
}

# Load data
df <- read.csv(DATA_CSV)
stopifnot("date" %in% names(df))
df$date <- .parse_dt(df$date, tz = TZ_USE)
df <- df %>% arrange(date)

# --- PHYSICALLY DEFENSIBLE RAW-DATA QUALITY CONTROL ---
# Sentinel values are already converted to NA by to_num(). Negative values in
# precipitation, discharge, and concentration channels are invalid physical
# readings and are therefore set to NA, rather than reflected with abs().
physical_columns <- unique(c(
  unlist(lapply(c("NF", "SHA", "TTP"), function(ss) {
    c(
      detect_prec_col(names(df), ss),
      detect_q_col(names(df), ss),
      detect_wq_col(names(df), ss, "NO3"),
      detect_wq_col(names(df), ss, "DOC"),
      detect_wq_col(names(df), ss, "EC"),
      detect_wq_col(names(df), ss, "TSS")
    )
  }))
))
physical_columns <- physical_columns[
  !is.na(physical_columns) & physical_columns %in% names(df)
]

negative_counts <- vapply(
  physical_columns,
  function(cc) sum(to_num(df[[cc]]) < 0, na.rm = TRUE),
  integer(1)
)

for (cc in physical_columns) {
  z <- to_num(df[[cc]])
  z[is.finite(z) & z < 0] <- NA_real_
  df[[cc]] <- z
}

if (sum(negative_counts) > 0L) {
  message(
    "Raw-data QC: converted ",
    sum(negative_counts),
    " negative physical readings to NA across ",
    sum(negative_counts > 0L),
    " channel(s)."
  )
} else {
  message("Raw-data QC: no negative physical readings were detected.")
}
# --- END PHYSICALLY DEFENSIBLE RAW-DATA QUALITY CONTROL ---

dt_df_s <- get_dt_seconds(df$date)
if (!is.finite(dt_df_s) || dt_df_s <= 0) stop("Cannot infer valid timestep from df$date.")

# Rainfall event detection
rainEvent <- function(df,
                      pDry = 2,
                      pMin = 1,
                      saveFile = FALSE) {

  colnames(df)[2] <- c("prec")
  df$date <- .parse_dt(df$date, tz = TZ_USE)
  df$prec <- to_num(df$prec)
  df$event <- 0

  tStep <- as.numeric(unique(diff(df$date, units = "hours"))[1])
  if (!is.finite(tStep) || tStep <= 0) stop("rainEvent: invalid timestep.")
  pDry <- max(1, as.integer(round(pDry / tStep)))

  eTable <- data.frame(
    ID = numeric(), tStart = character(), tEnd = character(), pDur = numeric(), tDry = numeric(),
    pTotal = numeric(), pMax = numeric(), pInt = numeric(),
    stringsAsFactors = FALSE
  )

  e <- "start"
  i <- 1
  n <- nrow(df)

  for (t in 1:n) {

    if (e == "start") {
      if (is.na(df$prec[t]) || df$prec[t] == 0) next
      df$event[t] <- i
      e <- "stop"
      next
    } else {
      if (!is.na(df$prec[t]) && df$prec[t] > 0) next

      look_from <- t + 1
      look_to   <- min(n, t + pDry)
      if (look_from <= look_to) {
        if (sum(df$prec[look_from:look_to], na.rm = TRUE) > 0) next
      }

      tStart <- which(df$event == i)
      if (length(tStart) == 0) {
        e <- "start"
        next
      }

      pTotal <- sum(df$prec[tStart:t], na.rm = TRUE)

      if (pTotal < pMin) {
        df$event[tStart] <- 0
        e <- "start"
        next
      }

      df$event[t] <- i

      tStart_ts <- df$date[min(tStart)]
      tEnd_ts   <- df$date[t]

      pDur <- as.numeric(difftime(tEnd_ts, tStart_ts, units = "hours"))
      tPrev <- if (i > 1) {
        prev_idx <- which(df$event == (i - 1))
        if (length(prev_idx) >= 2) df$date[prev_idx[2]] else NA
      } else NA_real_
      tPrev <- as.numeric(difftime(tStart_ts, tPrev, units = "hours"))

      pMax <- max(df$prec[min(tStart):t], na.rm = TRUE) * 6
      pInt <- ifelse(is.finite(pDur) && pDur > 0, pTotal / pDur, NA_real_)

      eTable[i, 1] <- i
      eTable[i, 2:3] <- format(c(tStart_ts, tEnd_ts), format = "%Y-%m-%d %H:%M:%S")
      eTable[i, 4:8] <- c(pDur, tPrev, pTotal, pMax, pInt)

      i <- i + 1
      e <- "start"
      next
    }
  }

  if (saveFile != FALSE) {
    write.table(
      eTable,
      paste0(saveFile, "_", format(Sys.time(), format = "%Y%m%d_%H%M"), ".csv"),
      row.names = FALSE, sep = ","
    )
  }

  return(eTable)
}

# Discharge event detection
# with safe indexing only
qEvent <- function(df,
                   dfE,
                   minIncr = 0.5,
                   maxDelay = 6,
                   maxDur = 72,
                   minDry = 10,
                   maxEnd = 0.10,
                   minPeak = 1.2,
                   savePlot = FALSE,
                   saveFile = FALSE) {

  colnames(df)[2:3] <- c("prec", "q")
  df$date <- .parse_dt(df$date, tz = TZ_USE)
  df$prec <- to_num(df$prec)
  df$q    <- to_num(df$q)
  df$event <- 0

  dfE$tStart <- .parse_dt(dfE$tStart, tz = TZ_USE)
  dfE$tEnd   <- .parse_dt(dfE$tEnd,   tz = TZ_USE)

  tStep <- as.numeric(unique(diff(df$date, units = "hours"))[1])
  if (!is.finite(tStep) || tStep <= 0) stop("qEvent: invalid timestep.")
  minIncr <- max(1, as.integer(round(minIncr / tStep)))
  maxDelay <- max(1, as.integer(round(maxDelay / tStep)))

  df$change <- zoo::rollapply(
    c(0, diff(df$q)),
    width = minIncr,
    function(x) median(x, na.rm = TRUE),
    fill = -1,
    align = "left",
    partial = TRUE
  )

  eTable <- data.frame(
    ID = numeric(), tStart = character(), tEnd = character(), qDur = numeric(), qDelay = numeric(),
    qStart = numeric(), qPeak = numeric(), qEnd = numeric(), qIncr = numeric(),
    stringsAsFactors = FALSE
  )

  if (savePlot != FALSE) {
    fName <- paste0(savePlot, "_events_", format(Sys.time(), format = "%Y%m%d_%H%M"))
    dir.create(fName, showWarnings = FALSE, recursive = TRUE)
  } else {
    fName <- NULL
  }

  nEvents <- nrow(dfE)
  if (nEvents == 0) return(eTable)

  for (i in 1:nEvents) {

    idx_rs <- which(df$date == dfE$tStart[i])[1]
    idx_re <- which(df$date == dfE$tEnd[i])[1]
    if (!is.finite(idx_rs) || !is.finite(idx_re)) {
      eTable[i, 1] <- i
      next
    }

    tmp <- df[max(1, idx_rs - 108):min(idx_re + 504, nrow(df)), ]
    eTable[i, 1] <- i

    if (!is.null(fName)) {
      png(paste0(fName, "/Event_", i, ".png"), width = 16, height = 10, units = "cm", res = 300, pointsize = 10)
      par(mar = c(2, 3.5, 1, 3.5), oma = c(0, 0, 0, 0), mfrow = c(1, 1), pty = "m",
          mgp = c(1.5, 0.5, 0), cex = 0.9, cex.axis = 0.9,
          tcl = -0.25, xaxs = "i", yaxs = "i", bty = "u", fg = "#6e706f", lend = "butt")

      plot(tmp$date, tmp$prec, type = "h", col = "#386e93", xlab = "", ylab = "", xlim = range(tmp$date), yaxt = "n")
      if (nEvents > 1) {
        rect(as.POSIXct(dfE$tStart[-i]), rep(0, nEvents - 1), as.POSIXct(dfE$tEnd[-i]), rep(20, nEvents - 1),
             col = "#8ca6ab22", border = NA)
      }
      rect(as.POSIXct(dfE$tStart[i]), 0, as.POSIXct(dfE$tEnd[i]), 20, col = "#8ca6ab66", border = NA)
      axis(side = 4, at = NULL, labels = TRUE)
      mtext(expression("Precipitation [mm 10 min"^"-1"*"]"), side = 4, line = 2, col = "#386e93")

      if (sum(!is.na(tmp$q)) > 0) {
        par(new = TRUE)
        plot(tmp$date, tmp$q, type = "l", col = "#474973", xlab = "", ylab = "", xlim = range(tmp$date), xaxt = "n")
        mtext(expression("Discharge [m"^"3"*"s"^"-1"*"]"), side = 2, line = 2, col = "#474973")
      } else {
        par(fig = c(0.7, 0.9, 0.6, 0.9), new = TRUE, mar = c(0, 0, 0, 0), bty = "n")
        plot(NA, NA, type = "n", xlab = "", ylab = "", xlim = c(0, 10), ylim = c(0.5, 5.5), xaxt = "n", yaxt = "n")
        text(x = 0, y = 5, labels = bquote("Insufficient "*italic("Q")*" data"), pos = 4, col = "#e76c29")
        dev.off()
        next
      }
    }

    tStart <- idx_rs

    if (i == nEvents) {
      tSearch <- min(c(nrow(df), tStart + as.integer(round(maxDur / tStep))))
    } else {
      next_start <- which(df$date == dfE$tStart[i + 1])[1]
      if (!is.finite(next_start)) next_start <- nrow(df)
      tSearch <- min(c(next_start - 1, tStart + as.integer(round(maxDur / tStep))))
    }

    if (sum(!is.na(df$q[tStart:tSearch])) < 0.9 * (tSearch - tStart)) {
      if (!is.null(fName)) {
        par(fig = c(0.7, 0.9, 0.6, 0.9), new = TRUE, mar = c(0, 0, 0, 0), bty = "n")
        plot(NA, NA, type = "n", xlab = "", ylab = "", xlim = c(0, 10), ylim = c(0.5, 5.5), xaxt = "n", yaxt = "n")
        text(x = 0, y = 5, labels = bquote("Insufficient "*italic("Q")*" data"), pos = 4, col = "#e76c29")
        dev.off()
      }
      next
    }

    while (tStart <= nrow(df) && is.na(df$change[tStart])) tStart <- tStart + 1
    if (tStart > nrow(df)) {
      if (!is.null(fName)) dev.off()
      next
    }

    if (df$change[tStart] > 0) {
      while (tStart > 1 && (is.na(df$change[tStart]) || df$change[tStart] > 0)) tStart <- tStart - 1
      tStart <- tStart + 1
    } else {
      while (tStart <= nrow(df) && (is.na(df$change[tStart]) || df$change[tStart] <= 0)) tStart <- tStart + 1
      tStart <- max(tStart, idx_rs - 12)
    }

    if (tStart < 1 || tStart > nrow(df)) {
      if (!is.null(fName)) dev.off()
      next
    }

    qDelay <- as.numeric(difftime(df$date[tStart], dfE$tStart[i], units = "hours"))

    if (tStart > idx_rs + maxDelay) {
      if (!is.null(fName)) {
        pTotal <- dfE$pTotal[i]
        par(fig = c(0.7, 0.9, 0.6, 0.9), new = TRUE, mar = c(0, 0, 0, 0), bty = "n")
        plot(NA, NA, type = "n", xlab = "", ylab = "", xlim = c(0, 10), ylim = c(0.5, 5.5), xaxt = "n", yaxt = "n")
        text(x = 0, y = 5, labels = bquote(italic("t"["delay"])*"="*.(round(qDelay, digits = 2))), pos = 4, col = "#e76c29")
        text(x = 0, y = 4, labels = bquote(italic("P"["total"])*"="*.(round(pTotal, digits = 2))), pos = 4, col = "#000000")
        dev.off()
      }
      eTable$qDelay[i] <- qDelay
      next
    }

    while (tStart <= nrow(df) && is.na(df$q[tStart])) tStart <- tStart + 1
    if (tStart > nrow(df)) {
      if (!is.null(fName)) dev.off()
      next
    }

    qStart <- df$q[tStart]

    while (tStart <= nrow(df) && df$event[tStart] != 0) tStart <- tStart + 1
    if (tStart > tSearch) {
      if (!is.null(fName)) {
        pTotal <- dfE$pTotal[i]
        par(fig = c(0.7, 0.9, 0.6, 0.9), new = TRUE, mar = c(0, 0, 0, 0), bty = "n")
        plot(NA, NA, type = "n", xlab = "", ylab = "", xlim = c(0, 10), ylim = c(0.5, 5.5), xaxt = "n", yaxt = "n")
        text(x = 0, y = 5, labels = bquote("No "*italic("Q")*" response"), pos = 4, col = "#e76c29")
        text(x = 0, y = 4, labels = bquote(italic("P"["total"])*"="*.(round(pTotal, digits = 2))), pos = 4, col = "#000000")
        dev.off()
      }
      eTable$qDelay[i] <- qDelay
      next
    }

    df$event[tStart] <- i

    t_lim <- if (i == nEvents) {
      df$date[tStart] + as.difftime(maxDur, units = "hours")
    } else {
      min(c(dfE$tStart[i + 1], df$date[tStart] + as.difftime(maxDur, units = "hours")))
    }

    tmp2 <- tmp[tmp$date >= df$date[tStart] & tmp$date <= t_lim, , drop = FALSE]
    qPeak <- max(tmp2$q, na.rm = TRUE)[1]
    if (!is.finite(qPeak)) {
      if (!is.null(fName)) dev.off()
      next
    }

    tPeak <- which(df$date == tmp2$date[!is.na(tmp2$q) & tmp2$q == qPeak][1])[1]
    if (!is.finite(tPeak)) {
      if (!is.null(fName)) dev.off()
      next
    }

    if (!is.null(fName)) {
      points(df$date[tPeak], df$q[tPeak], col = "#c75f39", xpd = NA)
    }

    tEnd <- which(!is.na(df$q) & df$date > df$date[tPeak] & df$q <= qStart)[1]
    if (is.na(tEnd) || tEnd > tSearch) tEnd <- tSearch

    while (tEnd <= nrow(df) && df$event[tEnd] != 0) tEnd <- tEnd + 1
    if (tEnd > nrow(df)) tEnd <- nrow(df)

    df$event[tEnd] <- i
    qEnd <- df$q[tEnd]

    tStart_ts <- df$date[tStart]
    tEnd_ts   <- df$date[tEnd]

    qDur  <- as.numeric(difftime(tEnd_ts, tStart_ts, units = "hours"))
    qDelay <- as.numeric(difftime(tStart_ts, dfE$tStart[i], units = "hours"))
    qIncr <- (qPeak / qStart - 1) * 100
    tDry  <- dfE$tDry[i]

    if (!is.null(fName)) {
      pTotal <- dfE$pTotal[i]
      rect(tStart_ts, 0, tEnd_ts, 20, col = "#c59e8766", border = NA)

      par(fig = c(0.7, 0.9, 0.6, 0.9), new = TRUE, mar = c(0, 0, 0, 0), bty = "n")
      plot(NA, NA, type = "n", xlab = "", ylab = "", xlim = c(0, 10), ylim = c(0.5, 5.5), xaxt = "n", yaxt = "n")
      text(x = 0, y = 5, labels = bquote(italic("t"["delay"])*"="*.(round(qDelay, digits = 2))), pos = 4,
           col = ifelse(qDelay / tStep > maxDelay, "#e76c29", "#000000"))
      text(x = 0, y = 4, labels = bquote(italic("P"["total"])*"="*.(round(pTotal, digits = 2))), pos = 4, col = "#000000")
      text(x = 0, y = 3, labels = bquote(italic("t"["dry"])*"="*.(round(tDry, digits = 2))), pos = 4,
           col = ifelse(tDry < minDry, "#e76c29", "#000000"))
      text(x = 0, y = 2, labels = bquote(italic("Q"["peak"])*"="*.(round(qPeak, digits = 3))*", "*
                                           .(round(qIncr, digits = 1))*"%"), pos = 4,
           col = ifelse((qPeak / qStart) < minPeak, "#e76c29", "#000000"))
      text(x = 0, y = 1, labels = bquote(italic("Q"["end"])*"="*.(round(qEnd, digits = 3))*", "*
                                           .(round(((qEnd - qStart) / (qPeak - qStart)) * 100, digits = 1))*"%"), pos = 4,
           col = ifelse(((qEnd - qStart) / (qPeak - qStart)) > maxEnd, "#e76c29", "#000000"))
      dev.off()
    }

    eTable[i, 2:3] <- format(c(tStart_ts, tEnd_ts), format = "%Y-%m-%d %H:%M:%S")
    eTable[i, 4:9] <- c(qDur, qDelay, qStart, qPeak, qEnd, qIncr)
  }

  if (saveFile != FALSE) {
    write.table(
      eTable,
      paste0(saveFile, "_", format(Sys.time(), format = "%Y%m%d_%H%M"), ".csv"),
      row.names = FALSE, sep = ","
    )
  }

  return(eTable)
}

###############################################################################
# 1) Detect rainfall + discharge events
###############################################################################
message("=== EVENT DETECTION ===")

if (exists("eTable")) rm(eTable)

NF_prec_col  <- detect_prec_col(names(df), "NF")
SHA_prec_col <- detect_prec_col(names(df), "SHA")
TTP_prec_col <- detect_prec_col(names(df), "TTP")

NF_q_col  <- detect_q_col(names(df), "NF")
SHA_q_col <- detect_q_col(names(df), "SHA")
TTP_q_col <- detect_q_col(names(df), "TTP")

if (any(is.na(c(NF_prec_col, SHA_prec_col, TTP_prec_col)))) stop("Missing one or more precipitation columns.")
if (any(is.na(c(NF_q_col, SHA_q_col, TTP_q_col)))) stop("Missing one or more discharge columns.")

# Detect rainfall events
NFp  <- rainEvent(df = df[, c("date", NF_prec_col)],  saveFile = file.path(DIR_Q_SITE[["NF"]], "NF_prec"))
SHAp <- rainEvent(df = df[, c("date", SHA_prec_col)], saveFile = file.path(DIR_Q_SITE[["SHA"]], "SHA_prec"))
TTPp <- rainEvent(df = df[, c("date", TTP_prec_col)], pDry = 3, saveFile = file.path(DIR_Q_SITE[["TTP"]], "TTP_prec"))

# Detect discharge events
NFq <- qEvent(df = df[, c("date", NF_prec_col,  NF_q_col)],
              dfE = NFp, savePlot = file.path(DIR_Q_SITE[["NF"]], "NF_q"), saveFile = file.path(DIR_Q_SITE[["NF"]], "NF_q"))

SHAq <- qEvent(df = df[, c("date", SHA_prec_col, SHA_q_col)],
               dfE = SHAp, savePlot = file.path(DIR_Q_SITE[["SHA"]], "SHA_q"), saveFile = file.path(DIR_Q_SITE[["SHA"]], "SHA_q"),
               minDry = SHA_minDry, minPeak = SHA_minPeak)

TTPq <- qEvent(df = df[, c("date", TTP_prec_col, TTP_q_col)],
               dfE = TTPp, savePlot = file.path(DIR_Q_SITE[["TTP"]], "TTP_q"), saveFile = file.path(DIR_Q_SITE[["TTP"]], "TTP_q"),
               maxEnd = TTP_maxEnd)

# Selection helpers
get_latest_event_folder <- function(prefix, root) {
  cand <- list.dirs(path = root, full.names = TRUE, recursive = FALSE)
  cand <- cand[grepl(paste0("^", prefix, "_events_"), basename(cand))]
  if (length(cand) == 0) stop("No plot folders found for prefix = ", prefix, " under ", root)
  cand[which.max(file.info(cand)$mtime)]
}

copy_event_plots <- function(folder, event_ids) {
  event_ids <- sort(unique(as.integer(event_ids[!is.na(event_ids)])))
  if (length(event_ids) == 0) return(invisible(FALSE))

  dest <- file.path(folder, "OrigSel")
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)

  from_files <- file.path(folder, paste0("Event_", event_ids, ".png"))
  from_files <- from_files[file.exists(from_files)]

  if (length(from_files) == 0) return(invisible(FALSE))
  file.copy(from = from_files, to = dest, overwrite = TRUE)
  invisible(TRUE)
}

###############################################################################
# 2) SELECTION + LOCK FINAL EVENT UNIVERSE
###############################################################################
message("=== EVENT SELECTION ===")

NFfolder  <- get_latest_event_folder("NF_q", DIR_Q_SITE[["NF"]])
SHAfolder <- get_latest_event_folder("SHA_q", DIR_Q_SITE[["SHA"]])
TTPfolder <- get_latest_event_folder("TTP_q", DIR_Q_SITE[["TTP"]])

## Natural forest
NFsel <- NFq$ID[
  !is.na(NFq$tStart) &
    NFp$tDry >= NF_minDry &
    NFq$qPeak / NFq$qStart >= NF_minPeak &
    (NFq$qEnd - NFq$qStart) / (NFq$qPeak - NFq$qStart) < NF_maxEnd
]
NFsel <- sort(unique(as.integer(NFsel[!is.na(NFsel)])))
NFfinal <- NFsel
copy_event_plots(NFfolder, NFfinal)

## Smallholder agriculture
SHAsel <- SHAq$ID[
  !is.na(SHAq$tStart) &
    SHAp$tDry >= SHA_minDry &
    SHAq$qPeak / SHAq$qStart >= SHA_minPeak &
    (SHAq$qEnd - SHAq$qStart) / (SHAq$qPeak - SHAq$qStart) < SHA_maxEnd
]
SHAsel <- sort(unique(as.integer(SHAsel[!is.na(SHAsel)])))
SHAfinal <- SHAsel
copy_event_plots(SHAfolder, SHAfinal)

## Tea/tree plantation
TTPsel <- TTPq$ID[
  !is.na(TTPq$tStart) &
    TTPp$tDry >= TTP_minDry &
    TTPq$qPeak / TTPq$qStart >= TTP_minPeak &
    (TTPq$qEnd - TTPq$qStart) / (TTPq$qPeak - TTPq$qStart) < TTP_maxEnd
]
TTPsel <- sort(unique(as.integer(TTPsel[!is.na(TTPsel)])))
TTPfinal <- TTPsel
copy_event_plots(TTPfolder, TTPfinal)

cat("\n--- final selected counts ---\n")

# 3) FINAL COMBINED EVENT TABLE ACROSS SITES (eTable) [EXACT-ID LOCK]
###############################################################################
message("=== BUILD FINAL eTable (EXACT-ID LOCK) ===")

normalize_eTable_pre <- function(eTable_in, sites, tz = TZ_USE) {
  eTable_in %>%
    mutate(
      site   = trimws(as.character(site)),
      ID     = suppressWarnings(as.integer(ID)),
      pStart = .parse_dt(pStart, tz = tz),
      pEnd   = .parse_dt(pEnd,   tz = tz),
      tStart = .parse_dt(tStart, tz = tz),
      tEnd   = .parse_dt(tEnd,   tz = tz)
    ) %>%
    filter(site %in% sites, !is.na(ID)) %>%
    distinct(site, ID, .keep_all = TRUE) %>%
    arrange(site, ID)
}

make_event_key_pre <- function(eTable_in) {
  eTable_in %>%
    distinct(site, ID) %>%
    arrange(site, ID)
}

build_site_event_table <- function(site_name, eventP, eventQ, final_ids) {

  final_ids <- sort(unique(as.integer(final_ids[!is.na(final_ids)])))

  eventP <- eventP %>% mutate(ID = suppressWarnings(as.integer(ID)))
  eventQ <- eventQ %>% mutate(ID = suppressWarnings(as.integer(ID)))

  colnames(eventP)[2:3] <- c("pStart", "pEnd")

  eventP2 <- eventP %>% filter(ID %in% final_ids) %>% distinct(ID, .keep_all = TRUE)
  eventQ2 <- eventQ %>% filter(ID %in% final_ids) %>% distinct(ID, .keep_all = TRUE)

  miss_p <- setdiff(final_ids, eventP2$ID)
  miss_q <- setdiff(final_ids, eventQ2$ID)

  if (length(miss_p) > 0) stop(site_name, ": missing final IDs in rainfall table: ", paste(miss_p, collapse = ", "))
  if (length(miss_q) > 0) stop(site_name, ": missing final IDs in discharge table: ", paste(miss_q, collapse = ", "))

  out <- tibble(ID = final_ids) %>%
    left_join(eventP2, by = "ID") %>%
    left_join(eventQ2, by = "ID") %>%
    mutate(site = site_name) %>%
    arrange(match(ID, final_ids))

  if (!identical(out$ID, final_ids)) {
    stop(site_name, ": eTable IDs are not identical to final_ids after join.")
  }

  out
}

eTable_list <- list(
  NF  = build_site_event_table("NF",  NFp,  NFq,  NFfinal),
  SHA = build_site_event_table("SHA", SHAp, SHAq, SHAfinal),
  TTP = build_site_event_table("TTP", TTPp, TTPq, TTPfinal)
)

eTable <- bind_rows(eTable_list)

# Add season WITHOUT DUPLICATING ROWS
if ("season" %in% names(df)) {
  season_lookup <- df %>%
    transmute(
      date = .parse_dt(date, tz = TZ_USE),
      season = as.character(season)
    ) %>%
    distinct(date, .keep_all = TRUE)

  eTable$pStart <- .parse_dt(eTable$pStart, tz = TZ_USE)
  idx <- match(eTable$pStart, season_lookup$date)
  eTable$season <- season_lookup$season[idx]
} else {
  eTable$season <- NA_character_
}

eTable$season <- factor(as.character(eTable$season), levels = season_levels)

# Normalize + exact audit against final arrays
eTable <- normalize_eTable_pre(eTable, sites, tz = TZ_USE)

eTable_ids <- eTable %>%
  distinct(site, ID) %>%
  arrange(site, ID)

# Create an on-the-fly reference table for auditing instead of final_ref
audit_ref <- bind_rows(
  tibble(site = "NF",  ID = NFfinal),
  tibble(site = "SHA", ID = SHAfinal),
  tibble(site = "TTP", ID = TTPfinal)
) %>%
  filter(!is.na(ID)) %>%
  distinct(site, ID) %>%
  arrange(site, ID)

extra_in_eTable <- anti_join(eTable_ids, audit_ref, by = c("site", "ID"))
missing_in_eTable <- anti_join(audit_ref, eTable_ids, by = c("site", "ID"))

cat("\n--- eTable counts after exact lock ---\n")
print(eTable_ids %>% count(site, name = "n_eTable"))

if (nrow(extra_in_eTable) > 0 || nrow(missing_in_eTable) > 0) {
  cat("\n--- extra IDs in eTable ---\n")
  print(extra_in_eTable)
  cat("\n--- missing IDs in eTable ---\n")
  print(missing_in_eTable)
  stop("eTable does not exactly match original final arrays. Stopping here.")
}

# Construct expected vector dynamically to replace expected_counts
expected_counts <- c(
  NF  = length(NFfinal),
  SHA = length(SHAfinal),
  TTP = length(TTPfinal)
)

count_check <- eTable_ids %>% count(site, name = "n_eTable")
for (ss in names(expected_counts)) {
  got <- count_check$n_eTable[count_check$site == ss]
  if (length(got) != 1 || got != expected_counts[[ss]]) {
    stop(ss, ": expected ", expected_counts[[ss]], " final events but eTable has ", got)
  }
}

EVENTS_FINAL_CSV <- file.path(DIR_Q_EVENTS, "events_final.csv")

if (file.exists(EVENTS_FINAL_CSV)) file.remove(EVENTS_FINAL_CSV)
write.csv(eTable, EVENTS_FINAL_CSV, row.names = FALSE)

cat("\nLocked events_final.csv written successfully to:\n", EVENTS_FINAL_CSV, "\n")

# Print final event summary rainfall-discharge events
print(eTable %>% group_by(site) %>% summarise(n_events = n(), .groups = "drop"))

###############################################################################
# 4) GUARD BEFORE CONCLUSIVE TABLE / ANY LATER BLOCK
###############################################################################
message("=== PRE-CONCLUSIVE GUARD ===")

# Read the newly exported 2015-2020 csv file from disk
events_final_disk <- read.csv(EVENTS_FINAL_CSV, stringsAsFactors = FALSE) %>%
  mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID))
  ) %>%
  distinct(site, ID) %>%
  arrange(site, ID)

# Re-verify against our dynamic 2015-2020 memory array instead of final_ref
extra_on_disk   <- anti_join(events_final_disk, audit_ref, by = c("site", "ID"))
missing_on_disk <- anti_join(audit_ref, events_final_disk, by = c("site", "ID"))

cat("\n--- disk events_final.csv counts (2015-2020) ---\n")
print(events_final_disk %>% count(site, name = "n_disk"))

if (nrow(extra_on_disk) > 0 || nrow(missing_on_disk) > 0) {
  cat("\n--- extra IDs on disk ---\n")
  print(extra_on_disk)
  cat("\n--- missing IDs on disk ---\n")
  print(missing_on_disk)
  stop("CRITICAL ERROR: events_final.csv on disk does not match memory selections.")
}

# Lock the key structure for the upcoming Water Quality loop metrics
event_key_master <- make_event_key_pre(eTable)
message("Pre-conclusive guard passed successfully. Memory and disk are aligned!")

###############################################################################

###############################################################################
# 5) WQ SCREENING AND AUDIT DIAGNOSTICS 
# How many events will survive the 90% completeness check and
# how many are responsive under your current thresholds
###############################################################################
message("=== RUNNING WATER QUALITY SCREENING AUDIT ===")

# --- HARDCODED USER SETTINGS FOR ENFORCED LOGIC ---
min_completeness  <- 0.90   # 90% data density check
HI_only_if_return <- FALSE   # Gate HI calculation by baseline return
solute_list       <- c("NO3", "DOC", "EC", "TSS")

# Ensure global threshold objects exist in memory from section 2.4
if (!exists("resp_thresh")) resp_thresh <- 0.15
if (!exists("ret_thresh"))  ret_thresh  <- 0.20

audit_list <- list()

for (s in sites) {
  et_s <- eTable %>% filter(site == s)
  if(nrow(et_s) == 0) next

  q_col <- detect_q_col(names(df), s)
  vars_map <- c(
    NO3 = detect_wq_col(names(df), s, "NO3"),
    DOC = detect_wq_col(names(df), s, "DOC"),
    EC  = detect_wq_col(names(df), s, "EC"),
    TSS = detect_wq_col(names(df), s, "TSS")
  )

  site_total <- nrow(et_s)

  # Track events with at least one complete solute to replace global gate metric
  passed_any_comp <- 0

  # Track completeness counts per individual solute
  comp_counts <- c(NO3 = 0, DOC = 0, EC = 0, TSS = 0)
  # Track responsiveness counts per individual solute
  resp_counts <- c(NO3 = 0, DOC = 0, EC = 0, TSS = 0)

  for (i in seq_len(nrow(et_s))) {
    ev <- et_s[i, ]

    # Isolate window
    vars_exist <- vars_map[!is.na(vars_map) & vars_map %in% names(df)]
    datWQ <- df %>% filter(date >= ev$tStart & date <= ev$tEnd)

    # Check data presence completeness
    comp <- sapply(unname(vars_exist), function(v) {
      x <- datWQ[[v]]
      if (length(x) == 0) return(0)
      if (all(is.na(x))) return(0)
      mean(!is.na(x))
    })

    # Flag to see if this storm had any valid water quality data
    has_valid_solute <- FALSE
    # Test completeness and responsiveness per individual solute (Decoupled Logic)
    for (p in names(vars_map)) {
      vname <- vars_map[[p]]
      if (!is.na(vname) && vname %in% names(df)) {

        # 1. Check solute-specific completeness first
        solute_comp <- if (vname %in% names(comp)) comp[[vname]] else 0
        if (solute_comp >= min_completeness) {
          comp_counts[p] <- comp_counts[p] + 1
          has_valid_solute <- TRUE

          # 2. Evaluate responsiveness if completeness check passes
          C <- to_num(datWQ[[vname]])
          C0 <- calc_event_C0(
            df = df,
            col = vname,
            tStart = ev$tStart
          )

          if (is.finite(C0) && C0 > 0 && length(C) > 0 && !all(is.na(C))) {
            resp_info <- calc_response(C, C0)
            if (is.finite(resp_info$response) && (resp_info$response >= resp_thresh)) {
              resp_counts[p] <- resp_counts[p] + 1
            }
          }
        }
      }
    }
    if (has_valid_solute) {
      passed_any_comp <- passed_any_comp + 1
    }
  }

  cat(sprintf("\n[SITE %s]:\n", s))
  cat(sprintf("  -> Total Physical Storm Events (Gate A): %d\n", site_total))
  cat(sprintf("  -> Events with >=1 Complete Solute (90%%): %d (%.1f%%)\n",
              passed_any_comp, (passed_any_comp / site_total) * 100))
  cat("  -> Summary Per Solute Parameter:\n")
  for(p in names(vars_map)) {
    cat(sprintf("     * %s:\n", p))
    cat(sprintf("       - Passed 90%% Data Density Check:   %d events\n", comp_counts[p]))
    cat(sprintf("       - Responsive (out of complete):   %d events (under resp_thresh = %.2f)\n",
                resp_counts[p], resp_thresh))
  }
}

###############################################################################
# 6) CONCLUSIVE EVENT TABLE (Rainfall + Hydrology + Antecedent + WQ)  [FULL]
# - Computes ALL hydrology + rainfall metrics per event
# - Computes WQ event metrics (response/return/HI/FI/C-Q slopes/loads) per solute
# - Uses robust column detection (detect_* helpers from earlier in your script)
# - Outputs: Events_Conclusive_Table_AllMetrics.csv (+ optional diagnostics)
###############################################################################
message("=== CONCLUSIVE TABLE (ALL METRICS + WQ METRICS) ===")

# REQUIREMENTS (must exist from previous sections)
stopifnot(exists("df"), exists("eTable"), exists("sites"), exists("catchment_area_km2"))
stopifnot(exists("TZ_USE"), exists("resp_thresh"), exists("ret_thresh"))
stopifnot(exists("API_days"), exists("API_k"))
stopifnot(exists("detect_prec_col"), exists("detect_q_col"), exists("detect_wq_col"))
stopifnot(exists(".parse_dt"), exists("to_num"), exists("get_dt_seconds"))
stopifnot(exists("calc_API_GW"), exists("calc_response"), exists("calc_return_ratio"))
stopifnot(exists("calc_HI_Lloyd"), exists("calc_HI_Zuecco"), exists("calc_m_CQ"))
stopifnot(exists("calc_FI_peak"), exists("calc_FI_mean"))
stopifnot(exists("calc_RB"), exists("calc_recession_k"))

# USER SETTINGS (WQ block)
min_completeness  <- 0.90
HI_only_if_return <- FALSE
solute_list       <- c("NO3", "DOC", "EC", "TSS")
resp_thresh       <- 0.15
ret_thresh        <- 0.20

# NEW LOGIC: HELPER FOR INSTANTANEOUS DOMINANT STATUS INTEGRATION (Section 2.7)
calc_event_dominant_status_screening <- function(C_values, C0, thresh = 0.15) {
  C_clean <- suppressWarnings(as.numeric(C_values))
  C_clean <- C_clean[is.finite(C_clean)]
  if (length(C_clean) == 0L || !is.finite(C0) || C0 <= 0) return("Unclassified/NA")
  st_ratios <- (C_clean - C0) / C0
  timesteps_status <- dplyr::case_when(
    st_ratios >  thresh ~ "Mobilization",
    st_ratios < -thresh ~ "Dilution",
    TRUE                ~ "Chemostasis"
  )
  status_counts <- table(
    factor(timesteps_status,
           levels = c("Chemostasis", "Mobilization", "Dilution"))
  )
  if (sum(status_counts) == 0L) return("Unclassified/NA")
  names(status_counts)[which.max(status_counts)]
}

# NEW LOGIC: CALCULATE RECALCULATED FLOW REGIMES FROM THE CONTINUOUS DAILY DATASET (SJ11)
message("Calculating baseline flow thresholds from entire continuous dataset...")
flow_regimes_full <- list()

for (s in sites) {
  q_col_name <- detect_q_col(names(df), s)
  if (!is.na(q_col_name) && q_col_name %in% names(df)) {
    continuous_q <- tibble::tibble(
      date = as.Date(df$date, tz = TZ_USE),
      Q = to_num(df[[q_col_name]])
    ) %>%
      dplyr::filter(!is.na(date), is.finite(Q), Q > 0) %>%
      dplyr::group_by(date) %>%
      dplyr::summarise(
        Q_daily = mean(Q, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      dplyr::pull(Q_daily)

    # Long-term daily-flow regime boundaries (33rd and 66th percentiles).
    thresh_q <- stats::quantile(
      continuous_q,
      probs = c(0.33, 0.66),
      na.rm = TRUE,
      names = FALSE
    )
    flow_regimes_full[[s]] <- list(low = thresh_q[1], high = thresh_q[2])
  }
}

# Standardize / coerce eTable
eTable2 <- eTable %>%
  mutate(
    site   = trimws(as.character(site)),
    ID     = suppressWarnings(as.integer(ID)),
    pStart = .parse_dt(pStart, tz = TZ_USE),
    pEnd   = .parse_dt(pEnd, tz = TZ_USE),
    tStart = .parse_dt(tStart, tz = TZ_USE),
    tEnd   = .parse_dt(tEnd, tz = TZ_USE)
  )

# WQ METRICS LOOP GENERATION MATRIX
make_empty_wq_out_screening <- function(solutes = solute_list) {
  out <- tibble()
  for (p in solutes) {
    empty_solute_metrics <- tibble(
      !!paste0("comp_", p)         := NA_real_,
      !!paste0("C0_", p)           := NA_real_,
      !!paste0("response_", p)     := FALSE,      # Force logical defaults to preserve structures
      !!paste0("max_dev_", p)      := NA_real_,
      !!paste0("peak_", p)         := NA_real_,
      !!paste0("return_", p)       := FALSE,      # Force logical defaults to preserve structures
      !!paste0("ret_ratio_", p)    := NA_real_,
      !!paste0("HI_Lloyd_", p)     := NA_real_,
      !!paste0("HI_Zuecco_", p)    := NA_real_,
      !!paste0("m_rise_", p)       := NA_real_,
      !!paste0("m_fall_", p)       := NA_real_,
      !!paste0("m_mean_", p)       := NA_real_,
      !!paste0("FI_peak_", p)      := NA_real_,
      !!paste0("FI_mean_", p)      := NA_real_,
      !!paste0("Chemical_Status_", p) := "Unclassified/NA"
    )
    if (nrow(out) == 0) out <- empty_solute_metrics else out <- bind_cols(out, empty_solute_metrics)
  }
  return(out)
}

compute_WQ_ev_one_screening <- function(df, ev, q_col, vars_map, min_comp = 0.90, dt_fallback_s = NA_real_) {
  if (is.na(q_col) || !(q_col %in% names(df)) || is.na(ev$tStart) || is.na(ev$tEnd) || ev$tEnd < ev$tStart) {
    wq_out <- make_empty_wq_out_screening()
    return(bind_cols(tibble(site = ev$site, ID = ev$ID, n_response = 0L, n_return = 0L), wq_out))
  }

  vars_exist <- vars_map[!is.na(vars_map) & vars_map %in% names(df)]
  datWQ <- df %>%
    filter(date >= ev$tStart & date <= ev$tEnd) %>%
    select(date, Q = all_of(q_col), any_of(unname(vars_exist))) %>%
    mutate(Q = to_num(Q), across(any_of(unname(vars_exist)), ~ to_num(.x)))

  dt_s <- get_dt_seconds(datWQ$date)
  if (!is.finite(dt_s) || dt_s <= 0) dt_s <- dt_fallback_s

  comp <- sapply(unname(vars_exist), function(v) {
    x <- datWQ[[v]]
    if (length(x) == 0 || all(is.na(x))) return(0)
    mean(!is.na(x))
  })
  wq_out     <- tibble()
  n_response <- 0L
  n_return   <- 0L
  Q          <- datWQ$Q

  for (p in names(vars_map)) {
    vname <- vars_map[[p]]
    solute_comp <- if (!is.na(vname) && vname %in% names(comp)) comp[[vname]] else 0

    if (is.na(vname) || !(vname %in% names(df)) || solute_comp < min_comp) {
      solute_tbl <- tibble(
        !!paste0("comp_", p)         := solute_comp,
        !!paste0("C0_", p)           := NA_real_,
        !!paste0("response_", p)     := FALSE,
        !!paste0("max_dev_", p)      := NA_real_,
        !!paste0("peak_", p)         := NA_real_,
        !!paste0("return_", p)       := FALSE,
        !!paste0("ret_ratio_", p)    := NA_real_,
        !!paste0("HI_Lloyd_", p)     := NA_real_,
        !!paste0("HI_Zuecco_", p)    := NA_real_,
        !!paste0("m_rise_", p)       := NA_real_,
        !!paste0("m_fall_", p)       := NA_real_,
        !!paste0("m_mean_", p)       := NA_real_,
        !!paste0("FI_peak_", p)      := NA_real_,
        !!paste0("FI_mean_", p)      := NA_real_,
        !!paste0("Chemical_Status_", p) := "Unclassified/NA"
      )
      wq_out <- if (nrow(wq_out) == 0) solute_tbl else bind_cols(wq_out, solute_tbl)
      next
    }

    C  <- datWQ[[vname]]
    C0 <- calc_event_C0(
      df = df,
      col = vname,
      tStart = ev$tStart
    )

    # 1. Compute Base Responsiveness Flags
    resp_info     <- calc_response(C, C0)
    response_flag <- if (is.finite(resp_info$response) && resp_info$response >= resp_thresh) TRUE else FALSE
    if (response_flag) n_response <- n_response + 1L

    # 2. Compute Return and Boundary Return Constraints
    end_val      <- tail(C[!is.na(C)], 1)
    ret_ratio    <- if (length(end_val) > 0) calc_return_ratio(end_val, C0, resp_info$peak) else NA_real_
    return_flag  <- if (is.finite(ret_ratio) && ret_ratio <= ret_thresh) TRUE else FALSE
    chem_status <- calc_event_dominant_status_screening(
      C_values = C,
      C0 = C0,
      thresh = resp_thresh
    )

    if (return_flag) n_return <- n_return + 1L

    # 3. CRITICAL STRUCTURAL UPDATE: Strict Dual-Constraint Gate Check for Hysteresis Indices (Section 2.5)
    do_hi <- isTRUE(response_flag)

    hi_l <- if (do_hi) calc_HI_Lloyd(Q, C, C0) else NA_real_
    hi_z <- if (do_hi) calc_HI_Zuecco(Q, C) else NA_real_

    # Slopes and Concentration Metrics
    slopes <- calc_m_CQ(Q, C)
    fi_p   <- calc_FI_peak(C0, resp_info$peak)
    fi_m   <- calc_FI_mean(C0, mean(C, na.rm = TRUE))

    solute_tbl <- tibble(
      !!paste0("comp_", p)         := solute_comp,
      !!paste0("C0_", p)           := C0,
      !!paste0("response_", p)     := response_flag,   # Saved explicitly as structural boolean
      !!paste0("max_dev_", p)      := resp_info$response,
      !!paste0("peak_", p)         := resp_info$peak,
      !!paste0("return_", p)       := return_flag,     # Saved explicitly as structural boolean
      !!paste0("ret_ratio_", p)    := ret_ratio,
      !!paste0("HI_Lloyd_", p)     := hi_l,
      !!paste0("HI_Zuecco_", p)    := hi_z,
      !!paste0("m_rise_", p)       := slopes[["m_rise"]],
      !!paste0("m_fall_", p)       := slopes[["m_fall"]],
      !!paste0("m_mean_", p)       := slopes[["m_mean"]],
      !!paste0("FI_peak_", p)      := fi_p,
      !!paste0("FI_mean_", p)      := fi_m,
      !!paste0("Chemical_Status_", p) := chem_status
    )

    wq_out <- if (nrow(wq_out) == 0) solute_tbl else bind_cols(wq_out, solute_tbl)
  }

  return(bind_cols(tibble(site = ev$site, ID = ev$ID, n_response = n_response, n_return = n_return), wq_out))
}

# --- Compile Water Quality Array Across All Events ---
wq_list   <- list()
diag_tbl  <- list()
dt_fall_s <- if (exists("dt_df_s")) dt_df_s else 600

for (s in sites) {
  et_s <- eTable2 %>% filter(site == s)
  if (nrow(et_s) == 0) next

  q_col    <- detect_q_col(names(df), s)
  vars_map <- c(
    NO3 = detect_wq_col(names(df), s, "NO3"),
    DOC = detect_wq_col(names(df), s, "DOC"),
    EC  = detect_wq_col(names(df), s, "EC"),
    TSS = detect_wq_col(names(df), s, "TSS")
  )

  for (i in seq_len(nrow(et_s))) {
    # FIX: Extract rows using matrix/dataframe brackets [i, ] instead of function calls ( )
    row_wq <- compute_WQ_ev_one_screening(df, et_s[i, ], q_col, vars_map, min_comp = min_completeness, dt_fallback_s = dt_fall_s)

    # FIX: Correct the element allocation syntax using double brackets [[ ]] for lists
    wq_list[[length(wq_list) + 1]] <- row_wq
    diag_tbl[[length(diag_tbl) + 1]] <- tibble(
      site       = et_s[i, ]$site,
      ID         = et_s[i, ]$ID,
      n_response = row_wq$n_response,
      n_return   = row_wq$n_return
    )
  }
}

WQ_ev <- bind_rows(wq_list)

# HYDROMETRIC BASELINE PROFILE CLASSIFICATION BLOCK
events_hydrology <- eTable2 %>%
  rowwise() %>%
  mutate(
    Flow_Class = {
      bounds_i <- flow_regimes_full[[as.character(site)]]
      if (
        is.null(bounds_i) ||
        !is.finite(qStart) ||
        !is.finite(bounds_i$low) ||
        !is.finite(bounds_i$high)
      ) {
        "Unclassified"
      } else if (qStart < bounds_i$low) {
        "Low Flow Regime"
      } else if (qStart > bounds_i$high) {
        "High Flow Regime"
      } else {
        "Mid Flow Regime"
      }
    }
  ) %>%
  ungroup()

# CONSOLIDATE AND BUILD SINGLE SOURCE OF TRUTH CONCLUSIVE TABLE
events_conclusive <- events_hydrology

if (nrow(events_conclusive) > 0 && nrow(WQ_ev) > 0) {
  events_conclusive <- events_conclusive %>%
    mutate(
      site = trimws(as.character(site)),
      ID   = suppressWarnings(as.integer(ID))
    ) %>%
    left_join(WQ_ev, by = c("site", "ID"))
}

# Define outputs paths
conclusive_csv_path  <- file.path(DIR_Q_EVENTS, "Events_Conclusive_Table_AllMetrics.csv")
diagnostics_csv_path <- file.path(DIR_Q_EVENTS, "Events_Conclusive_DIAGNOSTICS.csv")

write_csv_safe(events_conclusive, conclusive_csv_path, row.names = FALSE)
write.csv(bind_rows(diag_tbl), diagnostics_csv_path, row.names = FALSE)

Events_Conclusive_Table_AllMetrics <- events_conclusive

# VERIFICATION AUDIT PRINT METHOD (PERFECT LOGICAL MATCHING GUARANTEED)
cat("\n--- FIXED: WQ_ev response counts before join ---\n")
print(
  WQ_ev %>%
    summarise(across(starts_with("response_"), ~ sum(.x == TRUE, na.rm = TRUE)))
)
message("Saved conclusively compiled master frames to: ", normalizePath(conclusive_csv_path))

#  SPACE-OPTIMIZED, DYNAMIC SCALES, FIXED LABELS
# Save File Updated to: "HI_Lloyd_hysteresis_distribution.png"
message("Initializing master data transformation and formatting layout for Fig6B...")

# --- STEP 1: CALCULATE THE ENTIRE HYDROMETRIC PERC_TABLE BOUNDARIES ---
flow_regimes_full <- list()
for (s in sites) {
  q_col_name <- detect_q_col(names(df), s)
  if (!is.na(q_col_name) && q_col_name %in% names(df)) {
    continuous_q <- tibble::tibble(
      date = as.Date(df$date, tz = TZ_USE),
      Q = to_num(df[[q_col_name]])
    ) %>%
      dplyr::filter(!is.na(date), is.finite(Q), Q > 0) %>%
      dplyr::group_by(date) %>%
      dplyr::summarise(
        Q_daily = mean(Q, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      dplyr::pull(Q_daily)

    # Long-term daily-flow regime boundaries (33rd and 66th percentiles).
    thresh_q <- stats::quantile(
      continuous_q,
      probs = c(0.33, 0.66),
      na.rm = TRUE,
      names = FALSE
    )
    flow_regimes_full[[s]] <- list(low = thresh_q[1], high = thresh_q[2])
  }
}

# --- STEP 2: RE-CLASSIFY EXCEEDANCE LEVELS AND ASSIGN MATCHED FACTOR LEVELS ---
Events_Conclusive_Table_AllMetrics <- Events_Conclusive_Table_AllMetrics %>%
  rowwise() %>%
  mutate(
    regime_bounds = list(flow_regimes_full[[site]]),
    Flow_Class = case_when(
      is.null(regime_bounds)       ~ "Low Flow",
      qStart < regime_bounds$low   ~ "Low Flow",
      qStart > regime_bounds$high  ~ "High Flow",
      TRUE                         ~ "Mid Flow"
    )
  ) %>%
  ungroup() %>%
  # Enforce order on the factor so R plots Low -> Mid -> High across your charts
  mutate(Flow_Class = factor(Flow_Class, levels = c("Low Flow", "Mid Flow", "High Flow")))

# --- STEP 3: CONFIGURE THE PLOTTING CANVAS WITH INCREASED TEXT MARGINS ---
# UPDATED: Changed image target name to match requested title framework
fig6b_path <- file.path(DIR_Q_EVENTS, "HI_Lloyd_hysteresis_distribution_initial.png")
png(fig6b_path, width = 25, height = 34, units = "cm", res = 300)

# Expanded bottom margins (mar = 4.5) and bottom outer margin (oma = 3) to prevent cut-offs
par(mfrow = c(5, 3), mar = c(4.5, 5.0, 2.5, 1.5), oma = c(3, 2, 1, 1))

row_labels <- c("Discharge (Q)", "Nitrate (NO3)", "DOC", "EC", "TSS")
solutes    <- c("NO3", "DOC", "EC", "TSS")

# --- ROW 1: HYDROMETRIC DISTRIBUTIONS (WITH RE-POSITIONED AXIS LABELS) ---
for (s in sites) {
  plot_data <- Events_Conclusive_Table_AllMetrics %>% filter(site == s)
  if (nrow(plot_data) > 0) {
    hist(plot_data$qStart,
         main = paste(s, "-", row_labels[1]),
         col = "#474973", border = "white",
         xlab = "", ylab = "Storm Frequency", # Left blank to handle via custom mtext line
         las = 1, cex.main = 1.1)

    # mgp-style injection to lower the title text line safely away from your tick markers
    mtext(expression("Initial Q [m"^3*"s"^-1*"]"), side = 1, line = 2.5, cex = 0.85)
  } else {
    plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
    text(1, 1, paste("No Data for", s))
  }
}

# --- ROWS 2-5: DYNAMIC CO-ALIGNED WATER QUALITY SCALES ---
for (row_idx in 2:5) {
  p_name <- solutes[row_idx - 1]
  hi_col <- paste0("HI_Lloyd_", p_name)

  # Calculate extended bounds across sites to ensure every single whisker cap renders
  whisker_extremes <- c()
  for (s in sites) {
    site_data <- Events_Conclusive_Table_AllMetrics %>%
      filter(site == s, is.finite(get(hi_col)), !is.na(Flow_Class))
    if (nrow(site_data) > 0) {
      bp_calc <- boxplot(get(hi_col) ~ Flow_Class, data = site_data, plot = FALSE)
      whisker_extremes <- c(whisker_extremes, bp_calc$stats[c(1, 5), ])
    }
  }

  if (length(whisker_extremes) > 0) {
    true_min <- min(whisker_extremes, na.rm = TRUE)
    true_max <- max(whisker_extremes, na.rm = TRUE)
    padding  <- (true_max - true_min) * 0.10 # 10% padding boundary clearance
    y_limits <- c(min(true_min - padding, -0.05), max(true_max + padding, 0.05))
  } else {
    y_limits <- c(-1, 1)
  }

  # Build the site-specific panel sub-plots
  for (s in sites) {
    plot_data <- Events_Conclusive_Table_AllMetrics %>% filter(site == s)
    clean_plot_data <- plot_data %>% filter(is.finite(get(hi_col)), !is.na(Flow_Class))

    if (nrow(clean_plot_data) > 0) {
      panel_color <- switch(p_name, "NO3" = "#8ca6ab", "DOC" = "#c59e87", "EC" = "#b0a8b9", "TSS" = "#a3b899")

      # Plot the box matrix without default x-axes to let our custom axis build the layout cleanly
      boxplot(get(hi_col) ~ Flow_Class,
              data = clean_plot_data,
              main = paste(s, "-", row_labels[row_idx]),
              col = panel_color,
              xaxt = "n", # Suppress native labels to avoid text dropouts
              xlab = "",
              ylab = bquote("Hysteresis Index (" * italic("HI")["Lloyd"] * ")"),
              ylim = y_limits,
              las = 1,
              notch = FALSE,
              cex.axis = 0.95,
              cex.main = 1.1)

      # Force a horizontal reference line at zero to separate loop topologies
      abline(h = 0, lty = 2, col = "gray40", lwd = 1.2)

      # MANUALLY BUILD AXIS LABELS: Fixes the missing category bug instantly
      axis(side = 1, at = 1:3, labels = c("Low Flow", "Mid Flow", "High Flow"),
           cex.axis = 0.95, padj = 0.3)

    } else {
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, paste("No Gated Events\nfor", p_name), cex = 0.9, col = "gray50")
    }
  }
}

# Safely close down graphics devices and flush background memory to the file location
dev.off()
message("SUCCESS: Optimized Figure 6B saved as 'HI_Lloyd_hysteresis_distribution.png'!")

# ========================= PUBLICATION FIGURE 2 =========================
# 1) Use one daily summary statistic per variable:
#    - Discharge = daily mean
#    - Precipitation = daily sum
#    - NO3, DOC, EC = daily median
#    - TSS = daily maximum
# 2) Show clear internal panel statistics:
#    - Discharge row: responsive-event count, mean Q, peak Q
#    - Constituent rows: mean, max, CV
# 3) Keep a common y-scale within each variable row across the three sites.
###############################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(lubridate)
})

if ("package:plyr" %in% search()) {
  detach("package:plyr", unload = TRUE)
}

# 1. FIGURE SETTINGS

FIG6B_FILENAME <- file.path(DIR_MAIN_FIG_PNG, "Figure2.png")

# High-resolution export for manuscript use
FIG6B_WIDTH_CM   <- 48
FIG6B_HEIGHT_CM  <- 40
FIG6B_RES_DPI    <- 800

# Main typography
FIG6B_CEX_AXIS        <- 1.80   # y-axis numerical values
FIG6B_CEX_YEAR        <- 1.55   # year labels
FIG6B_CEX_MAIN        <- 1.95   # NF / SHA / TTP
FIG6B_CEX_YLAB        <- 1.60   # row-axis titles
FIG6B_CEX_STATS       <- 1.80   # internal statistics
FIG6B_CEX_ROW_LABEL   <- 1.90   # Discharge, NO3-N, DOC, EC, TSS
FIG6B_CEX_PRECIP_AXIS <- 1.35
FIG6B_CEX_DATE        <- 1.70

FIG6B_BOX_LWD <- 1.15

# Vertical positioning inside each panel.
# Fractions are measured downward from the top of the plotting region.
FIG6B_ROW_LABEL_TOP_FRAC <- 0.045
FIG6B_STATS_TOP_FRAC     <- 0.155

FIG6B_SHOW_STATS <- TRUE

# Fixed NO3 maximum is fine here because the panel range in your adopted figure
# is already visually appropriate and comparable across sites.
FIG6B_NO3_YMAX <- 4
FIG6B_EC_YMIN <- 20   #fix EC min

# Keep the EC plotting cap only for visual readability.
# IMPORTANT: summary statistics below still use the full reported values.
FIG6B_EC_REMOVE_EXTREME_OUTLIER <- TRUE
FIG6B_EC_CAP_PROB <- 0.999

FIG6B_PRECIP_COL      <- "grey80"
FIG6B_PRECIP_LINE_COL <- "grey75"
FIG6B_PRECIP_AXIS_COL <- "black"
FIG6B_PRECIP_LWD      <- 0.9

sites     <- c("NF", "SHA", "TTP")
vars_grid <- c("Discharge", "NO3", "DOC", "EC", "TSS")
vars_all  <- c("Precipitation", "Discharge", "NO3", "DOC", "EC", "TSS")

# Consistent manuscript constituent colours
var_colors <- c(
  Discharge = "black",
  NO3       = "#ff3b30",
  DOC       = "#d8a11d",
  EC        = "#a64cff",
  TSS       = "#2ca02c"
)

# Reviewer-facing label text
row_label_map <- c(
  Discharge = "Discharge",
  NO3       = paste0("NO", "\u2083", "\u2013", "N"),
  DOC       = "DOC",
  EC        = "EC",
  TSS       = "TSS"
)

unit_short_map <- c(
  Discharge = paste0("m", "\u00B3", " s", "\u207B", "\u00B9"),
  NO3       = paste0("mg N L", "\u207B", "\u00B9"),
  DOC       = paste0("mg L", "\u207B", "\u00B9"),
  EC        = paste0("\u00B5", "S cm", "\u207B", "\u00B9"),
  TSS       = paste0("mg L", "\u207B", "\u00B9")
)

# 2. HELPER FUNCTIONS

safe_min <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0) return(NA_real_)
  min(x)
}

safe_max <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0) return(NA_real_)
  max(x)
}

safe_mean <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0) return(NA_real_)
  mean(x)
}

safe_sd <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) <= 1) return(NA_real_)
  stats::sd(x)
}

safe_cv <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0) return(NA_real_)
  mu <- mean(x)
  if (!is.finite(mu) || mu == 0) return(NA_real_)
  100 * stats::sd(x) / mu
}

safe_sum <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0) return(NA_real_)
  sum(x)
}

safe_median <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0) return(NA_real_)
  median(x)
}

fmt_pub <- function(x) {
  if (!is.finite(x)) return("NA")
  ax <- abs(x)
  digits <- if (ax < 10) 2 else if (ax < 1000) 1 else 0
  format(round(x, digits), nsmall = digits, trim = TRUE,
         scientific = FALSE, big.mark = ",")
}

make_ylabel <- function(varname) {
  switch(
    varname,
    Discharge = expression(Discharge ~ (m^3/s)),
    NO3       = expression(NO[3] * "-N" ~ (mg~N/L)),
    DOC       = expression(DOC ~ (mg/L)),
    EC        = expression(EC ~ (mu*S/cm)),
    TSS       = expression(TSS ~ (mg/L))
  )
}

.get_global_max <- function(site_ts_list, varname, use_robust = FALSE, prob = 0.995) {
  vals <- unlist(lapply(site_ts_list, function(tt) to_num(tt[[varname]])), use.names = FALSE)
  vals <- vals[is.finite(vals)]
  if (length(vals) == 0) return(1)
  if (use_robust) return(as.numeric(stats::quantile(vals, probs = prob, na.rm = TRUE)))
  max(vals, na.rm = TRUE)
}

# 3. LOAD DATA

df <- read.csv(DATA_CSV, stringsAsFactors = FALSE)
stopifnot("date" %in% names(df))
df$date <- .parse_dt(df$date, tz = TZ_USE)
df <- df %>% arrange(date)

# 4. MAP ORIGINAL COLUMNS

column_map <- purrr::map_dfr(sites, function(s) {
  tibble(
    site = s,
    Variable = vars_all,
    source_col = c(
      detect_prec_col(names(df), s),
      detect_q_col(names(df), s),
      detect_wq_col(names(df), s, "NO3"),
      detect_wq_col(names(df), s, "DOC"),
      detect_wq_col(names(df), s, "EC"),
      detect_wq_col(names(df), s, "TSS")
    )
  )
})

write.csv(
  column_map,
  file.path(DIR_REPRO_TMP_TAB, "Table_ColumnMapping_OriginalData_For_Fig6B.csv"),
  row.names = FALSE
)

# DAILY AGGREGATION FOR FIGURE 1
# IMPORTANT:
# The figure uses daily summaries:
#   - Discharge    -> daily mean
#   - Precipitation-> daily sum
#   - NO3, DOC, EC -> daily median
#   - TSS          -> daily maximum

get_site_ts_daily <- function(df, site_name, column_map) {

  cm <- column_map %>% filter(site == site_name)

  out <- tibble(datetime = df$date)

  for (vv in vars_all) {
    cc <- cm %>% filter(Variable == vv) %>% pull(source_col)
    if (length(cc) == 1 && !is.na(cc) && cc %in% names(df)) {
      out[[vv]] <- to_num(df[[cc]])
    } else {
      out[[vv]] <- NA_real_
    }
  }

  out$Day <- as.Date(out$datetime, tz = TZ_USE)

  daily <- out %>%
    group_by(Day) %>%
    summarise(
      Precipitation = safe_sum(Precipitation),
      Discharge     = safe_mean(Discharge),
      NO3           = safe_median(NO3),
      DOC           = safe_median(DOC),
      EC            = safe_median(EC),
      TSS           = safe_max(TSS),
      .groups = "drop"
    )

  all_days <- tibble(
    Day = seq.Date(
      from = as.Date("2015-01-01"),
      to   = as.Date("2020-12-31"),
      by   = "day"
    )
  )

  daily <- all_days %>%
    left_join(daily, by = "Day") %>%
    mutate(date = as.POSIXct(Day, tz = TZ_USE)) %>%
    select(date, Precipitation, Discharge, NO3, DOC, EC, TSS)

  daily
}

site_ts_list <- setNames(
  lapply(sites, function(s) get_site_ts_daily(df, s, column_map)),
  sites
)

# EC plotting cap for readability only
ec_cap <- .get_global_max(
  site_ts_list,
  "EC",
  use_robust = TRUE,
  prob = FIG6B_EC_CAP_PROB
)

# 6. MANUAL SUMMARY VALUES FOR PANEL ANNOTATIONS
# Quick-use approved summary table, aready results.
# This avoids discrepancies during the manuscript revision stage.

fig6b_summary <- tribble(
  ~site, ~Variable,       ~Mean_value, ~Max_value, ~CV_value,
  "NF",  "Discharge",      0.84,          6.22,      114.7,
  "SHA", "Discharge",      0.52,          5.63,      122.3,
  "TTP", "Discharge",      0.71,          4.36,       94.9,

  "NF",  "NO3",            0.38,          5.64,       36.4,
  "SHA", "NO3",            0.97,          2.88,       38.0,
  "TTP", "NO3",            1.74,          3.55,       26.9,

  "NF",  "DOC",            2.91,          8.57,       54.6,
  "SHA", "DOC",            2.54,         24.5,        70.5,
  "TTP", "DOC",            2.13,         23.5,        68.6,

  "NF",  "EC",            33.1,          84.3,        24.7,
  "SHA", "EC",            59.7,         284.0,        24.9,
  "TTP", "EC",            42.9,          81.7,         8.6,

  "NF",  "TSS",           31.7,        1266.0,        72.6,
  "SHA", "TSS",          120.1,        3358.0,       143.2,
  "TTP", "TSS",           43.9,        2848.0,       161.7
)

# Responsive-event counts for the discharge row obtained earlier 
fig6b_event_counts <- c(NF = 246L, SHA = 170L, TTP = 200L)

get_fig6b_stat <- function(site_name, varname, field) {

  zz <- fig6b_summary %>%
    dplyr::filter(
      site == site_name,
      Variable == varname
    )

  if (
    nrow(zz) == 0L ||
    !field %in% names(zz)
  ) {
    return(NA_real_)
  }

  suppressWarnings(
    as.numeric(zz[[field]][1])
  )
}

# 7. AXES AND LIMITS

# Exact common time extent for every panel
xlim_global <- c(
  as.POSIXct("2015-01-01 00:00:00", tz = TZ_USE),
  as.POSIXct("2020-12-31 23:59:59", tz = TZ_USE)
)

# Put the year tick AND year label at the same location.
# July centres each year visually within its annual block.
x_ticks_years <- as.POSIXct(
  paste0(2015:2020, "-07-01 00:00:00"),
  tz = TZ_USE
)

x_label_strings <- as.character(2015:2020)

ylim_global <- lapply(vars_grid, function(v) {
  c(
    0,
    .get_global_max(
      site_ts_list,
      v,
      use_robust = FALSE
    ) * 1.10
  )
})
names(ylim_global) <- vars_grid

ylim_global[["NO3"]] <- c(0,FIG6B_NO3_YMAX)
ylim_global[["EC"]] <- c(FIG6B_EC_YMIN,ec_cap * 1.10)

ylim_precip_global <- c(
  -.get_global_max(
    site_ts_list,
    "Precipitation",
    use_robust = FALSE
  ) * 1.05,
  0
)
# 8. PANEL STATISTICS WRITER

add_stats_text_from_table <- function(site_name, varname) {

  if (!FIG6B_SHOW_STATS) {
    return(invisible(NULL))
  }

  usr <- par("usr")

  dx <- usr[2] - usr[1]
  dy <- usr[4] - usr[3]

  stats_x <- usr[1] + 0.030 * dx
  stats_y <- usr[4] - FIG6B_STATS_TOP_FRAC * dy

  if (varname == "Discharge") {

    txt_lines <- c(
      paste0(
        "Valid events = ",
        fig6b_event_counts[[site_name]]
      ),
      paste0(
        "Mean Q = ",
        fmt_pub(
          get_fig6b_stat(
            site_name,
            "Discharge",
            "Mean_value"
          )
        )
      ),
      paste0(
        "Peak Q = ",
        fmt_pub(
          get_fig6b_stat(
            site_name,
            "Discharge",
            "Max_value"
          )
        )
      )
    )

  } else {

    txt_lines <- c(
      paste0(
        "Mean = ",
        fmt_pub(
          get_fig6b_stat(
            site_name,
            varname,
            "Mean_value"
          )
        )
      ),
      paste0(
        "Max = ",
        fmt_pub(
          get_fig6b_stat(
            site_name,
            varname,
            "Max_value"
          )
        )
      ),
      paste0(
        "CV = ",
        fmt_pub(
          get_fig6b_stat(
            site_name,
            varname,
            "CV_value"
          )
        ),
        "%"
      )
    )
  }

  # Optional white backing beneath statistics.
  # This prevents rainfall bars or sharp constituent peaks from obscuring text.

  stats_string <- paste(txt_lines, collapse = "\n")

  text_width <- strwidth(
    stats_string,
    cex = FIG6B_CEX_STATS,
    units = "user"
  )

  line_height <- strheight(
    "Ag",
    cex = FIG6B_CEX_STATS,
    units = "user"
  )

  n_lines <- length(txt_lines)

  rect(
    xleft   = stats_x - 0.008 * dx,
    xright  = stats_x + text_width + 0.015 * dx,
    ytop    = stats_y + 0.025 * dy,
    ybottom = stats_y -
      (n_lines * line_height) -
      0.020 * dy,
    col = grDevices::adjustcolor(
      "white",
      alpha.f = 0.84
    ),
    border = NA
  )

  text(
    x = stats_x,
    y = stats_y,
    labels = stats_string,
    adj = c(0, 1),
    cex = FIG6B_CEX_STATS,
    col = "black",
    font = 1
  )

  invisible(NULL)
}

# 9. PANEL DRAWING FUNCTION

plot_grid_cell <- function(
    site_name,
    varname,
    site_ts,
    xlim_global,
    ylim_global,
    ylim_precip_global,
    is_top_row = FALSE,
    is_bottom_row = FALSE,
    is_first_col = FALSE,
    is_last_col = FALSE) {

  if (is.null(site_ts)) {

    plot.new()
    box(lwd = FIG6B_BOX_LWD)

    return(invisible(NULL))
  }

  # Larger margins for enlarged tick labels

  par(
    mar = c(
      if (is_bottom_row) 6.0 else 1.55,
      if (is_first_col)  8.4 else 3.25,
      if (is_top_row)    3.0 else 1.15,
      if (is_last_col)   6.1 else 1.40
    ),
    family = "sans"
  )

  y <- to_num(site_ts[[varname]])

  if (
    varname == "EC" &&
    FIG6B_EC_REMOVE_EXTREME_OUTLIER
  ) {
    y[y > ec_cap] <- NA_real_
  }

  # Primary time series

  plot(
    site_ts$date,
    y,
    type = "l",
    col = var_colors[[varname]],
    #lwd = if (varname == "Discharge") 1.65 else 1.15,
    lwd = if (varname == "Discharge") 3.2 else 3.0,
    xlim = xlim_global,
    ylim = ylim_global[[varname]],
    xaxt = "n",
    yaxt = "n",
    xlab = "",
    ylab = "",
    bty = "o",
    xaxs = "i",
    yaxs = "i"
  )

  # Y-axis
  # las = 1 makes numerical values horizontal and much easier to read.

  axis(
    side = 2,
    las = 1,
    cex.axis = FIG6B_CEX_AXIS,
    lwd = FIG6B_BOX_LWD,
    lwd.ticks = 1.0,
    tck = -0.018,
    mgp = c(3, 0.65, 0)
  )

  # One row-level y-axis title only on the left column

  if (is_first_col) {

    mtext(
      make_ylabel(varname),
      side = 2,
      line = 5.8,
      cex = FIG6B_CEX_YLAB,
      col = var_colors[[varname]]
    )
  }

  # Bottom-row date ticks:
  # tick and its corresponding year use exactly the same timestamp.

  if (is_bottom_row) {

    axis(
      side = 1,
      at = x_ticks_years,
      labels = x_label_strings,
      las = 1,
      cex.axis = FIG6B_CEX_YEAR,
      lwd = FIG6B_BOX_LWD,
      lwd.ticks = 1.10,
      tck = -0.025,
      mgp = c(3, 0.75, 0)
    )
  }

  # Site headings

  if (is_top_row) {

    title(
      main = site_name,
      cex.main = FIG6B_CEX_MAIN,
      font.main = 2,
      line = 1.0
    )
  }

  # Precipitation overlay only in discharge row

  if (varname == "Discharge") {

    p <- to_num(site_ts$Precipitation)

    par(new = TRUE)

    plot(
      site_ts$date,
      -p,
      type = "h",
      lwd = FIG6B_PRECIP_LWD,
      col = FIG6B_PRECIP_COL,
      xlim = xlim_global,
      ylim = ylim_precip_global,
      xaxt = "n",
      yaxt = "n",
      xlab = "",
      ylab = "",
      bty = "n",
      xaxs = "i",
      yaxs = "i"
    )

    # Right precipitation axis on TTP panel only

    if (is_last_col) {

      atP <- pretty(
        ylim_precip_global,
        n = 5
      )

      atP <- atP[
        atP >= ylim_precip_global[1] &
          atP <= ylim_precip_global[2]
      ]

      axis(
        side = 4,
        at = atP,
        labels = abs(atP),
        las = 1,
        cex.axis = FIG6B_CEX_PRECIP_AXIS,
        lwd = FIG6B_BOX_LWD,
        lwd.ticks = 1.0,
        tck = -0.018
      )

      mtext(
        expression(
          Precipitation ~
            (mm ~ d^{-1})
        ),
        side = 4,
        line = 4.2,
        cex = FIG6B_CEX_PRECIP_AXIS
      )
    }

    # Redraw Q above the rainfall bars.

    par(new = TRUE)

    plot(
      site_ts$date,
      y,
      type = "l",
      col = var_colors[["Discharge"]],
      lwd = 1.65,
      xlim = xlim_global,
      ylim = ylim_global[["Discharge"]],
      xaxt = "n",
      yaxt = "n",
      xlab = "",
      ylab = "",
      bty = "n",
      xaxs = "i",
      yaxs = "i"
    )
  }

  # Constituent / variable identity
  #
  # Display once per row in the first column.
  # It is intentionally placed ABOVE the statistical block.

  if (is_first_col) {

    usr <- par("usr")

    dx <- usr[2] - usr[1]
    dy <- usr[4] - usr[3]

    text(
      x = usr[1] + 0.025 * dx,
      y = usr[4] -
        FIG6B_ROW_LABEL_TOP_FRAC * dy,
      labels = row_label_map[[varname]],
      adj = c(0, 1),
      cex = FIG6B_CEX_ROW_LABEL,
      font = 2,
      col = var_colors[[varname]]
    )
  }

  # Statistics are added AFTER titles/data so they remain visible.

  add_stats_text_from_table(
    site_name = site_name,
    varname = varname
  )

  box(
    lwd = FIG6B_BOX_LWD,
    col = "grey15"
  )

  invisible(NULL)
}

# 10. EXPORT FIGURE
message(
  "Rendering revised high-resolution Figure 1 daily-summary matrix..."
)

if (
  requireNamespace(
    "ragg",
    quietly = TRUE
  )
) {

  ragg::agg_png(
    filename = FIG6B_FILENAME,
    width = FIG6B_WIDTH_CM,
    height = FIG6B_HEIGHT_CM,
    units = "cm",
    res = FIG6B_RES_DPI,
    scaling = 1,
    background = "white"
  )

} else {

  png(
    filename = FIG6B_FILENAME,
    width = FIG6B_WIDTH_CM,
    height = FIG6B_HEIGHT_CM,
    units = "cm",
    res = FIG6B_RES_DPI,
    bg = "white",
    pointsize = 13,
    type = if (
      capabilities("cairo")
    ) {
      "cairo"
    } else {
      getOption("bitmapType")
    }
  )
}

layout(
  matrix(
    1:(length(vars_grid) * length(sites)),
    nrow = length(vars_grid),
    byrow = TRUE
  )
)

# Larger bottom outer margin is deliberately reserved for the
# single shared x-axis title "Date".
par(
  oma = c(
    4.2,   # bottom
    0.9,   # left
    1.2,   # top
    2.5    # right
  )
)

for (r in seq_along(vars_grid)) {

  vv <- vars_grid[r]

  for (cidx in seq_along(sites)) {

    ss <- sites[cidx]

    plot_grid_cell(
      site_name = ss,
      varname = vv,
      site_ts = site_ts_list[[ss]],
      xlim_global = xlim_global,
      ylim_global = ylim_global,
      ylim_precip_global = ylim_precip_global,
      is_top_row = r == 1L,
      is_bottom_row = r == length(vars_grid),
      is_first_col = cidx == 1L,
      is_last_col = cidx == length(sites)
    )
  }
}

# Common centrally aligned x-axis title

mtext(
  "Date",
  side = 1,
  outer = TRUE,
  line = 0.8,
  cex = FIG6B_CEX_DATE,
  font = 2
)

dev.off()

message(
  "Revised Figure 1 exported successfully:\n",
  normalizePath(
    FIG6B_FILENAME,
    winslash = "/",
    mustWork = FALSE
  )
)

cat("\nFigure 1 responsive-event counts used in annotations:\n")
print(fig6b_event_counts)

cat("\nDaily aggregation used for Figure 1:\n")
cat("  Discharge     = daily mean\n")
cat("  Precipitation = daily sum\n")
cat("  NO3-N         = daily median\n")
cat("  DOC           = daily median\n")
cat("  EC            = daily median\n")
cat("  TSS           = daily maximum\n")

################################################################################
# CORE WATER-QUALITY EVENT OUTPUTS
# Only WQ_response, WQ_return, and WQ_hysteresis are retained.
################################################################################
message("=== CORE WQ EVENT OUTPUTS ===")

WQ_ev_conclusive <- WQ_ev
Events_Conclusive_Table_AllMetrics <- drop_list_columns(
  events_conclusive,
  context = "Events_Conclusive_Table_AllMetrics"
)
write_csv_safe(
  Events_Conclusive_Table_AllMetrics,
  file.path(DIR_Q_EVENTS, "Events_Conclusive_Table_AllMetrics.csv"),
  row.names = FALSE
)

core_safe_plot <- function(dates, values, ylab_text, base_value = NULL) {
  values <- suppressWarnings(as.numeric(values))
  if (length(values) < 2L || all(!is.finite(values))) {
    plot.new(); box(); title(ylab = ylab_text); return(invisible(NULL))
  }
  plot(dates, values, type = "l", ylab = ylab_text, xlab = "")
  if (!is.null(base_value) && is.finite(base_value)) abline(h = base_value, lty = 2)
  invisible(NULL)
}

core_time_cols <- function(n) {
  if (requireNamespace("scales", quietly = TRUE) && "viridis_pal" %in% getNamespaceExports("scales")) {
    return(scales::viridis_pal(option = "D")(n))
  }
  grDevices::hcl.colors(n, "Viridis")
}

for (s in sites) {
  ev_site <- Events_Conclusive_Table_AllMetrics %>% dplyr::filter(site == s) %>% dplyr::arrange(ID)
  if (nrow(ev_site) == 0L) next

  q_col <- detect_q_col(names(df), s)
  vars_map <- c(
    NO3 = detect_wq_col(names(df), s, "NO3"),
    DOC = detect_wq_col(names(df), s, "DOC"),
    EC  = detect_wq_col(names(df), s, "EC"),
    TSS = detect_wq_col(names(df), s, "TSS")
  )

  response_dir <- DIR_RESP_SITE[[s]]
  return_dir   <- DIR_RETURN_SITE[[s]]
  hyst_dir     <- DIR_HYST_SITE[[s]]

  for (ii in seq_len(nrow(ev_site))) {
    ev <- ev_site[ii, , drop = FALSE]
    IDi <- as.integer(ev$ID[[1]])
    dat_ev <- df %>% dplyr::filter(date >= ev$tStart[[1]], date <= ev$tEnd[[1]])
    if (nrow(dat_ev) < 10L) next

    response_flags <- vapply(names(vars_map), function(p) {
      nm <- paste0("response_", p)
      nm %in% names(ev) && isTRUE(ev[[nm]][[1]])
    }, logical(1))
    return_flags <- vapply(names(vars_map), function(p) {
      nm <- paste0("return_", p)
      nm %in% names(ev) && isTRUE(ev[[nm]][[1]])
    }, logical(1))

    if (any(response_flags)) {
      response_file <- file.path(response_dir, paste0("Event_", IDi, ".png"))
      png(response_file, width = 18, height = 24, units = "cm", res = 300)
      par(mfrow = c(5, 1), mar = c(2, 4.1, 1, 2.1), mgp = c(2.5, 0.7, 0), cex = 0.8)
      core_safe_plot(dat_ev$date, dat_ev[[q_col]], "Discharge [m3 s-1]")
      for (p in names(vars_map)) {
        vname <- vars_map[[p]]
        ylab_text <- paste0(p, " [", ifelse(p == "EC", "uS cm-1", "mg L-1"), "]")
        c0_name <- paste0("C0_", p)
        c0 <- if (c0_name %in% names(ev)) suppressWarnings(as.numeric(ev[[c0_name]][[1]])) else NA_real_
        if (is.na(vname) || !vname %in% names(dat_ev)) {
          plot.new(); box(); title(ylab = ylab_text)
        } else {
          core_safe_plot(dat_ev$date, dat_ev[[vname]], ylab_text, c0)
        }
      }
      dev.off()
      if (any(return_flags)) file.copy(response_file, file.path(return_dir, basename(response_file)), overwrite = TRUE)
    }

    time_col <- core_time_cols(nrow(dat_ev))
    for (p in names(vars_map)) {
      hi_name <- paste0("HI_Lloyd_", p)
      vname <- vars_map[[p]]
      hi_val <- if (hi_name %in% names(ev)) suppressWarnings(as.numeric(ev[[hi_name]][[1]])) else NA_real_
      if (!is.finite(hi_val) || is.na(vname) || !vname %in% names(dat_ev)) next
      loop_file <- file.path(hyst_dir, paste0("Event_", IDi, "_", p, ".png"))
      png(loop_file, width = 12, height = 12, units = "cm", res = 300)
      par(mar = c(3.5, 3.5, 2, 1), mgp = c(2.1, 0.6, 0), cex = 0.8)
      plot(
        to_num(dat_ev[[q_col]]), to_num(dat_ev[[vname]]),
        pch = 16, col = time_col,
        xlab = "Discharge [m3 s-1]", ylab = paste0(p, " concentration"),
        main = sprintf("%s | Event %d | HI = %.3f", s, IDi, hi_val)
      )
      dev.off()
    }
  }
}
message("Core WQ response/return/hysteresis outputs completed.")

# =================== AUTHORITATIVE WQ / CLUSTER ANALYSIS ===================

# Intermediate figures/tables from the analytical engine are transient.
FIGDIR <- DIR_REPRO_TMP_FIG
TABDIR <- DIR_REPRO_TMP_TAB
DIR_PAPER <- DIR_REPRO_TMP
DIR_PAPER_FIG <- DIR_REPRO_TMP_FIG
DIR_PAPER_TAB <- DIR_REPRO_TMP_TAB

###############################################################################
# TIME-RESOLVED WQ STATUS, GEOMETRY AND FIGURE 2 POPULATIONS
###############################################################################

message("=== WQ STATUS + FIGURE 2a/2d WORKFLOW ===")

# 0. Configuration and local export helpers
if (!exists("resp_thresh"))     resp_thresh     <- 0.15
if (!exists("ret_thresh"))      ret_thresh      <- 0.20
if (!exists("min_completeness")) min_completeness <- 0.90
if (!exists("solute_list"))     solute_list     <- c("NO3", "DOC", "EC", "TSS")
if (!exists("sites"))           sites           <- c("NF", "SHA", "TTP")
if (!exists("TABDIR"))          TABDIR          <- if (exists("DIR_PAPER_TAB")) DIR_PAPER_TAB else file.path(getwd(), "Tables")
if (!exists("FIGDIR"))          FIGDIR          <- if (exists("DIR_PAPER_FIG")) DIR_PAPER_FIG else file.path(getwd(), "Figures")

if (!exists("eps_direct")) eps_direct <- 0.02
if (!exists("eps_single")) eps_single <- 0.03
if (!exists("k_grid"))     k_grid     <- seq(0.05, 0.95, by = 0.05)
if (!exists("rep_min_pts")) rep_min_pts <- min_pts_hyst

dir.create(TABDIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGDIR, recursive = TRUE, showWarnings = FALSE)

write_csv_authoritative <- function(dat, filename) {
  dat <- as.data.frame(dat, stringsAsFactors = FALSE)
  list_cols <- names(dat)[vapply(dat, is.list, logical(1))]
  if (length(list_cols) > 0L) {
    message("Removing list column(s) before exporting ", filename, ": ", paste(list_cols, collapse = ", "))
    dat <- dat[, setdiff(names(dat), list_cols), drop = FALSE]
  }
  out_file <- file.path(TABDIR, filename)
  utils::write.csv(
    dat,
    file = out_file,
    row.names = FALSE,
    na = "",
    fileEncoding = "UTF-8"
  )
  invisible(out_file)
}

median_finite <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x) == 0L) return(NA_real_)
  stats::median(x)
}

mean_finite <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x) == 0L) return(NA_real_)
  mean(x)
}

pct_safe <- function(n, d) {
  ifelse(is.finite(d) & d > 0, 100 * n / d, NA_real_)
}

calc_return_ratio_vector <- function(C_vector, baseline) {
  C_vector <- suppressWarnings(as.numeric(C_vector))
  C_valid <- C_vector[is.finite(C_vector)]
  if (length(C_valid) == 0L || !is.finite(baseline) || baseline <= 0) return(NA_real_)

  end_value <- tail(C_valid, 1L)
  peak_up   <- max(C_valid)
  peak_down <- min(C_valid)

  dev_up   <- abs(peak_up - baseline)
  dev_down <- abs(peak_down - baseline)
  peak_value <- if (dev_up >= dev_down) peak_up else peak_down

  denominator <- abs(peak_value - baseline)
  if (!is.finite(denominator) || denominator == 0) return(NA_real_)
  abs(end_value - baseline) / denominator
}

# 1. Time-resolved event status, exactly matching manuscript Section 2.7
calc_event_dominant_status <- function(C_values, C0, threshold = resp_thresh) {
  C_values <- suppressWarnings(as.numeric(C_values))
  C_values <- C_values[is.finite(C_values)]

  if (length(C_values) == 0L || !is.finite(C0) || C0 <= 0) {
    return(NA_character_)
  }

  status_ratio <- (C_values - C0) / C0

  timestep_status <- dplyr::case_when(
    status_ratio >  threshold ~ "mobilization",
    status_ratio < -threshold ~ "dilution",
    TRUE                      ~ "chemostasis"
  )

  # Deterministic tie rule: chemostasis, then mobilization, then dilution.
  status_counts <- table(
    factor(
      timestep_status,
      levels = c("chemostasis", "mobilization", "dilution")
    )
  )

  names(status_counts)[which.max(status_counts)]
}

# 2. Rebuild event-solute metrics with stored time-resolved status
make_empty_wq_out <- function(solutes = solute_list) {
  out <- tibble::tibble(.rows = 1L)

  for (p in solutes) {
    out[[paste0("response_", p)]]        <- NA
    out[[paste0("return_", p)]]          <- NA
    out[[paste0("ret_ratio_", p)]]       <- NA_real_
    out[[paste0("C0_", p)]]              <- NA_real_
    out[[paste0("Cmax_", p)]]            <- NA_real_
    out[[paste0("Cmin_", p)]]            <- NA_real_
    out[[paste0("Cmean_", p)]]           <- NA_real_
    out[[paste0("Cw_", p)]]              <- NA_real_
    out[[paste0("DeltaC_", p)]]          <- NA_real_
    out[[paste0("FI_peak_", p)]]         <- NA_real_
    out[[paste0("FI_mean_", p)]]         <- NA_real_
    out[[paste0("HI_Lloyd_", p)]]        <- NA_real_
    out[[paste0("HI_Zuecco_", p)]]       <- NA_real_
    out[[paste0("m_rise_", p)]]          <- NA_real_
    out[[paste0("m_fall_", p)]]          <- NA_real_
    out[[paste0("m_mean_", p)]]          <- NA_real_
    out[[paste0("Load_g_", p)]]          <- NA_real_
    out[[paste0("Chemical_Status_", p)]] <- NA_character_
  }

  out
}

compute_WQ_ev_one <- function(
    df,
    ev,
    q_col,
    vars_map,
    min_comp = min_completeness,
    dt_fallback_s = NA_real_) {

  invalid_event <-
    is.na(q_col) ||
    !(q_col %in% names(df)) ||
    is.na(ev$tStart) ||
    is.na(ev$tEnd) ||
    ev$tEnd < ev$tStart

  if (invalid_event) {
    return(
      dplyr::bind_cols(
        tibble::tibble(
          site = as.character(ev$site),
          ID = as.integer(ev$ID),
          n_response = 0L,
          n_return = 0L
        ),
        make_empty_wq_out()
      )
    )
  }

  datWQ <- df %>%
    dplyr::filter(date >= ev$tStart, date <= ev$tEnd)

  if (nrow(datWQ) < 3L) {
    return(
      dplyr::bind_cols(
        tibble::tibble(
          site = as.character(ev$site),
          ID = as.integer(ev$ID),
          n_response = 0L,
          n_return = 0L
        ),
        make_empty_wq_out()
      )
    )
  }

  dt_s <- get_dt_seconds(datWQ$date)
  if (!is.finite(dt_s) || dt_s <= 0) dt_s <- dt_fallback_s
  Q <- to_num(datWQ[[q_col]])

  wq_out <- tibble::tibble(.rows = 1L)
  n_response <- 0L
  n_return   <- 0L

  for (p in names(vars_map)) {
    vname <- vars_map[[p]]

    solute_comp <- 0
    if (!is.na(vname) && vname %in% names(datWQ)) {
      raw_solute <- datWQ[[vname]]
      if (length(raw_solute) > 0L && !all(is.na(raw_solute))) {
        solute_comp <- mean(!is.na(raw_solute))
      }
    }

    if (
      is.na(vname) ||
      !(vname %in% names(df)) ||
      solute_comp < min_comp
    ) {
      blank_sol <- make_empty_wq_out(p)
      wq_out <- dplyr::bind_cols(wq_out, blank_sol)
      next
    }

    C  <- to_num(datWQ[[vname]])
    C0 <- calc_event_C0(
      df = df,
      col = vname,
      tStart = ev$tStart
    )
    if (!is.finite(C0)) C0 <- NA_real_

    Cmax  <- safe_max(C)
    Cmin  <- safe_min(C)
    Cmean <- safe_mean(C)

    response_info <- list(response = NA_real_, peak = NA_real_)
    response_flag <- FALSE
    if (is.finite(C0) && C0 > 0 && any(is.finite(C))) {
      response_info <- calc_response(C, C0)
      response_flag <- is.finite(response_info$response) &&
        response_info$response >= resp_thresh
    }

    if (isTRUE(response_flag)) n_response <- n_response + 1L

    ret_ratio <- if (isTRUE(response_flag)) {
      calc_return_ratio_vector(C, C0)
    } else {
      NA_real_
    }

    return_flag <- isTRUE(response_flag) &&
      is.finite(ret_ratio) &&
      ret_ratio <= ret_thresh

    if (isTRUE(return_flag)) n_return <- n_return + 1L

    # Status is calculated for every complete, valid event-solute series.
    # It is not inferred from Cmax/Cmin and is not gated by return-to-baseline.
    event_status <- calc_event_dominant_status(
      C_values = C,
      C0 = C0,
      threshold = resp_thresh
    )

    do_hi <- isTRUE(response_flag)

    HI_L <- if (do_hi) calc_HI_Lloyd(Q, C, C0) else NA_real_
    HI_Z <- if (do_hi) calc_HI_Zuecco(Q, C) else NA_real_

    m_metrics <- if (do_hi) {
      calc_m_CQ(Q, C)
    } else {
      c(m_rise = NA_real_, m_fall = NA_real_, m_mean = NA_real_)
    }

    Cw <- if (
      length(Q) == length(C) &&
      sum(Q, na.rm = TRUE) > 0
    ) {
      sum(Q * C, na.rm = TRUE) / sum(Q, na.rm = TRUE)
    } else {
      NA_real_
    }

    event_load <- if (
      length(Q) == length(C) &&
      is.finite(dt_s)
    ) {
      sum(Q * C * dt_s, na.rm = TRUE)
    } else {
      NA_real_
    }

    solute_result <- tibble::tibble(
      !!paste0("response_", p)        := response_flag,
      !!paste0("return_", p)          := return_flag,
      !!paste0("ret_ratio_", p)       := ret_ratio,
      !!paste0("C0_", p)              := C0,
      !!paste0("Cmax_", p)            := Cmax,
      !!paste0("Cmin_", p)            := Cmin,
      !!paste0("Cmean_", p)           := Cmean,
      !!paste0("Cw_", p)              := Cw,
      !!paste0("DeltaC_", p)          := Cmax - Cmin,
      !!paste0("FI_peak_", p)         := calc_FI_peak(C0, response_info$peak),
      !!paste0("FI_mean_", p)         := calc_FI_mean(C0, Cmean),
      !!paste0("HI_Lloyd_", p)        := HI_L,
      !!paste0("HI_Zuecco_", p)       := HI_Z,
      !!paste0("m_rise_", p)          := unname(m_metrics[["m_rise"]]),
      !!paste0("m_fall_", p)          := unname(m_metrics[["m_fall"]]),
      !!paste0("m_mean_", p)          := unname(m_metrics[["m_mean"]]),
      !!paste0("Load_g_", p)          := event_load,
      !!paste0("Chemical_Status_", p) := event_status
    )

    wq_out <- dplyr::bind_cols(wq_out, solute_result)
  }

  dplyr::bind_cols(
    tibble::tibble(
      site = as.character(ev$site),
      ID = as.integer(ev$ID),
      n_response = n_response,
      n_return = n_return
    ),
    wq_out
  )
}

WQ_ev_list <- list()

for (s in sites) {
  et_s <- eTable %>%
    dplyr::filter(site == s)

  if (nrow(et_s) == 0L) next

  q_col <- detect_q_col(names(df), s)
  vars_map <- c(
    NO3 = detect_wq_col(names(df), s, "NO3"),
    DOC = detect_wq_col(names(df), s, "DOC"),
    EC  = detect_wq_col(names(df), s, "EC"),
    TSS = detect_wq_col(names(df), s, "TSS")
  )

  message("Rebuilding time-resolved WQ metrics for site: ", s)

  for (i in seq_len(nrow(et_s))) {
    WQ_ev_list[[length(WQ_ev_list) + 1L]] <- compute_WQ_ev_one(
      df = df,
      ev = et_s[i, ],
      q_col = q_col,
      vars_map = vars_map,
      min_comp = min_completeness,
      dt_fallback_s = get_dt_seconds(df$date)
    )
  }
}

WQ_ev <- dplyr::bind_rows(WQ_ev_list)

if (nrow(WQ_ev) == 0L) {
  stop("The rebuilt WQ_ev table contains no rows.", call. = FALSE)
}

message("SUCCESS: rebuilt WQ_ev with time-resolved event status; rows = ", nrow(WQ_ev))

# 3. Adaptive long-format reshaping that preserves Chemical_Status_*
get_solute_cols_adaptive <- function(df_wide, solute_name, all_names) {
  find_metric <- function(prefix) {
    candidates <- c(
      paste0(prefix, "_", solute_name),
      paste0(prefix, "_", tolower(solute_name)),
      paste0(solute_name, "_", prefix),
      paste0(tolower(solute_name), "_", prefix)
    )

    matched <- intersect(candidates, all_names)
    if (length(matched) > 0L) return(df_wide[[matched[1L]]])
    NA
  }

  response_value <- find_metric("response")
  return_value   <- find_metric("return")
  status_value   <- find_metric("Chemical_Status")

  tibble::tibble(
    solute = solute_name,
    response = as.logical(response_value),
    ret = if (is.character(return_value)) {
      tolower(return_value) %in% c("returned", "true")
    } else {
      as.logical(return_value)
    },
    event_chemical_status = as.character(status_value),
    HI      = suppressWarnings(as.numeric(find_metric("HI_Lloyd"))),
    HIz     = suppressWarnings(as.numeric(find_metric("HI_Zuecco"))),
    C0      = suppressWarnings(as.numeric(find_metric("C0"))),
    Cmax    = suppressWarnings(as.numeric(find_metric("Cmax"))),
    Cmin    = suppressWarnings(as.numeric(find_metric("Cmin"))),
    Cmean   = suppressWarnings(as.numeric(find_metric("Cmean"))),
    Cw      = suppressWarnings(as.numeric(find_metric("Cw"))),
    FI_peak = suppressWarnings(as.numeric(find_metric("FI_peak"))),
    FI_mean = suppressWarnings(as.numeric(find_metric("FI_mean")))
  )
}

message("Reshaping WQ_ev into the authoritative event-solute matrix.")

WQ_names <- names(WQ_ev)

WQ_long <- WQ_ev %>%
  dplyr::mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID))
  ) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    .solute_rows = list(
      dplyr::bind_rows(
        lapply(
          solute_list,
          function(solute_name) {
            get_solute_cols_adaptive(
              df_wide = dplyr::pick(dplyr::everything()),
              solute_name = solute_name,
              all_names = WQ_names
            )
          }
        )
      )
    )
  ) %>%
  dplyr::ungroup() %>%
  dplyr::select(site, ID, .solute_rows) %>%
  tidyr::unnest(.solute_rows)

# IMPORTANT: always rebuild event_metrics from the current event register.
# Do not reuse a pre-existing/stale event_metrics object from a restored workspace,
# because Section 3.3 requires tDry and qStart from the current eTable/eTable2.
event_metrics <- if (exists("eTable2")) eTable2 else eTable

event_metrics <- event_metrics %>%
  dplyr::mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID))
  ) %>%
  dplyr::distinct(site, ID, .keep_all = TRUE)

required_event_metric_cols <- c("site", "ID", "tDry", "qStart")
missing_event_metric_cols <- setdiff(required_event_metric_cols, names(event_metrics))
if (length(missing_event_metric_cols) > 0L) {
  stop(
    "Current event register is missing required columns: ",
    paste(missing_event_metric_cols, collapse = ", "),
    call. = FALSE
  )
}

EVS <- WQ_long %>%
  dplyr::left_join(event_metrics, by = c("site", "ID")) %>%
  dplyr::mutate(
    chem_status = stringr::str_to_lower(
      trimws(as.character(event_chemical_status))
    ),
    chem_status = dplyr::case_when(
      chem_status %in% c("mobilization", "mobilisation") ~ "mobilization",
      chem_status == "dilution"                          ~ "dilution",
      chem_status == "chemostasis"                       ~ "chemostasis",
      TRUE                                                ~ NA_character_
    ),
    chem_status = factor(
      chem_status,
      levels = c("mobilization", "dilution", "chemostasis")
    )
  )

message("SUCCESS: EVS now uses the time-integrated status defined in Section 2.7.")

# 4. Event geometry and loop classification
# SELF-CONTAINED: includes interpolation and normalization helpers

if (!exists("k_grid")) {
  k_grid <- seq(0.05, 0.95, by = 0.05)
}

if (!exists("eps_direct")) {
  eps_direct <- 0.02
}

if (!exists("eps_single")) {
  eps_single <- 0.03
}

# Safely interpolate concentration against discharge
#
# Duplicate discharge values are first collapsed to their mean concentration.
# This prevents the "collapsing to unique x values" warning and avoids failure
# when the same discharge value occurs more than once.

approx_unique <- function(x, y, xout, rule = 2) {

  x <- suppressWarnings(as.numeric(x))
  y <- suppressWarnings(as.numeric(y))
  xout_numeric <- suppressWarnings(as.numeric(xout))

  valid <- is.finite(x) & is.finite(y)

  if (sum(valid) == 0L) {
    return(
      list(
        x = xout,
        y = rep(NA_real_, length(xout_numeric))
      )
    )
  }

  interpolation_data <- data.frame(
    x = x[valid],
    y = y[valid]
  )

  interpolation_data <- stats::aggregate(
    y ~ x,
    data = interpolation_data,
    FUN = function(z) {
      mean(z, na.rm = TRUE)
    }
  )

  interpolation_data <- interpolation_data[
    order(interpolation_data$x),
    ,
    drop = FALSE
  ]

  if (nrow(interpolation_data) == 1L) {
    return(
      list(
        x = xout,
        y = rep(
          interpolation_data$y[1L],
          length(xout_numeric)
        )
      )
    )
  }

  interpolated <- stats::approx(
    x = interpolation_data$x,
    y = interpolation_data$y,
    xout = xout_numeric,
    rule = rule,
    ties = "ordered"
  )

  interpolated$x <- xout
  interpolated
}

# Event-scale 0–1 normalization
#
# Constant finite series are returned as zero rather than NaN.

# Extract discharge and concentration for one event–solute combination

get_event_series_for_solute_pre_vaughan <- function(
    site_name,
    event_id,
    solute_name) {

  ev <- eTable %>%
    dplyr::filter(
      site == site_name,
      ID == event_id
    ) %>%
    dplyr::slice(1L)

  if (nrow(ev) == 0L) {
    return(NULL)
  }

  q_col <- detect_q_col(
    names(df),
    site_name
  )

  c_col <- detect_wq_col(
    names(df),
    site_name,
    solute_name
  )

  if (
    is.na(q_col) ||
    is.na(c_col) ||
    !(q_col %in% names(df)) ||
    !(c_col %in% names(df))
  ) {
    return(NULL)
  }

  event_series <- df %>%
    dplyr::filter(
      date >= ev$tStart,
      date <= ev$tEnd
    ) %>%
    dplyr::transmute(
      Q = to_num(.data[[q_col]]),
      C = to_num(.data[[c_col]])
    )

  if (nrow(event_series) == 0L) {
    return(NULL)
  }

  event_series
}

# Lloyd hysteresis profile across normalized discharge positions

HI_profile_Lloyd <- function(Q, C, k = k_grid,
                             min_points = min_pts_hyst,
                             min_limb_points = min_pts_limb) {
  Q <- suppressWarnings(as.numeric(Q)); C <- suppressWarnings(as.numeric(C))
  k <- suppressWarnings(as.numeric(k))
  ok <- is.finite(Q) & is.finite(C); Q <- Q[ok]; C <- C[ok]
  if (length(Q) < min_points || length(k) == 0L || any(!is.finite(k))) {
    return(rep(NA_real_, length(k)))
  }
  i_peak <- which.max(Q)
  if (i_peak < min_limb_points || (length(Q)-i_peak+1L) < min_limb_points) {
    return(rep(NA_real_, length(k)))
  }
  Qr <- Q[seq_len(i_peak)]; Cr <- C[seq_len(i_peak)]
  Qf <- Q[i_peak:length(Q)]; Cf <- C[i_peak:length(C)]
  if (length(unique(Qr)) < min_limb_points || length(unique(Qf)) < min_limb_points) {
    return(rep(NA_real_, length(k)))
  }
  Qlo <- max(min(Qr), min(Qf)); Qhi <- min(max(Qr), max(Qf))
  Cmin <- min(C); Cmax <- max(C)
  if (!is.finite(Qlo) || !is.finite(Qhi) || Qhi <= Qlo ||
      !is.finite(Cmin) || !is.finite(Cmax) || Cmax <= Cmin) {
    return(rep(NA_real_, length(k)))
  }
  Qk <- Qlo + k*(Qhi-Qlo)
  Crk <- approx_unique(Qr,Cr,xout=Qk,rule=1)$y
  Cfk <- approx_unique(Qf,Cf,xout=Qk,rule=1)$y
  out <- (Crk-Cmin)/(Cmax-Cmin) - (Cfk-Cmin)/(Cmax-Cmin)
  out[!is.finite(out)] <- NA_real_
  out
}

classify_loop_type <- function(HIk, k = k_grid,
                               direct_threshold = 0.02,
                               zero_tolerance = 0.01,
                               low_flow_limit = 0.30) {
  HIk <- suppressWarnings(as.numeric(HIk)); k <- suppressWarnings(as.numeric(k))
  ok <- is.finite(HIk) & is.finite(k); HIk <- HIk[ok]; k <- k[ok]
  if (length(HIk)==0L) return(NA_character_)
  if (mean(abs(HIk)) < direct_threshold) return("Direct / Synchronous")
  low <- k <= low_flow_limit; high <- k > low_flow_limit
  if (any(low) && any(high)) {
    low_linear <- all(abs(HIk[low]) < zero_tolerance)
    high_cw <- all(HIk[high] >= -zero_tolerance) &&
      mean(abs(HIk[high])) >= direct_threshold
    high_acw <- all(HIk[high] <= zero_tolerance) &&
      mean(abs(HIk[high])) >= direct_threshold
    if (low_linear && high_cw && !high_acw) return("SingleLine+Loop (Clockwise)")
    if (low_linear && high_acw && !high_cw) return("SingleLine+Loop (AntiClockwise)")
  }
  cw <- all(HIk >= -zero_tolerance); acw <- all(HIk <= zero_tolerance)
  if (cw && !acw) return("Clockwise")
  if (acw && !cw) return("AntiClockwise")
  core <- k >= 0.10 & k <= 0.90; z <- HIk[core]
  if (length(z)>1L && any(z>zero_tolerance) && any(z< -zero_tolerance)) {
    return("Figure-8 / Mixed")
  }
  NA_character_
}

loop_area_between_limbs <- function(Q, C, k = seq(0,1,by=0.01),
                                    min_points = min_pts_hyst,
                                    min_limb_points = min_pts_limb) {
  Q <- suppressWarnings(as.numeric(Q)); C <- suppressWarnings(as.numeric(C))
  k <- suppressWarnings(as.numeric(k))
  ok <- is.finite(Q)&is.finite(C); Q <- Q[ok]; C <- C[ok]
  if (length(Q)<min_points || length(k)<2L || any(!is.finite(k))) return(NA_real_)
  i_peak <- which.max(Q)
  if (i_peak<min_limb_points || (length(Q)-i_peak+1L)<min_limb_points) return(NA_real_)
  Qr <- Q[seq_len(i_peak)]; Cr <- C[seq_len(i_peak)]
  Qf <- Q[i_peak:length(Q)]; Cf <- C[i_peak:length(C)]
  if (length(unique(Qr))<min_limb_points || length(unique(Qf))<min_limb_points) return(NA_real_)
  Qlo <- max(min(Qr),min(Qf)); Qhi <- min(max(Qr),max(Qf))
  Qmin <- min(Q); Qmax <- max(Q); Cmin <- min(C); Cmax <- max(C)
  if (!is.finite(Qlo)||!is.finite(Qhi)||Qhi<=Qlo||Qmax<=Qmin||Cmax<=Cmin) return(NA_real_)
  Qk <- Qlo + k*(Qhi-Qlo)
  Crk <- approx_unique(Qr,Cr,xout=Qk,rule=1)$y
  Cfk <- approx_unique(Qf,Cf,xout=Qk,rule=1)$y
  qn <- (Qk-Qmin)/(Qmax-Qmin)
  crn <- (Crk-Cmin)/(Cmax-Cmin); cfn <- (Cfk-Cmin)/(Cmax-Cmin)
  ok <- is.finite(qn)&is.finite(crn)&is.finite(cfn)
  if (sum(ok)<2L) return(NA_real_)
  qn <- qn[ok]; sep <- abs(crn[ok]-cfn[ok]); ord <- order(qn)
  qn <- qn[ord]; sep <- sep[ord]
  a <- sum((sep[-1L]+sep[-length(sep)])/2*diff(qn),na.rm=TRUE)
  ifelse(is.finite(a),as.numeric(a),NA_real_)
}

loop_metrics_list <- list()
loop_points_list  <- list()

for (s in sites) {
  message("Calculating loop geometry for site: ", s)

  responsive_rows <- EVS %>%
    dplyr::filter(site == s, response %in% TRUE)

  if (nrow(responsive_rows) == 0L) next

  for (solute_name in solute_list) {
    event_ids <- responsive_rows %>%
      dplyr::filter(solute == solute_name) %>%
      dplyr::pull(ID) %>%
      unique()

    if (length(event_ids) == 0L) next

    for (event_id in event_ids) {
      event_series <- get_event_series_for_solute_pre_vaughan(
        site_name = s,
        event_id = event_id,
        solute_name = solute_name
      )

      if (is.null(event_series) || nrow(event_series) < rep_min_pts) next

      HIk <- HI_profile_Lloyd(
        event_series$Q,
        event_series$C,
        k = k_grid
      )

      loop_metrics_list[[length(loop_metrics_list) + 1L]] <- tibble::tibble(
        site = s,
        ID = as.integer(event_id),
        solute = solute_name,
        loop_area = loop_area_between_limbs(event_series$Q, event_series$C),
        loop_type = classify_loop_type(HIk, k = k_grid),
        HI_mean_k = mean_finite(HIk)
      )

      loop_points_list[[length(loop_points_list) + 1L]] <- event_series
    }
  }
}

loop_metrics <- if (length(loop_metrics_list) == 0L) {
  tibble::tibble(
    site = character(),
    ID = integer(),
    solute = character(),
    loop_area = double(),
    loop_type = character(),
    HI_mean_k = double()
  )
} else {
  dplyr::bind_rows(loop_metrics_list) %>%
    dplyr::distinct(site, ID, solute, .keep_all = TRUE)
}

EVS2 <- EVS %>%
  dplyr::left_join(
    loop_metrics,
    by = c("site", "ID", "solute")
  ) %>%
  dplyr::mutate(
    HI_use = dplyr::case_when(
      is.finite(HI)        ~ HI,
      is.finite(HI_mean_k) ~ HI_mean_k,
      TRUE                 ~ NA_real_
    ),
    HI_use = pmax(-1, pmin(1, HI_use))
  )

#

###############################################################################
# CORRECTED VAUGHAN FLUSHING INDEX — COMPUTED BEFORE INTEGRATED RESPONSE ANALYSIS
###############################################################################
# Vaughan et al. (2017) flushing index calculated directly from each accepted event trajectory.
################################################################################

message("\n=== VAUGHAN FLUSHING-INDEX CALCULATION ===")

required_fast_objects <- c(
  "df", "EVS2", "eTable", "TZ_USE", "sites", "WORKDIR",
  "REPRO_ROOT", "DIR_REPRO", "DIR_MAIN_FIG_PNG", "DIR_MAIN_FIG_ALT",
  "DIR_MAIN_TAB", "DIR_SUPP_FIG_PNG", "DIR_SUPP_FIG_ALT", "DIR_SUPP_TAB"
)
missing_fast_objects <- required_fast_objects[
  !vapply(required_fast_objects, exists, logical(1), inherits = TRUE)
]
if (length(missing_fast_objects) > 0L) {
  stop(
    "Cannot start the fast Vaughan-FI correction. Missing object(s): ",
    paste(missing_fast_objects, collapse = ", "),
    call. = FALSE
  )
}

required_fast_functions <- c(
  "detect_q_col", "detect_prec_col", "detect_wq_col", "to_num", ".parse_dt"
)
missing_fast_functions <- required_fast_functions[
  !vapply(
    required_fast_functions,
    exists,
    logical(1),
    mode = "function",
    inherits = TRUE
  )
]
if (length(missing_fast_functions) > 0L) {
  stop(
    "Cannot start the fast Vaughan-FI correction. Missing function(s): ",
    paste(missing_fast_functions, collapse = ", "),
    call. = FALSE
  )
}

# Keep the current event register authoritative for event windows and hydrology.
event_metrics <- if (exists("eTable2", inherits = TRUE)) eTable2 else eTable
event_metrics <- event_metrics %>%
  dplyr::mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    tStart = if (inherits(tStart, "POSIXct")) tStart else .parse_dt(tStart, tz = TZ_USE),
    tEnd = if (inherits(tEnd, "POSIXct")) tEnd else .parse_dt(tEnd, tz = TZ_USE)
  ) %>%
  dplyr::distinct(site, ID, .keep_all = TRUE)

# AUTHORITATIVE MANUSCRIPT EVENT-UNIVERSE LOCK
MANUSCRIPT_START <- as.POSIXct("2015-01-01 00:00:00", tz = TZ_USE)
MANUSCRIPT_END   <- as.POSIXct("2020-12-31 23:59:59", tz = TZ_USE)
MANUSCRIPT_SITES <- c("NF", "SHA", "TTP")
MANUSCRIPT_SOLUTES <- c("NO3", "DOC", "EC", "TSS")
MANUSCRIPT_EXPECTED_COUNTS <- c(NF = 279L, SHA = 190L, TTP = 226L)
MANUSCRIPT_EXPECTED_EVENTS <- 695L

# Event membership is defined by accepted hydrograph onset within 2015-2020.
event_metrics <- event_metrics %>%
  dplyr::filter(
    site %in% MANUSCRIPT_SITES,
    !is.na(tStart),
    !is.na(tEnd),
    tStart >= MANUSCRIPT_START,
    tStart <= MANUSCRIPT_END,
    tEnd >= tStart
  ) %>%
  dplyr::distinct(site, ID, .keep_all = TRUE)

manuscript_event_counts <- event_metrics %>%
  dplyr::count(site, name = "n_events") %>%
  dplyr::arrange(match(site, MANUSCRIPT_SITES))

observed_counts <- stats::setNames(
  manuscript_event_counts$n_events,
  manuscript_event_counts$site
)

if (
  !all(names(MANUSCRIPT_EXPECTED_COUNTS) %in% names(observed_counts)) ||
  any(observed_counts[names(MANUSCRIPT_EXPECTED_COUNTS)] != MANUSCRIPT_EXPECTED_COUNTS) ||
  sum(manuscript_event_counts$n_events) != MANUSCRIPT_EXPECTED_EVENTS
) {
  stop(
    paste0(
      "MANUSCRIPT EVENT-UNIVERSE CHECK FAILED.\n",
      "Expected NF=279, SHA=190, TTP=226; total=695.\n",
      "Observed: ",
      paste(names(observed_counts), observed_counts, sep = "=", collapse = ", "),
      "."
    ),
    call. = FALSE
  )
}

MANUSCRIPT_EVENT_KEY <- event_metrics %>%
  dplyr::select(site, ID) %>%
  dplyr::distinct()

# Lock all downstream event-level/event-solute objects used by this tail.
eTable <- eTable %>%
  dplyr::mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    tStart = if (inherits(tStart, "POSIXct")) tStart else .parse_dt(tStart, tz = TZ_USE),
    tEnd = if (inherits(tEnd, "POSIXct")) tEnd else .parse_dt(tEnd, tz = TZ_USE)
  ) %>%
  dplyr::semi_join(MANUSCRIPT_EVENT_KEY, by = c("site", "ID")) %>%
  dplyr::distinct(site, ID, .keep_all = TRUE)

if (exists("eTable2", inherits = TRUE) && is.data.frame(eTable2)) {
  eTable2 <- eTable2 %>%
    dplyr::mutate(
      site = trimws(as.character(site)),
      ID = suppressWarnings(as.integer(ID)),
      tStart = if (inherits(tStart, "POSIXct")) tStart else .parse_dt(tStart, tz = TZ_USE),
      tEnd = if (inherits(tEnd, "POSIXct")) tEnd else .parse_dt(tEnd, tz = TZ_USE)
    ) %>%
    dplyr::semi_join(MANUSCRIPT_EVENT_KEY, by = c("site", "ID")) %>%
    dplyr::distinct(site, ID, .keep_all = TRUE)
}

EVS2 <- EVS2 %>%
  dplyr::mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    solute = toupper(trimws(as.character(solute)))
  ) %>%
  dplyr::semi_join(MANUSCRIPT_EVENT_KEY, by = c("site", "ID"))

if (exists("EVS", inherits = TRUE) && is.data.frame(EVS)) {
  EVS <- EVS %>%
    dplyr::mutate(
      site = trimws(as.character(site)),
      ID = suppressWarnings(as.integer(ID)),
      solute = toupper(trimws(as.character(solute)))
    ) %>%
    dplyr::semi_join(MANUSCRIPT_EVENT_KEY, by = c("site", "ID"))
}

if (
  exists("Events_Conclusive_Table_AllMetrics", inherits = TRUE) &&
  is.data.frame(Events_Conclusive_Table_AllMetrics) &&
  all(c("site", "ID") %in% names(Events_Conclusive_Table_AllMetrics))
) {
  Events_Conclusive_Table_AllMetrics <- Events_Conclusive_Table_AllMetrics %>%
    dplyr::mutate(
      site = trimws(as.character(site)),
      ID = suppressWarnings(as.integer(ID))
    ) %>%
    dplyr::semi_join(MANUSCRIPT_EVENT_KEY, by = c("site", "ID"))
}

# Raw-data view used only where a full-record 2015-2020 summary is required.
df_manuscript <- df %>%
  dplyr::filter(
    !is.na(date),
    date >= MANUSCRIPT_START,
    date <= MANUSCRIPT_END
  )

message(
  "SUCCESS: manuscript event universe locked internally: ",
  "NF=279, SHA=190, TTP=226; total=695."
)

# Vaughan et al. (2017) event flushing index
#
# FI = Cnorm(at peak discharge) - Cnorm(at event onset)
# Cnorm = (C - Cmin) / (Cmax - Cmin)
#
# Therefore every valid FI must lie within [-1, +1].
#
# IMPORTANT:
#   * "event onset" here is the first finite concentration observation within
#     the accepted discharge-event window beginning at tStart.
#   * Qpeak is identified from the discharge series.
#   * concentration must be observed at the Qpeak timestep; no silent
#     interpolation is used when that concentration value is missing.
calc_FI_vaughan <- function(Q, C) {
  Q <- suppressWarnings(as.numeric(Q))
  C <- suppressWarnings(as.numeric(C))

  empty_result <- function(reason = NA_character_) {
    list(
      FI = NA_real_,
      C_initial = NA_real_,
      C_qpeak = NA_real_,
      C_min = NA_real_,
      C_max = NA_real_,
      Q_peak = NA_real_,
      i_initial = NA_integer_,
      i_qpeak = NA_integer_,
      reason = reason
    )
  }

  if (length(Q) != length(C) || length(Q) < 2L) {
    return(empty_result("Q/C length mismatch or insufficient observations"))
  }

  finite_q <- which(is.finite(Q))
  finite_c <- which(is.finite(C))
  if (length(finite_q) == 0L || length(finite_c) < 2L) {
    return(empty_result("insufficient finite Q or C observations"))
  }

  i_initial <- finite_c[1L]
  i_qpeak <- finite_q[which.max(Q[finite_q])]

  if (!is.finite(C[i_qpeak])) {
    z <- empty_result("concentration missing at peak-discharge timestep")
    z$C_initial <- C[i_initial]
    z$Q_peak <- Q[i_qpeak]
    z$i_initial <- i_initial
    z$i_qpeak <- i_qpeak
    return(z)
  }

  C_min <- min(C[finite_c], na.rm = TRUE)
  C_max <- max(C[finite_c], na.rm = TRUE)
  C_range <- C_max - C_min

  if (!is.finite(C_range) || C_range <= 0) {
    z <- empty_result("zero or invalid event concentration range")
    z$C_initial <- C[i_initial]
    z$C_qpeak <- C[i_qpeak]
    z$C_min <- C_min
    z$C_max <- C_max
    z$Q_peak <- Q[i_qpeak]
    z$i_initial <- i_initial
    z$i_qpeak <- i_qpeak
    return(z)
  }

  C_initial_norm <- (C[i_initial] - C_min) / C_range
  C_qpeak_norm <- (C[i_qpeak] - C_min) / C_range
  FI <- C_qpeak_norm - C_initial_norm

  # Floating-point protection only; no substantive truncation.
  if (is.finite(FI) && FI > 1 && FI <= 1 + 1e-12) FI <- 1
  if (is.finite(FI) && FI < -1 && FI >= -1 - 1e-12) FI <- -1

  list(
    FI = as.numeric(FI),
    C_initial = as.numeric(C[i_initial]),
    C_qpeak = as.numeric(C[i_qpeak]),
    C_min = as.numeric(C_min),
    C_max = as.numeric(C_max),
    Q_peak = as.numeric(Q[i_qpeak]),
    i_initial = as.integer(i_initial),
    i_qpeak = as.integer(i_qpeak),
    reason = NA_character_
  )
}

# Build FI only for event-solute combinations already represented in EVS2.
fi_event_register <- event_metrics %>%
  dplyr::select(site, ID, tStart, tEnd) %>%
  dplyr::filter(!is.na(tStart), !is.na(tEnd), tEnd >= tStart) %>%
  dplyr::distinct(site, ID, .keep_all = TRUE)

fi_needed <- EVS2 %>%
  dplyr::transmute(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    solute = toupper(trimws(as.character(solute)))
  ) %>%
  dplyr::filter(
    site %in% c("NF", "SHA", "TTP"),
    solute %in% c("NO3", "DOC", "EC", "TSS"),
    !is.na(ID)
  ) %>%
  dplyr::distinct(site, ID, solute)

fi_event_keys <- fi_needed %>%
  dplyr::distinct(site, ID) %>%
  dplyr::left_join(fi_event_register, by = c("site", "ID"))

fi_rows <- vector("list", nrow(fi_event_keys) * 4L)
fi_counter <- 0L

for (i in seq_len(nrow(fi_event_keys))) {
  ev_i <- fi_event_keys[i, , drop = FALSE]
  site_i <- as.character(ev_i$site)
  ID_i <- as.integer(ev_i$ID)

  solutes_i <- fi_needed %>%
    dplyr::filter(site == site_i, ID == ID_i) %>%
    dplyr::pull(solute)

  if (
    length(solutes_i) == 0L ||
    is.na(ev_i$tStart) ||
    is.na(ev_i$tEnd)
  ) next

  q_col_i <- detect_q_col(names(df), site_i)

  if (is.na(q_col_i) || !(q_col_i %in% names(df))) {
    for (solute_i in solutes_i) {
      fi_counter <- fi_counter + 1L
      fi_rows[[fi_counter]] <- tibble::tibble(
        site = site_i,
        ID = ID_i,
        solute = solute_i,
        FI_Vaughan = NA_real_,
        FI_Cinitial = NA_real_,
        FI_CQpeak = NA_real_,
        FI_Cmin = NA_real_,
        FI_Cmax = NA_real_,
        FI_Qpeak = NA_real_,
        FI_Qpeak_time = as.POSIXct(NA, tz = TZ_USE),
        FI_status = "missing discharge column"
      )
    }
    next
  }

  idx_i <- which(
    df$date >= ev_i$tStart &
      df$date <= ev_i$tEnd
  )

  if (length(idx_i) < 2L) next

  Q_i <- to_num(df[[q_col_i]][idx_i])
  date_i <- df$date[idx_i]

  for (solute_i in solutes_i) {
    c_col_i <- detect_wq_col(names(df), site_i, solute_i)
    fi_counter <- fi_counter + 1L

    if (is.na(c_col_i) || !(c_col_i %in% names(df))) {
      fi_rows[[fi_counter]] <- tibble::tibble(
        site = site_i,
        ID = ID_i,
        solute = solute_i,
        FI_Vaughan = NA_real_,
        FI_Cinitial = NA_real_,
        FI_CQpeak = NA_real_,
        FI_Cmin = NA_real_,
        FI_Cmax = NA_real_,
        FI_Qpeak = NA_real_,
        FI_Qpeak_time = as.POSIXct(NA, tz = TZ_USE),
        FI_status = "missing concentration column"
      )
      next
    }

    C_i <- to_num(df[[c_col_i]][idx_i])
    fi_i <- calc_FI_vaughan(Q_i, C_i)

    qpeak_time_i <- if (
      is.finite(fi_i$i_qpeak) &&
      fi_i$i_qpeak >= 1L &&
      fi_i$i_qpeak <= length(date_i)
    ) {
      date_i[fi_i$i_qpeak]
    } else {
      as.POSIXct(NA, tz = TZ_USE)
    }

    fi_rows[[fi_counter]] <- tibble::tibble(
      site = site_i,
      ID = ID_i,
      solute = solute_i,
      FI_Vaughan = fi_i$FI,
      FI_Cinitial = fi_i$C_initial,
      FI_CQpeak = fi_i$C_qpeak,
      FI_Cmin = fi_i$C_min,
      FI_Cmax = fi_i$C_max,
      FI_Qpeak = fi_i$Q_peak,
      FI_Qpeak_time = qpeak_time_i,
      FI_status = dplyr::if_else(
        is.na(fi_i$reason),
        "valid",
        fi_i$reason
      )
    )
  }
}

fi_vaughan_lookup <- dplyr::bind_rows(fi_rows[seq_len(fi_counter)]) %>%
  dplyr::distinct(site, ID, solute, .keep_all = TRUE)

if (nrow(fi_vaughan_lookup) == 0L) {
  stop("No Vaughan FI values could be constructed from the existing workspace.", call. = FALSE)
}

bad_fi <- fi_vaughan_lookup %>%
  dplyr::filter(
    is.finite(FI_Vaughan),
    FI_Vaughan < -1 - 1e-10 | FI_Vaughan > 1 + 1e-10
  )

if (nrow(bad_fi) > 0L) {
  stop(
    "Vaughan FI validation failed: ",
    nrow(bad_fi),
    " value(s) lie outside [-1, 1].",
    call. = FALSE
  )
}

# INSTALL CORRECTED VAUGHAN FI AS THE AUTHORITATIVE FI
# Remove any previous Vaughan-audit columns so this block is idempotent.
EVS2 <- EVS2 %>%
  dplyr::select(
    -dplyr::any_of(c(
      "FI_Vaughan", "FI_Cinitial", "FI_CQpeak", "FI_Cmin", "FI_Cmax",
      "FI_Qpeak", "FI_Qpeak_time", "FI_status"
    ))
  ) %>%
  dplyr::left_join(
    fi_vaughan_lookup,
    by = c("site", "ID", "solute")
  ) %>%
  dplyr::mutate(FI_peak = FI_Vaughan)

# Keep EVS synchronized because a few retained helpers can use it as fallback.
if (exists("EVS", inherits = TRUE) && is.data.frame(EVS)) {
  EVS <- EVS %>%
    dplyr::select(
      -dplyr::any_of(c(
        "FI_Vaughan", "FI_Cinitial", "FI_CQpeak", "FI_Cmin", "FI_Cmax",
        "FI_Qpeak", "FI_Qpeak_time", "FI_status"
      ))
    ) %>%
    dplyr::left_join(
      fi_vaughan_lookup,
      by = c("site", "ID", "solute")
    ) %>%
    dplyr::mutate(FI_peak = FI_Vaughan)
}

# Hard reproducibility checks for the 695 x 4 event-constituent universe.
fi_distinct_events <- fi_vaughan_lookup %>%
  dplyr::distinct(site, ID) %>%
  nrow()

if (fi_distinct_events != MANUSCRIPT_EXPECTED_EVENTS) {
  stop(
    "Vaughan FI audit contains ", fi_distinct_events,
    " distinct events; expected exactly 695.",
    call. = FALSE
  )
}

expected_fi_rows <- MANUSCRIPT_EXPECTED_EVENTS * length(MANUSCRIPT_SOLUTES)
if (nrow(fi_vaughan_lookup) != expected_fi_rows) {
  stop(
    "Vaughan FI audit contains ", nrow(fi_vaughan_lookup),
    " event-constituent rows; expected exactly ", expected_fi_rows, ".",
    call. = FALSE
  )
}

# Permanent reproducibility outputs: no legacy-metric comparison is retained.

fi_vaughan_summary <- fi_vaughan_lookup %>%
  dplyr::group_by(site, solute) %>%
  dplyr::summarise(
    n_total = dplyr::n(),
    n_valid = sum(is.finite(FI_Vaughan)),
    valid_percent = 100 * mean(is.finite(FI_Vaughan)),
    FI_min = ifelse(any(is.finite(FI_Vaughan)), min(FI_Vaughan, na.rm = TRUE), NA_real_),
    FI_Q1 = ifelse(any(is.finite(FI_Vaughan)), stats::quantile(FI_Vaughan, 0.25, na.rm = TRUE), NA_real_),
    FI_median = ifelse(any(is.finite(FI_Vaughan)), stats::median(FI_Vaughan, na.rm = TRUE), NA_real_),
    FI_Q3 = ifelse(any(is.finite(FI_Vaughan)), stats::quantile(FI_Vaughan, 0.75, na.rm = TRUE), NA_real_),
    FI_max = ifelse(any(is.finite(FI_Vaughan)), max(FI_Vaughan, na.rm = TRUE), NA_real_),
    .groups = "drop"
  )

message(
  "Vaughan FI installed as authoritative FI_peak. Valid finite range: ",
  sprintf("%.3f", min(fi_vaughan_lookup$FI_Vaughan, na.rm = TRUE)),
  " to ",
  sprintf("%.3f", max(fi_vaughan_lookup$FI_Vaughan, na.rm = TRUE)),
  "; valid FI rows = ", sum(is.finite(fi_vaughan_lookup$FI_Vaughan)),
  " / ", nrow(fi_vaughan_lookup), "."
)

################################################################################
# END FAST VAUGHAN-FI CONSTRUCTION
################################################################################

###############################################################################
# SECTION 3.3 — AUTHORITATIVE INTEGRATED RESPONSE ANALYSIS (SINGLE PASS)
###############################################################################
# SECTION 3.3 - INTEGRATED RESPONSE-PATTERN AND ENVIRONMENTAL-CONTROL ANALYSIS
#
# Integrated analysis of HI_Lloyd, A_loop and FI_peak as joint response variables.
#
# Required upstream objects:
#   EVS2, eTable, df, TZ_USE, detect_q_col(), detect_prec_col(), to_num()
#
# Main outputs:
#   1. multivariate response groups based on HI_use, loop_area, and FI_peak;
#   2. silhouette and bootstrap-Jaccard stability diagnostics;
#   3. rainfall-pulse and discharge-peak complexity metrics;
#   4. cluster composition and catchment-constituent enrichment tables;
#   5. environmental-condition tests with Benjamini-Hochberg correction;
#   6. descriptive enrichment and hydrological response-profile figures;
#   7. site-solute-adjusted cluster-probability curves and transition ranges;
#   8. PAM clustering diagnostics and representative medoid records;
#   9. an integrated four-panel figure for the main manuscript.
################################################################################

message("\n=== SECTION 3.3 INTEGRATED RESPONSE ANALYSIS ===")

# 0. PACKAGE AND OBJECT CHECKS

ir33_required_packages <- c(
  "dplyr", "tidyr", "purrr", "tibble", "ggplot2", "patchwork",
  "cluster", "zoo", "stringr", "scales", "mgcv"
)

ir33_missing_packages <- ir33_required_packages[
  !vapply(ir33_required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(ir33_missing_packages) > 0L) {
  stop(
    "Install the following package(s) before running the Section 3.3 module: ",
    paste(ir33_missing_packages, collapse = ", "),
    call. = FALSE
  )
}

ir33_required_objects <- c("EVS2", "eTable", "df", "TZ_USE")
ir33_missing_objects <- ir33_required_objects[
  !vapply(ir33_required_objects, exists, logical(1), inherits = TRUE)
]

ir33_required_functions <- c(
  "detect_q_col", "detect_prec_col", "to_num", ".parse_dt"
)
ir33_missing_functions <- ir33_required_functions[
  !vapply(
    ir33_required_functions,
    exists,
    logical(1),
    mode = "function",
    inherits = TRUE
  )
]

if (length(ir33_missing_objects) > 0L || length(ir33_missing_functions) > 0L) {
  stop(
    paste0(
      "The Section 3.3 module cannot run because upstream objects/functions ",
      "are missing.\nObjects: ",
      paste(ir33_missing_objects, collapse = ", "),
      "\nFunctions: ",
      paste(ir33_missing_functions, collapse = ", ")
    ),
    call. = FALSE
  )
}

# 1. SETTINGS AND OUTPUT DIRECTORIES

IR33_SITES <- c("NF", "SHA", "TTP")
IR33_SOLUTES <- c("NO3", "DOC", "EC", "TSS")
IR33_RESPONSE_COLUMNS <- c("HI_use", "loop_area", "FI_peak")
IR33_K_CANDIDATES <- 2:6
IR33_MIN_CLUSTER_FRACTION <- 0.05
IR33_MIN_CLUSTER_N <- 20L
IR33_BOOTSTRAP_REPS <- 200L
IR33_SEED <- 20260730L
IR33_RAIN_WET_THRESHOLD_MM <- 0.05

# Site-specific dry gaps used to separate distinct rainfall pulses. These match
# the event-delineation Methods: 2 h in NF and SHA, and 3 h in TTP.
IR33_RAIN_MIN_DRY_HOURS <- c(NF = 2, SHA = 2, TTP = 3)

IR33_Q_MIN_PEAK_SEPARATION_HOURS <- 2
IR33_Q_MIN_PROMINENCE_FRACTION <- 0.10

# Adjusted cluster-probability curves. The transition range is the contiguous
# section around the steepest fitted change where the absolute first derivative
# is at least 50% of its maximum. It is descriptive, not a causal threshold.
IR33_GAM_K <- 5L
IR33_GAM_GRID_N <- 160L
IR33_TRANSITION_SLOPE_FRACTION <- 0.50
IR33_GAM_MIN_N <- 100L

IR33_ROOT <- if (exists("DIR_PAPER", inherits = TRUE)) {
  file.path(DIR_PAPER, "Section3_3_Integrated_Response_Analysis")
} else if (exists("WORKDIR", inherits = TRUE)) {
  file.path(WORKDIR, "PaperStyle_Outputs", "Section3_3_Integrated_Response_Analysis")
} else {
  file.path(getwd(), "PaperStyle_Outputs", "Section3_3_Integrated_Response_Analysis")
}

IR33_FIG <- file.path(IR33_ROOT, "Figures")
IR33_TAB <- file.path(IR33_ROOT, "Tables")

invisible(lapply(
  c(IR33_ROOT, IR33_FIG, IR33_TAB),
  dir.create,
  recursive = TRUE,
  showWarnings = FALSE
))

# 2. LOCAL HELPERS

ir33_first_existing <- function(candidates, available_names) {
  hit <- candidates[candidates %in% available_names]
  if (length(hit) == 0L) NA_character_ else hit[1L]
}

ir33_add_alias <- function(data, target, candidates) {
  if (target %in% names(data)) return(data)
  source_col <- ir33_first_existing(candidates, names(data))
  if (!is.na(source_col)) {
    data[[target]] <- data[[source_col]]
  } else {
    data[[target]] <- NA_real_
  }
  data
}

ir33_as_true <- function(x) {
  tolower(trimws(as.character(x))) %in% c("true", "1", "yes", "responsive")
}

ir33_winsorize <- function(x, probs = c(0.01, 0.99)) {
  x <- suppressWarnings(as.numeric(x))
  ok <- is.finite(x)
  if (!any(ok)) return(x)
  q <- stats::quantile(x[ok], probs = probs, na.rm = TRUE, names = FALSE)
  if (!all(is.finite(q)) || q[1] >= q[2]) return(x)
  x[ok] <- pmin(q[2], pmax(q[1], x[ok]))
  x
}

ir33_robust_z <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  ok <- is.finite(x)
  out <- rep(NA_real_, length(x))
  if (!any(ok)) return(out)
  centre <- stats::median(x[ok], na.rm = TRUE)
  spread <- stats::mad(x[ok], center = centre, constant = 1.4826, na.rm = TRUE)
  if (!is.finite(spread) || spread <= 0) {
    spread <- stats::sd(x[ok], na.rm = TRUE)
  }
  if (!is.finite(spread) || spread <= 0) {
    out[ok] <- 0
  } else {
    out[ok] <- (x[ok] - centre) / spread
  }
  out
}

ir33_count_rain_pulses <- function(
    precipitation,
    wet_threshold = IR33_RAIN_WET_THRESHOLD_MM,
    min_dry_steps = 6L) {
  precipitation <- suppressWarnings(as.numeric(precipitation))
  precipitation[!is.finite(precipitation)] <- 0
  if (length(precipitation) == 0L || max(precipitation, na.rm = TRUE) <= wet_threshold) {
    return(0L)
  }

  wet <- precipitation > wet_threshold
  pulse_start <- logical(length(wet))

  for (i in seq_along(wet)) {
    if (!wet[i]) next
    if (i == 1L) {
      pulse_start[i] <- TRUE
      next
    }
    left <- max(1L, i - min_dry_steps)
    previous_window <- wet[left:(i - 1L)]
    pulse_start[i] <- !any(previous_window)
  }

  as.integer(sum(pulse_start))
}

ir33_discharge_peak_metrics <- function(
    discharge,
    timestep_minutes = 10,
    minimum_separation_hours = IR33_Q_MIN_PEAK_SEPARATION_HOURS,
    minimum_prominence_fraction = IR33_Q_MIN_PROMINENCE_FRACTION) {

  q <- suppressWarnings(as.numeric(discharge))
  valid <- is.finite(q)
  if (sum(valid) < 7L) {
    return(tibble::tibble(
      discharge_peak_count = NA_integer_,
      discharge_peak_separation_h = NA_real_,
      discharge_peak_prominence_max = NA_real_
    ))
  }

  # Preserve event order and interpolate only internal short gaps for peak finding.
  q_work <- q
  if (any(!valid)) {
    idx <- seq_along(q_work)
    q_work[!valid] <- stats::approx(
      x = idx[valid],
      y = q_work[valid],
      xout = idx[!valid],
      rule = 2,
      ties = "ordered"
    )$y
  }

  q_smooth <- zoo::rollapply(
    q_work,
    width = 5L,
    FUN = stats::median,
    fill = NA_real_,
    align = "center",
    partial = TRUE,
    na.rm = TRUE
  )

  n <- length(q_smooth)
  if (n < 3L) {
    return(tibble::tibble(
      discharge_peak_count = 0L,
      discharge_peak_separation_h = NA_real_,
      discharge_peak_prominence_max = NA_real_
    ))
  }

  candidates <- which(
    q_smooth[2:(n - 1L)] > q_smooth[1:(n - 2L)] &
      q_smooth[2:(n - 1L)] >= q_smooth[3:n]
  ) + 1L

  q_range <- diff(range(q_smooth, na.rm = TRUE))
  if (!is.finite(q_range) || q_range <= 0 || length(candidates) == 0L) {
    return(tibble::tibble(
      discharge_peak_count = 0L,
      discharge_peak_separation_h = NA_real_,
      discharge_peak_prominence_max = NA_real_
    ))
  }

  separation_steps <- max(
    1L,
    as.integer(round(minimum_separation_hours * 60 / timestep_minutes))
  )

  prominence <- vapply(candidates, function(i) {
    left_index <- max(1L, i - separation_steps):i
    right_index <- i:min(n, i + separation_steps)
    left_min <- min(q_smooth[left_index], na.rm = TRUE)
    right_min <- min(q_smooth[right_index], na.rm = TRUE)
    q_smooth[i] - max(left_min, right_min)
  }, numeric(1))

  keep <- is.finite(prominence) &
    prominence >= minimum_prominence_fraction * q_range
  candidates <- candidates[keep]
  prominence <- prominence[keep]

  if (length(candidates) == 0L) {
    return(tibble::tibble(
      discharge_peak_count = 0L,
      discharge_peak_separation_h = NA_real_,
      discharge_peak_prominence_max = NA_real_
    ))
  }

  # Retain the highest peaks first and enforce the minimum separation.
  order_by_height <- order(q_smooth[candidates], decreasing = TRUE)
  accepted <- integer()
  accepted_prominence <- numeric()

  for (j in order_by_height) {
    candidate_i <- candidates[j]
    if (
      length(accepted) == 0L ||
      all(abs(candidate_i - accepted) >= separation_steps)
    ) {
      accepted <- c(accepted, candidate_i)
      accepted_prominence <- c(accepted_prominence, prominence[j])
    }
  }

  accepted <- sort(accepted)
  peak_separation_h <- if (length(accepted) >= 2L) {
    (max(accepted) - min(accepted)) * timestep_minutes / 60
  } else {
    NA_real_
  }

  tibble::tibble(
    discharge_peak_count = as.integer(length(accepted)),
    discharge_peak_separation_h = peak_separation_h,
    discharge_peak_prominence_max = max(accepted_prominence, na.rm = TRUE)
  )
}

ir33_safe_kruskal <- function(values, groups) {
  ok <- is.finite(values) & !is.na(groups)
  values <- values[ok]
  groups <- droplevels(factor(groups[ok]))
  if (length(values) < 10L || nlevels(groups) < 2L) {
    return(c(statistic = NA_real_, p = NA_real_, n = length(values)))
  }
  test <- try(stats::kruskal.test(values ~ groups), silent = TRUE)
  if (inherits(test, "try-error")) {
    return(c(statistic = NA_real_, p = NA_real_, n = length(values)))
  }
  c(
    statistic = unname(test$statistic),
    p = unname(test$p.value),
    n = length(values)
  )
}

ir33_safe_chisq <- function(
    x,
    y,
    seed = IR33_SEED,
    B = 5000L) {

  tab <- table(x, y, useNA = "no")

  if (nrow(tab) < 2L || ncol(tab) < 2L || sum(tab) == 0L) {
    return(list(
      statistic = NA_real_,
      p = NA_real_,
      method = NA_character_,
      table = tab,
      expected = matrix(NA_real_, nrow(tab), ncol(tab)),
      stdres = matrix(NA_real_, nrow(tab), ncol(tab))
    ))
  }

  # The asymptotic fit supplies the Pearson statistic, expected frequencies,
  # and adjusted standardized residuals. The reported p-value is simulated.
  asymptotic_test <- suppressWarnings(
    stats::chisq.test(tab, correct = FALSE)
  )

  set.seed(seed)
  simulated_test <- suppressWarnings(
    stats::chisq.test(
      tab,
      correct = FALSE,
      simulate.p.value = TRUE,
      B = B
    )
  )

  list(
    statistic = unname(asymptotic_test$statistic),
    p = unname(simulated_test$p.value),
    method = paste0(
      "Pearson chi-squared test with simulated p-value (B = ",
      format(B, big.mark = ","),
      ")"
    ),
    table = tab,
    expected = asymptotic_test$expected,
    stdres = asymptotic_test$stdres
  )
}

ir33_bootstrap_jaccard <- function(
    x,
    original_cluster,
    k,
    bootstrap_reps = IR33_BOOTSTRAP_REPS,
    seed = IR33_SEED) {

  x <- as.matrix(x)
  original_cluster <- as.integer(original_cluster)
  n <- nrow(x)
  clusters <- sort(unique(original_cluster))
  output <- matrix(
    NA_real_,
    nrow = bootstrap_reps,
    ncol = length(clusters),
    dimnames = list(NULL, paste0("Cluster_", clusters))
  )

  set.seed(seed)

  for (b in seq_len(bootstrap_reps)) {
    sampled_index <- sample(seq_len(n), size = n, replace = TRUE)
    fit_b <- try(
      cluster::pam(x[sampled_index, , drop = FALSE], k = k),
      silent = TRUE
    )
    if (inherits(fit_b, "try-error")) next

    assignment_data <- tibble::tibble(
      original_index = sampled_index,
      bootstrap_cluster = as.integer(fit_b$clustering)
    ) %>%
      dplyr::count(original_index, bootstrap_cluster, name = "frequency") %>%
      dplyr::group_by(original_index) %>%
      dplyr::slice_max(
        order_by = frequency,
        n = 1L,
        with_ties = FALSE
      ) %>%
      dplyr::ungroup()

    sampled_unique <- assignment_data$original_index

    for (cluster_i in clusters) {
      original_members <- sampled_unique[
        original_cluster[sampled_unique] == cluster_i
      ]
      if (length(original_members) == 0L) next

      jaccard_candidates <- vapply(sort(unique(assignment_data$bootstrap_cluster)), function(cluster_j) {
        bootstrap_members <- assignment_data$original_index[
          assignment_data$bootstrap_cluster == cluster_j
        ]
        union_n <- length(union(original_members, bootstrap_members))
        if (union_n == 0L) return(NA_real_)
        length(intersect(original_members, bootstrap_members)) / union_n
      }, numeric(1))

      output[b, paste0("Cluster_", cluster_i)] <- max(
        jaccard_candidates,
        na.rm = TRUE
      )
    }
  }

  tibble::tibble(
    Cluster = clusters,
    mean_bootstrap_jaccard = colMeans(output, na.rm = TRUE),
    median_bootstrap_jaccard = apply(output, 2, stats::median, na.rm = TRUE),
    valid_bootstrap_replicates = colSums(is.finite(output))
  )
}

ir33_save_plot <- function(plot_object, filename, width_mm, height_mm) {
  ggplot2::ggsave(
    filename = filename,
    plot = plot_object,
    width = width_mm,
    height = height_mm,
    units = "mm",
    dpi = 600,
    bg = "white"
  )
}

ir33_average_binomial_predictions <- function(
    fit,
    newdata,
    grid_id,
    confidence_level = 0.95) {

  X <- stats::predict(
    fit,
    newdata = newdata,
    type = "lpmatrix"
  )

  beta <- stats::coef(fit)
  covariance <- stats::vcov(fit)
  eta <- drop(X %*% beta)
  probability <- stats::plogis(eta)
  z_value <- stats::qnorm(1 - (1 - confidence_level) / 2)

  split_rows <- split(seq_len(nrow(X)), grid_id)

  purrr::map_dfr(
    names(split_rows),
    function(grid_i) {
      rows_i <- split_rows[[grid_i]]
      X_i <- X[rows_i, , drop = FALSE]
      p_i <- probability[rows_i]

      # Delta-method gradient of the mean probability over the observed
      # catchment-constituent distribution represented in newdata.
      weights_i <- p_i * (1 - p_i)
      gradient_i <- colMeans(
        X_i * matrix(
          weights_i,
          nrow = length(weights_i),
          ncol = ncol(X_i)
        )
      )

      variance_i <- drop(
        t(gradient_i) %*% covariance %*% gradient_i
      )
      standard_error_i <- sqrt(max(0, variance_i))
      estimate_i <- mean(p_i)

      tibble::tibble(
        grid_id = as.integer(grid_i),
        probability = estimate_i,
        standard_error = standard_error_i,
        lower = pmax(0, estimate_i - z_value * standard_error_i),
        upper = pmin(1, estimate_i + z_value * standard_error_i)
      )
    }
  )
}

ir33_transition_range <- function(
    x,
    probability,
    slope_fraction = IR33_TRANSITION_SLOPE_FRACTION) {

  x <- suppressWarnings(as.numeric(x))
  probability <- suppressWarnings(as.numeric(probability))
  ok <- is.finite(x) & is.finite(probability)
  x <- x[ok]
  probability <- probability[ok]

  if (length(x) < 5L || length(unique(x)) < 5L) {
    return(tibble::tibble(
      transition_point = NA_real_,
      transition_lower = NA_real_,
      transition_upper = NA_real_,
      maximum_absolute_slope = NA_real_,
      direction = NA_character_
    ))
  }

  ordering <- order(x)
  x <- x[ordering]
  probability <- probability[ordering]

  derivative <- diff(probability) / diff(x)
  derivative_midpoint <- (x[-1L] + x[-length(x)]) / 2

  if (!any(is.finite(derivative))) {
    return(tibble::tibble(
      transition_point = NA_real_,
      transition_lower = NA_real_,
      transition_upper = NA_real_,
      maximum_absolute_slope = NA_real_,
      direction = NA_character_
    ))
  }

  maximum_index <- which.max(abs(derivative))
  maximum_slope <- derivative[maximum_index]

  if (!is.finite(maximum_slope) || abs(maximum_slope) <= .Machine$double.eps) {
    return(tibble::tibble(
      transition_point = NA_real_,
      transition_lower = NA_real_,
      transition_upper = NA_real_,
      maximum_absolute_slope = abs(maximum_slope),
      direction = "flat"
    ))
  }

  active <- abs(derivative) >= slope_fraction * abs(maximum_slope)

  # Retain the contiguous active segment containing the steepest change.
  left_index <- maximum_index
  while (left_index > 1L && isTRUE(active[left_index - 1L])) {
    left_index <- left_index - 1L
  }

  right_index <- maximum_index
  while (
    right_index < length(active) &&
    isTRUE(active[right_index + 1L])
  ) {
    right_index <- right_index + 1L
  }

  tibble::tibble(
    transition_point = derivative_midpoint[maximum_index],
    transition_lower = x[left_index],
    transition_upper = x[right_index + 1L],
    maximum_absolute_slope = abs(maximum_slope),
    direction = ifelse(maximum_slope > 0, "increasing", "decreasing")
  )
}

ir33_fit_adjusted_continuous_gam <- function(
    data,
    target_cluster,
    predictor,
    k = IR33_GAM_K,
    grid_n = IR33_GAM_GRID_N) {

  model_data <- data %>%
    dplyr::transmute(
      target = as.integer(Cluster_short == target_cluster),
      driver = suppressWarnings(as.numeric(.data[[predictor]])),
      site_solute = factor(site_solute)
    ) %>%
    dplyr::filter(
      is.finite(driver),
      !is.na(site_solute)
    ) %>%
    droplevels()

  if (
    nrow(model_data) < IR33_GAM_MIN_N ||
    length(unique(model_data$driver)) < 8L ||
    length(unique(model_data$target)) < 2L
  ) {
    return(list(
      fit = NULL,
      curve = tibble::tibble(),
      transition = tibble::tibble(),
      diagnostics = tibble::tibble(
        target_cluster = target_cluster,
        predictor = predictor,
        model_type = "continuous GAM",
        n = nrow(model_data),
        converged = FALSE,
        deviance_explained = NA_real_,
        AIC = NA_real_,
        smooth_p_value = NA_real_,
        note = "Insufficient observations, predictor variation, or outcome classes."
      )
    ))
  }

  k_use <- max(
    3L,
    min(
      as.integer(k),
      length(unique(model_data$driver)) - 1L
    )
  )

  gam_formula <- stats::as.formula(
    paste0(
      "target ~ s(driver, k = ",
      k_use,
      ", bs = 'tp') + site_solute"
    )
  )
  environment(gam_formula) <- asNamespace("mgcv")

  fit <- try(
    mgcv::gam(
      formula = gam_formula,
      data = model_data,
      family = stats::binomial(),
      method = "REML"
    ),
    silent = TRUE
  )

  if (inherits(fit, "try-error")) {
    return(list(
      fit = NULL,
      curve = tibble::tibble(),
      transition = tibble::tibble(),
      diagnostics = tibble::tibble(
        target_cluster = target_cluster,
        predictor = predictor,
        model_type = "continuous GAM",
        n = nrow(model_data),
        converged = FALSE,
        deviance_explained = NA_real_,
        AIC = NA_real_,
        smooth_p_value = NA_real_,
        note = as.character(fit)
      )
    ))
  }

  limits <- stats::quantile(
    model_data$driver,
    probs = c(0.02, 0.98),
    na.rm = TRUE,
    names = FALSE
  )

  driver_grid <- seq(
    limits[1],
    limits[2],
    length.out = grid_n
  )

  site_weights <- model_data %>%
    dplyr::count(site_solute, name = "weight") %>%
    dplyr::mutate(weight = weight / sum(weight))

  prediction_data <- tidyr::crossing(
    grid_id = seq_along(driver_grid),
    site_solute = levels(model_data$site_solute)
  ) %>%
    dplyr::mutate(
      driver = driver_grid[grid_id],
      site_solute = factor(
        site_solute,
        levels = levels(model_data$site_solute)
      )
    ) %>%
    dplyr::left_join(site_weights, by = "site_solute")

  # Weighted marginalization over the observed catchment-constituent mix.
  X <- stats::predict(
    fit,
    newdata = prediction_data,
    type = "lpmatrix"
  )
  beta <- stats::coef(fit)
  covariance <- stats::vcov(fit)
  eta <- drop(X %*% beta)
  p <- stats::plogis(eta)
  z_value <- stats::qnorm(0.975)

  split_rows <- split(seq_len(nrow(X)), prediction_data$grid_id)

  curve <- purrr::map_dfr(
    names(split_rows),
    function(grid_i) {
      rows_i <- split_rows[[grid_i]]
      X_i <- X[rows_i, , drop = FALSE]
      p_i <- p[rows_i]
      w_i <- prediction_data$weight[rows_i]
      w_i <- w_i / sum(w_i)

      estimate_i <- sum(w_i * p_i)
      gradient_i <- colSums(
        X_i * matrix(
          w_i * p_i * (1 - p_i),
          nrow = length(rows_i),
          ncol = ncol(X_i)
        )
      )
      variance_i <- drop(
        t(gradient_i) %*% covariance %*% gradient_i
      )
      se_i <- sqrt(max(0, variance_i))

      tibble::tibble(
        grid_id = as.integer(grid_i),
        driver_value = driver_grid[as.integer(grid_i)],
        probability = estimate_i,
        standard_error = se_i,
        lower = pmax(0, estimate_i - z_value * se_i),
        upper = pmin(1, estimate_i + z_value * se_i)
      )
    }
  ) %>%
    dplyr::mutate(
      target_cluster = target_cluster,
      predictor = predictor,
      .before = 1
    )

  transition <- ir33_transition_range(
    x = curve$driver_value,
    probability = curve$probability
  ) %>%
    dplyr::mutate(
      target_cluster = target_cluster,
      predictor = predictor,
      .before = 1
    )

  fit_summary <- summary(fit)
  smooth_p <- if (
    !is.null(fit_summary$s.table) &&
    nrow(fit_summary$s.table) >= 1L
  ) {
    unname(fit_summary$s.table[1L, "p-value"])
  } else {
    NA_real_
  }

  diagnostics <- tibble::tibble(
    target_cluster = target_cluster,
    predictor = predictor,
    model_type = "continuous GAM",
    n = nrow(model_data),
    converged = isTRUE(fit$converged),
    deviance_explained = unname(fit_summary$dev.expl),
    AIC = stats::AIC(fit),
    smooth_p_value = smooth_p,
    note = "Site-solute-adjusted marginal probability curve."
  )

  list(
    fit = fit,
    curve = curve,
    transition = transition,
    diagnostics = diagnostics
  )
}

ir33_fit_adjusted_discrete_gam <- function(
    data,
    target_cluster,
    predictor = "discharge_peak_count") {

  model_data <- data %>%
    dplyr::transmute(
      target = as.integer(Cluster_short == target_cluster),
      driver_numeric = suppressWarnings(as.numeric(.data[[predictor]])),
      site_solute = factor(site_solute)
    ) %>%
    dplyr::filter(
      is.finite(driver_numeric),
      !is.na(site_solute)
    ) %>%
    dplyr::mutate(
      driver_factor = dplyr::case_when(
        driver_numeric >= 3 ~ "3+",
        TRUE ~ as.character(as.integer(driver_numeric))
      ),
      driver_factor = factor(
        driver_factor,
        levels = c("0", "1", "2", "3+")
      )
    ) %>%
    dplyr::filter(!is.na(driver_factor)) %>%
    droplevels()

  if (
    nrow(model_data) < IR33_GAM_MIN_N ||
    nlevels(model_data$driver_factor) < 2L ||
    length(unique(model_data$target)) < 2L
  ) {
    return(list(
      fit = NULL,
      curve = tibble::tibble(),
      diagnostics = tibble::tibble(
        target_cluster = target_cluster,
        predictor = predictor,
        model_type = "discrete adjusted binomial model",
        n = nrow(model_data),
        converged = FALSE,
        deviance_explained = NA_real_,
        AIC = NA_real_,
        smooth_p_value = NA_real_,
        note = "Insufficient observations, predictor levels, or outcome classes."
      )
    ))
  }

  fit <- try(
    mgcv::gam(
      target ~ driver_factor + site_solute,
      data = model_data,
      family = stats::binomial(),
      method = "REML"
    ),
    silent = TRUE
  )

  if (inherits(fit, "try-error")) {
    return(list(
      fit = NULL,
      curve = tibble::tibble(),
      diagnostics = tibble::tibble(
        target_cluster = target_cluster,
        predictor = predictor,
        model_type = "discrete adjusted binomial model",
        n = nrow(model_data),
        converged = FALSE,
        deviance_explained = NA_real_,
        AIC = NA_real_,
        smooth_p_value = NA_real_,
        note = as.character(fit)
      )
    ))
  }

  site_weights <- model_data %>%
    dplyr::count(site_solute, name = "weight") %>%
    dplyr::mutate(weight = weight / sum(weight))

  driver_levels <- levels(model_data$driver_factor)

  prediction_data <- tidyr::crossing(
    grid_id = seq_along(driver_levels),
    site_solute = levels(model_data$site_solute)
  ) %>%
    dplyr::mutate(
      driver_factor = factor(
        driver_levels[grid_id],
        levels = driver_levels
      ),
      site_solute = factor(
        site_solute,
        levels = levels(model_data$site_solute)
      )
    ) %>%
    dplyr::left_join(site_weights, by = "site_solute")

  X <- stats::predict(
    fit,
    newdata = prediction_data,
    type = "lpmatrix"
  )
  beta <- stats::coef(fit)
  covariance <- stats::vcov(fit)
  eta <- drop(X %*% beta)
  p <- stats::plogis(eta)
  z_value <- stats::qnorm(0.975)

  split_rows <- split(seq_len(nrow(X)), prediction_data$grid_id)

  curve <- purrr::map_dfr(
    names(split_rows),
    function(grid_i) {
      rows_i <- split_rows[[grid_i]]
      X_i <- X[rows_i, , drop = FALSE]
      p_i <- p[rows_i]
      w_i <- prediction_data$weight[rows_i]
      w_i <- w_i / sum(w_i)

      estimate_i <- sum(w_i * p_i)
      gradient_i <- colSums(
        X_i * matrix(
          w_i * p_i * (1 - p_i),
          nrow = length(rows_i),
          ncol = ncol(X_i)
        )
      )
      variance_i <- drop(
        t(gradient_i) %*% covariance %*% gradient_i
      )
      se_i <- sqrt(max(0, variance_i))

      tibble::tibble(
        grid_id = as.integer(grid_i),
        driver_level = driver_levels[as.integer(grid_i)],
        probability = estimate_i,
        standard_error = se_i,
        lower = pmax(0, estimate_i - z_value * se_i),
        upper = pmin(1, estimate_i + z_value * se_i)
      )
    }
  ) %>%
    dplyr::mutate(
      target_cluster = target_cluster,
      predictor = predictor,
      driver_level = factor(driver_level, levels = driver_levels),
      .before = 1
    )

  fit_summary <- summary(fit)

  diagnostics <- tibble::tibble(
    target_cluster = target_cluster,
    predictor = predictor,
    model_type = "discrete adjusted binomial model",
    n = nrow(model_data),
    converged = isTRUE(fit$converged),
    deviance_explained = unname(fit_summary$dev.expl),
    AIC = stats::AIC(fit),
    smooth_p_value = NA_real_,
    note = "Site-solute-adjusted marginal probabilities by peak-count category."
  )

  list(
    fit = fit,
    curve = curve,
    diagnostics = diagnostics
  )
}

# 3. BUILD THE COMMON GEOMETRY-RESOLVED RESPONSE POPULATION

# Authoritative event-level hydrological covariates are taken directly from the
# current event register. This protects Section 3.3 from stale/incomplete EVS2
# objects and guarantees that antecedent dry period and initial discharge exist.
ir33_event_covariates <- event_metrics %>%
  dplyr::transmute(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    antecedent_dry_period_event = suppressWarnings(as.numeric(tDry)),
    initial_discharge_event = suppressWarnings(as.numeric(qStart))
  ) %>%
  dplyr::distinct(site, ID, .keep_all = TRUE)

ir33_data <- EVS2 %>%
  dplyr::mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    solute = toupper(trimws(as.character(solute))),
    response_flag = ir33_as_true(response),
    HI_use = suppressWarnings(as.numeric(HI_use)),
    loop_area = suppressWarnings(as.numeric(loop_area)),
    FI_peak = suppressWarnings(as.numeric(FI_peak)),
    loop_type = as.character(loop_type)
  ) %>%
  dplyr::filter(
    site %in% IR33_SITES,
    solute %in% IR33_SOLUTES,
    response_flag,
    is.finite(HI_use),
    is.finite(loop_area),
    loop_area >= 0,
    is.finite(FI_peak),
    !is.na(loop_type),
    nzchar(loop_type)
  ) %>%
  dplyr::distinct(site, ID, solute, .keep_all = TRUE) %>%
  dplyr::left_join(ir33_event_covariates, by = c("site", "ID"))

if (nrow(ir33_data) < 100L) {
  stop(
    "Fewer than 100 common geometry-resolved combinations were available. ",
    "Check EVS2 and the response/geometry fields before clustering.",
    call. = FALSE
  )
}

# Harmonize compact environmental predictor names.
ir33_alias_map <- list(
  event_rainfall = c("P", "pTotal", "Depth_mm", "Pcum_event"),
  rainfall_duration = c("Ts", "pDur", "Duration_h", "Tevent_h"),
  maximum_rainfall_intensity = c("Imax", "pMax", "Imax_event"),
  mean_rainfall_intensity = c("Imean", "pInt", "Imean_event", "Pmean"),
  antecedent_dry_period = c("tDry", "t_Dry", "DryPeriod_h"),
  initial_discharge = c("Q0", "qStart", "Initial_Q"),
  pre_event_concentration = c("C0", "Baseline_C", "C_baseline")
)

for (target_name in names(ir33_alias_map)) {
  ir33_data <- ir33_add_alias(
    ir33_data,
    target = target_name,
    candidates = ir33_alias_map[[target_name]]
  )
  ir33_data[[target_name]] <- suppressWarnings(as.numeric(ir33_data[[target_name]]))
}

# The event register is authoritative for these two event-level variables.
# Coalesce it over any alias inherited from EVS2 so Figure 7a and Figure S5
# cannot silently lose antecedent dry period because of a stale join upstream.
ir33_data <- ir33_data %>%
  dplyr::mutate(
    antecedent_dry_period = dplyr::coalesce(
      antecedent_dry_period_event,
      antecedent_dry_period
    ),
    initial_discharge = dplyr::coalesce(
      initial_discharge_event,
      initial_discharge
    )
  ) %>%
  dplyr::select(
    -dplyr::any_of(c(
      "antecedent_dry_period_event",
      "initial_discharge_event"
    ))
  )

# Fail early with a useful message instead of generating an empty C1 panel.
if (sum(is.finite(ir33_data$antecedent_dry_period)) < IR33_GAM_MIN_N) {
  stop(
    "Antecedent dry period is unavailable for enough Section 3.3 records (finite n = ",
    sum(is.finite(ir33_data$antecedent_dry_period)),
    "). Check tDry in eTable/eTable2 before fitting Figure 7a.",
    call. = FALSE
  )
}

# 4. QUANTIFY RAINFALL-PULSE AND DISCHARGE-PEAK COMPLEXITY

ir33_event_register <- eTable %>%
  dplyr::mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    tStart = if (inherits(tStart, "POSIXct")) {
      tStart
    } else {
      .parse_dt(tStart, tz = TZ_USE)
    },
    tEnd = if (inherits(tEnd, "POSIXct")) {
      tEnd
    } else {
      .parse_dt(tEnd, tz = TZ_USE)
    }
  ) %>%
  dplyr::filter(
    site %in% IR33_SITES,
    !is.na(ID),
    !is.na(tStart),
    !is.na(tEnd),
    tEnd >= tStart
  ) %>%
  dplyr::distinct(site, ID, .keep_all = TRUE)

ir33_event_keys <- ir33_data %>%
  dplyr::distinct(site, ID) %>%
  dplyr::left_join(ir33_event_register, by = c("site", "ID"))

ir33_complexity_rows <- vector("list", nrow(ir33_event_keys))

for (i in seq_len(nrow(ir33_event_keys))) {
  event_i <- ir33_event_keys[i, , drop = FALSE]
  site_i <- event_i$site
  q_col_i <- detect_q_col(names(df), site_i)
  p_col_i <- detect_prec_col(names(df), site_i)

  if (
    is.na(q_col_i) || is.na(p_col_i) ||
    !(q_col_i %in% names(df)) || !(p_col_i %in% names(df)) ||
    is.na(event_i$tStart) || is.na(event_i$tEnd)
  ) {
    ir33_complexity_rows[[i]] <- tibble::tibble(
      site = site_i,
      ID = event_i$ID,
      rainfall_pulse_count = NA_integer_,
      discharge_peak_count = NA_integer_,
      discharge_peak_separation_h = NA_real_,
      discharge_peak_prominence_max = NA_real_
    )
    next
  }

  event_series_i <- df %>%
    dplyr::filter(date >= event_i$tStart, date <= event_i$tEnd) %>%
    dplyr::transmute(
      date = date,
      precipitation = to_num(.data[[p_col_i]]),
      discharge = to_num(.data[[q_col_i]])
    )

  timestep_minutes_i <- if (nrow(event_series_i) >= 2L) {
    as.numeric(
      stats::median(diff(event_series_i$date), na.rm = TRUE),
      units = "mins"
    )
  } else {
    10
  }
  if (!is.finite(timestep_minutes_i) || timestep_minutes_i <= 0) {
    timestep_minutes_i <- 10
  }

  rain_min_dry_hours_i <- unname(IR33_RAIN_MIN_DRY_HOURS[site_i])
  if (!is.finite(rain_min_dry_hours_i)) {
    stop(
      "No rainfall-pulse dry-gap setting was found for site: ",
      site_i,
      call. = FALSE
    )
  }

  rain_min_dry_steps_i <- max(
    1L,
    as.integer(round(rain_min_dry_hours_i * 60 / timestep_minutes_i))
  )

  q_metrics_i <- ir33_discharge_peak_metrics(
    event_series_i$discharge,
    timestep_minutes = timestep_minutes_i
  )

  ir33_complexity_rows[[i]] <- tibble::tibble(
    site = site_i,
    ID = event_i$ID,
    rainfall_pulse_count = ir33_count_rain_pulses(
      event_series_i$precipitation,
      min_dry_steps = rain_min_dry_steps_i
    ),
    discharge_peak_count = q_metrics_i$discharge_peak_count,
    discharge_peak_separation_h = q_metrics_i$discharge_peak_separation_h,
    discharge_peak_prominence_max = q_metrics_i$discharge_peak_prominence_max
  )
}

ir33_event_complexity <- dplyr::bind_rows(ir33_complexity_rows) %>%
  dplyr::mutate(
    multiple_rainfall_pulses = rainfall_pulse_count >= 2L,
    multiple_discharge_peaks = discharge_peak_count >= 2L,
    compound_hydrograph = multiple_rainfall_pulses | multiple_discharge_peaks
  )

ir33_data <- ir33_data %>%
  dplyr::left_join(ir33_event_complexity, by = c("site", "ID"))

# 5. MULTIVARIATE RESPONSE-PATTERN CLUSTERING

# Corrected Vaughan FI is signed and bounded within [-1, 1]. No signed-log
# transformation is applied. Consistent with the manuscript preprocessing,
# each response dimension is Winsorized at the 1st/99th percentiles and then
# robustly standardized using the median and MAD.
ir33_data <- ir33_data %>%
  dplyr::mutate(
    HI_cluster_input = ir33_robust_z(ir33_winsorize(HI_use)),
    loop_area_cluster_input = ir33_robust_z(ir33_winsorize(loop_area)),
    FI_peak_cluster_input = ir33_robust_z(ir33_winsorize(FI_peak))
  )

ir33_cluster_matrix <- ir33_data %>%
  dplyr::select(
    HI_cluster_input,
    loop_area_cluster_input,
    FI_peak_cluster_input
  ) %>%
  as.matrix()

if (any(!is.finite(ir33_cluster_matrix))) {
  stop(
    "The clustering matrix contains non-finite values after preprocessing.",
    call. = FALSE
  )
}

ir33_distance <- stats::dist(ir33_cluster_matrix, method = "euclidean")
ir33_k_diagnostics <- list()
ir33_pam_fits <- list()

for (k_i in IR33_K_CANDIDATES) {
  if (k_i >= nrow(ir33_cluster_matrix)) next

  set.seed(IR33_SEED + k_i)
  fit_i <- cluster::pam(
    ir33_cluster_matrix,
    k = k_i,
    metric = "euclidean",
    stand = FALSE
  )

  silhouette_i <- cluster::silhouette(fit_i$clustering, ir33_distance)
  cluster_sizes_i <- table(fit_i$clustering)
  minimum_required_i <- max(
    IR33_MIN_CLUSTER_N,
    ceiling(IR33_MIN_CLUSTER_FRACTION * nrow(ir33_cluster_matrix))
  )

  ir33_k_diagnostics[[as.character(k_i)]] <- tibble::tibble(
    k = k_i,
    average_silhouette = mean(silhouette_i[, "sil_width"], na.rm = TRUE),
    minimum_cluster_n = min(cluster_sizes_i),
    maximum_cluster_n = max(cluster_sizes_i),
    minimum_size_requirement = minimum_required_i,
    size_rule_passed = min(cluster_sizes_i) >= minimum_required_i
  )
  ir33_pam_fits[[as.character(k_i)]] <- fit_i
}

ir33_k_table <- dplyr::bind_rows(ir33_k_diagnostics)

valid_k <- ir33_k_table %>%
  dplyr::filter(size_rule_passed, is.finite(average_silhouette))

if (nrow(valid_k) == 0L) {
  warning(
    "No candidate k met the minimum cluster-size rule. Selecting the highest ",
    "silhouette solution and flagging the result for cautious interpretation."
  )
  valid_k <- ir33_k_table %>%
    dplyr::filter(is.finite(average_silhouette))
}

IR33_SELECTED_K <- valid_k %>%
  dplyr::arrange(dplyr::desc(average_silhouette), k) %>%
  dplyr::slice(1L) %>%
  dplyr::pull(k)

# The corrected 2015-2020 manuscript analysis selects k = 3. Fail rather than
# silently rendering a manuscript layout that no longer matches the analysis.
if (!identical(as.integer(IR33_SELECTED_K), 3L)) {
  stop(
    "Corrected PAM selection returned k = ", IR33_SELECTED_K,
    "; the manuscript reproduction expects k = 3. Review the analytical change ",
    "before generating manuscript figures/tables.",
    call. = FALSE
  )
}

ir33_selected_fit <- ir33_pam_fits[[as.character(IR33_SELECTED_K)]]
ir33_data$Cluster_number <- as.integer(ir33_selected_fit$clustering)

ir33_cluster_stability <- ir33_bootstrap_jaccard(
  x = ir33_cluster_matrix,
  original_cluster = ir33_data$Cluster_number,
  k = IR33_SELECTED_K
)

ir33_selected_silhouette <- ir33_k_table %>%
  dplyr::filter(k == IR33_SELECTED_K) %>%
  dplyr::pull(average_silhouette)

ir33_minimum_stability <- min(
  ir33_cluster_stability$mean_bootstrap_jaccard,
  na.rm = TRUE
)

IR33_DISCRETE_ARCHETYPES_SUPPORTED <- is.finite(ir33_selected_silhouette) &&
  ir33_selected_silhouette >= 0.25 &&
  is.finite(ir33_minimum_stability) &&
  ir33_minimum_stability >= 0.60

# AUTHORITATIVE RESPONSE-GROUP COLOURS
# Applied consistently to Main Figure 7 and Supplementary Figures S3-S5.
# Ocean & Steel palette (journal-safe, high readability).
IR33_CLUSTER_PALETTE <- c(
  C1 = "#1A365D",  # Deep Navy Blue
  C2 = "#718096",  # Cool Slate Gray
  C3 = "#63B3ED",  # Bright Sky Blue
  C4 = "#805AD5",  # fallback if corrected FI selects k > 3
  C5 = "#38A169",
  C6 = "#DD6B20"
)

IR33_CLUSTER_PALETTE_ACTIVE <- IR33_CLUSTER_PALETTE[
  intersect(
    names(IR33_CLUSTER_PALETTE),
    paste0("C", seq_len(IR33_SELECTED_K))
  )
]

# 5.1 PAM medoids and clustering diagnostics

ir33_medoid_indices <- as.integer(ir33_selected_fit$id.med)

ir33_medoid_records <- ir33_data[
  ir33_medoid_indices,
  ,
  drop = FALSE
] %>%
  dplyr::mutate(
    Medoid_for_cluster = seq_along(ir33_medoid_indices),
    .before = 1
  ) %>%
  dplyr::select(
    Medoid_for_cluster,
    Cluster_number,
    site,
    ID,
    solute,
    HI_use,
    loop_area,
    FI_peak,
    loop_type,
    dplyr::everything()
  )

ir33_selected_silhouette_object <- cluster::silhouette(
  ir33_selected_fit$clustering,
  ir33_distance
)

ir33_selected_silhouette_table <- tibble::as_tibble(
  as.data.frame(ir33_selected_silhouette_object),
  rownames = "row_index"
) %>%
  dplyr::transmute(
    row_index = as.integer(row_index),
    Cluster_number = as.integer(cluster),
    Neighbor_cluster = as.integer(neighbor),
    silhouette_width = sil_width
  )

diagnostic_palette <- IR33_CLUSTER_PALETTE_ACTIVE

panel_diag_k <- ggplot2::ggplot(
  ir33_k_table,
  ggplot2::aes(
    x = k,
    y = average_silhouette
  )
) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 2.6) +
  ggplot2::geom_point(
    data = ir33_k_table %>%
      dplyr::filter(k == IR33_SELECTED_K),
    size = 4,
    shape = 21,
    fill = "white",
    stroke = 1
  ) +
  ggplot2::scale_x_continuous(
    breaks = IR33_K_CANDIDATES
  ) +
  ggplot2::labs(
    title = "a) Candidate cluster solutions",
    x = "Number of clusters (k)",
    y = "Average silhouette width"
  ) +
  ggplot2::theme_bw(base_size = 10) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold")
  )

panel_diag_silhouette <- ir33_selected_silhouette_table %>%
  dplyr::mutate(
    Cluster_short = factor(
      paste0("C", Cluster_number),
      levels = paste0("C", seq_len(IR33_SELECTED_K))
    )
  ) %>%
  ggplot2::ggplot(
    ggplot2::aes(
      x = Cluster_short,
      y = silhouette_width,
      fill = Cluster_short
    )
  ) +
  ggplot2::geom_hline(
    yintercept = 0,
    linetype = 2,
    colour = "grey45"
  ) +
  # Whiskers intentionally span the observed minimum and maximum for each C1-C3 group.
  # stat_boxplot() draws explicit horizontal whisker caps; coef = Inf makes
  # the whiskers reach the group minima/maxima rather than the default 1.5 x IQR.
  ggplot2::stat_boxplot(
    geom = "errorbar",
    coef = Inf,
    width = 0.34,
    linewidth = 0.55
  ) +
  ggplot2::geom_boxplot(
    width = 0.62,
    coef = Inf,
    outlier.shape = NA,
    linewidth = 0.55
  ) +
  ggplot2::scale_fill_manual(
    values = diagnostic_palette,
    guide = "none"
  ) +
  ggplot2::labs(
    title = "b) Selected-solution silhouette widths",
    x = "Response group",
    y = "Silhouette width"
  ) +
  ggplot2::theme_bw(base_size = 10) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold")
  )

panel_diag_jaccard <- ir33_cluster_stability %>%
  dplyr::mutate(
    Cluster_short = factor(
      paste0("C", Cluster),
      levels = paste0("C", seq_len(IR33_SELECTED_K))
    )
  ) %>%
  ggplot2::ggplot(
    ggplot2::aes(
      x = Cluster_short,
      y = mean_bootstrap_jaccard,
      fill = Cluster_short
    )
  ) +
  ggplot2::geom_hline(
    yintercept = 0.60,
    linetype = 2,
    colour = "grey45"
  ) +
  ggplot2::geom_col(width = 0.62) +
  ggplot2::geom_text(
    ggplot2::aes(
      label = sprintf("%.3f", mean_bootstrap_jaccard)
    ),
    vjust = -0.35,
    size = 3.2
  ) +
  ggplot2::scale_fill_manual(
    values = diagnostic_palette,
    guide = "none"
  ) +
  ggplot2::scale_y_continuous(
    limits = c(0, 1.05),
    expand = ggplot2::expansion(mult = c(0, 0.02))
  ) +
  ggplot2::labs(
    title = "c) Bootstrap-Jaccard stability",
    x = "Response group",
    y = "Mean Jaccard similarity"
  ) +
  ggplot2::theme_bw(base_size = 10) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold")
  )

ir33_cluster_diagnostic_figure <-
  (panel_diag_k |
     panel_diag_silhouette |
     panel_diag_jaccard) +
  patchwork::plot_annotation(
    title = "PAM response-group selection and stability diagnostics",
    subtitle = paste0(
      "Selected k = ",
      IR33_SELECTED_K,
      "; average silhouette = ",
      sprintf("%.3f", ir33_selected_silhouette)
    ),
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(
        face = "bold",
        hjust = 0.5,
        size = 13
      ),
      plot.subtitle = ggplot2::element_text(
        hjust = 0.5,
        size = 9
      )
    )
  )

# 6. ASSIGN DESCRIPTIVE RESPONSE-GROUP LABELS

loop_tertiles <- stats::quantile(
  ir33_data$loop_area,
  probs = c(1 / 3, 2 / 3),
  na.rm = TRUE,
  names = FALSE
)

IR33_DASH <- intToUtf8(0x2013L)

ir33_cluster_profiles <- ir33_data %>%
  dplyr::group_by(Cluster_number) %>%
  dplyr::summarise(
    n = dplyr::n(),
    HI_median = stats::median(HI_use, na.rm = TRUE),
    HI_mean = mean(HI_use, na.rm = TRUE),
    loop_area_median = stats::median(loop_area, na.rm = TRUE),
    loop_area_mean = mean(loop_area, na.rm = TRUE),
    FI_peak_median = stats::median(FI_peak, na.rm = TRUE),
    FI_peak_mean = mean(FI_peak, na.rm = TRUE),
    HI_standardized_mean = mean(HI_cluster_input, na.rm = TRUE),
    loop_area_standardized_mean = mean(loop_area_cluster_input, na.rm = TRUE),
    FI_peak_standardized_mean = mean(FI_peak_cluster_input, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    # Use observational limb-dominance language rather than assuming a source
    # delivery mechanism from HI sign alone.
    timing_label = dplyr::case_when(
      HI_median > 0.05 ~ "rising-limb dominant",
      HI_median < -0.05 ~ "falling-limb dominant",
      TRUE ~ "balanced-limb"
    ),
    complexity_label = dplyr::case_when(
      loop_area_median <= loop_tertiles[1] ~ "low-separation",
      loop_area_median <= loop_tertiles[2] ~ "moderate-separation",
      TRUE ~ "high-separation"
    ),
    flushing_label = dplyr::case_when(
      FI_peak_median > 0.15 ~ "positive-FI flushing",
      FI_peak_median < -0.15 ~ "negative-FI dilution",
      TRUE ~ "weak-net-FI"
    ),
    Cluster_label = paste0(
      "C", Cluster_number, ": ",
      timing_label, IR33_DASH,
      complexity_label, IR33_DASH,
      flushing_label
    )
  )

# Encoding-safe en dash
EN_DASH <- intToUtf8(0x2013L)

# Remove any old/duplicated labels before joining the authoritative labels
ir33_data <- ir33_data %>%
  dplyr::select(
    -dplyr::any_of(c(
      "Cluster_label",
      "Cluster_label.x",
      "Cluster_label.y",
      "site_solute"
    ))
  ) %>%
  dplyr::left_join(
    ir33_cluster_profiles %>%
      dplyr::select(
        Cluster_number,
        Cluster_label
      ),
    by = "Cluster_number"
  ) %>%
  dplyr::mutate(

    Cluster_label = factor(
      as.character(Cluster_label),
      levels = as.character(
        ir33_cluster_profiles$Cluster_label[
          order(ir33_cluster_profiles$Cluster_number)
        ]
      )
    ),

    site_solute = paste(
      site,
      solute,
      sep = EN_DASH
    )
  )


#-------------------------------------------------------
################################################################################
# EXPORT COMPLETE EVENT-CONSTITUENT CLUSTER MATRIX
# One row = one event × constituent combination used in PAM clustering
################################################################################

Event_Constituent_Cluster_Matrix <- ir33_data %>%
  
  # Add a simple cluster identifier for easy reading
  dplyr::mutate(
    Cluster = paste0("C", Cluster_number)
  ) %>%
  
  # Put the most important reviewer-facing variables first.
  # All remaining variables in ir33_data are retained afterwards.
  dplyr::relocate(
    dplyr::any_of(c(
      "site",
      "ID",
      "solute",
      "site_solute",
      "Cluster",
      "Cluster_number",
      "Cluster_label",
      
      # Raw clustering metrics
      "HI_use",
      "loop_area",
      "FI_peak",
      
      # Standardized values actually used by PAM
      "HI_cluster_input",
      "loop_area_cluster_input",
      "FI_peak_cluster_input",
      
      # Additional response descriptors
      "loop_type",
      "chem_status"
    ))
  )

# Export as an Excel-friendly CSV
if (requireNamespace("readr", quietly = TRUE)) {
  
  readr::write_excel_csv(
    Event_Constituent_Cluster_Matrix,
    file.path(
      DIR_MAIN_TAB,
      "Event_Constituent_Cluster_Matrix.csv"
    ),
    na = ""
  )
  
} else {
  
  utils::write.csv(
    Event_Constituent_Cluster_Matrix,
    file.path(
      DIR_MAIN_TAB,
      "Event_Constituent_Cluster_Matrix.csv"
    ),
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
}

message(
  "Exported complete event-constituent cluster matrix: ",
  file.path(
    DIR_MAIN_TAB,
    "Event_Constituent_Cluster_Matrix.csv"
  )
)


# 7. CLUSTER COMPOSITION, ENRICHMENT, AND COMPOUND-HYDROGRAPH TESTS

ir33_cluster_composition_site_solute <- ir33_data %>%
  dplyr::count(Cluster_label, site, solute, name = "n") %>%
  dplyr::group_by(Cluster_label) %>%
  dplyr::mutate(percent_within_cluster = 100 * n / sum(n)) %>%
  dplyr::ungroup()

ir33_cluster_composition_loop <- ir33_data %>%
  dplyr::count(Cluster_label, loop_type, name = "n") %>%
  dplyr::group_by(Cluster_label) %>%
  dplyr::mutate(percent_within_cluster = 100 * n / sum(n)) %>%
  dplyr::ungroup()

ir33_compound_summary <- ir33_data %>%
  dplyr::group_by(Cluster_label) %>%
  dplyr::summarise(
    n = dplyr::n(),
    multiple_rainfall_pulses_n = sum(multiple_rainfall_pulses %in% TRUE, na.rm = TRUE),
    multiple_rainfall_pulses_pct = 100 * mean(multiple_rainfall_pulses %in% TRUE, na.rm = TRUE),
    multiple_discharge_peaks_n = sum(multiple_discharge_peaks %in% TRUE, na.rm = TRUE),
    multiple_discharge_peaks_pct = 100 * mean(multiple_discharge_peaks %in% TRUE, na.rm = TRUE),
    compound_hydrograph_n = sum(compound_hydrograph %in% TRUE, na.rm = TRUE),
    compound_hydrograph_pct = 100 * mean(compound_hydrograph %in% TRUE, na.rm = TRUE),
    .groups = "drop"
  )

cluster_site_solute_table <- table(
  ir33_data$Cluster_label,
  ir33_data$site_solute
)
cluster_site_solute_test <- ir33_safe_chisq(
  ir33_data$Cluster_label,
  ir33_data$site_solute,
  seed = IR33_SEED + 1L
)

cluster_site_solute_expected <- cluster_site_solute_test$expected
cluster_site_solute_stdres <- cluster_site_solute_test$stdres

ir33_site_solute_enrichment <- as.data.frame(cluster_site_solute_table) %>%
  dplyr::rename(
    Cluster_label = Var1,
    site_solute = Var2,
    observed_n = Freq
  ) %>%
  dplyr::mutate(
    expected_n = as.vector(cluster_site_solute_expected),
    observed_expected_ratio = dplyr::if_else(
      expected_n > 0,
      observed_n / expected_n,
      NA_real_
    ),
    standardized_residual = as.vector(cluster_site_solute_stdres)
  )

ir33_categorical_tests <- purrr::map_dfr(
  c("site", "solute", "site_solute", "loop_type", "compound_hydrograph",
    "multiple_rainfall_pulses", "multiple_discharge_peaks"),
  function(variable_i) {
    result_i <- ir33_safe_chisq(
      ir33_data$Cluster_label,
      ir33_data[[variable_i]],
      seed = IR33_SEED + match(variable_i, c(
        "site", "solute", "site_solute", "loop_type", "compound_hydrograph",
        "multiple_rainfall_pulses", "multiple_discharge_peaks"
      ))
    )
    tibble::tibble(
      Variable = variable_i,
      Statistic = result_i$statistic,
      p_value = result_i$p,
      Method = result_i$method
    )
  }
) %>%
  dplyr::mutate(
    q_value_BH = stats::p.adjust(p_value, method = "BH"),
    significant_q05 = is.finite(q_value_BH) & q_value_BH < 0.05
  )

# 8. CHARACTERIZE ENVIRONMENTAL CONDITIONS BY RESPONSE GROUP

# Pre-event concentration is summarized as antecedent chemical state.
# Corrected Vaughan FI does not contain the pre-event C0 algebraically; C0 is
# retained because it remains central to responsiveness and chemical-status
# classification and is useful as an antecedent chemical-state descriptor.
ir33_primary_environmental_predictors <- c(
  "event_rainfall",
  "rainfall_duration",
  "maximum_rainfall_intensity",
  "mean_rainfall_intensity",
  "antecedent_dry_period",
  "initial_discharge",
  "rainfall_pulse_count",
  "discharge_peak_count",
  "discharge_peak_separation_h"
)

ir33_available_environmental_predictors <- ir33_primary_environmental_predictors[
  ir33_primary_environmental_predictors %in% names(ir33_data)
]

ir33_environmental_summary <- purrr::map_dfr(
  ir33_available_environmental_predictors,
  function(predictor_i) {
    ir33_data %>%
      dplyr::group_by(Cluster_label) %>%
      dplyr::summarise(
        Predictor = predictor_i,
        n_finite = sum(is.finite(.data[[predictor_i]])),
        median = stats::median(.data[[predictor_i]], na.rm = TRUE),
        Q1 = stats::quantile(.data[[predictor_i]], 0.25, na.rm = TRUE),
        Q3 = stats::quantile(.data[[predictor_i]], 0.75, na.rm = TRUE),
        mean = mean(.data[[predictor_i]], na.rm = TRUE),
        sd = stats::sd(.data[[predictor_i]], na.rm = TRUE),
        .groups = "drop"
      )
  }
)

ir33_environmental_tests <- purrr::map_dfr(
  ir33_available_environmental_predictors,
  function(predictor_i) {
    result_i <- ir33_safe_kruskal(
      values = ir33_data[[predictor_i]],
      groups = ir33_data$Cluster_label
    )
    tibble::tibble(
      Predictor = predictor_i,
      Kruskal_Wallis_statistic = unname(result_i["statistic"]),
      p_value = unname(result_i["p"]),
      n = as.integer(unname(result_i["n"]))
    )
  }
) %>%
  dplyr::mutate(
    q_value_BH = stats::p.adjust(p_value, method = "BH"),
    significant_q05 = is.finite(q_value_BH) & q_value_BH < 0.05
  ) %>%
  dplyr::arrange(q_value_BH, p_value)

ir33_c0_sensitivity_summary <- ir33_data %>%
  dplyr::group_by(Cluster_label, solute) %>%
  dplyr::summarise(
    n_finite_C0 = sum(is.finite(pre_event_concentration)),
    median_C0 = stats::median(pre_event_concentration, na.rm = TRUE),
    Q1_C0 = stats::quantile(pre_event_concentration, 0.25, na.rm = TRUE),
    Q3_C0 = stats::quantile(pre_event_concentration, 0.75, na.rm = TRUE),
    .groups = "drop"
  )

# 9. CLUSTER ENRICHMENT AND HYDROLOGICAL RESPONSE PROFILES

# This section replaces the former multiclass random-forest analysis. It creates
# descriptive graphics directly from (i) positive catchment-constituent
# enrichment and (ii) environmental variables showing BH-adjusted differences
# among response groups. These are association profiles, not predictive or
# causal response functions.

IR33_ENRICHMENT_RESIDUAL_CUTOFF <- 2
IR33_ENRICHMENT_OE_CUTOFF <- 1

# Select all environmental variables with BH-adjusted q < 0.05. The preferred
# order matches the variables emphasized in Table 2, while any additional
# significant variables are retained and ordered by q value.
ir33_profile_priority <- c(
  "event_rainfall",
  "maximum_rainfall_intensity",
  "antecedent_dry_period",
  "discharge_peak_count",
  "rainfall_duration",
  "mean_rainfall_intensity",
  "initial_discharge",
  "rainfall_pulse_count",
  "discharge_peak_separation_h"
)

ir33_profile_predictors <- ir33_environmental_tests %>%
  dplyr::filter(significant_q05) %>%
  dplyr::mutate(
    profile_order = match(Predictor, ir33_profile_priority),
    profile_order = dplyr::if_else(
      is.na(profile_order),
      length(ir33_profile_priority) + dplyr::row_number(),
      profile_order
    )
  ) %>%
  dplyr::arrange(profile_order, q_value_BH, p_value) %>%
  dplyr::pull(Predictor)

if (length(ir33_profile_predictors) == 0L) {
  warning(
    "No environmental variables had BH-adjusted q < 0.05. ",
    "The hydrological response-profile figure will contain a diagnostic note."
  )
}

# 9.1 Pairwise post-hoc comparisons after significant Kruskal-Wallis tests

ir33_environmental_posthoc <- purrr::map_dfr(
  ir33_profile_predictors,
  function(predictor_i) {
    posthoc_data_i <- ir33_data %>%
      dplyr::transmute(
        Cluster_label = droplevels(Cluster_label),
        value = suppressWarnings(as.numeric(.data[[predictor_i]]))
      ) %>%
      dplyr::filter(
        !is.na(Cluster_label),
        is.finite(value)
      )

    if (
      nrow(posthoc_data_i) < 10L ||
      nlevels(posthoc_data_i$Cluster_label) < 2L
    ) {
      return(tibble::tibble())
    }

    test_i <- stats::pairwise.wilcox.test(
      x = posthoc_data_i$value,
      g = posthoc_data_i$Cluster_label,
      p.adjust.method = "BH",
      exact = FALSE
    )

    as.data.frame(
      as.table(test_i$p.value),
      stringsAsFactors = FALSE
    ) %>%
      tibble::as_tibble() %>%
      dplyr::rename(
        Cluster_1 = Var1,
        Cluster_2 = Var2,
        p_adjusted_BH = Freq
      ) %>%
      dplyr::filter(
        !is.na(Cluster_1),
        !is.na(Cluster_2),
        is.finite(p_adjusted_BH)
      ) %>%
      dplyr::mutate(
        Predictor = predictor_i,
        significant_q05 = p_adjusted_BH < 0.05,
        .before = 1
      )
  }
)

# 9.2 Positive catchment-constituent enrichment profiles

# Positive enrichment requires both a residual >= 2 and an observed-to-expected
# ratio > 1. The threshold identifies combinations contributing most strongly
# to the significant cluster-by-catchment-constituent association.
ir33_enrichment_profile_data <- ir33_site_solute_enrichment %>%
  dplyr::filter(
    observed_n > 0,
    is.finite(standardized_residual),
    is.finite(observed_expected_ratio),
    standardized_residual >= IR33_ENRICHMENT_RESIDUAL_CUTOFF,
    observed_expected_ratio > IR33_ENRICHMENT_OE_CUTOFF
  ) %>%
  dplyr::mutate(
    Cluster_short = stringr::str_extract(
      as.character(Cluster_label),
      "^C[0-9]+"
    ),
    Cluster_short = factor(
      Cluster_short,
      levels = paste0("C", seq_len(IR33_SELECTED_K))
    ),
    site_solute = factor(
      site_solute,
      levels = unique(site_solute[order(standardized_residual)])
    )
  )

if (nrow(ir33_enrichment_profile_data) > 0L) {
  panel_enrichment_profile <- ggplot2::ggplot(
    ir33_enrichment_profile_data,
    ggplot2::aes(
      x = observed_expected_ratio,
      y = site_solute
    )
  ) +
    ggplot2::geom_vline(
      xintercept = 1,
      linetype = 2,
      linewidth = 0.4,
      colour = "grey45"
    ) +
    ggplot2::geom_point(
      ggplot2::aes(
        size = observed_n,
        fill = standardized_residual
      ),
      shape = 21,
      colour = "black",
      alpha = 0.85
    ) +
    ggplot2::facet_wrap(
      ~Cluster_short,
      scales = "free_y",
      nrow = 1
    ) +
    ggplot2::scale_size_continuous(
      range = c(3, 9),
      name = "Observed n"
    ) +
    ggplot2::labs(
      title = "a) Enriched catchment-constituent combinations",
      x = "Observed-to-expected ratio",
      y = "Catchment-constituent combination",
      fill = "Standardized\nresidual"
    ) +
    ggplot2::theme_bw(base_size = 10) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      legend.position = "bottom",
      strip.text = ggplot2::element_text(face = "bold")
    )
} else {
  panel_enrichment_profile <- ggplot2::ggplot() +
    ggplot2::annotate(
      "text",
      x = 0,
      y = 0,
      label = paste0(
        "No combinations met residual >= ",
        IR33_ENRICHMENT_RESIDUAL_CUTOFF,
        " and observed-to-expected ratio > ",
        IR33_ENRICHMENT_OE_CUTOFF
      )
    ) +
    ggplot2::labs(
      title = "a) Enriched catchment-constituent combinations"
    ) +
    ggplot2::theme_void(base_size = 10) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold")
    )
}

# 9.3 Cluster-specific hydrological response profiles

ir33_predictor_labels <- c(
  event_rainfall = "Event rainfall (mm)",
  rainfall_duration = "Rainfall duration (h)",
  maximum_rainfall_intensity = "Maximum rainfall intensity (mm h^-1)",
  mean_rainfall_intensity = "Mean rainfall intensity (mm h^-1)",
  antecedent_dry_period = "Antecedent dry period (h)",
  initial_discharge = "Initial discharge",
  rainfall_pulse_count = "Rainfall-pulse count",
  discharge_peak_count = "Discharge-peak count",
  discharge_peak_separation_h = "Discharge-peak separation (h)"
)

ir33_hydrological_profile_data <- ir33_environmental_summary %>%
  dplyr::filter(Predictor %in% ir33_profile_predictors) %>%
  dplyr::left_join(
    ir33_environmental_tests %>%
      dplyr::select(
        Predictor,
        Kruskal_Wallis_statistic,
        p_value,
        q_value_BH
      ),
    by = "Predictor"
  ) %>%
  dplyr::mutate(
    Cluster_short = stringr::str_extract(
      as.character(Cluster_label),
      "^C[0-9]+"
    ),
    Cluster_short = factor(
      Cluster_short,
      levels = paste0("C", seq_len(IR33_SELECTED_K))
    ),
    Predictor_label = unname(ir33_predictor_labels[Predictor]),
    Predictor_label = dplyr::if_else(
      is.na(Predictor_label),
      Predictor,
      Predictor_label
    ),
    facet_label = paste0(
      Predictor_label,
      "\nBH q = ",
      format.pval(q_value_BH, digits = 2, eps = 0.001)
    )
  )

if (nrow(ir33_hydrological_profile_data) > 0L) {
  panel_hydrological_profile <- ggplot2::ggplot(
    ir33_hydrological_profile_data,
    ggplot2::aes(
      x = Cluster_short,
      y = median,
      group = 1
    )
  ) +
    ggplot2::geom_line(
      linewidth = 0.55,
      colour = "grey45"
    ) +
    ggplot2::geom_linerange(
      ggplot2::aes(
        ymin = Q1,
        ymax = Q3
      ),
      linewidth = 0.9
    ) +
    ggplot2::geom_point(size = 3) +
    ggplot2::facet_wrap(
      ~facet_label,
      scales = "free_y",
      ncol = 2
    ) +
    ggplot2::labs(
      title = "b) Hydrological context of response groups",
      x = "Response group",
      y = "Median and interquartile range"
    ) +
    ggplot2::theme_bw(base_size = 10) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      strip.text = ggplot2::element_text(face = "bold"),
      axis.text.x = ggplot2::element_text(face = "bold"),
      legend.position = "none"
    )
} else {
  panel_hydrological_profile <- ggplot2::ggplot() +
    ggplot2::annotate(
      "text",
      x = 0,
      y = 0,
      label = "No BH-significant environmental variables were available."
    ) +
    ggplot2::labs(
      title = "b) Hydrological context of response groups"
    ) +
    ggplot2::theme_void(base_size = 10) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold")
    )
}

# 9.4 Combined enrichment and hydrological-profile figure

ir33_response_profile_figure <-
  panel_enrichment_profile /
  panel_hydrological_profile +
  patchwork::plot_layout(heights = c(0.9, 1.25)) +
  patchwork::plot_annotation(
    title = "Response-group enrichment and hydrological profiles",
    subtitle = paste0(
      "Positive enrichment: standardized residual >= ",
      IR33_ENRICHMENT_RESIDUAL_CUTOFF,
      " and observed-to-expected ratio > ",
      IR33_ENRICHMENT_OE_CUTOFF,
      "; hydrological profiles show medians and interquartile ranges"
    ),
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(
        face = "bold",
        hjust = 0.5,
        size = 13
      ),
      plot.subtitle = ggplot2::element_text(
        hjust = 0.5,
        size = 9
      )
    )
  )

# 10. HYDROLOGICAL DISTRIBUTIONS AND ADJUSTED CLUSTER-PROBABILITY CURVES

# 10.1 Distribution plots for the four hydrological variables used in Main Figure 7

ir33_distribution_palette <- IR33_CLUSTER_PALETTE_ACTIVE

# Figure S5 must contain exactly the four hydrological contexts used in Main Figure 7,
# irrespective of whether every global Kruskal-Wallis BH q-value is < 0.05.
ir33_distribution_predictors <- c(
  "antecedent_dry_period",
  "discharge_peak_count",
  "event_rainfall",
  "maximum_rainfall_intensity"
)

missing_distribution_predictors <- setdiff(
  ir33_distribution_predictors,
  names(ir33_data)
)
if (length(missing_distribution_predictors) > 0L) {
  stop(
    "Figure S5 cannot be built because predictor(s) are missing: ",
    paste(missing_distribution_predictors, collapse = ", "),
    call. = FALSE
  )
}

if (length(ir33_distribution_predictors) > 0L) {
  ir33_hydrological_distribution_data <- ir33_data %>%
    dplyr::mutate(
      Cluster_short = stringr::str_extract(
        as.character(Cluster_label),
        "^C[0-9]+"
      ),
      Cluster_short = factor(
        Cluster_short,
        levels = paste0("C", seq_len(IR33_SELECTED_K))
      )
    ) %>%
    dplyr::select(
      Cluster_short,
      dplyr::all_of(ir33_distribution_predictors)
    ) %>%
    tidyr::pivot_longer(
      cols = -Cluster_short,
      names_to = "Predictor",
      values_to = "Value"
    ) %>%
    dplyr::filter(is.finite(Value)) %>%
    dplyr::left_join(
      ir33_environmental_tests %>%
        dplyr::select(Predictor, q_value_BH),
      by = "Predictor"
    ) %>%
    dplyr::mutate(
      Predictor_label = unname(ir33_predictor_labels[Predictor]),
      Predictor_label = dplyr::if_else(
        is.na(Predictor_label),
        Predictor,
        Predictor_label
      ),
      facet_label = paste0(
        Predictor_label,
        "\nBH q = ",
        format.pval(q_value_BH, digits = 2, eps = 0.001)
      ),
      Predictor = factor(Predictor, levels = ir33_distribution_predictors),
      facet_label = factor(
        facet_label,
        levels = unique(facet_label[order(Predictor)])
      )
    )

  panel_hydrological_distributions <- ggplot2::ggplot(
    ir33_hydrological_distribution_data,
    ggplot2::aes(
      x = Cluster_short,
      y = Value,
      fill = Cluster_short,
      colour = Cluster_short
    )
  ) +
    ggplot2::geom_violin(
      scale = "width",
      trim = FALSE,
      alpha = 0.20,
      linewidth = 0.45
    ) +
    ggplot2::geom_boxplot(
      width = 0.18,
      outlier.shape = NA,
      alpha = 0.70,
      linewidth = 0.45
    ) +
    ggplot2::geom_jitter(
      width = 0.10,
      height = 0,
      alpha = 0.10,
      size = 0.55,
      show.legend = FALSE
    ) +
    ggplot2::facet_wrap(
      ~facet_label,
      scales = "free_y",
      ncol = 2
    ) +
    ggplot2::scale_fill_manual(
      values = ir33_distribution_palette,
      guide = "none"
    ) +
    ggplot2::scale_colour_manual(
      values = ir33_distribution_palette,
      guide = "none"
    ) +
    ggplot2::labs(
      title = "Hydrological distributions across response groups",
      subtitle = paste0(
        "Violin distributions, median and interquartile range, and ",
        "event-level observations"
      ),
      x = "Response group",
      y = NULL
    ) +
    ggplot2::theme_bw(base_size = 10) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(
        face = "bold",
        hjust = 0.5
      ),
      plot.subtitle = ggplot2::element_text(hjust = 0.5),
      strip.text = ggplot2::element_text(face = "bold"),
      axis.text.x = ggplot2::element_text(face = "bold")
    )

} else {
  ir33_hydrological_distribution_data <- tibble::tibble()
}

# 10.2 Site-solute-adjusted response-group probability curves

# The corrected FI can change cluster membership and even the selected number of
# groups. Therefore the old hard-coded mapping (C1~dry period, C2~Q peaks,
# C3~rainfall/intensity) is not assumed here.
#
# We retain the same four manuscript hydrological signatures, but for each one
# fit a one-versus-rest adjusted model for every selected response group. The
# displayed group is the successfully fitted group with the largest adjusted
# probability range for that predictor. The complete candidate diagnostics and
# the selected group for each panel are retained in memory for Main Figure 7.
#
# Curves are marginal probabilities averaged over the observed
# catchment-constituent distribution. They are descriptive associations, not
# causal effects or deterministic thresholds.

ir33_probability_model_data <- ir33_data %>%
  dplyr::mutate(
    Cluster_short = stringr::str_extract(
      as.character(Cluster_label),
      "^C[0-9]+"
    ),
    Cluster_short = factor(
      Cluster_short,
      levels = paste0("C", seq_len(IR33_SELECTED_K))
    ),
    site_solute = factor(site_solute)
  )

ir33_probability_predictor_labels <- c(
  antecedent_dry_period = "Antecedent dry period (h)",
  discharge_peak_count = "Discharge peak count",
  event_rainfall = "Event rainfall (mm)",
  maximum_rainfall_intensity = "Maximum rainfall intensity (mm h^-1)"
)

ir33_probability_specs <- tibble::tribble(
  ~panel, ~predictor, ~model_kind,
  "a", "antecedent_dry_period",       "continuous",
  "b", "discharge_peak_count",        "discrete",
  "c", "event_rainfall",              "continuous",
  "d", "maximum_rainfall_intensity",  "continuous"
)

ir33_probability_model_results <- list()
ir33_probability_candidate_rows <- list()
ir33_probability_curve_rows <- list()
ir33_probability_transition_rows <- list()
ir33_probability_diag_rows <- list()

cluster_targets <- paste0("C", seq_len(IR33_SELECTED_K))

for (spec_i in seq_len(nrow(ir33_probability_specs))) {
  panel_i <- ir33_probability_specs$panel[spec_i]
  predictor_i <- ir33_probability_specs$predictor[spec_i]
  model_kind_i <- ir33_probability_specs$model_kind[spec_i]

  for (cluster_i in cluster_targets) {
    fit_i <- if (identical(model_kind_i, "continuous")) {
      ir33_fit_adjusted_continuous_gam(
        data = ir33_probability_model_data,
        target_cluster = cluster_i,
        predictor = predictor_i
      )
    } else {
      ir33_fit_adjusted_discrete_gam(
        data = ir33_probability_model_data,
        target_cluster = cluster_i,
        predictor = predictor_i
      )
    }

    model_key_i <- paste(panel_i, cluster_i, predictor_i, sep = "__")
    ir33_probability_model_results[[model_key_i]] <- fit_i

    curve_i <- fit_i$curve
    diag_i <- fit_i$diagnostics

    probability_range_i <- if (
      is.data.frame(curve_i) &&
      nrow(curve_i) >= 2L &&
      any(is.finite(curve_i$probability))
    ) {
      diff(range(curve_i$probability, na.rm = TRUE))
    } else {
      NA_real_
    }

    converged_i <- if (
      is.data.frame(diag_i) &&
      nrow(diag_i) > 0L
    ) {
      isTRUE(diag_i$converged[[1]])
    } else {
      FALSE
    }

    ir33_probability_candidate_rows[[length(ir33_probability_candidate_rows) + 1L]] <-
      tibble::tibble(
        panel = panel_i,
        predictor = predictor_i,
        model_kind = model_kind_i,
        target_cluster = cluster_i,
        converged = converged_i,
        probability_range = probability_range_i
      )

    if (is.data.frame(curve_i) && nrow(curve_i) > 0L) {
      ir33_probability_curve_rows[[length(ir33_probability_curve_rows) + 1L]] <-
        curve_i %>%
        dplyr::mutate(
          panel = panel_i,
          model_kind = model_kind_i,
          .before = 1
        )
    }

    if (
      identical(model_kind_i, "continuous") &&
      is.data.frame(fit_i$transition) &&
      nrow(fit_i$transition) > 0L
    ) {
      ir33_probability_transition_rows[[length(ir33_probability_transition_rows) + 1L]] <-
        fit_i$transition %>%
        dplyr::mutate(panel = panel_i, .before = 1)
    }

    if (is.data.frame(diag_i) && nrow(diag_i) > 0L) {
      ir33_probability_diag_rows[[length(ir33_probability_diag_rows) + 1L]] <-
        diag_i %>%
        dplyr::mutate(
          panel = panel_i,
          model_kind = model_kind_i,
          probability_range = probability_range_i,
          .before = 1
        )
    }
  }
}

ir33_probability_candidates <- dplyr::bind_rows(ir33_probability_candidate_rows)

ir33_probability_panel_selection <- ir33_probability_candidates %>%
  dplyr::group_by(panel, predictor, model_kind) %>%
  dplyr::arrange(
    dplyr::desc(converged),
    dplyr::desc(probability_range),
    target_cluster,
    .by_group = TRUE
  ) %>%
  dplyr::slice(1L) %>%
  dplyr::ungroup() %>%
  dplyr::left_join(
    ir33_environmental_tests %>%
      dplyr::select(Predictor, q_value_BH),
    by = c("predictor" = "Predictor")
  )

ir33_probability_all_curves <- dplyr::bind_rows(ir33_probability_curve_rows)
ir33_probability_all_transitions <- dplyr::bind_rows(ir33_probability_transition_rows)
ir33_probability_model_diagnostics <- dplyr::bind_rows(ir33_probability_diag_rows)

selected_probability_keys <- ir33_probability_panel_selection %>%
  dplyr::select(panel, predictor, target_cluster, model_kind)

ir33_probability_curves_continuous <- ir33_probability_all_curves %>%
  dplyr::filter(model_kind == "continuous") %>%
  dplyr::inner_join(
    selected_probability_keys %>%
      dplyr::filter(model_kind == "continuous"),
    by = c("panel", "predictor", "target_cluster", "model_kind")
  )

ir33_probability_curve_discrete <- ir33_probability_all_curves %>%
  dplyr::filter(model_kind == "discrete") %>%
  dplyr::inner_join(
    selected_probability_keys %>%
      dplyr::filter(model_kind == "discrete"),
    by = c("panel", "predictor", "target_cluster", "model_kind")
  )

ir33_transition_ranges <- ir33_probability_all_transitions %>%
  dplyr::inner_join(
    selected_probability_keys %>%
      dplyr::filter(model_kind == "continuous") %>%
      dplyr::select(panel, predictor, target_cluster),
    by = c("panel", "predictor", "target_cluster")
  )

# 11. INTEGRATED FOUR-PANEL FIGURE

# Short cluster labels used across panels
cluster_short_levels <- paste0("C", seq_len(IR33_SELECTED_K))

# Authoritative response-group palette used in Main Figure 7 and Figures S3-S5.
cluster_palette <- IR33_CLUSTER_PALETTE_ACTIVE[cluster_short_levels]

# Separate palette for panel d to avoid confusion with cluster colours
hydrograph_palette <- c(
  "Either feature" = "#1B9E77",            # teal
  "Multiple discharge peaks" = "#7570B3",  # purple
  "Multiple rainfall pulses" = "#4D4D4D"   # dark grey
)

# Common theme
theme_ir33 <- ggplot2::theme_bw(base_size = 11) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(
      face = "bold",
      size = 15,
      hjust = 0
    ),
    axis.title = ggplot2::element_text(
      size = 13,
      face = "plain"
    ),
    axis.text = ggplot2::element_text(
      size = 11,
      colour = "black"
    ),
    panel.grid.major = ggplot2::element_line(
      colour = "grey88",
      linewidth = 0.35
    ),
    panel.grid.minor = ggplot2::element_blank(),
    panel.border = ggplot2::element_rect(
      colour = "grey40",
      fill = NA,
      linewidth = 0.55
    ),
    legend.title = ggplot2::element_text(
      face = "bold",
      size = 10
    ),
    legend.text = ggplot2::element_text(size = 10),
    plot.margin = ggplot2::margin(4, 4, 4, 4)
  )

ir33_data_plot <- ir33_data %>%
  dplyr::mutate(
    Cluster_short = stringr::str_extract(as.character(Cluster_label), "^C[0-9]+"),
    Cluster_short = factor(Cluster_short, levels = cluster_short_levels)
  )

ir33_medoid_plot <- ir33_medoid_records %>%
  dplyr::mutate(
    Cluster_short = factor(
      paste0("C", Cluster_number),
      levels = cluster_short_levels
    )
  )

# Panel a

panel_a <- ggplot2::ggplot(
  ir33_data_plot,
  ggplot2::aes(
    x = HI_use,
    y = loop_area,
    colour = Cluster_short,
    size = abs(FI_peak)
  )
) +
  ggplot2::geom_point(alpha = 0.42, stroke = 0) +
  ggplot2::geom_point(
    data = ir33_medoid_plot,
    ggplot2::aes(
      x = HI_use,
      y = loop_area
    ),
    inherit.aes = FALSE,
    shape = 23,
    size = 3.3,
    stroke = 0.8,
    fill = "white",
    colour = "black"
  ) +
  ggplot2::geom_text(
    data = ir33_medoid_plot,
    ggplot2::aes(
      x = HI_use,
      y = loop_area,
      label = Cluster_short
    ),
    inherit.aes = FALSE,
    nudge_y = 0.035,
    size = 3.2,
    fontface = "bold"
  ) +
  ggplot2::geom_vline(
    xintercept = 0,
    linetype = 2,
    colour = "grey45",
    linewidth = 0.55
  ) +
  ggplot2::scale_colour_manual(
    values = cluster_palette,
    drop = FALSE,
    guide = "none"
  ) +
  ggplot2::scale_size_continuous(
    range = c(0.9, 4.2),
    guide = "none"
  ) +
  ggplot2::labs(
    title = "a) Joint event-response space",
    x = expression(HI[Lloyd]),
    y = expression(A[loop])
  ) +
  theme_ir33

# Panel b

profile_long <- ir33_cluster_profiles %>%
  dplyr::mutate(
    Cluster_short = paste0("C", Cluster_number),
    Cluster_short = factor(Cluster_short, levels = cluster_short_levels)
  ) %>%
  dplyr::select(
    Cluster_short,
    HI_standardized_mean,
    loop_area_standardized_mean,
    FI_peak_standardized_mean
  ) %>%
  tidyr::pivot_longer(
    cols = c(
      HI_standardized_mean,
      loop_area_standardized_mean,
      FI_peak_standardized_mean
    ),
    names_to = "Response",
    values_to = "Standardized_mean"
  ) %>%
  dplyr::mutate(
    Response = dplyr::recode(
      Response,
      HI_standardized_mean = "HI_Lloyd",
      loop_area_standardized_mean = "A_loop",
      FI_peak_standardized_mean = "FI_Vaughan"
    ),
    Response = factor(Response, levels = c("HI_Lloyd", "A_loop", "FI_Vaughan"))
  )

panel_b <- ggplot2::ggplot(
  profile_long,
  ggplot2::aes(
    x = Response,
    y = Standardized_mean,
    group = Cluster_short,
    colour = Cluster_short
  )
) +
  ggplot2::geom_hline(
    yintercept = 0,
    colour = "grey55",
    linetype = 2,
    linewidth = 0.55
  ) +
  ggplot2::geom_line(linewidth = 1.15) +
  ggplot2::geom_point(size = 3.0) +
  ggplot2::scale_colour_manual(
    values = cluster_palette,
    breaks = cluster_short_levels,
    drop = FALSE,
    name = NULL
  ) +
  ggplot2::scale_x_discrete(
    limits = c("HI_Lloyd", "A_loop", "FI_Vaughan"),
    drop = FALSE,
    expand = ggplot2::expansion(add = 0.35)
  ) +
  # Extra upper expansion leaves clean space for the horizontal C1-C3 legend
  # without reducing the rectangular plotting frame.
  ggplot2::scale_y_continuous(
    expand = ggplot2::expansion(mult = c(0.06, 0.20))
  ) +
  ggplot2::guides(
    colour = ggplot2::guide_legend(
      nrow = 1,
      byrow = TRUE,
      title = NULL,
      override.aes = list(linetype = 0, shape = 16, size = 3.5)
    )
  ) +
  ggplot2::labs(
    title = "b) Standardized multivariate profiles",
    x = NULL,
    y = "Robust standardized mean"
  ) +
  theme_ir33 +
  ggplot2::theme(
    # Unboxed horizontal C1, C2, C3 legend placed at the top of panel b.
    # A numeric position is used for compatibility with older ggplot2 versions.
    legend.position = c(0.50, 0.985),
    legend.justification = c(0.50, 1.00),
    legend.direction = "horizontal",
    legend.title = ggplot2::element_blank(),
    legend.background = ggplot2::element_blank(),
    legend.box.background = ggplot2::element_blank(),
    legend.key = ggplot2::element_blank(),
    legend.margin = ggplot2::margin(0, 0, 0, 0),
    legend.spacing.x = grid::unit(2.0, "mm"),
    legend.key.width = grid::unit(7, "mm"),
    legend.key.height = grid::unit(4, "mm")
  )

# Panel c
# IMPORTANT: site_solute was rebuilt upstream with EN_DASH.  Do not hard-code
# corrupted dash strings here because they do not match the UTF-8
# labels and collapse all heat-map columns to NA.  The labels are reconstructed
# from the site and solute codes so this panel is also robust to a stale object
# created before the encoding correction.

ir33_site_solute_levels <- c(
  paste("NF",  "DOC", sep = EN_DASH),
  paste("NF",  "EC",  sep = EN_DASH),
  paste("NF",  "NO3", sep = EN_DASH),
  paste("NF",  "TSS", sep = EN_DASH),
  paste("SHA", "DOC", sep = EN_DASH),
  paste("SHA", "EC",  sep = EN_DASH),
  paste("SHA", "NO3", sep = EN_DASH),
  paste("SHA", "TSS", sep = EN_DASH),
  paste("TTP", "DOC", sep = EN_DASH),
  paste("TTP", "EC",  sep = EN_DASH),
  paste("TTP", "NO3", sep = EN_DASH),
  paste("TTP", "TSS", sep = EN_DASH)
)

ir33_enrichment_plot <- ir33_site_solute_enrichment %>%
  dplyr::mutate(
    Cluster_short = stringr::str_extract(
      as.character(Cluster_label),
      "^C[0-9]+"
    ),
    Cluster_short = factor(
      Cluster_short,
      levels = rev(cluster_short_levels)
    ),

    # Recover the two components independently.  This works whether the
    # incoming separator is a correct en dash, an ASCII hyphen, or mojibake.
    site_code = stringr::str_extract(
      as.character(site_solute),
      "^(NF|SHA|TTP)"
    ),
    solute_code = stringr::str_extract(
      as.character(site_solute),
      "(DOC|EC|NO3|TSS)$"
    ),
    site_solute_clean = dplyr::if_else(
      !is.na(site_code) & !is.na(solute_code),
      paste(site_code, solute_code, sep = EN_DASH),
      NA_character_
    ),
    site_solute = factor(
      site_solute_clean,
      levels = ir33_site_solute_levels
    )
  ) %>%
  dplyr::select(-site_code, -solute_code, -site_solute_clean)

panel_c_with_legend <- ggplot2::ggplot(
  ir33_enrichment_plot,
  ggplot2::aes(
    x = site_solute,
    y = Cluster_short,
    fill = standardized_residual
  )
) +
  ggplot2::geom_tile(colour = "white", linewidth = 0.45) +
  ggplot2::scale_x_discrete(
    limits = ir33_site_solute_levels,
    drop = FALSE
  ) +
  ggplot2::scale_fill_gradient2(
    low = "#6C63C7",
    mid = "white",
    high = "#C62828",
    midpoint = 0,
    name = "Standardized residual"
  ) +
  ggplot2::labs(
    title = paste0(
      "c) Catchment",
      EN_DASH,
      "constituent enrichment"
    ),
    x = paste0(
      "Catchment",
      EN_DASH,
      "constituent combination"
    ),
    y = NULL
  ) +
  ggplot2::guides(
    fill = ggplot2::guide_colourbar(
      direction = "horizontal",
      title.position = "top",
      title.hjust = 0.5,
      barwidth = grid::unit(58, "mm"),
      barheight = grid::unit(4, "mm")
    )
  ) +
  theme_ir33 +
  ggplot2::theme(
    panel.grid = ggplot2::element_blank(),
    # Reduced constituent/tick-label size as requested.
    axis.text.x = ggplot2::element_text(
      angle = 45,
      hjust = 1,
      vjust = 1,
      size = 8.0
    ),
    axis.title.x = ggplot2::element_text(size = 9.2),
    axis.text.y = ggplot2::element_text(size = 11.0),
    legend.position = "bottom",
    legend.justification = "center",
    legend.background = ggplot2::element_blank(),
    legend.box.background = ggplot2::element_blank(),
    legend.margin = ggplot2::margin(0, 0, 0, 0)
  )

legend_c <- cowplot::get_legend(panel_c_with_legend)
panel_c <- panel_c_with_legend +
  ggplot2::theme(legend.position = "none")

# Panel d

compound_long <- ir33_compound_summary %>%
  dplyr::mutate(
    Cluster_short = stringr::str_extract(as.character(Cluster_label), "^C[0-9]+"),
    Cluster_short = factor(Cluster_short, levels = cluster_short_levels)
  ) %>%
  dplyr::select(
    Cluster_short,
    multiple_rainfall_pulses_pct,
    multiple_discharge_peaks_pct,
    compound_hydrograph_pct
  ) %>%
  tidyr::pivot_longer(
    cols = -Cluster_short,
    names_to = "Hydrograph_feature",
    values_to = "Percent"
  ) %>%
  dplyr::mutate(
    Hydrograph_feature = dplyr::recode(
      Hydrograph_feature,
      compound_hydrograph_pct = "Either feature",
      multiple_discharge_peaks_pct = "Multiple discharge peaks",
      multiple_rainfall_pulses_pct = "Multiple rainfall pulses"
    ),
    Hydrograph_feature = factor(
      Hydrograph_feature,
      levels = c(
        "Either feature",
        "Multiple discharge peaks",
        "Multiple rainfall pulses"
      )
    )
  )

panel_d_with_legend <- ggplot2::ggplot(
  compound_long,
  ggplot2::aes(
    x = Cluster_short,
    y = Percent,
    fill = Hydrograph_feature
  )
) +
  ggplot2::geom_col(
    position = ggplot2::position_dodge(width = 0.78),
    width = 0.68
  ) +
  ggplot2::scale_fill_manual(
    values = hydrograph_palette,
    drop = FALSE,
    name = NULL
  ) +
  ggplot2::scale_x_discrete(
    limits = cluster_short_levels,
    drop = FALSE
  ) +
  ggplot2::scale_y_continuous(
    limits = c(0, 100),
    expand = ggplot2::expansion(mult = c(0, 0.03))
  ) +
  ggplot2::labs(
    title = "d) Compound rainfall-runoff structure",
    x = NULL,
    y = "Event combinations (%)"
  ) +
  ggplot2::guides(
    fill = ggplot2::guide_legend(
      nrow = 1,
      byrow = TRUE,
      title = NULL
    )
  ) +
  theme_ir33 +
  ggplot2::theme(
    legend.position = "bottom",
    legend.justification = "center",
    legend.direction = "horizontal",
    legend.title = ggplot2::element_blank(),
    legend.background = ggplot2::element_blank(),
    legend.box.background = ggplot2::element_blank(),
    legend.key = ggplot2::element_blank(),
    legend.margin = ggplot2::margin(0, 0, 0, 0),
    legend.text = ggplot2::element_text(size = 8.6),
    legend.spacing.x = grid::unit(1.4, "mm"),
    legend.key.width = grid::unit(4.5, "mm"),
    legend.key.height = grid::unit(3.8, "mm")
  )

legend_d <- cowplot::get_legend(panel_d_with_legend)
panel_d <- panel_d_with_legend +
  ggplot2::theme(legend.position = "none")

# Combine panels
# All four plot grobs are aligned together so their true rectangular panel
# frames share the same height. Panel-b's legend is overlaid inside its panel,
# while the panel-c colourbar and panel-d legend are placed together in one
# unboxed bottom row. No global title or subtitle is added.
aligned_s4_panels <- cowplot::align_plots(
  panel_a,
  panel_b,
  panel_c,
  panel_d,
  align = "hv",
  axis = "tblr"
)

ir33_integrated_core <- cowplot::plot_grid(
  aligned_s4_panels[[1]],
  aligned_s4_panels[[2]],
  aligned_s4_panels[[3]],
  aligned_s4_panels[[4]],
  ncol = 2,
  rel_widths = c(1.10, 0.90),
  rel_heights = c(1.00, 1.00)
)

ir33_integrated_bottom_legends <- cowplot::plot_grid(
  legend_c,
  legend_d,
  ncol = 2,
  rel_widths = c(1.10, 0.90),
  align = "h"
)

ir33_integrated_figure <- cowplot::plot_grid(
  ir33_integrated_core,
  ir33_integrated_bottom_legends,
  ncol = 1,
  rel_heights = c(1.00, 0.11)
)

# 12. RUN SUMMARY FOR MANUSCRIPT DECISIONS

ir33_summary_lines <- c(
  paste0("Geometry-resolved combinations used: ", nrow(ir33_data)),
  paste0("Selected PAM cluster number: ", IR33_SELECTED_K),
  paste0("Average silhouette: ", sprintf("%.4f", ir33_selected_silhouette)),
  paste0("Minimum mean bootstrap Jaccard: ", sprintf("%.4f", ir33_minimum_stability)),
  paste0(
    "Discrete response archetypes supported: ",
    ifelse(IR33_DISCRETE_ARCHETYPES_SUPPORTED, "YES", "NO")
  ),
  "Interpretation rule:",
  paste0(
    "  Use 'response archetypes' only when average silhouette >= 0.25 and ",
    "all mean bootstrap Jaccard values >= 0.60. Otherwise use 'response groups' ",
    "or describe a continuous multivariate response structure."
  ),
  paste0(
    "BH-significant variables retained for graphical profiling: ",
    if (length(ir33_profile_predictors) > 0L) {
      paste(ir33_profile_predictors, collapse = ", ")
    } else {
      "none"
    }
  ),
  paste0(
    "Positive enrichment profiles required standardized residual >= ",
    IR33_ENRICHMENT_RESIDUAL_CUTOFF,
    " and observed-to-expected ratio > ",
    IR33_ENRICHMENT_OE_CUTOFF,
    "."
  ),
  paste0(
    "Rainfall-pulse dry gaps used: NF = ",
    IR33_RAIN_MIN_DRY_HOURS["NF"],
    " h; SHA = ",
    IR33_RAIN_MIN_DRY_HOURS["SHA"],
    " h; TTP = ",
    IR33_RAIN_MIN_DRY_HOURS["TTP"],
    " h."
  ),
  paste0(
    "Median-IQR, violin, and enrichment profiles are descriptive cluster ",
    "comparisons and are not causal response functions."
  ),
  paste0(
    "Adjusted cluster-probability models fitted successfully: ",
    sum(ir33_probability_model_diagnostics$converged %in% TRUE),
    " of ",
    nrow(ir33_probability_model_diagnostics),
    "."
  ),
  paste0(
    "Adjusted probability curves account for catchment-constituent setting. ",
    "Their transition bands are sample-dependent ranges around the steepest ",
    "fitted change, not deterministic or causal thresholds."
  ),
  paste0(
    "PAM medoid records were exported as objective representative ",
    "event-constituent combinations for each response group."
  ),
  paste0(
    "C0 remains the pre-event baseline for responsiveness and chemical status; ",
    "corrected Vaughan FI is calculated independently from event-normalized concentrations."
  )
)

writeLines(
  ir33_summary_lines,
  con = file.path(IR33_ROOT, "Section3_3_Analysis_Run_Summary.txt")
)

message("Section 3.3 integrated analysis completed.")
message("Output directory: ", normalizePath(IR33_ROOT, winslash = "/", mustWork = FALSE))
message("Selected k: ", IR33_SELECTED_K)
message("Average silhouette: ", round(ir33_selected_silhouette, 4))
message("Minimum bootstrap Jaccard: ", round(ir33_minimum_stability, 4))
message(
  "BH-significant profile variables: ",
  if (length(ir33_profile_predictors) > 0L) {
    paste(ir33_profile_predictors, collapse = ", ")
  } else {
    "none"
  }
)
message(
  "Adjusted cluster-probability models fitted: ",
  sum(ir33_probability_model_diagnostics$converged %in% TRUE),
  " of ",
  nrow(ir33_probability_model_diagnostics)
)
message(
  "Discrete archetypes supported: ",
  ifelse(IR33_DISCRETE_ARCHETYPES_SUPPORTED, "YES", "NO")
)
message("=== END SECTION 3.3 INTEGRATED RESPONSE ANALYSIS ===\n")

###############################################################################
# MANUSCRIPT / SUPPLEMENTARY TABLES AND FIGURES
###############################################################################

# 5. Define the three nested analytical populations
status_levels <- c("mobilization", "dilution", "chemostasis")

fig2a_population <- EVS2 %>%
  dplyr::mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    solute = toupper(trimws(as.character(solute))),
    chem_status = stringr::str_to_lower(trimws(as.character(chem_status)))
  ) %>%
  dplyr::filter(
    site %in% sites,
    solute %in% solute_list,
    chem_status %in% status_levels
  ) %>%
  dplyr::distinct(site, ID, solute, .keep_all = TRUE)

responsive_population <- fig2a_population %>%
  dplyr::filter(response %in% TRUE)

fig2d_population <- responsive_population %>%
  dplyr::filter(
    is.finite(HI_use),
    is.finite(loop_area),
    loop_area >= 0,
    !is.na(loop_type),
    nzchar(trimws(as.character(loop_type)))
  )

# Compatibility object used by the proximity section and later modules.
EVS2_prox <- fig2d_population

message("Figure 2a all classifiable event-solute records: ", nrow(fig2a_population))
message("Responsive event-solute records: ", nrow(responsive_population))
message("Figure 2d responsive geometry-resolved records: ", nrow(fig2d_population))

# 6. Exact Figure 2a table and direct population-comparison table
site_solute_keys <- fig2a_population %>%
  dplyr::distinct(site, solute)

summarise_status_population <- function(dat, prefix, keys = site_solute_keys) {
  status_counts <- keys %>%
    tidyr::crossing(chem_status = status_levels) %>%
    dplyr::left_join(
      dat %>%
        dplyr::count(site, solute, chem_status, name = "events_n"),
      by = c("site", "solute", "chem_status")
    ) %>%
    dplyr::mutate(events_n = dplyr::coalesce(events_n, 0L)) %>%
    dplyr::group_by(site, solute) %>%
    dplyr::mutate(
      population_total = sum(events_n),
      events_percent = dplyr::if_else(
        population_total > 0,
        100 * events_n / population_total,
        NA_real_
      )
    ) %>%
    dplyr::ungroup()

  status_wide <- status_counts %>%
    dplyr::select(
      site,
      solute,
      chem_status,
      events_n,
      events_percent,
      population_total
    ) %>%
    tidyr::pivot_wider(
      names_from = chem_status,
      values_from = c(events_n, events_percent),
      names_glue = paste0(prefix, "_{chem_status}_{.value}"),
      values_fill = list(events_n = 0L, events_percent = 0)
    )

  names(status_wide)[names(status_wide) == "population_total"] <-
    paste0(prefix, "_total_events")

  dominant_status <- status_counts %>%
    dplyr::mutate(
      tie_priority = match(
        chem_status,
        c("chemostasis", "mobilization", "dilution")
      )
    ) %>%
    dplyr::arrange(
      site,
      solute,
      dplyr::desc(events_n),
      tie_priority
    ) %>%
    dplyr::group_by(site, solute) %>%
    dplyr::slice(1L) %>%
    dplyr::ungroup() %>%
    dplyr::select(site, solute, chem_status, events_n, events_percent)

  names(dominant_status)[3:5] <- c(
    paste0(prefix, "_dominant_status"),
    paste0(prefix, "_dominant_n"),
    paste0(prefix, "_dominant_percent")
  )

  dplyr::left_join(
    status_wide,
    dominant_status,
    by = c("site", "solute")
  )
}

status_all <- summarise_status_population(
  fig2a_population,
  prefix = "all"
)

status_responsive <- summarise_status_population(
  responsive_population,
  prefix = "responsive"
)

status_geometry <- summarise_status_population(
  fig2d_population,
  prefix = "geometry"
)

Table_Figure2a_vs_Figure2d_ChemicalStatus <- status_all %>%
  dplyr::left_join(status_responsive, by = c("site", "solute")) %>%
  dplyr::left_join(status_geometry, by = c("site", "solute")) %>%
  dplyr::mutate(
    responsive_retention_percent = dplyr::if_else(
      all_total_events > 0,
      100 * responsive_total_events / all_total_events,
      NA_real_
    ),
    geometry_retention_percent = dplyr::if_else(
      all_total_events > 0,
      100 * geometry_total_events / all_total_events,
      NA_real_
    ),
    dominance_shift = dplyr::case_when(
      all_dominant_status == geometry_dominant_status ~
        "No dominance change",
      all_dominant_status == "chemostasis" &
        geometry_dominant_status == "mobilization" ~
        "Chemostatic full population; mobilization-dominated active subset",
      all_dominant_status == "chemostasis" &
        geometry_dominant_status == "dilution" ~
        "Chemostatic full population; dilution-dominated active subset",
      TRUE ~
        "Dominance changes after responsiveness and geometry conditioning"
    ),
    methodological_interpretation = paste0(
      "All-event columns quantify prevalence across every classifiable storm. ",
      "Responsive columns retain storms with at least one ±15% threshold excursion. ",
      "Geometry columns additionally require finite HI, finite normalized loop area, ",
      "and a valid loop type. Event status is time-integrated and unchanged across scales."
    )
  ) %>%
  dplyr::arrange(
    factor(site, levels = c("NF", "SHA", "TTP")),
    factor(solute, levels = c("DOC", "EC", "NO3", "TSS"))
  )

Table_Figure2a_PooledChemicalStatus <- fig2a_population %>%
  dplyr::count(solute, chem_status, name = "events_n") %>%
  tidyr::complete(
    solute = c("DOC", "EC", "NO3", "TSS"),
    chem_status = status_levels,
    fill = list(events_n = 0L)
  ) %>%
  dplyr::group_by(solute) %>%
  dplyr::mutate(
    total_events = sum(events_n),
    events_percent = dplyr::if_else(
      total_events > 0,
      100 * events_n / total_events,
      NA_real_
    )
  ) %>%
  dplyr::ungroup() %>%
  dplyr::arrange(
    factor(solute, levels = c("DOC", "EC", "NO3", "TSS")),
    factor(chem_status, levels = status_levels)
  )

write_csv_authoritative(
  Table_Figure2a_PooledChemicalStatus,
  "Table_Figure2a_PooledChemicalStatus_BySolute.csv"
)

write_csv_authoritative(
  Table_Figure2a_vs_Figure2d_ChemicalStatus,
  "Table_Figure2a_vs_Figure2d_ChemicalStatus_BySiteSolute.csv"
)

# 7. Figure 2a and Figure 2b from the authoritative populations
fig2a_plot_data <- fig2a_population %>%
  dplyr::mutate(
    solute = factor(solute, levels = c("DOC", "EC", "NO3", "TSS")),
    chem_status = factor(
      chem_status,
      levels = c("mobilization", "dilution", "chemostasis")
    )
  )

p1 <- ggplot2::ggplot(
  fig2a_plot_data,
  ggplot2::aes(x = solute, fill = chem_status)
) +
  ggplot2::geom_bar(
    position = "fill",
    width = 0.65,
    colour = "white",
    linewidth = 0.3
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::percent,
    expand = c(0, 0)
  ) +
  ggplot2::scale_fill_manual(
    values = c(
      mobilization = "#D95F02",
      dilution = "#7570B3",
      chemostasis = "#1B9E77"
    ),
    breaks = c("mobilization", "dilution", "chemostasis"),
    labels = c("mobilization", "dilution", "chemostasis"),
    name = "Chemical Behavior",
    drop = FALSE
  ) +
  ggplot2::labs(
    title = "a) Solute Transport Dominance",
    x = "Solute Parameter",
    y = "Proportional Contribution of Storm Events"
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    axis.line.x = ggplot2::element_line(colour = "#333333"),
    axis.line.y = ggplot2::element_line(colour = "#333333"),
    axis.text = ggplot2::element_text(colour = "black", face = "bold"),
    plot.title = ggplot2::element_text(face = "bold", hjust = 0, size = 12.5),
    legend.position = "bottom",
    legend.title = ggplot2::element_text(face = "bold")
  )

p_transport_dominance <- p1

p2 <- EVS2 %>%
  dplyr::filter(is.finite(HI_use)) %>%
  dplyr::mutate(
    solute = factor(solute, levels = c("DOC", "EC", "NO3", "TSS"))
  ) %>%
  ggplot2::ggplot(
    ggplot2::aes(x = solute, y = HI_use, fill = solute)
  ) +
  ggplot2::geom_hline(
    yintercept = 0,
    linetype = "dashed",
    colour = "grey50",
    linewidth = 0.5
  ) +
  ggplot2::geom_boxplot(
    width = 0.5,
    outlier.shape = NA,
    alpha = 0.7,
    colour = "#222222",
    coef = Inf
  ) +
  ggplot2::geom_jitter(
    ggplot2::aes(colour = solute),
    width = 0.15,
    size = 1.2,
    alpha = 0.4
  ) +
  ggplot2::scale_y_continuous(
    limits = c(-1, 1),
    breaks = seq(-1, 1, by = 0.5)
  ) +
  ggplot2::scale_fill_brewer(palette = "Pastel1", guide = "none") +
  ggplot2::scale_colour_brewer(palette = "Dark2", guide = "none") +
  ggplot2::labs(
    title = "b) Hysteresis Strength & Direction",
    x = "Solute Parameter",
    y = expression(bold(Hysteresis ~ Index ~ (HI[Lloyd])))
  ) +
  ggplot2::annotate(
    "text",
    x = 0.6,
    y = 0.75,
    label = "Clockwise (+)",
    fontface = "italic",
    size = 3,
    colour = "grey30",
    hjust = 0
  ) +
  ggplot2::annotate(
    "text",
    x = 0.6,
    y = -0.75,
    label = "Counter-Clockwise (-)",
    fontface = "italic",
    size = 3,
    colour = "grey30",
    hjust = 0
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    axis.line.x = ggplot2::element_line(colour = "#333333"),
    axis.line.y = ggplot2::element_line(colour = "#333333"),
    axis.text = ggplot2::element_text(colour = "black", face = "bold"),
    plot.title = ggplot2::element_text(face = "bold", hjust = 0, size = 12.5)
  )

p_hysteresis_strength <- p2

output_file <- file.path(FIGDIR, "WQ_Hysteresis_Dominance_Summary.png")
final_figure <- p1 + p2 + patchwork::plot_layout(widths = c(1.1, 1))

ggplot2::ggsave(
  filename = output_file,
  plot = final_figure,
  width = 10,
  height = 5.5,
  units = "in",
  dpi = 600,
  bg = "white",
  limitsize = FALSE
)

ggplot2::ggsave(
  filename = file.path(FIGDIR, "Figure2a_ChemicalStatus_Dominance.png"),
  plot = p1,
  width = 5.5,
  height = 5.5,
  units = "in",
  dpi = 600,
  bg = "white",
  limitsize = FALSE
)

message("Saved authoritative Figure 2a–b source: ", output_file)

# 8. Figure 2d source-proximity/pathway-complexity table
landuse_meta <- tibble::tibble(
  site = c("NF", "TTP", "SHA"),
  land_use_type = c(
    "Natural forest",
    "Tea/tree plantation",
    "Smallholder agriculture"
  ),
  land_use_intensity_rank = c(1L, 2L, 3L)
)

loop_type_counts <- fig2d_population %>%
  dplyr::count(site, solute, loop_type, name = "loop_n") %>%
  dplyr::group_by(site, solute) %>%
  dplyr::mutate(
    total_classified_events = sum(loop_n),
    loop_percent = pct_safe(loop_n, total_classified_events)
  ) %>%
  dplyr::arrange(
    site,
    solute,
    dplyr::desc(loop_n),
    loop_type
  ) %>%
  dplyr::mutate(loop_rank = dplyr::row_number()) %>%
  dplyr::ungroup()

loop_dominance <- loop_type_counts %>%
  dplyr::group_by(site, solute) %>%
  dplyr::summarise(
    total_classified_events = dplyr::first(total_classified_events),
    dominant_loop_type = dplyr::first(loop_type),
    dominant_loop_events = dplyr::first(loop_n),
    dominant_loop_percent = dplyr::first(loop_percent),
    secondary_loop_type = dplyr::nth(loop_type, 2L, default = NA_character_),
    secondary_loop_events = dplyr::nth(loop_n, 2L, default = 0L),
    secondary_loop_percent = dplyr::nth(loop_percent, 2L, default = 0),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    secondary_loop_type = dplyr::coalesce(secondary_loop_type, "None"),
    loop_dominance_gap_percent = dominant_loop_percent - secondary_loop_percent,
    loop_dominance_class = dplyr::case_when(
      dominant_loop_percent >= 80 ~ "Very strong",
      dominant_loop_percent >= 60 ~ "Strong",
      dominant_loop_percent >= 40 ~ "Moderate",
      TRUE                        ~ "Weak / mixed"
    )
  )

site_solute_summary <- fig2d_population %>%
  dplyr::group_by(site, solute) %>%
  dplyr::summarise(
    n_valid_events = dplyr::n(),
    median_HI = median_finite(HI_use),
    mean_HI = mean_finite(HI_use),
    median_loop_area = median_finite(loop_area),
    mean_loop_area = mean_finite(loop_area),

    n_positive_HI = sum(HI_use > 0.05, na.rm = TRUE),
    n_negative_HI = sum(HI_use < -0.05, na.rm = TRUE),
    n_near_zero_HI = sum(abs(HI_use) <= 0.05, na.rm = TRUE),

    pct_positive_HI = pct_safe(n_positive_HI, dplyr::n()),
    pct_negative_HI = pct_safe(n_negative_HI, dplyr::n()),
    pct_near_zero_HI = pct_safe(n_near_zero_HI, dplyr::n()),

    n_mobilization = sum(chem_status == "mobilization", na.rm = TRUE),
    n_proximal_mobilization = sum(
      chem_status == "mobilization" & HI_use > 0.05,
      na.rm = TRUE
    ),
    n_delayed_mobilization = sum(
      chem_status == "mobilization" & HI_use < -0.05,
      na.rm = TRUE
    ),
    n_near_zero_mobilization = sum(
      chem_status == "mobilization" & abs(HI_use) <= 0.05,
      na.rm = TRUE
    ),

    pct_proximal_mobilization = pct_safe(
      n_proximal_mobilization,
      n_mobilization
    ),
    pct_delayed_mobilization = pct_safe(
      n_delayed_mobilization,
      n_mobilization
    ),
    pct_near_zero_mobilization = pct_safe(
      n_near_zero_mobilization,
      n_mobilization
    ),
    .groups = "drop"
  ) %>%
  dplyr::left_join(landuse_meta, by = "site") %>%
  dplyr::left_join(loop_dominance, by = c("site", "solute"))

valid_area_medians <- site_solute_summary$median_loop_area[
  is.finite(site_solute_summary$median_loop_area)
]

pathway_thresholds <- if (length(valid_area_medians) >= 3L) {
  stats::quantile(
    valid_area_medians,
    probs = c(1 / 3, 2 / 3),
    na.rm = TRUE,
    names = FALSE,
    type = 7
  )
} else {
  c(NA_real_, NA_real_)
}

pathway_low_threshold  <- pathway_thresholds[1L]
pathway_high_threshold <- pathway_thresholds[2L]

site_solute_summary <- site_solute_summary %>%
  dplyr::mutate(
    source_proximity_class = dplyr::case_when(
      median_HI > 0.05   ~ "Predominantly proximal / early delivery",
      median_HI < -0.05  ~ "Predominantly distal / delayed delivery",
      is.finite(median_HI) ~ "Balanced or mixed timing",
      TRUE                ~ "Not evaluated"
    ),
    source_proximity_strength = dplyr::case_when(
      !is.finite(median_HI) ~ "Not evaluated",
      abs(median_HI) <= 0.05 ~ "Weak",
      abs(median_HI) < 0.20  ~ "Moderate",
      TRUE                   ~ "Strong"
    ),
    pathway_complexity_class = dplyr::case_when(
      !is.finite(median_loop_area) ~ "Not evaluated",
      is.finite(pathway_low_threshold) &
        median_loop_area <= pathway_low_threshold ~ "Low pathway complexity",
      is.finite(pathway_high_threshold) &
        median_loop_area <= pathway_high_threshold ~ "Moderate pathway complexity",
      TRUE ~ "High pathway complexity"
    ),
    proximal_mobilization_frequency = dplyr::case_when(
      n_mobilization <= 0 ~ "No mobilization cases",
      pct_proximal_mobilization >= 50 ~ "Frequent proximal mobilization",
      pct_proximal_mobilization >= 20 ~ "Occasional proximal mobilization",
      TRUE ~ "Rare proximal mobilization"
    ),
    dominant_mobilization_timing = dplyr::case_when(
      n_mobilization <= 0 ~ "No mobilization cases",
      n_proximal_mobilization > n_delayed_mobilization ~
        "Predominantly proximal / early",
      n_delayed_mobilization > n_proximal_mobilization ~
        "Predominantly distal / delayed",
      n_near_zero_mobilization > pmax(
        n_proximal_mobilization,
        n_delayed_mobilization
      ) ~ "Predominantly synchronous / near zero",
      TRUE ~ "Mixed mobilization timing"
    ),
    pathway_low_threshold = pathway_low_threshold,
    pathway_high_threshold = pathway_high_threshold
  )

nf_reference <- site_solute_summary %>%
  dplyr::filter(site == "NF") %>%
  dplyr::select(
    solute,
    NF_median_HI = median_HI,
    NF_median_loop_area = median_loop_area
  )

site_solute_summary <- site_solute_summary %>%
  dplyr::left_join(nf_reference, by = "solute") %>%
  dplyr::mutate(
    HI_difference_from_NF = median_HI - NF_median_HI,
    loop_area_difference_from_NF = median_loop_area - NF_median_loop_area,
    loop_area_ratio_to_NF = dplyr::if_else(
      is.finite(NF_median_loop_area) & NF_median_loop_area > 0,
      median_loop_area / NF_median_loop_area,
      NA_real_
    ),
    pathway_complexity_vs_NF = dplyr::case_when(
      site == "NF" ~ "Reference catchment",
      !is.finite(loop_area_ratio_to_NF) ~ "No valid NF reference",
      loop_area_ratio_to_NF >= 1.25 ~ "Higher than NF",
      loop_area_ratio_to_NF <= 0.75 ~ "Lower than NF",
      TRUE ~ "Similar to NF"
    )
  )

Table_SourceProximity_PathwayComplexity <- site_solute_summary %>%
  dplyr::left_join(
    Table_Figure2a_vs_Figure2d_ChemicalStatus,
    by = c("site", "solute")
  ) %>%
  dplyr::mutate(
    plotted_x_median_HI = median_HI,
    plotted_y_median_loop_area = median_loop_area,
    figure_reference = "Figure 2d",
    analysis_population_fig2a = paste0(
      "All event-solute records with valid time-integrated chemical status, ",
      "including responsive and nonresponsive events."
    ),
    analysis_population_fig2d = paste0(
      "Responsive events with finite HI, finite normalized loop area, ",
      "and a valid loop classification."
    ),
    dominance_difference_explanation = dplyr::case_when(
      all_dominant_status == geometry_dominant_status ~
        "The same event status dominates the full and geometry-resolved populations.",
      all_dominant_status == "chemostasis" &
        geometry_dominant_status == "mobilization" ~
        paste0(
          "The full population is chemostasis-dominated because it retains buffered events; ",
          "the geometry-resolved population is mobilization-enriched after conditioning on responsiveness."
        ),
      all_dominant_status == "chemostasis" &
        geometry_dominant_status == "dilution" ~
        paste0(
          "The full population is chemostasis-dominated because it retains buffered events; ",
          "the geometry-resolved population is dilution-enriched after conditioning on responsiveness."
        ),
      TRUE ~
        paste0(
          "The difference reflects nested analytical denominators, not a change in the ",
          "time-resolved event-status classification rule."
        )
    ),
    interpretation_note = paste0(
      source_proximity_class,
      "; ",
      pathway_complexity_class,
      "; dominant loop: ",
      dominant_loop_type,
      " (",
      sprintf("%.1f", dominant_loop_percent),
      "%)."
    )
  ) %>%
  dplyr::arrange(
    factor(site, levels = c("NF", "SHA", "TTP")),
    factor(solute, levels = c("DOC", "EC", "NO3", "TSS"))
  )

# Compatibility aliases expected elsewhere in the script.
proximity_table_enhanced <- Table_SourceProximity_PathwayComplexity
proximity_table_boosted  <- Table_SourceProximity_PathwayComplexity
proximity_table          <- Table_SourceProximity_PathwayComplexity

site_solute_add <- Table_SourceProximity_PathwayComplexity %>%
  dplyr::mutate(
    n_valid_site_solute = n_valid_events,
    median_HI_site_solute = median_HI,
    mean_HI_site_solute = mean_HI,
    median_loop_area_site_solute = median_loop_area,
    mean_loop_area_site_solute = mean_loop_area,
    source_connectivity_class = proximal_mobilization_frequency
  )

dominance_add <- loop_dominance %>%
  dplyr::transmute(
    site,
    solute,
    total_valid_events = total_classified_events,
    dominant_loop = dominant_loop_type,
    dominant_n = dominant_loop_events,
    dominant_pct = dominant_loop_percent,
    second_loop = secondary_loop_type,
    second_n = secondary_loop_events,
    second_pct = secondary_loop_percent,
    dominance_gap_pct = loop_dominance_gap_percent,
    dominance_class = loop_dominance_class
  )

landuse_looparea_cor <- site_solute_summary %>%
  dplyr::filter(
    is.finite(median_loop_area),
    is.finite(land_use_intensity_rank)
  ) %>%
  dplyr::select(
    site,
    solute,
    land_use_intensity_rank,
    median_loop_area
  ) %>%
  tidyr::pivot_wider(
    names_from = site,
    values_from = median_loop_area,
    names_prefix = "median_loop_area_"
  ) %>%
  dplyr::left_join(
    site_solute_summary %>%
      dplyr::filter(
        is.finite(median_loop_area),
        is.finite(land_use_intensity_rank)
      ) %>%
      dplyr::group_by(solute) %>%
      dplyr::summarise(
        n_sites_for_landuse_test = dplyr::n_distinct(site),
        rho_landuse_looparea = dplyr::if_else(
          dplyr::n_distinct(site) == 3L,
          suppressWarnings(
            stats::cor(
              land_use_intensity_rank,
              median_loop_area,
              method = "spearman",
              use = "complete.obs"
            )
          ),
          NA_real_
        ),
        .groups = "drop"
      ),
    by = "solute"
  ) %>%
  dplyr::mutate(
    landuse_looparea_interpretation = dplyr::case_when(
      !is.finite(rho_landuse_looparea) ~ "Insufficient complete catchments",
      rho_landuse_looparea >= 0.5 ~ "Loop area increases across the specified land-use rank",
      rho_landuse_looparea <= -0.5 ~ "Loop area decreases across the specified land-use rank",
      TRUE ~ "Weak or non-monotonic pattern across the specified land-use rank"
    ),
    inference_note = paste0(
      "Exploratory descriptive contrast based on three catchments; ",
      "no inferential p-value is reported."
    )
  )

write_csv_authoritative(
  Table_SourceProximity_PathwayComplexity,
  "Table_SourceProximity_PathwayComplexity_BySiteSolute.csv"
)

write_csv_authoritative(
  Table_SourceProximity_PathwayComplexity,
  "Table_SpatialProximity_Indicators_BySiteSolute_ENHANCED.csv"
)

write_csv_authoritative(
  dominance_add,
  "Table_DeliveryReliability_DominantLoop_BySiteSolute.csv"
)

write_csv_authoritative(
  landuse_looparea_cor,
  "Table_LandUseIntensity_LoopArea_Correlation_BySolute.csv"
)

# 9. Figure 2d from the exact exported table coordinates
plot_data <- Table_SourceProximity_PathwayComplexity %>%
  dplyr::filter(
    is.finite(plotted_x_median_HI),
    is.finite(plotted_y_median_loop_area)
  ) %>%
  dplyr::mutate(
    site = factor(site, levels = c("NF", "SHA", "TTP")),
    solute = factor(solute, levels = c("DOC", "EC", "NO3", "TSS")),
    land_use_type = factor(
      land_use_type,
      levels = c(
        "Natural forest",
        "Smallholder agriculture",
        "Tea/tree plantation"
      )
    )
  )

if (nrow(plot_data) == 0L) {
  stop("No valid coordinates are available for Figure 2d.", call. = FALSE)
}

overall_loop_area_median <- stats::median(
  plot_data$plotted_y_median_loop_area,
  na.rm = TRUE
)

gg_proximity_grid_v2 <- ggplot2::ggplot(
  plot_data,
  ggplot2::aes(
    x = plotted_x_median_HI,
    y = plotted_y_median_loop_area,
    colour = land_use_type,
    shape = solute
  )
) +
  ggplot2::geom_vline(
    xintercept = 0,
    linetype = "dashed",
    colour = "grey55",
    linewidth = 0.55
  ) +
  ggplot2::geom_hline(
    yintercept = overall_loop_area_median,
    linetype = "dotted",
    colour = "grey55",
    linewidth = 0.55
  ) +
  ggplot2::geom_point(
    size = 4.4,
    stroke = 1.15,
    alpha = 1
  ) +
  ggplot2::scale_colour_manual(
    values = c(
      "Natural forest" = "#2E7D32",
      "Smallholder agriculture" = "#C62828",
      "Tea/tree plantation" = "#1565C0"
    ),
    breaks = c(
      "Natural forest",
      "Smallholder agriculture",
      "Tea/tree plantation"
    ),
    drop = FALSE
  ) +
  ggplot2::scale_shape_manual(
    values = c(
      DOC = 16,
      EC = 17,
      NO3 = 15,
      TSS = 3
    ),
    labels = c(
      DOC = "DOC",
      EC = "EC",
      NO3 = expression(NO[3]^"-"),
      TSS = "TSS"
    ),
    drop = FALSE
  ) +
  ggplot2::scale_x_continuous(
    limits = c(-1.02, 1.02),
    breaks = seq(-1, 1, by = 0.1),
    expand = ggplot2::expansion(mult = c(0.01, 0.01))
  ) +
  ggplot2::scale_y_continuous(
    expand = ggplot2::expansion(mult = c(0.06, 0.08))
  ) +
  ggplot2::labs(
    title = "d) Catchment Solute Transport Fingerprints",
    x = paste0(
      "Distal / Delayed Sources (Negative HI)  |  ",
      "Proximal / Early Flushing (Positive HI)"
    ),
    y = "Pathway Complexity (Median Loop Area)",
    colour = "Catchment Class",
    shape = "Water Quality Parameter"
  ) +
  ggplot2::guides(
    shape = ggplot2::guide_legend(
      order = 1,
      override.aes = list(colour = "black", size = 4)
    ),
    colour = ggplot2::guide_legend(
      order = 2,
      override.aes = list(shape = 16, size = 4)
    )
  ) +
  ggplot2::theme_bw(base_size = 11) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(
      face = "bold",
      size = 12.5,
      hjust = 0
    ),
    axis.title.x = ggplot2::element_text(
      face = "bold",
      size = 10.5,
      margin = ggplot2::margin(t = 12)
    ),
    axis.title.y = ggplot2::element_text(
      face = "bold",
      size = 10.5,
      margin = ggplot2::margin(r = 12)
    ),
    axis.text = ggplot2::element_text(
      colour = "black",
      size = 9.5
    ),
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major = ggplot2::element_line(
      colour = "grey90",
      linewidth = 0.4
    ),
    legend.position = c(0.98, 0.08),
    legend.justification = c(1, 0),
    legend.box = "vertical",
    legend.background = ggplot2::element_rect(
      fill = "white",
      colour = "grey70",
      linewidth = 0.45
    ),
    legend.title = ggplot2::element_text(face = "bold", size = 9),
    legend.text = ggplot2::element_text(size = 8.5),
    legend.margin = ggplot2::margin(t = 6, r = 8, b = 6, l = 8)
  )

OUT_PROXIMITY <- file.path(
  FIGDIR,
  "Figure_Solute_Proximity_vs_Complexity_v2.png"
)

output_file_path <- OUT_PROXIMITY

ggplot2::ggsave(
  filename = OUT_PROXIMITY,
  plot = gg_proximity_grid_v2,
  width = 8.2,
  height = 6.5,
  units = "in",
  dpi = 600,
  bg = "white",
  limitsize = FALSE
)

# 10. Output audit
proximity_output_audit <- tibble::tibble(
  output_name = c(
    "Table_Figure2a_PooledChemicalStatus_BySolute.csv",
    "Table_Figure2a_vs_Figure2d_ChemicalStatus_BySiteSolute.csv",
    "Table_SourceProximity_PathwayComplexity_BySiteSolute.csv",
    "Table_SpatialProximity_Indicators_BySiteSolute_ENHANCED.csv",
    "Table_LandUseIntensity_LoopArea_Correlation_BySolute.csv",
    "WQ_Hysteresis_Dominance_Summary.png",
    "Figure2a_ChemicalStatus_Dominance.png",
    "Figure_Solute_Proximity_vs_Complexity_v2.png"
  ),
  output_path = c(
    file.path(TABDIR, "Table_Figure2a_PooledChemicalStatus_BySolute.csv"),
    file.path(TABDIR, "Table_Figure2a_vs_Figure2d_ChemicalStatus_BySiteSolute.csv"),
    file.path(TABDIR, "Table_SourceProximity_PathwayComplexity_BySiteSolute.csv"),
    file.path(TABDIR, "Table_SpatialProximity_Indicators_BySiteSolute_ENHANCED.csv"),
    file.path(TABDIR, "Table_LandUseIntensity_LoopArea_Correlation_BySolute.csv"),
    output_file,
    file.path(FIGDIR, "Figure2a_ChemicalStatus_Dominance.png"),
    OUT_PROXIMITY
  )
) %>%
  dplyr::mutate(
    exists = file.exists(output_path),
    size_bytes = dplyr::if_else(
      exists,
      as.numeric(file.info(output_path)$size),
      NA_real_
    )
  )

write_csv_authoritative(
  proximity_output_audit,
  "Audit_Figure2a_Figure2d_Outputs.csv"
)

if (!all(proximity_output_audit$exists)) {
  missing_outputs <- proximity_output_audit$output_name[
    !proximity_output_audit$exists
  ]
  stop(
    "One or more Figure 2a/2d outputs were not created: ",
    paste(missing_outputs, collapse = ", "),
    call. = FALSE
  )
}

# Optional validation logs retained for compatibility.
print_dominance_summaries <- function(dat, label_text) {
  cat("\n======================================================================\n")
  cat(" DOMINANCE SUMMARY: ", toupper(label_text), "\n", sep = "")
  cat("======================================================================\n")
  print(table(dat$solute, dat$chem_status, useNA = "ifany"))
  cat("\nLoop types:\n")
  print(table(dat$solute, dat$loop_type, useNA = "ifany"))
  cat("======================================================================\n")
  invisible(NULL)
}

print_dominance_summaries(EVS2, "ALL SITES")
for (s in sites) {
  print_dominance_summaries(
    EVS2 %>% dplyr::filter(site == s),
    paste0("SITE ", s)
  )
}

message("Saved Figure 2a table: ", file.path(TABDIR, "Table_Figure2a_PooledChemicalStatus_BySolute.csv"))
message("Saved nested-population audit: ", file.path(TABDIR, "Table_Figure2a_vs_Figure2d_ChemicalStatus_BySiteSolute.csv"))
message("Saved Figure 2d table: ", file.path(TABDIR, "Table_SourceProximity_PathwayComplexity_BySiteSolute.csv"))
message("Saved Figure 2d: ", OUT_PROXIMITY)
message("=== AUTHORITATIVE WQ STATUS + FIGURE 2a/2d WORKFLOW COMPLETED ===")

# ========================= INITIAL-FLOW ANALYSIS =========================
# 1. TRUE HISTORICAL BASELINE FLOW CLASSIFICATION (6-Year Continuous Dataset)
site_flow_thresholds <- list()

for (s in sites) {
  q_col_continuous <- detect_q_col(names(df), s)

  if (!is.na(q_col_continuous) && q_col_continuous %in% names(df)) {
    raw_q_series <- to_num(df[[q_col_continuous]])
    valid_q <- raw_q_series[is.finite(raw_q_series) & raw_q_series > 0]

    site_flow_thresholds[[s]] <- list(
      p33 = quantile(valid_q, probs = 0.33, na.rm = TRUE),
      p66 = quantile(valid_q, probs = 0.66, na.rm = TRUE)
    )

    cat(sprintf("[Baseline Lock] Site %s thresholds: 33rd=%.3f, 66th=%.3f\n",
                s, site_flow_thresholds[[s]]$p33, site_flow_thresholds[[s]]$p66))
  } else {
    stop(sprintf("CRITICAL ERROR: Continuous discharge column missing for site %s!", s))
  }
}

# 2. VERBOSE ERROR-HUNTING TRACKING LOOP
WQ_ev_list <- list()

for (s in c("NF", "SHA", "TTP")) {
  et_s <- eTable2 %>% filter(site == s)
  if (nrow(et_s) == 0) next

  q_col <- detect_q_col(names(df), s)
  vars_map <- c(
    NO3 = detect_wq_col(names(df), s, "NO3"),
    DOC = detect_wq_col(names(df), s, "DOC"),
    EC  = detect_wq_col(names(df), s, "EC"),
    TSS = detect_wq_col(names(df), s, "TSS")
  )

  message(sprintf("\n>>> Processing site %s: Evaluating %d storm windows...", s, nrow(et_s)))

  for (i in seq_len(nrow(et_s))) {
    ev <- et_s[i, ]

    row_out <- tryCatch({
      compute_WQ_ev_one(
        df = df,
        ev = ev,
        q_col = q_col,
        vars_map = vars_map,
        min_comp = 0.90,
        dt_fallback_s = get_dt_seconds(df$date)
      )
    }, error = function(e) {
      cat(sprintf(" [Storm Row %d Failed] Error details: %s\n", i, conditionMessage(e)))
      return(NULL)
    })

    if (!is.null(row_out) && is.data.frame(row_out) && nrow(row_out) > 0) {
      WQ_ev_list[[length(WQ_ev_list) + 1]] <- row_out
    }
  }
}

if (length(WQ_ev_list) > 0) {
  WQ_ev_df <- do.call(rbind, WQ_ev_list)
  cat(sprintf("\n=== SUCCESS: Extracted %d active storm rows ===\n", nrow(WQ_ev_df)))
} else {
  message("\nCRITICAL: Master collection list remains empty.")
}

# 3. FIG 5: HYSTERESIS TYPE OCCURRENCE (%) + HI[Lloyd] DISTRIBUTION
# 1. Use the authoritative Section 2.6 profile and classifier defined above.
HI_profile_Lloyd_figure <- function(Q, C, k = seq(0.05,0.95,by=0.05)) {
  HI_profile_Lloyd(Q,C,k,min_points=min_pts_hyst,min_limb_points=min_pts_limb)
}
classify_loop_type_manuscript <- function(HIk, k = seq(0.05,0.95,by=0.05)) {
  z <- classify_loop_type(HIk,k)
  ifelse(is.na(z),"NA",z)
}

# 3. Setup factor labels and high-contrast palette matching manuscript terminology
solute_order <- c("TSS", "EC", "DOC", "NO3")
loop_levels  <- c("AntiClockwise", "Figure-8 / Mixed", "Direct / Synchronous", "Clockwise",
                  "SingleLine+Loop (AntiClockwise)", "SingleLine+Loop (Clockwise)", "NA")

loop_colors <- c(
  "AntiClockwise"                   = "#1F77B4",
  "Clockwise"                       = "#D62728",
  "Figure-8 / Mixed"                = "#9467BD",
  "Direct / Synchronous"            = "#BCBD22",
  "SingleLine+Loop (AntiClockwise)" = "#AEC7E8",
  "SingleLine+Loop (Clockwise)"     = "#FF9896",
  "NA"                              = "#7F7F7F"
)

base_th <- theme_bw(base_size = 12) +
  theme(
    panel.grid   = element_blank(),
    axis.text    = element_text(face = "bold", colour = "black", size = 10),
    axis.title   = element_text(face = "bold", size = 11),
    legend.text  = element_text(size = 10),
    legend.title = element_text(size = 11, face = "bold")
  )

# 4. Re-process EVS2 dataset matching the recalculated metrics engine

# 1. Re-calculate metrics by pulling the actual high-frequency time series (pts)
EVS2_updated_list <- list()

for (i in seq_len(nrow(EVS2))) {
  row_data <- EVS2[i, ]

  # Fetch the real underlying paired time-series data vectors for this event
  pts <- tryCatch({
    get_event_series_for_solute_pre_vaughan(
      site_name   = as.character(row_data$site),
      event_id    = as.integer(row_data$ID),
      solute_name = as.character(row_data$solute)
    )
  }, error = function(e) NULL)

  if (!is.null(pts) && is.data.frame(pts) && nrow(pts) >= 10) {
    # Calculate grid profile array metrics using Section 2.6 formulas
    HIk_array <- HI_profile_Lloyd_figure(pts$Q, pts$C, k = seq(0.05, 0.95, by = 0.05))

    row_data$HI_use    <- mean(HIk_array, na.rm = TRUE)
    row_data$loop_type <- classify_loop_type_manuscript(HIk_array, k = seq(0.05, 0.95, by = 0.05))
  } else {
    # Safe fallback if high-frequency point requirements fail constraints
    row_data$HI_use    <- NA_real_
    row_data$loop_type <- "NA"
  }

  EVS2_updated_list[[i]] <- row_data
}

# 2. Bind collection rows back together safely and enforce uniform factor matching
EVS2_updated <- bind_rows(EVS2_updated_list) %>%
  mutate(
    solute    = factor(solute, levels = solute_order),
    loop_type = factor(ifelse(is.na(loop_type) | loop_type == "" | loop_type == "na", "NA", loop_type),
                       levels = loop_levels)
  )

# RE-BUILT COMPILATION CANVAS GENERATOR FUNCTION
make_fig5_panel_joined <- function(site_name, show_xaxis = TRUE) {

  # Filters data to display matching parameters
  dat <- EVS2_updated %>%
    filter(site == site_name, response %in% TRUE, is.finite(HI_use))

  occ <- dat %>%
    count(solute, loop_type) %>%
    group_by(solute) %>%
    mutate(pct = 100 * n / sum(n)) %>%
    ungroup()

  p_occ <- ggplot(occ, aes(pct, solute, fill = loop_type)) +
    geom_col(width = 0.75, show.legend = show_xaxis) +
    scale_x_continuous(limits = c(0, 100), expand = c(0, 0)) +
    scale_fill_manual(values = loop_colors, drop = FALSE) +
    labs(x = if(show_xaxis) "Hysteresis type occurrence (%)" else NULL, y = NULL) +
    base_th +
    theme(
      plot.margin = ggplot2::margin(5, 0, 5, 5),
      axis.text.x = if(!show_xaxis) element_blank() else element_text(face = "bold", size = 10),
      axis.ticks.x = if(!show_xaxis) element_blank() else element_line()
    )

  p_hi <- ggplot(dat, aes(HI_use, solute)) +
    stat_boxplot(geom = "errorbar", coef = 0, width = 0.3) +
    geom_boxplot(coef = 0, outlier.shape = NA, linewidth = 0.7, fill = "grey95") +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    scale_y_discrete(position = "right") +
    # Signed Lloyd hysteresis index ranges from anticlockwise (-) to clockwise (+)
    coord_cartesian(xlim = c(-1.02, 1.02)) +
    annotate("text", x = Inf, y = Inf, label = site_name,
             hjust = 1.2, vjust = 1.5, size = 5, fontface = "bold") +
    labs(x = if(show_xaxis) expression(bold(HI[Lloyd])) else NULL, y = NULL) +
    base_th +
    theme(
      axis.text.y.left  = element_blank(),
      axis.ticks.y.left = element_blank(),
      axis.text.x = if(!show_xaxis) element_blank() else element_text(face = "bold", size = 10),
      axis.ticks.x = if(!show_xaxis) element_blank() else element_line(),
      plot.margin = ggplot2::margin(5, 5, 5, 0)
    )

  return(p_occ + p_hi + plot_layout(widths = c(2.5, 1)))
}

# 6. Save data logs and assemble grid layout canvas
fig5_occ <- EVS2_updated %>%
  filter(site %in% c("NF", "SHA", "TTP"), response %in% TRUE) %>%
  count(site, solute, loop_type, name = "n") %>%
  complete(site, solute, loop_type = factor(loop_levels, levels = loop_levels), fill = list(n = 0)) %>%
  group_by(site, solute) %>%
  mutate(total_n = sum(n), pct = ifelse(total_n > 0, 100 * n / total_n, NA_real_)) %>%
  ungroup()

write.csv(fig5_occ, file.path(TABDIR, "Fig5_loop_type_occurrence_by_site_solute.csv"), row.names = FALSE)

if (requireNamespace("patchwork", quietly = TRUE)) {
  p1 <- make_fig5_panel_joined("NF",  show_xaxis = FALSE)
  p2 <- make_fig5_panel_joined("SHA", show_xaxis = FALSE)
  p3 <- make_fig5_panel_joined("TTP", show_xaxis = TRUE)

  final_grid <- (p1 / p2 / p3) +
    plot_layout(guides = "collect") &
    theme(legend.position = "bottom") &
    guides(fill = guide_legend(title = "Hysteresis Loop Type", nrow = 2, byrow = TRUE))

  final_fig5 <- wrap_elements(final_grid) +
    labs(tag = "Solute Parameter") +
    theme(
      plot.tag.position = c(0.015, 0.5),
      plot.tag          = element_text(angle = 90, face = "bold", size = 14),
      plot.margin       = ggplot2::margin(t = 10, r = 10, b = 10, l = 45)
    )

  ggsave(
    filename = file.path(FIGDIR, "Fig5_Final_Clean.png"),
    plot     = final_fig5, width = 9.5, height = 8.5, dpi = 400, bg = "white"
  )
  message("Success: Aligned script execution complete. Check figure: Fig5_Final_Clean.png")
}

# 4. FLOW-REGIME DISTRIBUTION MATRIX & VISUALIZATION
# 1. Extract authoritative baseline percentiles from continuous master data
baseline_thresholds <- list()
for (s in c("NF", "SHA", "TTP")) {
  q_col <- detect_q_col(names(df), s)
  if (!is.na(q_col) && q_col %in% names(df)) {
    qv <- tibble::tibble(
      date = as.Date(df$date, tz = TZ_USE),
      Q = to_num(df[[q_col]])
    ) %>%
      dplyr::filter(!is.na(date), is.finite(Q), Q > 0) %>%
      dplyr::group_by(date) %>%
      dplyr::summarise(Q_daily = mean(Q, na.rm = TRUE), .groups = "drop") %>%
      dplyr::pull(Q_daily)
    thresholds <- stats::quantile(
      qv, probs = c(0.33, 0.66), na.rm = TRUE, names = FALSE
    )

    # FIXED: Enforced explicit indexing [1] and [2] to prevent vector corruption
    baseline_thresholds[[s]] <- tibble(
      site            = s,
      thresh_low_mid  = thresholds[1],
      thresh_mid_high = thresholds[2]
    )
  }
}
baseline_df <- bind_rows(baseline_thresholds)

# 2. Map active events using the authoritative event-register qStart.
# EVS2 is event-solute level and may not reliably carry qStart after earlier joins,
# so join qStart explicitly by site + event ID before flow-regime classification.
flow_qstart_register <- (if (exists("eTable2")) eTable2 else eTable) %>%
  dplyr::transmute(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    qStart = suppressWarnings(as.numeric(qStart))
  ) %>%
  dplyr::filter(!is.na(site), !is.na(ID)) %>%
  dplyr::distinct(site, ID, .keep_all = TRUE)

flow_condition_summary_by_site <- EVS2 %>%
  dplyr::mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID))
  ) %>%
  dplyr::filter(response %in% TRUE, is.finite(HI_use)) %>%
  dplyr::distinct(site, ID, .keep_all = TRUE) %>%
  dplyr::select(-dplyr::any_of(c("qStart", "qStart.x", "qStart.y"))) %>%
  dplyr::left_join(flow_qstart_register, by = c("site", "ID")) %>%
  dplyr::filter(is.finite(qStart)) %>%
  dplyr::left_join(baseline_df, by = "site") %>%
  dplyr::mutate(
    flow_group = dplyr::case_when(
      qStart <= thresh_low_mid ~ "Low Flow",
      qStart > thresh_low_mid & qStart <= thresh_mid_high ~ "Mid Flow",
      qStart > thresh_mid_high ~ "High Flow",
      TRUE ~ NA_character_
    ),
    flow_group = factor(
      flow_group,
      levels = c("Low Flow", "Mid Flow", "High Flow")
    )
  ) %>%
  dplyr::filter(!is.na(flow_group)) %>%
  dplyr::count(site, flow_group, name = "n_events") %>%
  dplyr::group_by(site) %>%
  dplyr::mutate(percent = round(100 * n_events / sum(n_events), 1)) %>%
  dplyr::ungroup()

# Export aligned distribution summary matrix
write.csv(
  flow_condition_summary_by_site,
  file.path(DIR_REPRO_TMP_TAB, "Table_FlowCondition_Summary_ActiveEvents_BySite.csv"),
  row.names = FALSE
)

# 3. Re-build the stacked column plot configuration data frame
flow_plot_dat <- flow_condition_summary_by_site %>%
  mutate(
    site  = factor(site, levels = c("NF", "SHA", "TTP")),
    label = paste0(n_events, " evts\n", sprintf("%.1f", percent), "%")
  )

# Build publication bar plot matching your exact colors and factor ordering
p_flow_condition <- ggplot(flow_plot_dat, aes(x = site, y = percent, fill = flow_group)) +
  geom_col(
    width = 0.60,
    color = "black",
    linewidth = 0.4,
    position = position_stack(reverse = FALSE)
  ) +
  geom_text(
    aes(label = label),
    position = position_stack(vjust = 0.5, reverse = FALSE),
    size = 3.5,
    color = "black",
    fontface = "bold"
  ) +
  scale_y_continuous(
    limits = c(0, 101),
    breaks = seq(0, 100, 20),
    labels = function(x) paste0(pmin(x, 100), "%"),
    expand = c(0, 0)
  ) +
  scale_fill_manual(
    values = c(
      "Low Flow" = "#9ecae1",
      "Mid Flow" = "#fdae6b",
      "High Flow" = "#de2d26"
    ),
    name = "Long-Term Baseline Flow Regime"
  ) +
  labs(
    x = "Catchment Channel Location",
    y = "Proportion of Sampled Storm Events (%)",
    title = "c) Distribution of Event Flow Conditions Standardized to Long-Term FDC"
  ) +
  theme_bw(base_size = 12) +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    axis.text          = element_text(color = "black", size = 10, face = "bold"),
    axis.title.x       = element_text(face = "bold", size = 11, margin = margin(t = 12)),
    axis.title.y       = element_text(face = "bold", size = 11, margin = margin(r = 12)),
    plot.title         = element_text(face = "bold", hjust = 0, size = 12.5, margin = margin(b = 10)),
    legend.position    = "bottom",
    legend.title       = element_text(face = "bold"),
    panel.border       = element_rect(color = "black", fill = NA, linewidth = 0.8)
  )
# Save visualization directly to your paper directory assets folder
ggsave(
  filename = file.path(FIGDIR, "Fig_Flow_Condition_Distribution_BySite.png"),
  plot     = p_flow_condition,
  width    = 7.5,
  height   = 5.8,
  dpi      = 400,
  bg       = "white"
)

# 4. Re-run your Chi-Square contingency matrix test
contingency_matrix <- flow_condition_summary_by_site %>%
  select(site, flow_group, n_events) %>%
  tidyr::pivot_wider(names_from = flow_group, values_from = n_events, values_fill = 0)

mat_data <- as.matrix(contingency_matrix %>% select(any_of(c("Low Flow", "Mid Flow", "High Flow"))))
rownames(mat_data) <- contingency_matrix$site

message("\n--- CHI-SQUARE HOMOGENEITY DIAGNOSTIC ---")
print(chisq.test(mat_data))

# REPRESENTATIVE-EVENT SUPPORT — MAIN FIGURES 5 AND 6

# Compatibility aliases required by the author-approved Figure 5/6 code.
norm01 <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  out <- rep(NA_real_, length(x))
  ok <- is.finite(x)
  if (!any(ok)) return(out)
  r <- range(x[ok], na.rm = TRUE)
  if (!all(is.finite(r))) return(out)
  if (diff(r) == 0) {
    out[ok] <- 0
    return(out)
  }
  out[ok] <- (x[ok] - r[1]) / diff(r)
  out
}

detect_solute_col <- function(df_names, site, solute, wq_map = NULL) {
  solute <- toupper(trimws(as.character(solute)[1]))
  if (!is.null(wq_map) && all(c("site", "param", "col") %in% names(wq_map))) {
    hit <- wq_map %>%
      dplyr::mutate(
        site = trimws(as.character(.data$site)),
        param = toupper(trimws(as.character(.data$param))),
        col = trimws(as.character(.data$col))
      ) %>%
      dplyr::filter(.data$site == .env$site, .data$param == .env$solute) %>%
      dplyr::pull(.data$col)
    hit <- hit[hit %in% df_names]
    if (length(hit) > 0L) return(hit[1L])
  }
  detect_wq_col(df_names, site, solute)
}

fig6_sites <- c("NF", "SHA", "TTP")
fig6_sites_ordered <- fig6_sites
fig6_rows <- c("Figure-8", "Anti-clockwise", "Clockwise")

# Author-approved representative events retained in the manuscript figures.
fig6_selected <- tibble::tribble(
  ~row_group,       ~site, ~solute, ~event_id,
  "Figure-8",       "NF",  "NO3",   44L,
  "Figure-8",       "SHA", "DOC",  303L,
  "Figure-8",       "TTP", "EC",    33L,
  "Anti-clockwise", "NF",  "DOC",  479L,
  "Anti-clockwise", "SHA", "TSS",  678L,
  "Anti-clockwise", "TTP", "DOC",  609L,
  "Clockwise",      "NF",  "EC",   523L,
  "Clockwise",      "SHA", "NO3",  683L,
  "Clockwise",      "TTP", "NO3",  502L
) %>%
  dplyr::mutate(
    row_group = factor(.data$row_group, levels = fig6_rows),
    site = factor(.data$site, levels = fig6_sites)
  ) %>%
  dplyr::arrange(.data$row_group, .data$site)

FIG6_LOOP_FILE  <- file.path(DIR_REPRO_TMP_FIG, "Fig6_Combined_Loops_AllSites_3x3.png")
FIG6_HYDRO_FILE <- file.path(DIR_REPRO_TMP_FIG, "Fig6_Combined_Hydrographs_AllSites_3x3.png")
FIG6_SEL_FILE   <- file.path(DIR_REPRO_TMP_TAB, "Table_Figure56_SelectedEvents.csv")
utils::write.csv(fig6_selected, FIG6_SEL_FILE, row.names = FALSE, fileEncoding = "UTF-8")

get_event_year <- function(site_name, event_id) {
  ev <- eTable %>%
    dplyr::filter(.data$site == site_name, .data$ID == event_id) %>%
    dplyr::slice(1L)
  if (nrow(ev) == 0L || is.na(ev$tStart[1])) return(NA_integer_)
  lubridate::year(.parse_dt(ev$tStart[1], tz = TZ_USE))
}

get_fig6_loop_data <- function(site_name, event_id, solute_name) {
  ev <- eTable %>%
    dplyr::filter(.data$site == site_name, .data$ID == event_id) %>%
    dplyr::slice(1L)
  if (nrow(ev) == 0L) return(NULL)

  q_col <- detect_q_col(names(df), site_name)
  c_col <- detect_solute_col(names(df), site_name, solute_name)
  if (is.na(q_col) || is.na(c_col)) return(NULL)

  z <- df %>%
    dplyr::filter(.data$date >= ev$tStart[1], .data$date <= ev$tEnd[1]) %>%
    dplyr::transmute(
      Q = to_num(.data[[q_col]]),
      C = to_num(.data[[c_col]])
    ) %>%
    dplyr::filter(is.finite(.data$Q), is.finite(.data$C))

  if (nrow(z) < 2L) return(NULL)
  z %>%
    dplyr::mutate(Qn = norm01(.data$Q), Cn = norm01(.data$C)) %>%
    dplyr::filter(is.finite(.data$Qn), is.finite(.data$Cn))
}

fig6_compute_dynamic_baseflow <- function(Q, smooth_k = 9L) {
  Q <- suppressWarnings(as.numeric(Q))
  n <- length(Q)
  if (n == 0L) return(numeric(0))
  if (all(!is.finite(Q))) return(rep(NA_real_, n))
  idx <- seq_len(n)
  ok <- is.finite(Q)
  if (sum(ok) == 1L) return(rep(Q[ok][1], n))

  Q_fill <- stats::approx(idx[ok], Q[ok], xout = idx, rule = 2)$y
  k1 <- min(max(3L, as.integer(smooth_k)), max(3L, n))
  run_min <- zoo::rollapply(
    Q_fill, width = k1, FUN = min, fill = NA_real_, align = "center", partial = TRUE
  )
  run_min[!is.finite(run_min)] <- Q_fill[!is.finite(run_min)]
  k2 <- k1
  if (k2 %% 2L == 0L) k2 <- k2 - 1L
  if (k2 < 3L) k2 <- 3L
  if (k2 > n) k2 <- if (n %% 2L == 1L) n else max(1L, n - 1L)
  if (k2 < 3L) return(pmin(run_min, Q_fill))
  bf <- stats::runmed(run_min, k = k2, endrule = "median")
  bf <- pmin(bf, Q_fill, na.rm = FALSE)
  bf[is.finite(bf) & bf < 0] <- 0
  bf
}

get_event_hydro_data <- function(site_name, event_id) {
  ev <- eTable %>%
    dplyr::filter(.data$site == site_name, .data$ID == event_id) %>%
    dplyr::slice(1L)
  if (nrow(ev) == 0L) return(NULL)

  q_col <- detect_q_col(names(df), site_name)
  p_col <- detect_prec_col(names(df), site_name)
  if (is.na(q_col) || is.na(p_col)) return(NULL)

  z <- df %>%
    dplyr::filter(.data$date >= ev$tStart[1], .data$date <= ev$tEnd[1]) %>%
    dplyr::transmute(
      date = .data$date,
      Q = to_num(.data[[q_col]]),
      P = to_num(.data[[p_col]])
    )
  if (nrow(z) == 0L) return(NULL)
  z %>% dplyr::mutate(BF = fig6_compute_dynamic_baseflow(.data$Q))
}

# Override the earlier extractor so Figure 5 has dates while all earlier Q/C callers remain valid.
get_event_series_for_solute <- function(site_name, event_id, solute_name) {
  ev <- eTable %>%
    dplyr::filter(.data$site == site_name, .data$ID == event_id) %>%
    dplyr::slice(1L)
  if (nrow(ev) == 0L) return(NULL)

  q_col <- detect_q_col(names(df), site_name)
  c_col <- detect_solute_col(names(df), site_name, solute_name)
  if (is.na(q_col) || is.na(c_col)) return(NULL)

  df %>%
    dplyr::filter(.data$date >= ev$tStart[1], .data$date <= ev$tEnd[1]) %>%
    dplyr::transmute(
      date = .data$date,
      Q = to_num(.data[[q_col]]),
      C = to_num(.data[[c_col]])
    )
}

add_event_time_axis <- function(dates, cex.axis = 1.0) {
  dates <- dates[!is.na(dates)]
  if (length(dates) == 0L) {
    axis(1, cex.axis = cex.axis)
    return(invisible(NULL))
  }
  axis.POSIXct(1, x = dates, format = "%d %b\n%H:%M", cex.axis = cex.axis, las = 1)
  invisible(NULL)
}

fig6_safe_range <- function(x, fallback = c(0, 1), expansion = 0.05) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x) == 0L) return(fallback)
  r <- range(x)
  if (!all(is.finite(r))) return(fallback)
  if (diff(r) == 0) {
    delta <- if (r[1] == 0) 1 else max(abs(r[1]) * 0.05, .Machine$double.eps)
    r <- r + c(-delta, delta)
  }
  r + c(-1, 1) * diff(r) * expansion
}

fig6_empty_panel <- function(label = "No eligible event", mar = c(2, 2, 1, 1)) {
  par(mar = mar)
  plot.new()
  plot.window(xlim = c(0, 1), ylim = c(0, 1))
  text(0.5, 0.5, label, cex = 0.9, col = "grey35")
  box()
  invisible(NULL)
}

dt_min <- get_dt_seconds(df$date) / 60

# Validate the fixed publication selections against the rebuilt event register.
missing_fig56 <- fig6_selected %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    exists = nrow(eTable %>% dplyr::filter(
      .data$site == as.character(site), .data$ID == event_id
    )) > 0L
  ) %>%
  dplyr::ungroup() %>%
  dplyr::filter(!.data$exists)
if (nrow(missing_fig56) > 0L) {
  stop(
    "Author-approved Figure 5/6 event(s) missing from rebuilt event register: ",
    paste0(missing_fig56$site, "-", missing_fig56$event_id, collapse = ", "),
    call. = FALSE
  )
}

# ================= REPRESENTATIVE EVENT FIGURE HELPERS =================
######################################################################
#########
# REPRESENTATIVE-EVENT SUPPORT FOR MAIN FIGURES 5 AND 6
# - Dynamically selects events based on best shape clarity (loop_area)
# - Diversifies solute parameters across catchments automatically
# - Self-healing explicit data-retrieval pipeline injected to prevent select() crashes
######################################################################
#########

################################################################################
# PART A — SHARED REPRESENTATIVE-EVENT DATA FOR MAIN FIGURES 5 AND 6
################################################################################

# A1. CONSISTENT CONSTITUENT COLOUR SYSTEM
# These are the same constituent colours used in manuscript Figures 1 and 2.
# Existing global definitions are respected when already available.

FIG6_CONSTITUENT_COLS <- if (exists("CONSTITUENT_COLS", inherits = TRUE)) {
  get("CONSTITUENT_COLS", inherits = TRUE)
} else {
  c(
    NO3 = "#FF3030",  # NO3-N: red
    DOC = "#D89B16",  # DOC: ochre/gold
    EC  = "#A64CFF",  # EC: purple
    TSS = "#2CA02C"   # TSS: green
  )
}

# Force the expected four keys even if the global object contains extras.
FIG6_CONSTITUENT_COLS <- FIG6_CONSTITUENT_COLS[c("NO3", "DOC", "EC", "TSS")]

if (any(is.na(FIG6_CONSTITUENT_COLS))) {
  FIG6_CONSTITUENT_COLS <- c(
    NO3 = "#FF3030",
    DOC = "#D89B16",
    EC  = "#A64CFF",
    TSS = "#2CA02C"
  )
}

FIG6_CONSTITUENT_LABELS <- c(
  NO3 = "NO3-N",
  DOC = "DOC",
  EC  = "EC",
  TSS = "TSS"
)

FIG6_DISCHARGE_COL <- "#0057FF"
FIG6_INITIAL_FLOW_COL <- "black"
FIG6_RAIN_COL <- "grey45"
FIG6_EXPORT_DPI <- 700

fig6_get_solute_key <- function(solute_name) {
  key <- toupper(trimws(as.character(solute_name)[1]))
  if (!key %in% names(FIG6_CONSTITUENT_COLS)) {
    stop("Unrecognised representative-event constituent: ", solute_name, call. = FALSE)
  }
  key
}

fig6_get_solute_col <- function(solute_name) {
  unname(FIG6_CONSTITUENT_COLS[fig6_get_solute_key(solute_name)])
}

fig6_get_solute_label <- function(solute_name) {
  key <- fig6_get_solute_key(solute_name)
  unname(FIG6_CONSTITUENT_LABELS[key])
}

fig6_get_solute_axis_title <- function(solute_name) {
  key <- fig6_get_solute_key(solute_name)

  switch(
    key,
    NO3 = "NO3-N (mg N/L)",
    DOC = "DOC (mg/L)",
    EC  = "EC (µS/cm)",
    TSS = "TSS (mg/L)"
  )
}

################################################################################
# A2. MAIN-TEXT FIGURE 3b / Fig6_Combined_Loops_AllSites_3x3.png
#     FINAL CLEAN FORMAT
#
# THIS REVISION ONLY:
#   - retain all current curves, colours, axes and panel arrangement
#   - reduce NF / SHA / TTP site-title size to approximately half
#   - retain current internal loop-type text
#   - bottom-right event label uses:
#         constituent | event | year
#   - retain current compact lower legend
################################################################################

draw_loop_panel_base <- function(sel_row,
                                 show_site_title = FALSE,
                                 show_xlab = FALSE,
                                 show_ylab = FALSE) {

  mar_use <- c(
    if (show_xlab) 7.2 else 3.0,
    if (show_ylab) 8.0 else 2.8,
    if (show_site_title) 3.8 else 1.5,
    1.7
  )

  if (is.null(sel_row) || nrow(sel_row) == 0L) {

    fig6_empty_panel(
      "No eligible event",
      mar = mar_use
    )

    return(invisible(NULL))
  }

  site_name <- as.character(sel_row$site[1])
  solute_v  <- as.character(sel_row$solute[1])
  event_id  <- suppressWarnings(as.integer(sel_row$event_id[1]))
  loop_type <- as.character(sel_row$row_group[1])

  pts <- get_fig6_loop_data(
    site_name,
    event_id,
    solute_v
  )

  yr <- get_event_year(
    site_name,
    event_id
  )

  sol_col <- fig6_get_solute_col(solute_v)
  sol_lab <- fig6_get_solute_label(solute_v)

  par(
    mar = mar_use,
    mgp = c(
      4.15,
      1.30,
      0
    ),
    tcl = -0.38
  )

  if (is.null(pts) || nrow(pts) < 2L) {

    fig6_empty_panel(
      "Insufficient paired Q-C data",
      mar = mar_use
    )

    if (show_site_title) {

      mtext(
        site_name,
        side = 3,
        line = 0.85,
        font = 2,
        cex = 0.85
      )
    }

    return(invisible(NULL))
  }

  plot(
    pts$Qn,
    pts$Cn,
    type = "n",
    xlim = c(
      -0.02,
      1.02
    ),
    ylim = c(
      -0.02,
      1.02
    ),
    xlab = if (show_xlab) {
      "Normalized discharge"
    } else {
      ""
    },
    ylab = if (show_ylab) {
      "Normalized solute concentration"
    } else {
      ""
    },
    xaxt = if (show_xlab) "s" else "n",
    yaxt = if (show_ylab) "s" else "n",
    cex.lab = 2.05,
    cex.axis = 1.90,
    xaxs = "i",
    yaxs = "i",
    lwd = 1.25
  )

  # Constituent-coloured trajectory
  lines(
    pts$Qn,
    pts$Cn,
    col = sol_col,
    lwd = 5.0,
    lend = "round",
    ljoin = "round"
  )

  # Start — solid black
  points(
    pts$Qn[1],
    pts$Cn[1],
    pch = 21,
    bg = "black",
    col = "black",
    cex = 2.15,
    lwd = 2.0
  )

  # End — solid black
  points(
    tail(pts$Qn, 1),
    tail(pts$Cn, 1),
    pch = 24,
    bg = "black",
    col = "black",
    cex = 2.65,
    lwd = 2.15
  )

  # Site title — reduced to approximately half current size
  if (show_site_title) {

    mtext(
      site_name,
      side = 3,
      line = 0.85,
      font = 2,
      cex = 0.85
    )
  }

  usr <- par("usr")

  # Hysteresis type — upper-left
  text(
    usr[1] + 0.035 * diff(usr[1:2]),
    usr[4] - 0.045 * diff(usr[3:4]),
    labels = loop_type,
    adj = c(
      0,
      1
    ),
    font = 2,
    cex = 1.52,
    col = "black"
  )

  # Constituent | event | year — lower-right
  text(
    usr[2] - 0.030 * diff(usr[1:2]),
    usr[3] + 0.055 * diff(usr[3:4]),
    labels = paste0(
      sol_lab,
      " | event ",
      event_id,
      " | ",
      yr
    ),
    adj = c(
      1,
      0
    ),
    cex = 1.48,
    col = sol_col,
    font = 2
  )

  box(
    lwd = 1.30
  )

  invisible(NULL)
}

# LOOP FIGURE LEGEND

draw_fig6_loop_legend <- function() {

  par(
    mar = c(
      0,
      0.70,
      0,
      0.70
    )
  )

  plot.new()

  plot.window(
    xlim = c(
      0,
      1
    ),
    ylim = c(
      0,
      1
    )
  )

  y_leg <- 0.88

  keys <- c(
    "NO3",
    "DOC",
    "EC",
    "TSS"
  )

  x_key <- c(
    0.08,
    0.28,
    0.47,
    0.64
  )

  for (i in seq_along(keys)) {

    segments(
      x_key[i],
      y_leg,
      x_key[i] + 0.065,
      y_leg,
      col = FIG6_CONSTITUENT_COLS[keys[i]],
      lwd = 5.2
    )

    text(
      x_key[i] + 0.078,
      y_leg,
      FIG6_CONSTITUENT_LABELS[keys[i]],
      adj = c(
        0,
        0.5
      ),
      cex = 1.42
    )
  }

  # Start
  points(
    0.80,
    y_leg,
    pch = 21,
    bg = "black",
    col = "black",
    cex = 1.70,
    lwd = 1.7
  )

  text(
    0.825,
    y_leg,
    "Start",
    adj = c(
      0,
      0.5
    ),
    cex = 1.38
  )

  # End
  points(
    0.905,
    y_leg,
    pch = 24,
    bg = "black",
    col = "black",
    cex = 1.85,
    lwd = 1.5
  )

  text(
    0.932,
    y_leg,
    "End",
    adj = c(
      0,
      0.5
    ),
    cex = 1.38
  )

  invisible(NULL)
}

################################################################################
# A3. Fig6_Combined_Hydrographs_AllSites_3x3.png
#
# FINAL REVISION:
#
#   - curves, colours, scales and events unchanged
#   - retain current axes/font sizes
#   - create modest visible separation among NF / SHA / TTP columns
#   - NF:
#       discharge title moved farther left
#       constituent axis moved farther left
#       constituent title moved farther left
#   - SHA:
#       secondary concentration hierarchy shifted only slightly outward
#   - TTP:
#       secondary concentration hierarchy shifted only slightly outward
#   - site-title size reduced to approximately half
################################################################################

fig6_pretty_axis_spec <- function(x,
                                  fallback = c(0, 1),
                                  n = 5,
                                  expansion = 0.03) {

  x_num <- suppressWarnings(
    as.numeric(x)
  )

  x_num <- x_num[
    is.finite(x_num)
  ]

  if (length(x_num) == 0L) {

    raw_rng <- fallback

  } else {

    raw_rng <- range(
      x_num,
      na.rm = TRUE
    )
  }

  if (
    !all(is.finite(raw_rng)) ||
    diff(raw_rng) <= 0
  ) {

    raw_rng <- fallback
  }

  pad <- diff(raw_rng) * expansion

  if (
    !is.finite(pad) ||
    pad <= 0
  ) {

    pad <- max(
      abs(raw_rng),
      na.rm = TRUE
    ) * 0.03

    if (
      !is.finite(pad) ||
      pad <= 0
    ) {

      pad <- 0.05
    }
  }

  expanded_rng <- c(
    raw_rng[1] - pad,
    raw_rng[2] + pad
  )

  ticks <- pretty(
    expanded_rng,
    n = n
  )

  ticks <- ticks[
    is.finite(ticks)
  ]

  if (length(ticks) < 2L) {

    ticks <- expanded_rng
  }

  plot_rng <- range(
    ticks,
    na.rm = TRUE
  )

  list(
    range = plot_rng,
    ticks = ticks
  )
}

draw_hydro_panel_base <- function(sel_row,
                                  dt_min = NA_real_,
                                  show_site_title = FALSE,
                                  show_xlab = FALSE,
                                  show_ylab = FALSE,
                                  show_rain_title = FALSE) {

  if (
    is.null(sel_row) ||
    nrow(sel_row) == 0L
  ) {

    fig6_empty_panel(
      "No eligible event"
    )

    return(invisible(NULL))
  }

  site_name <- as.character(
    sel_row$site[1]
  )

  solute_v <- as.character(
    sel_row$solute[1]
  )

  event_id <- suppressWarnings(
    as.integer(
      sel_row$event_id[1]
    )
  )

  yr <- get_event_year(
    site_name,
    event_id
  )

  # COLUMN-SPECIFIC SPACING

  if (identical(
    site_name,
    "NF"
  )) {

    # NF
    #
    # Move the entire left hierarchy outward while retaining the same relative
    # spacing among:
    #    discharge title -> constituent scale -> constituent title.
    #
    # A modest right margin also creates a visible NF–SHA separation.

    discharge_title_line <- 4.65
    solute_axis_line     <- 7.40
    solute_title_line    <- 12.15

    left_margin  <- 17.6
    right_margin <- 2.20

  } else if (identical(
    site_name,
    "SHA"
  )) {

    # SHA
    # Only a small outward displacement is required.

    discharge_title_line <- 2.85
    solute_axis_line     <- 5.95
    solute_title_line    <- 10.65

    left_margin  <- 13.2
    right_margin <- 2.00

  } else {

    # TTP
    # Small outward displacement of left secondary hierarchy.
    # Keep sufficient right margin for precipitation scale/title.

    discharge_title_line <- 2.85
    solute_axis_line     <- 5.95
    solute_title_line    <- 10.65

    left_margin  <- 13.0
    right_margin <- 8.8
  }

  mar_use <- c(
    if (show_xlab) 8.7 else 4.1,
    left_margin,
    if (show_site_title) 2.9 else 1.6,
    right_margin
  )

  hydro_dat <- get_event_hydro_data(
    site_name,
    event_id
  )

  sol_dat <- get_event_series_for_solute(
    site_name,
    event_id,
    solute_v
  )

  sol_col <- fig6_get_solute_col(
    solute_v
  )

  sol_lab <- fig6_get_solute_label(
    solute_v
  )

  sol_ylab <- fig6_get_solute_axis_title(
    solute_v
  )

  par(
    mar = mar_use,
    mgp = c(
      3.70,
      1.35,
      0
    ),
    tcl = -0.40,
    xpd = NA
  )

  if (
    is.null(hydro_dat) ||
    nrow(hydro_dat) < 2L
  ) {

    fig6_empty_panel(
      "Insufficient hydro data",
      mar = mar_use
    )

    if (show_site_title) {

      mtext(
        site_name,
        side = 3,
        line = 0.72,
        font = 2,
        cex = 1.03
      )
    }

    return(invisible(NULL))
  }

  plot_dates <- hydro_dat$date

  valid_dates <- plot_dates[
    !is.na(plot_dates)
  ]

  if (length(valid_dates) < 2L) {

    fig6_empty_panel(
      "Insufficient date information",
      mar = mar_use
    )

    return(invisible(NULL))
  }

  x_rng <- range(
    valid_dates,
    na.rm = TRUE
  )

  # DISCHARGE SCALE

  q_spec <- fig6_pretty_axis_spec(
    hydro_dat$Q,
    fallback = c(
      0,
      1
    ),
    n = 5,
    expansion = 0.025
  )

  q_rng   <- q_spec$range
  q_ticks <- q_spec$ticks

  # PRIMARY DISCHARGE PANEL

  plot(
    plot_dates,
    hydro_dat$Q,
    type = "l",
    col = FIG6_DISCHARGE_COL,
    lwd = 3.9,
    xlim = x_rng,
    ylim = q_rng,
    xlab = "",
    ylab = "",
    xaxt = "n",
    yaxt = "n",
    xaxs = "i",
    yaxs = "i",
    las = 1
  )

  axis(
    side = 2,
    at = q_ticks,
    line = 0,
    las = 1,
    cex.axis = 2.15,
    col.axis = "black",
    col = "black",
    lwd = 1.30,
    lwd.ticks = 1.30
  )

  if (show_ylab) {

    mtext(
      "Discharge (m³/s)",
      side = 2,
      line = discharge_title_line,
      col = FIG6_DISCHARGE_COL,
      cex = 1.70
    )
  }

  # DATE AXIS

  if (show_xlab) {

    add_event_time_axis(
      plot_dates,
      cex.axis = 1.85
    )

    mtext(
      "Date",
      side = 1,
      line = 5.15,
      cex = 1.62,
      col = "black"
    )
  }

  # INITIAL-FLOW REFERENCE

  lines(
    plot_dates,
    hydro_dat$BF,
    col = FIG6_INITIAL_FLOW_COL,
    lwd = 3.15,
    lty = 2
  )

  # RAINFALL SCALE

  p_vals <- suppressWarnings(
    as.numeric(
      hydro_dat$P
    )
  )

  p_vals <- p_vals[
    is.finite(p_vals)
  ]

  p_max <- if (length(p_vals) > 0L) {

    max(
      p_vals,
      na.rm = TRUE
    )

  } else {

    1
  }

  if (
    !is.finite(p_max) ||
    p_max <= 0
  ) {

    p_max <- 1
  }

  p_ticks <- pretty(
    c(
      0,
      p_max
    ),
    n = 5
  )

  p_ticks <- p_ticks[
    p_ticks >= 0
  ]

  p_upper <- max(
    p_ticks,
    na.rm = TRUE
  )

  if (
    !is.finite(p_upper) ||
    p_upper <= 0
  ) {

    p_upper <- p_max
  }

  # RAINFALL OVERLAY

  par(
    new = TRUE
  )

  plot(
    plot_dates,
    hydro_dat$P,
    type = "h",
    col = FIG6_RAIN_COL,
    lwd = 2.05,
    xlim = x_rng,
    ylim = c(
      p_upper,
      0
    ),
    axes = FALSE,
    xlab = "",
    ylab = "",
    xaxs = "i",
    yaxs = "i"
  )

  axis(
    side = 4,
    at = p_ticks,
    line = 0,
    las = 1,
    cex.axis = 2.05,
    col.axis = "black",
    col = "black",
    lwd = 1.30,
    lwd.ticks = 1.30
  )

  dt_min_use <- suppressWarnings(
    as.numeric(
      dt_min
    )[1]
  )

  rainfall_axis_title <- if (
    is.finite(dt_min_use) &&
    dt_min_use > 0
  ) {

    paste0(
      "P (mm/",
      format(
        round(
          dt_min_use,
          1
        ),
        trim = TRUE
      ),
      "-min)"
    )

  } else {

    "P (mm)"
  }

  if (isTRUE(show_rain_title)) {

    mtext(
      rainfall_axis_title,
      side = 4,
      line = 5.35,
      cex = 1.58,
      col = "black"
    )
  }

  # CONSTITUENT CONCENTRATION SCALE

  if (
    !is.null(sol_dat) &&
    nrow(sol_dat) > 1L
  ) {

    c_spec <- fig6_pretty_axis_spec(
      sol_dat$C,
      fallback = c(
        0,
        1
      ),
      n = 5,
      expansion = 0.025
    )

    c_rng   <- c_spec$range
    c_ticks <- c_spec$ticks

    # CONSTITUENT OVERLAY

    par(
      new = TRUE
    )

    plot(
      sol_dat$date,
      sol_dat$C,
      type = "l",
      col = sol_col,
      lwd = 3.65,
      xlim = x_rng,
      ylim = c_rng,
      axes = FALSE,
      xlab = "",
      ylab = "",
      xaxs = "i",
      yaxs = "i"
    )

    axis(
      side = 2,
      at = c_ticks,
      line = solute_axis_line,
      las = 1,
      cex.axis = 2.05,
      col.axis = sol_col,
      col = sol_col,
      lwd = 1.30,
      lwd.ticks = 1.30
    )

    mtext(
      sol_ylab,
      side = 2,
      line = solute_title_line,
      col = sol_col,
      cex = 1.58
    )
  }

  # SITE TITLE — APPROXIMATELY HALF CURRENT SIZE

  if (show_site_title) {

    mtext(
      site_name,
      side = 3,
      line = 0.72,
      font = 2,
      cex = 1.03
    )
  }

  # EVENT LABEL

  mtext(
    paste0(
      sol_lab,
      " | event ",
      event_id,
      " | ",
      yr
    ),
    side = 1,
    line = -1.55,
    adj = 1,
    cex = 1.18,
    col = sol_col,
    font = 2
  )

  box(
    lwd = 1.10
  )

  invisible(NULL)
}

# HYDROGRAPH LEGEND

draw_bottom_hydro_legend <- function() {

  par(
    mar = c(
      0,
      0.25,
      0,
      0.25
    )
  )

  plot.new()

  plot.window(
    xlim = c(
      0,
      1
    ),
    ylim = c(
      0,
      1
    )
  )

  y0 <- 0.91

  # Discharge
  segments(
    0.025,
    y0,
    0.065,
    y0,
    col = FIG6_DISCHARGE_COL,
    lwd = 4.2
  )

  text(
    0.072,
    y0,
    "Discharge",
    adj = c(
      0,
      0.5
    ),
    cex = 1.45
  )

  # Initial-flow reference
  segments(
    0.170,
    y0,
    0.212,
    y0,
    col = FIG6_INITIAL_FLOW_COL,
    lwd = 3.3,
    lty = 2
  )

  text(
    0.220,
    y0,
    "Initial-flow reference",
    adj = c(
      0,
      0.5
    ),
    cex = 1.45
  )

  # Rainfall
  segments(
    0.455,
    y0 - 0.060,
    0.455,
    y0 + 0.060,
    col = FIG6_RAIN_COL,
    lwd = 4.0
  )

  text(
    0.468,
    y0,
    "Rainfall",
    adj = c(
      0,
      0.5
    ),
    cex = 1.45
  )

  # Constituents
  keys <- c(
    "NO3",
    "DOC",
    "EC",
    "TSS"
  )

  x2 <- c(
    0.545,
    0.655,
    0.745,
    0.835
  )

  for (i in seq_along(keys)) {

    segments(
      x2[i],
      y0,
      x2[i] + 0.028,
      y0,
      col = FIG6_CONSTITUENT_COLS[keys[i]],
      lwd = 4.2
    )

    text(
      x2[i] + 0.035,
      y0,
      FIG6_CONSTITUENT_LABELS[keys[i]],
      adj = c(
        0,
        0.5
      ),
      cex = 1.45
    )
  }

  invisible(NULL)
}

################################################################################
# A4. DEVICE RENDERING
################################################################################

fig6_sites_ordered <- c(
  "NF",
  "SHA",
  "TTP"
)

# Pipeline A — hysteresis loops

message(
  "Rendering Pipeline A: harmonised hysteresis loops grid..."
)

png(
  FIG6_LOOP_FILE,
  width = 40,
  height = 32.8,
  units = "cm",
  res = FIG6_EXPORT_DPI
)

layout(
  rbind(
    matrix(
      1:9,
      nrow = 3,
      byrow = TRUE
    ),
    c(
      10,
      10,
      10
    )
  ),
  heights = c(
    1,
    1,
    1,
    0.125
  )
)

for (r in seq_along(fig6_rows)) {

  for (c in seq_along(fig6_sites_ordered)) {

    sel_row <- fig6_selected |>
      dplyr::filter(
        .data$row_group == fig6_rows[r],
        .data$site == fig6_sites_ordered[c]
      ) |>
      dplyr::slice(1)

    draw_loop_panel_base(
      sel_row = sel_row,
      show_site_title = (r == 1),
      show_xlab = (r == 3),
      show_ylab = (c == 1)
    )
  }
}

draw_fig6_loop_legend()

grDevices::dev.off()

# Pipeline B — hydrographs
# FINAL FIX:
#   - adds real blank spacer columns between NF / SHA / TTP
#   - keeps the current panel styling unchanged
#   - preserves the legend row

message(
  "Rendering Pipeline B: harmonised multi-axis hydrographs grid..."
)

png(
  FIG6_HYDRO_FILE,
  width = 52,
  height = 35.3,
  units = "cm",
  res = FIG6_EXPORT_DPI
)

# 3 plot columns + 2 blank spacer columns
# Row 4 is the legend spanning the full width
layout(
  matrix(
    c(
      1,  0, 2,  0, 3,
      4,  0, 5,  0, 6,
      7,  0, 8,  0, 9,
      10, 10, 10, 10, 10
    ),
    nrow = 4,
    byrow = TRUE
  ),
  widths = c(
    1.00, 0.13, 1.00, 0.14, 1.00
  ),
  heights = c(
    1.00, 1.00, 1.00, 0.13
  )
)

for (r in seq_along(fig6_rows)) {

  for (c in seq_along(fig6_sites_ordered)) {

    sel_row <- fig6_selected |>
      dplyr::filter(
        .data$row_group == fig6_rows[r],
        .data$site == fig6_sites_ordered[c]
      ) |>
      dplyr::slice(1)

    draw_hydro_panel_base(
      sel_row = sel_row,
      dt_min = dt_min,
      show_site_title = (r == 1),
      show_xlab = (r == 3),
      show_ylab = (c == 1),
      show_rain_title = (c == 3)
    )
  }
}

draw_bottom_hydro_legend()

grDevices::dev.off()

message(
  "SUCCESS: harmonised multi-axis hydrograph grid generated."
)

# ========================== HI-FI HELPERS ==========================
fig7_first_available_column <- function(candidates, available_names) {
  hit <- candidates[candidates %in% available_names]
  if (length(hit) == 0L) return(NA_character_)
  hit[1L]
}

fig7_get_hi_fi_source <- function() {
  source_candidates <- c("EVS2", "EVS")

  for (object_name in source_candidates) {
    if (!exists(object_name, inherits = TRUE)) next

    candidate_data <- get(object_name, inherits = TRUE)
    if (!is.data.frame(candidate_data)) next

    if (!all(c("site", "solute") %in% names(candidate_data))) next

    has_hi <- any(c("HI", "HI_Lloyd", "HI_use") %in% names(candidate_data))
    has_fi <- any(c("FI_peak", "FI_mean") %in% names(candidate_data))

    if (has_hi && has_fi) return(candidate_data)
  }

  stop(
    paste(
      "Main Figure 3 could not find an appropriate HI-FI source table.",
      "EVS2 or EVS must contain site, solute, an HI column, and an FI column."
    ),
    call. = FALSE
  )
}

fig7_normalize_chemical_status <- function(status_value) {
  status_chr <- tolower(trimws(as.character(status_value)))

  dplyr::case_when(
    status_chr %in% c(
      "mobilization", "mobilisation", "flushing", "mobilized", "mobilised"
    ) ~ "Mobilization",
    status_chr %in% c("dilution", "diluted") ~ "Dilution",
    status_chr %in% c(
      "chemostasis", "chemostatic", "no response", "non-responsive", "nonresponsive"
    ) ~ "Chemostasis",
    TRUE ~ NA_character_
  )
}

fig7_normalize_loop_type <- function(loop_value) {
  loop_chr <- tolower(trimws(as.character(loop_value)))

  dplyr::case_when(
    loop_chr %in% c(
      "clockwise",
      "singleline+loop (clockwise)",
      "single line + loop (clockwise)"
    ) ~ "Clockwise",

    loop_chr %in% c(
      "anticlockwise",
      "anti-clockwise",
      "counter-clockwise",
      "counterclockwise",
      "singleline+loop (anticlockwise)",
      "singleline+loop (anti-clockwise)",
      "single line + loop (anticlockwise)"
    ) ~ "Anti-clockwise",

    loop_chr %in% c(
      "figure-8 / mixed",
      "figure-8",
      "figure 8",
      "eight-shaped",
      "figure-eight",
      "mixed",
      "complex/linear",
      "mixed / sequential"
    ) ~ "Figure-8 / Mixed",

    loop_chr %in% c(
      "direct",
      "direct / synchronous",
      "linear"
    ) ~ "Direct",

    TRUE ~ NA_character_
  )
}

fig7_prepare_hi_fi_data <- function(
    solute_name,
    preferred_fi_metric = c("FI_peak", "FI_mean")) {

  preferred_fi_metric <- match.arg(preferred_fi_metric)

  raw_data  <- fig7_get_hi_fi_source()
  raw_names <- names(raw_data)

  # Prefer signed Lloyd HI.
  hi_column <- fig7_first_available_column(
    candidates = c("HI", "HI_Lloyd", "HI_use"),
    available_names = raw_names
  )

  fi_candidates <- if (preferred_fi_metric == "FI_peak") {
    c("FI_peak", "FI_mean")
  } else {
    c("FI_mean", "FI_peak")
  }

  fi_column <- fig7_first_available_column(
    candidates = fi_candidates,
    available_names = raw_names
  )

  if (is.na(hi_column)) {
    stop("Main Figure 3 requires HI, HI_Lloyd, or HI_use.", call. = FALSE)
  }

  if (is.na(fi_column)) {
    stop("Main Figure 3 requires FI_peak or FI_mean.", call. = FALSE)
  }

  plot_data <- raw_data

  plot_data$HI_plot <- suppressWarnings(as.numeric(plot_data[[hi_column]]))
  plot_data$FI_plot <- suppressWarnings(as.numeric(plot_data[[fi_column]]))

  if ("ID" %in% raw_names) {
    plot_data$event_id <- suppressWarnings(as.integer(plot_data$ID))
  } else if ("event_id" %in% raw_names) {
    plot_data$event_id <- suppressWarnings(as.integer(plot_data$event_id))
  } else {
    plot_data$event_id <- seq_len(nrow(plot_data))
  }

  if ("chem_status" %in% raw_names) {
    plot_data$chemical_status <- fig7_normalize_chemical_status(plot_data$chem_status)
  } else if ("Chemical_Status" %in% raw_names) {
    plot_data$chemical_status <- fig7_normalize_chemical_status(plot_data$Chemical_Status)
  } else {
    plot_data$chemical_status <- NA_character_
  }

  status_threshold <- if (
    exists("resp_thresh", inherits = TRUE) &&
    is.finite(get("resp_thresh", inherits = TRUE))
  ) {
    as.numeric(get("resp_thresh", inherits = TRUE))
  } else {
    0.15
  }

  derived_status <- dplyr::case_when(
    plot_data$FI_plot >= status_threshold  ~ "Mobilization",
    plot_data$FI_plot <= -status_threshold ~ "Dilution",
    is.finite(plot_data$FI_plot)            ~ "Chemostasis",
    TRUE                                    ~ NA_character_
  )

  missing_status <- is.na(plot_data$chemical_status) |
    trimws(plot_data$chemical_status) == ""

  plot_data$chemical_status[missing_status] <- derived_status[missing_status]

  if ("loop_type" %in% raw_names) {
    plot_data$loop_group <- fig7_normalize_loop_type(plot_data$loop_type)
  } else if ("Loop_Type" %in% raw_names) {
    plot_data$loop_group <- fig7_normalize_loop_type(plot_data$Loop_Type)
  } else {
    plot_data$loop_group <- NA_character_
  }

  derived_loop <- dplyr::case_when(
    plot_data$HI_plot > 0.02     ~ "Clockwise",
    plot_data$HI_plot < -0.02    ~ "Anti-clockwise",
    is.finite(plot_data$HI_plot) ~ "Direct",
    TRUE                         ~ NA_character_
  )

  missing_loop <- is.na(plot_data$loop_group) |
    trimws(plot_data$loop_group) == ""

  plot_data$loop_group[missing_loop] <- derived_loop[missing_loop]

  plot_data |>
    dplyr::transmute(
      site = trimws(as.character(.data$site)),
      solute = toupper(trimws(as.character(.data$solute))),
      event_id = .data$event_id,
      HI_plot = .data$HI_plot,
      FI_plot = .data$FI_plot,
      chemical_status = .data$chemical_status,
      loop_group = .data$loop_group
    ) |>
    dplyr::filter(
      .data$solute == toupper(solute_name),
      .data$site %in% c("NF", "SHA", "TTP"),
      is.finite(.data$HI_plot),
      is.finite(.data$FI_plot)
    ) |>
    dplyr::distinct(
      .data$site,
      .data$event_id,
      .data$solute,
      .keep_all = TRUE
    ) |>
    dplyr::mutate(
      site = factor(.data$site, levels = c("NF", "SHA", "TTP")),
      chemical_status = factor(
        .data$chemical_status,
        levels = c("Mobilization", "Dilution", "Chemostasis")
      ),
      loop_group = factor(
        .data$loop_group,
        levels = c("Clockwise", "Anti-clockwise", "Figure-8 / Mixed", "Direct")
      )
    ) |>
    dplyr::arrange(.data$site, .data$event_id)
}

# Actual FI range for each constituent rather than a symmetric/global scale.
fig7_constituent_fi_limits <- function(
    fi_values,
    expansion = 0.08,
    include_zero = TRUE) {

  x <- suppressWarnings(as.numeric(fi_values))
  x <- x[is.finite(x)]

  if (length(x) == 0L) return(c(-0.1, 0.1))

  if (isTRUE(include_zero)) x <- c(x, 0)

  r <- range(x, na.rm = TRUE)

  if (!all(is.finite(r))) return(c(-0.1, 0.1))

  if (diff(r) <= 0) {
    delta <- max(abs(r[1]) * 0.10, 0.05)
    return(r + c(-delta, delta))
  }

  pad <- diff(r) * expansion
  r + c(-pad, pad)
}

# B2. ONE SOLUTE = THREE CATCHMENT PANELS

# ================= MAIN FIGURE 3 HI-FI GRID (4 x 3) =================
# FINAL TYPOGRAPHY / RESOLUTION REVISION
#
# KEEP:
#   - current 4 × 3 arrangement
#   - site-name size unchanged
#   - constituent-name size unchanged
#   - FI limits:
#       NO3 = 3
#       DOC = 15
#       EC  = 1
#       TSS = 40
#   - HI range = -0.75 to +0.75
#
# CHANGE:
#   - ordinary text / numerical values = 1.5 × current size
#   - site and constituent strip labels remain unchanged
#   - quadrant labels = 1.5 ×
#   - event-count labels = 1.5 ×
#   - axis titles = 1.5 ×
#   - axis numerical values = 1.5 ×
#   - legend text = 1.5 ×
#   - export resolution increased from 800 to 900 dpi

# Publication Figure 4 workflow uses authoritative in-memory analysis objects.
FIGDIR <- DIR_REPRO_TMP_FIG
TABDIR <- DIR_REPRO_TMP_TAB

# ================= MAIN FIGURE 4 + SUPPLEMENTARY S2 =================

################################################################################
# REVIEWER-REVISED FIGURE WORKFLOW — CLEAN FINAL VERSION
#
# Main manuscript figure:
#   Figure4.png
#   (main-text Figure 4 after promotion of the former Figure S3)
#
# Supplementary figures:
#   Figure2_Constituent_Transport_Dominance.png
#   FigureS_InitialFlow_Classes_ByCatchment.png
#
# Main Figure 4 panels:
#   a) Hysteresis strength and direction
#   b) Catchment-constituent hysteresis fingerprints
#   c) Hysteresis type occurrence
#
# Panel c hierarchy:
#   CW / ACW / F8 labels
#   horizontal grouping line
#   centred constituent name
#   centred x-axis title below all groups
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
  library(patchwork)
})

if (!exists("FIGDIR")) stop("FIGDIR is not defined.", call. = FALSE)
if (!exists("TABDIR")) stop("TABDIR is not defined.", call. = FALSE)

dir.create(FIGDIR, recursive = TRUE, showWarnings = FALSE)
dir.create(TABDIR, recursive = TRUE, showWarnings = FALSE)

required_objects <- c(
  "fig2a_population",
  "EVS2",
  "fig2d_population",
  "flow_condition_summary_by_site",
  "Table_SourceProximity_PathwayComplexity"
)

missing_objects <- required_objects[
  !vapply(required_objects, exists, logical(1), inherits = TRUE)
]

if (length(missing_objects) > 0L) {
  stop(
    "Reviewer figure workflow cannot run. Missing object(s): ",
    paste(missing_objects, collapse = ", "),
    call. = FALSE
  )
}

# 1. MANUSCRIPT-WIDE COLOUR, LABEL, AND SHAPE SYSTEM

# Constituent colours:
# Use ONLY when colour itself represents constituent identity.
CONSTITUENT_COLS <- c(
  NO3 = "#FF3030",
  DOC = "#D89B16",
  EC  = "#A64CFF",
  TSS = "#2CA02C"
)

CONSTITUENT_LEVELS <- c(
  "NO3",
  "DOC",
  "EC",
  "TSS"
)

CONSTITUENT_LABELS <- c(
  NO3 = "NO3-N",
  DOC = "DOC",
  EC  = "EC",
  TSS = "TSS"
)

# REVIEWER REVISION:
# Chemical status is NOT a constituent. Use neutral greys only.
CHEM_STATUS_COLS <- c(
  mobilization = "grey28",
  dilution     = "grey58",
  chemostasis  = "grey84"
)

# REVIEWER REVISION:
# Initial-flow class is NOT a constituent. Use neutral greys only.
FLOW_CLASS_COLS <- c(
  "Low Flow"  = "grey84",
  "Mid Flow"  = "grey58",
  "High Flow" = "grey30"
)

# REVIEWER/AUTHOR REVISION:
# Hysteresis type is NOT a constituent. The neutral palette prevents a reader
# from interpreting, for example, a clockwise colour as "NO3-N".
HYST_TYPE_COLS <- c(
  "Clockwise"     = "grey25",
  "Anticlockwise" = "grey55",
  "Mixed/Fig-8"   = "grey85"
)

HYST_TYPE_LEVELS <- c(
  "Clockwise",
  "Anticlockwise",
  "Mixed/Fig-8"
)

# Catchment is encoded by shape in Figure 4b.
CATCHMENT_SHAPES <- c(
  "Natural forest"          = 16,  # circle
  "Smallholder agriculture" = 17,  # triangle
  "Tea/tree plantation"     = 15   # square
)

# High-resolution export setting for all revised figures.
EXPORT_DPI <- 800

# 2. COMMON PUBLICATION THEME

theme_mau_figure <- function(base_size = 14) {
  ggplot2::theme_bw(base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(
        colour = "grey86",
        linewidth = 0.42
      ),

      # Strong, consistent rectangular frame in panels a, b and c.
      panel.border = ggplot2::element_rect(
        colour = "black",
        fill = NA,
        linewidth = 1.65
      ),

      # Keep axis marks clearly visible.
      axis.ticks = ggplot2::element_line(
        colour = "black",
        linewidth = 0.90
      ),
      axis.ticks.length = grid::unit(3.6, "pt"),

      # Slightly larger numerical/text labels throughout.
      axis.text = ggplot2::element_text(
        colour = "black",
        size = 12.0
      ),

      # Requested: all axis titles remain plain (not bold).
      axis.title = ggplot2::element_text(
        colour = "black",
        size = 13.4,
        face = "plain"
      ),

      legend.title = ggplot2::element_text(
        face = "bold",
        size = 11.8
      ),
      legend.text = ggplot2::element_text(
        size = 11.2
      ),
      plot.title = ggplot2::element_text(
        face = "bold",
        size = 14.8,
        hjust = 0
      ),
      plot.margin = ggplot2::margin(
        t = 8,
        r = 10,
        b = 8,
        l = 8
      )
    )
}

# 3. OUTPUT FILES

FIGURE2_STATUS_FILE <- file.path(DIR_REPRO_TMP_FIG, "Figure2_Constituent_Transport_Dominance.png")

FIGURE4A_HI_FILE <- file.path(DIR_REPRO_TMP_FIG, "Figure4a_HI_Distribution_ByConstituent.png")

FIGURE4B_FINGERPRINT_FILE <- file.path(DIR_REPRO_TMP_FIG, "Figure4b_Catchment_Constituent_Hysteresis_Fingerprints.png")

FIGURE4C_TYPE_FILE <- file.path(DIR_REPRO_TMP_FIG, "Figure4c_Hysteresis_Type_Occurrence.png")

FIGURE4_COMBINED_FILE <- file.path(DIR_MAIN_FIG_PNG, "Figure4.png")

FIGURES_FLOW_FILE <- file.path(DIR_SUPP_FIG_PNG, "FigureS2.png")

# 4. SUPPLEMENTARY FIGURE — CONSTITUENT TRANSPORT DOMINANCE
# Standalone replacement for the original transport-dominance panel.
# Analytical population is unchanged: fig2a_population.

FIG2_CONSTITUENT_ORDER <- c(
  "DOC",
  "EC",
  "NO3",
  "TSS"
)

TRANSPORT_STATUS_COLS <- c(
  mobilization = "#343A40",
  dilution     = "#8D99AE",
  chemostasis  = "#D9D9D9"
)

fig2_status_summary <- fig2a_population %>%
  dplyr::transmute(
    solute = toupper(trimws(as.character(solute))),
    chem_status = tolower(trimws(as.character(chem_status)))
  ) %>%
  dplyr::filter(
    solute %in% CONSTITUENT_LEVELS,
    chem_status %in% c(
      "mobilization",
      "dilution",
      "chemostasis"
    )
  ) %>%
  dplyr::count(
    solute,
    chem_status,
    name = "n"
  ) %>%
  tidyr::complete(
    solute = FIG2_CONSTITUENT_ORDER,
    chem_status = c(
      "mobilization",
      "dilution",
      "chemostasis"
    ),
    fill = list(n = 0L)
  ) %>%
  dplyr::group_by(solute) %>%
  dplyr::mutate(
    total = sum(n),
    proportion = dplyr::if_else(
      total > 0,
      n / total,
      NA_real_
    ),
    percent = 100 * proportion,
    segment_label = dplyr::if_else(
      is.finite(percent) & percent >= 5,
      paste0(round(percent), "%"),
      ""
    )
  ) %>%
  dplyr::ungroup() %>%
  dplyr::mutate(
    solute = factor(
      solute,
      levels = FIG2_CONSTITUENT_ORDER
    ),
    chem_status = factor(
      chem_status,
      levels = c(
        "mobilization",
        "dilution",
        "chemostasis"
      )
    )
  )

utils::write.csv(
  fig2_status_summary,
  file.path(
    TABDIR,
    "Table_Figure2_ConstituentTransportDominance.csv"
  ),
  row.names = FALSE
)

fig2_constituent_labels <- tibble::tibble(
  solute = factor(
    FIG2_CONSTITUENT_ORDER,
    levels = FIG2_CONSTITUENT_ORDER
  ),
  label = unname(
    CONSTITUENT_LABELS[
      FIG2_CONSTITUENT_ORDER
    ]
  )
)

p_transport_dominance <- ggplot2::ggplot(
  fig2_status_summary,
  ggplot2::aes(
    x = solute,
    y = proportion,
    fill = chem_status
  )
) +
  ggplot2::geom_col(
    width = 0.58,
    colour = "white",
    linewidth = 0.95
  ) +
  ggplot2::geom_text(
    ggplot2::aes(
      label = segment_label
    ),
    position = ggplot2::position_stack(vjust = 0.5),
    colour = "black",
    size = 4.3,
    fontface = "bold"
  ) +
  ggplot2::geom_text(
    data = fig2_constituent_labels,
    ggplot2::aes(
      x = solute,
      y = -0.055,
      label = label,
      colour = solute
    ),
    inherit.aes = FALSE,
    size = 4.5,
    fontface = "bold",
    vjust = 1
  ) +
  ggplot2::scale_colour_manual(
    values = CONSTITUENT_COLS,
    guide = "none",
    drop = FALSE
  ) +
  ggplot2::scale_y_continuous(
    breaks = seq(0, 1, by = 0.25),
    labels = scales::label_percent(accuracy = 1),
    expand = c(0, 0)
  ) +
  ggplot2::scale_x_discrete(
    limits = FIG2_CONSTITUENT_ORDER,
    labels = rep("", length(FIG2_CONSTITUENT_ORDER)),
    drop = FALSE
  ) +
  ggplot2::scale_fill_manual(
    values = TRANSPORT_STATUS_COLS,
    breaks = c(
      "mobilization",
      "dilution",
      "chemostasis"
    ),
    labels = c(
      "Mobilisation",
      "Dilution",
      "Chemostasis"
    ),
    name = "Chemical status",
    drop = FALSE
  ) +
  ggplot2::coord_cartesian(
    ylim = c(0, 1),
    clip = "off"
  ) +
  ggplot2::labs(
    title = "Constituent transport dominance",
    x = "Constituent",
    y = "Proportion of classifiable event–constituent records"
  ) +
  theme_mau_figure(base_size = 14) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    axis.text.x = ggplot2::element_blank(),
    axis.ticks.x = ggplot2::element_blank(),
    axis.text.y = ggplot2::element_text(
      colour = "black",
      size = 13.6
    ),
    axis.title.x = ggplot2::element_text(
      face = "plain",
      size = 12.6,
      margin = ggplot2::margin(t = 10)
    ),
    axis.title.y = ggplot2::element_text(
      face = "plain",
      size = 12.6,
      margin = ggplot2::margin(r = 10)
    ),
    legend.position = "bottom",
    legend.justification = "center",
    legend.box.just = "center",
    legend.box = "horizontal",
    plot.margin = ggplot2::margin(
      t = 8,
      r = 10,
      b = 24,
      l = 8
    )
  )

ggplot2::ggsave(
  filename = FIGURE2_STATUS_FILE,
  plot = p_transport_dominance,
  width = 7.2,
  height = 5.8,
  units = "in",
  dpi = EXPORT_DPI,
  bg = "white",
  limitsize = FALSE
)

# 5. MAIN FIGURE 4a — HYSTERESIS STRENGTH AND DIRECTION
# Final requested format:
#   - observed min-to-max whiskers
#   - bold box/whisker/reference lines
#   - larger text and numerical labels
#   - constituent names in their constituent colours
#   - constituent names OUTSIDE the panel, directly below visible x-axis ticks
#   - axis titles plain (not bold)

fig3_hi_data <- EVS2 %>%
  dplyr::mutate(
    solute = toupper(
      trimws(
        as.character(solute)
      )
    ),
    HI_use = suppressWarnings(
      as.numeric(HI_use)
    )
  ) %>%
  dplyr::filter(
    solute %in% CONSTITUENT_LEVELS,
    is.finite(HI_use)
  ) %>%
  dplyr::mutate(
    solute = factor(
      solute,
      levels = CONSTITUENT_LEVELS
    )
  )

fig3_hi_minmax <- fig3_hi_data %>%
  dplyr::group_by(solute) %>%
  dplyr::summarise(
    HI_min = min(
      HI_use,
      na.rm = TRUE
    ),
    HI_max = max(
      HI_use,
      na.rm = TRUE
    ),
    .groups = "drop"
  )

# Native tick labels are suppressed because standard ggplot2 cannot colour
# individual discrete tick labels independently. These coloured labels are
# drawn just below the panel frame, while the actual tick marks remain visible.
fig3a_constituent_labels <- tibble::tibble(
  solute = factor(
    CONSTITUENT_LEVELS,
    levels = CONSTITUENT_LEVELS
  ),
  y = -1.085,
  label = unname(
    CONSTITUENT_LABELS[
      CONSTITUENT_LEVELS
    ]
  )
)

p_hysteresis_strength <- ggplot2::ggplot(
  fig3_hi_data,
  ggplot2::aes(
    x = solute,
    y = HI_use,
    fill = solute,
    colour = solute
  )
) +
  ggplot2::geom_hline(
    yintercept = 0,
    linetype = "dashed",
    colour = "grey45",
    linewidth = 1.00
  ) +
  ggplot2::geom_errorbar(
    data = fig3_hi_minmax,
    ggplot2::aes(
      x = solute,
      ymin = HI_min,
      ymax = HI_max,
      colour = solute
    ),
    inherit.aes = FALSE,
    width = 0.18,
    linewidth = 1.10
  ) +
  ggplot2::geom_boxplot(
    width = 0.48,
    outlier.shape = NA,
    alpha = 0.20,
    linewidth = 1.05,
    coef = Inf
  ) +
  ggplot2::geom_jitter(
    width = 0.13,
    height = 0,
    size = 1.75,
    alpha = 0.50,
    stroke = 0
  ) +
  ggplot2::scale_fill_manual(
    values = CONSTITUENT_COLS,
    guide = "none",
    drop = FALSE
  ) +
  ggplot2::scale_colour_manual(
    values = CONSTITUENT_COLS,
    guide = "none",
    drop = FALSE
  ) +

  # Keep the four x positions and tick marks; suppress only native black labels.
  ggplot2::scale_x_discrete(
    labels = rep(
      "",
      length(CONSTITUENT_LEVELS)
    ),
    drop = FALSE
  ) +

  # No y-scale limit here: coloured constituent names are drawn below -1.
  ggplot2::scale_y_continuous(
    breaks = seq(
      -1,
      1,
      by = 0.5
    ),
    expand = ggplot2::expansion(
      mult = c(
        0.02,
        0.02
      )
    )
  ) +
  ggplot2::annotate(
    "text",
    x = 0.60,
    y = 0.84,
    label = "Clockwise / earlier (+)",
    hjust = 0,
    size = 5.00,
    colour = "grey30",
    fontface = "italic"
  ) +
  ggplot2::annotate(
    "text",
    x = 0.60,
    y = -0.84,
    label = "Anticlockwise / delayed (-)",
    hjust = 0,
    size = 5.00,
    colour = "grey30",
    fontface = "italic"
  ) +

  # Coloured names are outside the rectangle and aligned with the x ticks.
  ggplot2::geom_text(
    data = fig3a_constituent_labels,
    ggplot2::aes(
      x = solute,
      y = y,
      label = label,
      colour = solute
    ),
    inherit.aes = FALSE,
    size = 5.00,
    fontface = "bold",
    hjust = 0.5,
    vjust = 1
  ) +
  ggplot2::labs(
    title = "a) Hysteresis strength and direction",
    x = "Constituent",
    y = expression(
      "Lloyd hysteresis index (" *
        HI[Lloyd] *
        ")"
    )
  ) +

  # The analytical panel remains exactly -1 to +1; clip off allows the coloured
  # labels to be displayed beneath the bottom frame.
  ggplot2::coord_cartesian(
    ylim = c(
      -1,
      1
    ),
    clip = "off"
  ) +
  theme_mau_figure(
    base_size = 14
  ) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),

    axis.text.x = ggplot2::element_blank(),

    # IMPORTANT: retain the four visible x-axis marks.
    axis.ticks.x = ggplot2::element_line(
      colour = "black",
      linewidth = 0.95
    ),
    axis.ticks.length.x = grid::unit(
      4.0,
      "pt"
    ),

    axis.text.y = ggplot2::element_text(
      size = 12.4
    ),
    axis.title.x = ggplot2::element_text(
      face = "plain",
      size = 13.8,
      margin = ggplot2::margin(
        t = 6
      )
    ),
    axis.title.y = ggplot2::element_text(
      face = "plain",
      size = 13.8,
      margin = ggplot2::margin(
        r = 10
      )
    ),

    # tick -> coloured constituent name -> centred x-axis title
    plot.margin = ggplot2::margin(
      t = 8,
      r = 10,
      b = 38,
      l = 8
    )
  )

ggplot2::ggsave(
  filename = FIGURE4A_HI_FILE,
  plot = p_hysteresis_strength,
  width = 8.0,
  height = 6.7,
  units = "in",
  dpi = EXPORT_DPI,
  bg = "white",
  limitsize = FALSE
)
# 6. MAIN FIGURE 4b — CATCHMENT–CONSTITUENT HYSTERESIS FINGERPRINTS
# Final requested format:
#   - constituent = colour
#   - catchment = shape
#   - HI_Lloyd display range = -0.50 to +0.50
#   - bold rectangular panel frame
#   - visible x- and y-axis tick marks
#   - bold dashed/dotted reference lines
#   - slightly larger text and numerical labels
#   - axis titles plain (not bold)

fig3_fingerprint_data <- Table_SourceProximity_PathwayComplexity %>%
  dplyr::filter(
    is.finite(
      plotted_x_median_HI
    ),
    is.finite(
      plotted_y_median_loop_area
    )
  ) %>%
  dplyr::mutate(
    site = factor(
      as.character(site),
      levels = c(
        "NF",
        "SHA",
        "TTP"
      )
    ),

    solute = factor(
      toupper(
        trimws(
          as.character(solute)
        )
      ),
      levels = CONSTITUENT_LEVELS
    ),

    land_use_type = factor(
      as.character(
        land_use_type
      ),
      levels = c(
        "Natural forest",
        "Smallholder agriculture",
        "Tea/tree plantation"
      )
    )
  ) %>%
  dplyr::filter(
    !is.na(solute),
    !is.na(land_use_type)
  )

if (nrow(fig3_fingerprint_data) == 0L) {
  stop(
    "No valid coordinates are available for Figure 2b.",
    call. = FALSE
  )
}

# Audit points outside requested HI display range

fig3b_outside_requested_range <- fig3_fingerprint_data %>%
  dplyr::filter(
    plotted_x_median_HI < -0.50 |
      plotted_x_median_HI > 0.50
  )

if (nrow(fig3b_outside_requested_range) > 0L) {

  warning(
    nrow(fig3b_outside_requested_range),
    " fingerprint point(s) fall outside the requested median HI_Lloyd ",
    "display range [-0.50, +0.50] and will not be shown."
  )

  utils::write.csv(
    fig3b_outside_requested_range,
    file.path(
      TABDIR,
      "Audit_Figure4b_PointsOutside_HI_Minus0.50_Plus0.50.csv"
    ),
    row.names = FALSE
  )
}

# Horizontal reference and annotation positions

overall_loop_area_median <- stats::median(
  fig3_fingerprint_data$plotted_y_median_loop_area,
  na.rm = TRUE
)

fingerprint_y_max <- max(
  fig3_fingerprint_data$plotted_y_median_loop_area,
  na.rm = TRUE
)

fingerprint_y_min <- min(
  fig3_fingerprint_data$plotted_y_median_loop_area,
  na.rm = TRUE
)

fingerprint_y_range <- (
  fingerprint_y_max -
    fingerprint_y_min
)

if (
  !is.finite(fingerprint_y_range) ||
  fingerprint_y_range <= 0
) {
  fingerprint_y_range <- 1
}

fingerprint_label_y <- (
  fingerprint_y_max +
    0.045 *
    fingerprint_y_range
)

# Plot

gg_proximity_grid_v2 <- ggplot2::ggplot(
  fig3_fingerprint_data,
  ggplot2::aes(
    x = plotted_x_median_HI,
    y = plotted_y_median_loop_area,
    colour = solute,
    shape = land_use_type
  )
) +

  # Bold vertical zero-reference line
  ggplot2::geom_vline(
    xintercept = 0,
    linetype = "dashed",
    colour = "grey55",
    linewidth = 1.00
  ) +

  # Bold horizontal median loop-area reference
  ggplot2::geom_hline(
    yintercept = overall_loop_area_median,
    linetype = "dotted",
    colour = "grey58",
    linewidth = 0.90
  ) +

  ggplot2::geom_point(
    size = 5.30,
    stroke = 1.25,
    alpha = 1
  ) +

# Constituent colours

ggplot2::scale_colour_manual(
  values = CONSTITUENT_COLS,
  breaks = CONSTITUENT_LEVELS,
  labels = CONSTITUENT_LABELS,
  name = "Constituent",
  drop = FALSE
) +

# Catchment shapes

ggplot2::scale_shape_manual(
  values = CATCHMENT_SHAPES,
  breaks = names(
    CATCHMENT_SHAPES
  ),
  labels = names(
    CATCHMENT_SHAPES
  ),
  name = "Catchment",
  drop = FALSE
) +

# X axis: requested -0.50 to +0.50 range

ggplot2::scale_x_continuous(
  limits = c(
    -0.50,
    0.50
  ),
  breaks = seq(
    -0.50,
    0.50,
    by = 0.25
  ),
  expand = ggplot2::expansion(
    mult = c(
      0.01,
      0.01
    )
  )
) +

# Y axis

ggplot2::scale_y_continuous(
  expand = ggplot2::expansion(
    mult = c(
      0.06,
      0.15
    )
  )
) +

# Direction annotations

ggplot2::annotate(
  "text",
  x = -0.48,
  y = fingerprint_label_y,
  label =  "Delayed (-)",
  hjust = 0,
  vjust = 0,
  size = 3.90,
  colour = "grey30",
  fontface = "italic"
) +

  ggplot2::annotate(
    "text",
    x = 0.48,
    y = fingerprint_label_y,
    label = "Earlier (+)",
    hjust = 1,
    vjust = 0,
    size = 3.90,
    colour = "grey30",
    fontface = "italic"
  ) +

# Titles

ggplot2::labs(
  title = "b) Catchment-constituent hysteresis fingerprints",

  x = expression(
    "Median Lloyd hysteresis index (" *
      HI[Lloyd] *
      ")"
  ),

  y = expression(
    "Median normalised loop area (" *
      A[loop] *
      ")"
  )
) +

# Legend configuration

ggplot2::guides(
  colour = ggplot2::guide_legend(
    order = 1,
    override.aes = list(
      shape = 16,
      size = 4.80
    )
  ),

  shape = ggplot2::guide_legend(
    order = 2,
    override.aes = list(
      colour = "black",
      size = 4.80
    )
  )
) +

  theme_mau_figure(
    base_size = 14
  ) +

  ggplot2::theme(

    # Legend

    legend.position = "bottom",
    legend.justification = "center",
    legend.box.just = "center",
    legend.box = "horizontal",

    legend.margin = ggplot2::margin(
      t = 3,
      r = 0,
      b = 2,
      l = 0
    ),

    # IMPORTANT:
    # Force panel b rectangular frame to match / exceed the visual weight
    # of panels a and c.

    panel.border = ggplot2::element_rect(
      colour = "black",
      fill = NA,
      linewidth = 2.00
    ),

    # Clearly visible axis marks

    axis.ticks = ggplot2::element_line(
      colour = "black",
      linewidth = 1.00
    ),

    axis.ticks.length = grid::unit(
      4.0,
      "pt"
    ),

    # Numerical values

    axis.text.x = ggplot2::element_text(
      colour = "black",
      size = 12.4
    ),

    axis.text.y = ggplot2::element_text(
      colour = "black",
      size = 12.4
    ),

    # Axis titles — plain, not bold

    axis.title.x = ggplot2::element_text(
      face = "plain",
      size = 13.8,
      margin = ggplot2::margin(
        t = 10
      )
    ),

    axis.title.y = ggplot2::element_text(
      face = "plain",
      size = 13.8,
      margin = ggplot2::margin(
        r = 10
      )
    )
  )

# Export

ggplot2::ggsave(
  filename = FIGURE4B_FINGERPRINT_FILE,
  plot = gg_proximity_grid_v2,
  width = 8.1,
  height = 6.7,
  units = "in",
  dpi = EXPORT_DPI,
  bg = "white",
  limitsize = FALSE
)
# 7. MAIN FIGURE 4c — HYSTERESIS TYPE OCCURRENCE
# FINAL CLEAN VERSION
#
# Hierarchical x-axis:
#
#       CW     ACW     F8
#             NO3-N
#
# followed by DOC, EC and TSS groups, then one centred x-axis title:
#
#                    Constituent
#
# IMPORTANT:
# The custom x-axis hierarchy is drawn in a separate aligned axis band.
# This prevents the CW/ACW/F8 labels, grouping lines, constituent names,
# and global "Constituent" title from being clipped at the bottom.

# 7.1 Detect hysteresis-type column

detect_hysteresis_type_col <- function(dat) {

  candidates <- c(
    "loop_type",
    "hysteresis_type",
    "loop_class",
    "geometry_class",
    "hyst_type",
    "loop_geometry",
    "direction_class",
    "HI_class"
  )

  found <- intersect(
    candidates,
    names(dat)
  )

  if (length(found) == 0L) {
    stop(
      "No hysteresis-type column was found in fig2d_population. Expected one of: ",
      paste(
        candidates,
        collapse = ", "
      ),
      call. = FALSE
    )
  }

  found[1]
}

# 7.2 Standardise hysteresis-type terminology

standardise_hysteresis_type <- function(x) {

  z <- tolower(
    trimws(
      as.character(x)
    )
  )

  dplyr::case_when(

    grepl(
      "anti.?clock|anticlock|counter",
      z
    ) ~ "Anticlockwise",

    grepl(
      "figure.?[- ]?8|figure.?eight|eight.?shaped|mixed",
      z
    ) ~ "Mixed/Fig-8",

    grepl(
      "(^|[^a-z])clockwise([^a-z]|$)|^clockwise$",
      z
    ) ~ "Clockwise",

    TRUE ~ NA_character_
  )
}

# 7.3 Identify source column

hyst_type_col <- detect_hysteresis_type_col(
  fig2d_population
)

# 7.4 Prepare raw loop-type data

fig3c_loop_raw <- fig2d_population %>%
  dplyr::transmute(

    solute = toupper(
      trimws(
        as.character(solute)
      )
    ),

    original_loop_type = as.character(
      .data[[hyst_type_col]]
    ),

    hysteresis_type = standardise_hysteresis_type(
      .data[[hyst_type_col]]
    )
  )

# 7.5 Audit unmapped loop types

fig3c_unmapped_loop_types <- fig3c_loop_raw %>%
  dplyr::filter(
    solute %in% CONSTITUENT_LEVELS,
    !is.na(original_loop_type),
    nzchar(
      trimws(
        original_loop_type
      )
    ),
    is.na(hysteresis_type)
  ) %>%
  dplyr::count(
    original_loop_type,
    name = "n"
  ) %>%
  dplyr::arrange(
    dplyr::desc(n)
  )

if (nrow(fig3c_unmapped_loop_types) > 0L) {

  utils::write.csv(
    fig3c_unmapped_loop_types,
    file.path(
      TABDIR,
      "Audit_Figure4c_Unmapped_LoopTypes.csv"
    ),
    row.names = FALSE
  )

  warning(
    "Panel c: ",
    sum(fig3c_unmapped_loop_types$n),
    " loop-type record(s) were not mapped to Clockwise, Anticlockwise, ",
    "or Mixed/Fig-8. See Audit_Figure4c_Unmapped_LoopTypes.csv."
  )
}

# 7.6 Hysteresis-type order and abbreviations

FIG3C_TYPE_ORDER <- c(
  "Clockwise",
  "Anticlockwise",
  "Mixed/Fig-8"
)

FIG3C_TYPE_SHORT <- c(
  "Clockwise"     = "CW",
  "Anticlockwise" = "ACW",
  "Mixed/Fig-8"   = "F8"
)

# 7.7 Summarise hysteresis occurrence by constituent

fig3c_looptype_summary <- fig3c_loop_raw %>%
  dplyr::filter(
    solute %in% CONSTITUENT_LEVELS,
    hysteresis_type %in% FIG3C_TYPE_ORDER
  ) %>%
  dplyr::count(
    solute,
    hysteresis_type,
    name = "n"
  ) %>%
  tidyr::complete(
    solute = CONSTITUENT_LEVELS,
    hysteresis_type = FIG3C_TYPE_ORDER,
    fill = list(
      n = 0L
    )
  ) %>%
  dplyr::group_by(solute) %>%
  dplyr::mutate(

    total = sum(n),

    proportion = dplyr::if_else(
      total > 0,
      n / total,
      NA_real_
    ),

    percent = 100 * proportion
  ) %>%
  dplyr::ungroup()

utils::write.csv(
  fig3c_looptype_summary,
  file.path(
    TABDIR,
    "Table_Figure4c_HysteresisTypeOccurrence_ByConstituent.csv"
  ),
  row.names = FALSE
)

# 7.8 Bar geometry

# Centre spacing equals bar width so CW–ACW–F8 touch within each constituent.
FIG3C_BAR_WIDTH <- 0.20

FIG3C_BAR_OFFSET <- c(
  "Clockwise"     = -0.20,
  "Anticlockwise" =  0.00,
  "Mixed/Fig-8"   =  0.20
)

fig3c_plot_data <- fig3c_looptype_summary %>%
  dplyr::mutate(

    solute = factor(
      solute,
      levels = CONSTITUENT_LEVELS
    ),

    hysteresis_type = factor(
      hysteresis_type,
      levels = FIG3C_TYPE_ORDER
    ),

    solute_number = as.numeric(
      solute
    ),

    x_position = solute_number + unname(
      FIG3C_BAR_OFFSET[
        as.character(
          hysteresis_type
        )
      ]
    ),

    type_short = unname(
      FIG3C_TYPE_SHORT[
        as.character(
          hysteresis_type
        )
      ]
    ),

    percent_label = paste0(
      round(percent),
      "%"
    ),

    # Very short bars receive the percentage immediately above the bar.
    # Other percentages remain vertically positioned close to bar tops.
    label_y = dplyr::case_when(
      proportion <= 0.035 ~ proportion + 0.018,
      TRUE ~ proportion - 0.028
    )
  )

# 7.9 Constituent grouping information

fig3c_constituent_labels <- tibble::tibble(

  solute = factor(
    CONSTITUENT_LEVELS,
    levels = CONSTITUENT_LEVELS
  ),

  x_position = seq_along(
    CONSTITUENT_LEVELS
  ),

  x_start = seq_along(
    CONSTITUENT_LEVELS
  ) - 0.30,

  x_end = seq_along(
    CONSTITUENT_LEVELS
  ) + 0.30,

  label = unname(
    CONSTITUENT_LABELS[
      CONSTITUENT_LEVELS
    ]
  )
)

# 7.10 MAIN BARPLOT
# No negative-y annotations are used in this component.
# The analytical panel therefore remains cleanly bounded at 0–75%.

p_hysteresis_type_main <- ggplot2::ggplot(
  fig3c_plot_data,
  ggplot2::aes(
    x = x_position,
    y = proportion,
    fill = solute
  )
) +

  # Touching bars within each constituent group.
  ggplot2::geom_col(
    width = FIG3C_BAR_WIDTH,
    colour = "white",
    linewidth = 0.55
  ) +

  # Vertical percentages near bar tops.
  #  ggplot2::geom_text(
  #    ggplot2::aes(
  #      y = label_y,
  #      label = percent_label
  #    ),
  #    angle = 90,
  #    size = 4.95,�#    fontface = "bold",
  #    colour = "black",
  #    vjust = 0.5,
  #    hjust = 0.5
  #  ) +

  # Internal hysteresis-type explanation.
  ggplot2::annotate(
    "text",
    x = 2.5,
    y = 0.680,
    label = "CW = Clockwise    ACW = Anticlockwise    F8 = Mixed/Fig-8",
    size = 4.25,
    fontface = "bold",
    colour = "grey20",
    hjust = 0.5,
    vjust = 1
  ) +

  ggplot2::scale_fill_manual(
    values = CONSTITUENT_COLS,
    guide = "none",
    drop = FALSE
  ) +

  ggplot2::scale_x_continuous(
    breaks = NULL,
    limits = c(
      0.55,
      4.45
    ),
    expand = c(
      0,
      0
    )
  ) +

  ggplot2::scale_y_continuous(
    limits = c(
      0,
      0.75
    ),
    breaks = c(
      0,
      0.25,
      0.50,
      0.75
    ),
    labels = scales::label_percent(
      accuracy = 1
    ),
    expand = c(
      0,
      0
    )
  ) +

  ggplot2::labs(
    title = "c) Hysteresis type occurrence",
    x = NULL,
    y = "Geometry-resolved responsive events (%)"
  ) +

  theme_mau_figure(
    base_size = 14
  ) +

  ggplot2::theme(

    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),

    axis.text.x = ggplot2::element_blank(),
    axis.ticks.x = ggplot2::element_blank(),
    axis.title.x = ggplot2::element_blank(),

    axis.text.y = ggplot2::element_text(
      colour = "black",
      size = 12.4
    ),

    axis.title.y = ggplot2::element_text(
      face = "plain",
      size = 13.8,
      margin = ggplot2::margin(
        r = 10
      )
    ),

    legend.position = "none",

    # No large bottom margin is needed because the custom hierarchy
    # is now a separate plot directly beneath this panel.
    plot.margin = ggplot2::margin(
      t = 2,
      r = 10,
      b = 0,
      l = 8
    )
  )

# 7.11 CUSTOM HIERARCHICAL X-AXIS BAND
#
#       CW       ACW       F8
#               NO3-N
#
# followed by corresponding DOC, EC and TSS groups
#
#                   Constituent
#
# This separate band prevents clipping and provides clearer vertical separation
# between CW/ACW/F8, the grouping line, constituent names, and the x-axis title.

p_hysteresis_type_axis <- ggplot2::ggplot() +

# First hierarchy: CW / ACW / F8

ggplot2::geom_text(
  data = fig3c_plot_data,
  ggplot2::aes(
    x = x_position,
    y = 0.82,
    label = type_short
  ),
  inherit.aes = FALSE,
  size = 3.65,
  colour = "grey15",
  fontface = "bold",
  hjust = 0.5,
  vjust = 0.5
) +

# Horizontal grouping line

ggplot2::geom_segment(
  data = fig3c_constituent_labels,
  ggplot2::aes(
    x = x_start,
    xend = x_end,
    y = 0.54,
    yend = 0.54
  ),
  inherit.aes = FALSE,
  colour = "black",
  linewidth = 1.05,
  lineend = "butt"
) +

# Second hierarchy: coloured constituent name

ggplot2::geom_text(
  data = fig3c_constituent_labels,
  ggplot2::aes(
    x = x_position,
    y = 0.24,
    label = label,
    colour = solute
  ),
  inherit.aes = FALSE,
  size = 5.00,
  fontface = "bold",
  hjust = 0.5,
  vjust = 0.5
) +

# Global x-axis title

ggplot2::annotate(
  "text",
  x = 2.5,
  y = 0.05,
  label = "Constituent",
  size = 4.60,
  fontface = "plain",
  colour = "black",
  hjust = 0.5,
  vjust = 0.5
) +

  ggplot2::scale_colour_manual(
    values = CONSTITUENT_COLS,
    guide = "none",
    drop = FALSE
  ) +

  # Same x-range as the main barplot so every label is perfectly aligned.
  ggplot2::scale_x_continuous(
    limits = c(
      0.55,
      4.45
    ),
    expand = c(
      0,
      0
    )
  ) +

  ggplot2::scale_y_continuous(
    limits = c(
      0,
      1
    ),
    expand = c(
      0,
      0
    )
  ) +

  ggplot2::coord_cartesian(
    clip = "off"
  ) +

  ggplot2::theme_void(
    base_size = 14
  ) +

  ggplot2::theme(
    legend.position = "none",

    plot.margin = ggplot2::margin(
      t = 0,
      r = 10,
      b = 2,
      l = 8
    )
  )

# 7.12 COMBINE BARPLOT + HIERARCHICAL X-AXIS BAND

p_hysteresis_type_occurrence <- (
  p_hysteresis_type_main /
    p_hysteresis_type_axis
) +
  patchwork::plot_layout(
    heights = c(
      1.00,
      0.16
    )
  )

# 7.13 EXPORT STANDALONE PANEL c

ggplot2::ggsave(
  filename = FIGURE4C_TYPE_FILE,
  plot = p_hysteresis_type_occurrence,
  width = 9.2,
  height = 7.0,
  units = "in",
  dpi = EXPORT_DPI,
  bg = "white",
  limitsize = FALSE
)

# 8. COMBINED MAIN FIGURE 4 — THREE SUBFIGURES
# Upper row:
#   a) Hysteresis strength and direction
#   b) Catchment-constituent hysteresis fingerprints
#
# Shared Constituent + Catchment legend remains centred below panels a and b.
#
# Lower row:
#   c) Hysteresis type occurrence

Figure4_TopRow <- (
  p_hysteresis_strength |
    gg_proximity_grid_v2
) +
  patchwork::plot_layout(
    widths = c(
      1.00,
      1.00
    ),
    guides = "collect"
  ) &
  ggplot2::theme(

    legend.position = "bottom",
    legend.direction = "horizontal",
    legend.justification = "center",
    legend.box.just = "center",
    legend.box = "horizontal",

    legend.margin = ggplot2::margin(
      t = 0,
      r = 0,
      b = 0,
      l = 0
    ),

    legend.box.spacing = grid::unit(
      0.5,
      "pt"
    )
  )

# Final three-panel synthesis

Figure4_Hysteresis_Synthesis <- (
  Figure4_TopRow /
    p_hysteresis_type_occurrence
) +
  patchwork::plot_layout(
    heights = c(
      1.00,
      0.80
    )
  )

# Export combined figure

ggplot2::ggsave(
  filename = FIGURE4_COMBINED_FILE,
  plot = Figure4_Hysteresis_Synthesis,
  width = 15.6,
  height = 12.5,
  units = "in",
  dpi = EXPORT_DPI,
  bg = "white",
  limitsize = FALSE
)

# 9. SUPPLEMENTARY FIGURE — INITIAL-FLOW CONDITIONS
# Standalone replacement for the original panel C.
#
# IMPORTANT:
# - The underlying flow-condition calculation is unchanged.
# - The original visual logic is retained:
#       Low flow  = blue
#       Mid flow  = orange
#       High flow = red
# - Counts and whole-number percentages are retained inside each segment.

FLOW_CLASS_COLS <- c(
  "Low Flow"  = "#92C5DE",
  "Mid Flow"  = "#FDAE61",
  "High Flow" = "#D73027"
)

flow_plot_dat_reviewer <- flow_condition_summary_by_site %>%
  dplyr::mutate(

    site = factor(
      as.character(site),
      levels = c(
        "NF",
        "SHA",
        "TTP"
      )
    ),

    # Keep this level order so the visual stack is:
    # bottom = High Flow
    # middle = Mid Flow
    # top    = Low Flow
    flow_group = factor(
      as.character(flow_group),
      levels = c(
        "Low Flow",
        "Mid Flow",
        "High Flow"
      )
    ),

    percent_whole = round(
      percent
    ),

    label = paste0(
      n_events,
      " events\n",
      percent_whole,
      "%"
    )
  ) %>%
  dplyr::filter(
    !is.na(site),
    !is.na(flow_group)
  )

p_flow_condition <- ggplot2::ggplot(
  flow_plot_dat_reviewer,
  ggplot2::aes(
    x = site,
    y = percent,
    fill = flow_group
  )
) +

  ggplot2::geom_col(
    width = 0.58,
    colour = "black",
    linewidth = 0.55
  ) +

  ggplot2::geom_text(
    ggplot2::aes(
      label = label
    ),
    position = ggplot2::position_stack(
      vjust = 0.5
    ),
    size = 4.0,
    colour = "black",
    lineheight = 0.92
  ) +

  ggplot2::scale_y_continuous(
    limits = c(
      0,
      100
    ),
    breaks = seq(
      0,
      100,
      by = 20
    ),
    labels = function(x) {
      paste0(
        x,
        "%"
      )
    },
    expand = c(
      0,
      0
    )
  ) +

  ggplot2::scale_fill_manual(
    values = FLOW_CLASS_COLS,
    breaks = c(
      "Low Flow",
      "Mid Flow",
      "High Flow"
    ),
    labels = c(
      "Low flow",
      "Mid flow",
      "High flow"
    ),
    name = "Initial-flow class",
    drop = FALSE
  ) +

  ggplot2::labs(
    title = "Initial-flow conditions relative to the long-term flow-duration curve",
    x = "Catchment",
    y = "Proportion of valid events (%)"
  ) +

  theme_mau_figure(
    base_size = 14
  ) +

  ggplot2::theme(

    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),

    axis.text.x = ggplot2::element_text(
      colour = "black",
      face = "bold",
      size = 12.4
    ),

    axis.text.y = ggplot2::element_text(
      colour = "black",
      size = 12.4
    ),

    axis.title.x = ggplot2::element_text(
      face = "plain",
      size = 13.8,
      margin = ggplot2::margin(
        t = 8
      )
    ),

    axis.title.y = ggplot2::element_text(
      face = "plain",
      size = 13.8,
      margin = ggplot2::margin(
        r = 10
      )
    ),

    legend.position = "bottom",
    legend.justification = "center",
    legend.box.just = "center",
    legend.box = "horizontal"
  )

ggplot2::ggsave(
  filename = FIGURES_FLOW_FILE,
  plot = p_flow_condition,
  width = 6.8,
  height = 5.7,
  units = "in",
  dpi = EXPORT_DPI,
  bg = "white",
  limitsize = FALSE
)

# 10. REVIEWER OUTPUT AUDIT

reviewer_figure_outputs <- tibble::tibble(

  figure_role = c(
    "Supplementary constituent transport dominance",
    "Main Figure 4 panel a",
    "Main Figure 4 panel b",
    "Main Figure 4 panel c",
    "Main Figure 4 combined",
    "Supplementary initial-flow figure"
  ),

  output_file = c(
    FIGURE2_STATUS_FILE,
    FIGURE4A_HI_FILE,
    FIGURE4B_FINGERPRINT_FILE,
    FIGURE4C_TYPE_FILE,
    FIGURE4_COMBINED_FILE,
    FIGURES_FLOW_FILE
  )
) %>%
  dplyr::mutate(

    exists = file.exists(
      output_file
    ),

    size_bytes = dplyr::if_else(
      exists,
      as.numeric(
        file.info(
          output_file
        )$size
      ),
      NA_real_
    )
  )

utils::write.csv(
  reviewer_figure_outputs,
  file.path(
    TABDIR,
    "Audit_FINAL_Reviewer_Revised_Figure_Outputs.csv"
  ),
  row.names = FALSE
)

print(
  reviewer_figure_outputs
)

if (
  !all(
    reviewer_figure_outputs$exists
  )
) {
  stop(
    "One or more reviewer-revised figure outputs were not created.",
    call. = FALSE
  )
}

# 11. COMPLETION MESSAGES

message(
  "\n=== REVIEWER-REVISED FIGURE WORKFLOW COMPLETED ==="
)

message(
  "Supplementary constituent transport dominance: ",
  FIGURE2_STATUS_FILE
)

message(
  "Main Figure 4 panel a: ",
  FIGURE4A_HI_FILE
)

message(
  "Main Figure 4 panel b: ",
  FIGURE4B_FINGERPRINT_FILE
)

message(
  "Main Figure 4 panel c: ",
  FIGURE4C_TYPE_FILE
)

message(
  "Main Figure 4 combined: ",
  FIGURE4_COMBINED_FILE
)

message(
  "Supplementary flow figure: ",
  FIGURES_FLOW_FILE
)

# 12. LEGACY FOUR-PANEL COMPOSITE — INTENTIONALLY DISABLED

message(
  "Legacy four-panel hydrochemical synthesis intentionally not generated. ",
  "Use Figure4.png as manuscript Figure 4, ",
  "with Figure2_Constituent_Transport_Dominance.png and ",
  "FigureS_InitialFlow_Classes_ByCatchment.png in the Supplementary Information."
)

################################################################################
# END REVIEWER-REVISED THREE-PANEL FIGURE WORKFLOW
################################################################################

FIGDIR <- DIR_REPRO_TMP_FIG
TABDIR <- DIR_REPRO_TMP_TAB
DIR_PAPER_FIG <- DIR_REPRO_TMP_FIG

# MAIN FIGURE 5 - 3 x 3 REPRESENTATIVE EVENT HYDROGRAPHS
#
# Required upstream objects/functions:
#   fig6_selected
#   fig6_rows
#   fig6_sites_ordered
#   get_event_hydro_data()
#   get_event_series_for_solute()
#   get_event_year()
#   DIR_MAIN_FIG_PNG
#   DIR_MAIN_FIG_ALT
#
# Final styling:
#   Discharge              = black solid
#   Initial-flow reference = blue dashed
#   NO3-N                  = red
#   DOC                    = orange
#   EC                     = purple
#   TSS                    = green
#   Rainfall               = grey

# 1. FIGURE COLOURS AND SAFE LABELS

FINAL_CONSTITUENT_COLS <- c(
  NO3 = "#FF3030",
  DOC = "#D89B16",
  EC  = "#A64CFF",
  TSS = "#2CA02C"
)

FINAL_CONSTITUENT_LABELS <- c(
  NO3 = "NO3-N",
  DOC = "DOC",
  EC  = "EC",
  TSS = "TSS"
)

FIG4_DISCHARGE_COL    <- "black"
FIG4_INITIAL_FLOW_COL <- "#1557B0"
FIG4_RAIN_COL         <- "grey45"

# 2. SHARED PUBLICATION SIZES

# Y-axis numerical values remain unchanged.
FIG4_CEX_AXIS <- 2.82

# X-axis date/time marked values only:
# reduction in the x-axis font.
FIG4_CEX_XAXIS <- FIG4_CEX_AXIS * 0.56

# Discharge title, constituent titles, rainfall title,
# bottom-right event annotation, and legend text.
FIG4_CEX_TEXT   <- 1.82
FIG4_CEX_LEGEND <- 2.82
FIG4_CEX_EVENT  <- 2.22

# Site titles deliberately remain unchanged.
FIG4_CEX_SITE <- 1.55

# Line widths
FIG4_LWD_DISCHARGE   <- 6.30
FIG4_LWD_REFERENCE   <- 5.50
FIG4_LWD_CONSTITUENT <- 6.05
FIG4_LWD_RAIN        <- 2.90

# 3. GENERAL SAFE RANGE HELPER

final_safe_range <- function(
    x,
    include_zero = FALSE,
    expansion = 0.08,
    fallback = c(0, 1)
) {

  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]

  if (length(x) == 0L) {
    return(fallback)
  }

  r <- range(x, na.rm = TRUE)

  if (isTRUE(include_zero)) {
    r <- range(c(r, 0), na.rm = TRUE)
  }

  if (!all(is.finite(r))) {
    return(fallback)
  }

  if (diff(r) == 0) {

    delta <- if (r[1] == 0) {
      1
    } else {
      max(
        abs(r[1]) * 0.08,
        .Machine$double.eps
      )
    }

    r <- r + c(
      -delta,
      delta
    )
  }

  pad <- diff(r) * expansion

  r + c(
    -pad,
    pad
  )
}

# 4. CONSTITUENT COLOUR HELPER

final_solute_colour <- function(solute_name) {

  solute_name <- toupper(
    trimws(
      as.character(solute_name)[1]
    )
  )

  value <- unname(
    FINAL_CONSTITUENT_COLS[solute_name]
  )

  if (
    length(value) == 0L ||
    is.na(value)
  ) {
    "grey25"
  } else {
    value
  }
}

# 5. CONSTITUENT TEXT LABEL HELPER

final_solute_label <- function(solute_name) {

  solute_name <- toupper(
    trimws(
      as.character(solute_name)[1]
    )
  )

  value <- unname(
    FINAL_CONSTITUENT_LABELS[solute_name]
  )

  if (
    length(value) == 0L ||
    is.na(value)
  ) {
    solute_name
  } else {
    value
  }
}

# 6. ENCODING-SAFE CONSTITUENT AXIS TITLES
#
# IMPORTANT:
# EC uses plotmath mu.
# There is no literal micro-symbol character in this code.

final_solute_axis_label <- function(solute_name) {

  solute_name <- toupper(
    trimws(
      as.character(solute_name)[1]
    )
  )

  switch(
    solute_name,

    NO3 = expression(
      "NO3-N [mg N L"^{-1}*"]"
    ),

    DOC = expression(
      "DOC [mg L"^{-1}*"]"
    ),

    EC = expression(
      "EC ["*mu*"S cm"^{-1}*"]"
    ),

    TSS = expression(
      "TSS [mg L"^{-1}*"]"
    ),

    expression("")
  )
}

# 7. TRUE SCALED-AXIS HELPER
#
# The axis limits are defined by genuine nice-number breaks.
# Therefore the first and last marks are real scale values.

fig4_make_pretty_scale <- function(
    x,
    n = 4,
    include_zero = FALSE
) {

  x <- suppressWarnings(
    as.numeric(x)
  )

  x <- x[
    is.finite(x)
  ]

  if (length(x) == 0L) {
    x <- c(0, 1)
  }

  if (isTRUE(include_zero)) {
    x <- c(
      x,
      0
    )
  }

  r <- range(
    x,
    na.rm = TRUE
  )

  if (!all(is.finite(r))) {
    r <- c(0, 1)
  }

  if (diff(r) == 0) {

    d <- if (r[1] == 0) {
      1
    } else {
      max(
        abs(r[1]) * 0.08,
        .Machine$double.eps
      )
    }

    r <- r + c(
      -d,
      d
    )
  }

  br <- pretty(
    r,
    n = n
  )

  br <- sort(
    unique(
      br[
        is.finite(br)
      ]
    )
  )

  if (
    length(br) < 2L ||
    min(br) > r[1] ||
    max(br) < r[2]
  ) {

    br <- pretty(
      c(
        r[1],
        r[2]
      ),
      n = max(
        5,
        n + 1
      )
    )

    br <- sort(
      unique(
        br[
          is.finite(br)
        ]
      )
    )
  }

  if (length(br) < 2L) {
    br <- r
  }

  list(
    limits = range(br),
    breaks = br
  )
}

# 8. X-AXIS DATE/TIME HELPER
#
# Uses exactly 3 evenly spaced tick positions so that the date/time labels
# remain clearly separated in the narrow bottom-row panels.

fig4_add_event_time_axis <- function(dates, cex.axis = FIG4_CEX_XAXIS) {

  if (length(dates) < 2L || all(is.na(dates))) {
    axis(side = 1, cex.axis = cex.axis)
    return(invisible(NULL))
  }

  dates <- as.POSIXct(dates)
  x_rng <- range(dates, na.rm = TRUE)

  tz_use <- attr(dates, "tzone")
  if (is.null(tz_use) || length(tz_use) == 0L ||
      is.na(tz_use[1]) || !nzchar(tz_use[1])) {
    tz_use <- "Africa/Nairobi"
  } else {
    tz_use <- tz_use[1]
  }

  # Use exactly three evenly spaced positions.
  #
  # The first and last labels are moved slightly inside the plotting range.
  # This prevents labels from crowding the panel edges and ensures that all
  # three date/time labels have approximately equal horizontal separation.

  event_duration <- as.numeric(difftime(x_rng[2], x_rng[1], units = "secs"))

  at_dates <- as.POSIXct(
    as.numeric(x_rng[1]) + event_duration * c(0.10, 0.50, 0.90),
    origin = "1970-01-01",
    tz = tz_use
  )

  # Tick marks.
  axis.POSIXct(
    side = 1,
    at = at_dates,
    labels = FALSE,
    tcl = -0.40,
    lwd = 1.35,
    lwd.ticks = 1.35
  )

  # Date row.
  mtext(
    format(at_dates, "%d %b"),
    side = 1,
    at = as.numeric(at_dates),
    line = 1.65,                    # position of DATE row
    cex = cex.axis,
    col = "black"
  )

  # Time row.
  mtext(
    format(at_dates, "%H:%M"),
    side = 1,
    at = as.numeric(at_dates),
    line = 3.85,                        # position of TIME row
    cex = cex.axis,
    col = "black"
  )

  invisible(NULL)
}
# 9. TRUE CONTINUOUS CONSTITUENT SECONDARY AXIS
#
# This is ONE axis only.
# No artificial endpoint tick marks are added.
#
# Its first and last ticks are genuine numeric scale endpoints,
# because the constituent plot itself uses:
#
#     ylim = c_limits
#
# where:
#
#     c_limits = range(c_breaks)
#

fig4_draw_solute_axis <- function(
    c_limits,
    c_breaks,
    solute_col,
    axis_line,
    cex.axis = FIG4_CEX_AXIS
) {

  c_breaks <- sort(
    unique(
      c_breaks[
        is.finite(c_breaks)
      ]
    )
  )

  axis(
    side = 2,
    at = c_breaks,
    labels = format(
      c_breaks,
      trim = TRUE
    ),
    line = axis_line,
    las = 1,
    col = solute_col,
    col.axis = solute_col,
    col.ticks = solute_col,
    cex.axis = cex.axis,
    lwd = 1.50,
    lwd.ticks = 1.50,
    tcl = -0.46
  )

  invisible(NULL)
}

# 10. INDIVIDUAL HYDROGRAPH PANEL

draw_hydro_panel_final <- function(
    sel_row,
    dt_min = NA_real_,
    show_site_title = FALSE,
    show_xlab = FALSE,
    show_rain_title = FALSE,
    show_discharge_title = FALSE,
    column_index = 1L
) {

  # Column-specific axis placement
  #
  # Total horizontal margins remain equal between columns.
  # This keeps all nine plot rectangles equal in width.

  if (column_index == 1L) {

    # NF
    discharge_title_line <- 5.90
    solute_axis_line     <- 10.20 # 9.45  -> 10.20 Move constituent numerical axis and title slightly farther
    solute_title_line    <- 15.60  #14.55 -> 15.60

    left_margin  <- 21.4
    right_margin <- 5.0

  } else if (column_index == 2L) {

    # SHA
    discharge_title_line <- 2.85
    solute_axis_line     <- 7.45
    solute_title_line    <- 12.45

    left_margin  <- 16.2
    right_margin <- 10.2

  } else {

    # TTP
    discharge_title_line <- 2.85
    solute_axis_line     <- 7.45
    solute_title_line    <- 12.45

    left_margin  <- 16.2
    right_margin <- 10.2
  }

  # Row-specific margins

  if (show_site_title) {

    bottom_margin <- 3.2
    top_margin    <- 5.2 # slightly more space above the top-row panels

  } else if (show_xlab) {

    bottom_margin <- 10.6
    top_margin    <- 1.8

  } else {

    bottom_margin <- 3.2
    top_margin    <- 1.8
  }

  par(
    mar = c(
      bottom_margin,
      left_margin,
      top_margin,
      right_margin
    ),
    mgp = c(
      2.8,
      0.90,
      0
    ),
    tcl = -0.32,
    xaxs = "i"
  )

  # Empty panel handling

  if (
    is.null(sel_row) ||
    nrow(sel_row) == 0L
  ) {

    plot.new()

    plot.window(
      xlim = c(0, 1),
      ylim = c(0, 1)
    )

    text(
      0.5,
      0.5,
      "No eligible event",
      cex = 1.25,
      col = "grey35"
    )

    box(
      lwd = 1.15
    )

    return(
      invisible(NULL)
    )
  }

  # Event identifiers

  site_name <- as.character(
    sel_row$site[1]
  )

  solute_v <- toupper(
    as.character(
      sel_row$solute[1]
    )
  )

  event_id <- suppressWarnings(
    as.integer(
      sel_row$event_id[1]
    )
  )

  event_year <- get_event_year(
    site_name,
    event_id
  )

  solute_col <- final_solute_colour(
    solute_v
  )

  solute_lab <- final_solute_label(
    solute_v
  )

  # Retrieve event data

  hydro_dat <- get_event_hydro_data(
    site_name,
    event_id
  )

  sol_dat <- get_event_series_for_solute(
    site_name,
    event_id,
    solute_v
  )

  if (
    is.null(hydro_dat) ||
    nrow(hydro_dat) < 2L
  ) {

    plot.new()

    plot.window(
      xlim = c(0, 1),
      ylim = c(0, 1)
    )

    text(
      0.5,
      0.5,
      "Insufficient hydrograph data",
      cex = 1.20,
      col = "grey35"
    )

    box(
      lwd = 1.15
    )

    return(
      invisible(NULL)
    )
  }

  # Shared x-range

  x_rng <- range(
    hydro_dat$date,
    na.rm = TRUE
  )

  # PRIMARY Y AXIS - DISCHARGE

  q_rng <- final_safe_range(
    hydro_dat$Q,
    include_zero = FALSE,
    expansion = 0.08
  )

  plot(
    hydro_dat$date,
    hydro_dat$Q,

    type = "l",

    xlim = x_rng,
    ylim = q_rng,

    xaxs = "i",
    yaxs = "r",

    col = FIG4_DISCHARGE_COL,
    lwd = FIG4_LWD_DISCHARGE,

    xlab = "",
    ylab = "",

    xaxt = "n",
    yaxt = "n"
  )

  # Discharge numerical values on every panel.
  # Same font size as x-axis date/time labels.
  axis(
    side = 2,
    las = 1,
    cex.axis = FIG4_CEX_AXIS,
    lwd = 1.40,
    lwd.ticks = 1.35,
    tcl = -0.38
  )

  # Discharge title only in NF column.
  if (isTRUE(show_discharge_title)) {

    mtext(
      expression(
        Discharge~(m^3~s^-1)
      ),
      side = 2,
      line = discharge_title_line,
      cex = FIG4_CEX_TEXT,
      col = "black"
    )
  }

  # INITIAL-FLOW REFERENCE

  if (
    "BF" %in% names(hydro_dat) &&
    length(hydro_dat$BF) == nrow(hydro_dat)
  ) {

    lines(
      hydro_dat$date,
      hydro_dat$BF,
      col = FIG4_INITIAL_FLOW_COL,
      lwd = FIG4_LWD_REFERENCE,
      lty = 2
    )
  }

  # RAINFALL - RIGHT AXIS

  p_values <- suppressWarnings(
    as.numeric(
      hydro_dat$P
    )
  )

  p_values[
    !is.finite(p_values)
  ] <- NA_real_

  rain_scale <- fig4_make_pretty_scale(
    p_values,
    n = 4,
    include_zero = TRUE
  )

  p_breaks <- rain_scale$breaks[
    rain_scale$breaks >= 0
  ]

  p_axis_max <- max(
    p_breaks,
    na.rm = TRUE
  )

  if (
    !is.finite(p_axis_max) ||
    p_axis_max <= 0
  ) {

    p_axis_max <- 1

    p_breaks <- c(
      0,
      0.5,
      1
    )
  }

  par(
    new = TRUE
  )

  plot(
    hydro_dat$date,
    p_values,

    type = "h",

    xlim = x_rng,

    # Inverted rainfall scale:
    # zero rainfall sits exactly on the top plot border.
    ylim = c(
      p_axis_max,
      0
    ),

    xaxs = "i",
    yaxs = "i",

    col = FIG4_RAIN_COL,
    lwd = FIG4_LWD_RAIN,

    axes = FALSE,
    xlab = "",
    ylab = ""
  )

  # Rainfall numerical values
  axis(
    side = 4,
    at = p_breaks,
    labels = format(
      p_breaks,
      trim = TRUE
    ),
    las = 1,
    cex.axis = FIG4_CEX_AXIS,
    lwd = 1.40,
    lwd.ticks = 1.40,
    tcl = -0.38
  )

  if (isTRUE(show_rain_title)) {

    dt_min_use <- suppressWarnings(
      as.numeric(dt_min)[1]
    )

    if (
      !is.finite(dt_min_use) ||
      dt_min_use <= 0
    ) {

      if (nrow(hydro_dat) >= 2L) {

        dt_min_use <- as.numeric(
          stats::median(
            diff(
              hydro_dat$date
            )
          ),
          units = "mins"
        )
      }
    }

    rain_lab <- if (
      is.finite(dt_min_use) &&
      dt_min_use > 0
    ) {

      paste0(
        "P [mm/",
        format(
          round(
            dt_min_use,
            1
          ),
          trim = TRUE
        ),
        "-min]"
      )

    } else {

      "P [mm/10-min]"
    }

    mtext(
      rain_lab,
      side = 4,
      line = 6.45,
      cex = FIG4_CEX_TEXT,
      col = "black"
    )
  }

  # SECONDARY Y AXIS - CONSTITUENT CONCENTRATION

  if (
    !is.null(sol_dat) &&
    nrow(sol_dat) > 1L
  ) {

    keep_sol <- (
      !is.na(sol_dat$date) &
        is.finite(
          suppressWarnings(
            as.numeric(
              sol_dat$C
            )
          )
        )
    )

    sol_dat <- sol_dat[
      keep_sol,
      ,
      drop = FALSE
    ]

    if (nrow(sol_dat) > 1L) {

      # One true scaled constituent axis.
      c_scale <- fig4_make_pretty_scale(
        sol_dat$C,
        n = 4,
        include_zero = FALSE
      )

      par(
        new = TRUE
      )

      plot(
        sol_dat$date,
        sol_dat$C,

        type = "l",

        xlim = x_rng,

        # Exact limits of the real secondary scale.
        ylim = c_scale$limits,

        xaxs = "i",
        yaxs = "i",

        col = solute_col,
        lwd = FIG4_LWD_CONSTITUENT,

        axes = FALSE,
        xlab = "",
        ylab = ""
      )

      # One continuous scaled line.
      fig4_draw_solute_axis(
        c_limits = c_scale$limits,
        c_breaks = c_scale$breaks,
        solute_col = solute_col,
        axis_line = solute_axis_line,
        cex.axis = FIG4_CEX_AXIS
      )

      # Constituent axis title.
      mtext(
        final_solute_axis_label(
          solute_v
        ),
        side = 2,
        line = solute_title_line,
        cex = FIG4_CEX_TEXT,
        col = solute_col
      )
    }
  }

  # X AXIS - BOTTOM ROW ONLY

  if (isTRUE(show_xlab)) {

    fig4_add_event_time_axis(
      hydro_dat$date,
      cex.axis = FIG4_CEX_XAXIS
    )

    mtext(
      "Date",
      side = 1,
      line = 6.85,
      cex = FIG4_CEX_TEXT,
      col = "black"
    )
  }

  # SITE TITLE

  if (isTRUE(show_site_title)) {

    mtext(
      site_name,
      side = 3,
      line = 0.80,
      font = 2,
      cex = FIG4_CEX_SITE
    )
  }

  # BOTTOM-RIGHT EVENT ANNOTATION

  usr <- par("usr")

  text(
    usr[2] -
      0.025 *
      diff(
        usr[1:2]
      ),

    usr[3] +
      0.040 *
      diff(
        usr[3:4]
      ),

    labels = paste0(
      solute_lab,
      " | event ",
      event_id,
      " | ",
      event_year
    ),

    adj = c(
      1,
      0
    ),

    cex = FIG4_CEX_EVENT,
    col = solute_col,
    font = 2
  )

  # Final plotting rectangle.
  box(
    lwd = 1.25
  )

  invisible(NULL)
}

# 11. SHARED BOTTOM LEGEND

draw_hydro_legend_final <- function() {

  par(mar = c(0.02, 0.40, 0.10, 0.40), xaxs = "i", yaxs = "i")
  plot.new()
  plot.window(xlim = c(0, 1), ylim = c(0, 1))

  y0 <- 0.72

  # Legend structure
  #
  # The entire legend width is calculated first and then centred.
  # This removes the unnecessarily large spaces around:
  #   Initial-flow reference -> NO3-N
  #   TSS -> Rainfall

  legend_labels <- c("Discharge", "Initial-flow reference", "NO3-N", "DOC", "EC", "TSS", "Rainfall")

  legend_cols <- c(
    FIG4_DISCHARGE_COL, FIG4_INITIAL_FLOW_COL,
    final_solute_colour("NO3"), final_solute_colour("DOC"),
    final_solute_colour("EC"), final_solute_colour("TSS"),
    FIG4_RAIN_COL
  )

  legend_lwd <- c(
    FIG4_LWD_DISCHARGE, FIG4_LWD_REFERENCE,
    rep(FIG4_LWD_CONSTITUENT, 4), FIG4_LWD_RAIN
  )

  legend_lty <- c(1, 2, 1, 1, 1, 1, 1)

  # Horizontal line length for ordinary legend symbols.
  # Rainfall uses a vertical stroke, so it requires less horizontal space.
  symbol_width <- c(rep(0.038, 6), 0.012)

  # Small space between each symbol and its corresponding text.
  symbol_text_gap <- 0.007

  # Compact gap between successive complete legend entries.
  item_gap <- 0.014

  # Calculate actual text widths in plotting coordinates.
  text_width <- strwidth(legend_labels, cex = FIG4_CEX_LEGEND, units = "user")

  # Width occupied by each complete legend item.
  item_width <- symbol_width + symbol_text_gap + text_width

  # Calculate the total width of the complete legend.
  total_width <- sum(item_width) + item_gap * (length(legend_labels) - 1)

  # Starting position selected so that the WHOLE legend is centred.
  x_cursor <- (1 - total_width) / 2

  # Draw each legend item

  for (ii in seq_along(legend_labels)) {

    # Rainfall is represented using a vertical grey line.
    if (legend_labels[ii] == "Rainfall") {

      rain_x <- x_cursor + symbol_width[ii] / 2

      segments(
        rain_x, y0 - 0.105, rain_x, y0 + 0.105,
        col = legend_cols[ii], lwd = legend_lwd[ii]
      )

    } else {

      # All other legend entries use horizontal line symbols.
      segments(
        x_cursor, y0, x_cursor + symbol_width[ii], y0,
        col = legend_cols[ii], lwd = legend_lwd[ii], lty = legend_lty[ii]
      )
    }

    # Draw the legend text immediately after the symbol.
    text(
      x_cursor + symbol_width[ii] + symbol_text_gap, y0,
      legend_labels[ii],
      adj = c(0, 0.5),
      cex = FIG4_CEX_LEGEND,
      col = "black"
    )

    # Advance horizontally to the next complete legend item.
    x_cursor <- x_cursor + item_width[ii] + item_gap
  }

  invisible(NULL)
}

# 12. COMPLETE 3 x 3 FIGURE

draw_complete_figure5 <- function() {

  # Wider panel columns.
  #
  # Spacer columns remain between NF-SHA and SHA-TTP to prevent the enlarged
  # secondary axes and their labels from overlapping adjacent panels.

  layout(
    matrix(
      c(
        1,  0,  2,  0,  3,
        4,  0,  5,  0,  6,
        7,  0,  8,  0,  9,
        10, 10, 10, 10, 10
      ),
      nrow = 4,
      byrow = TRUE
    ),

    widths = c(
      1.12,
      0.09,
      1.12,
      0.06,
      1.12
    ),

    heights = c(
      1.08,
      1.00,
      1.30,
      0.18
    )
  )

  for (
    r in seq_along(
      fig6_rows
    )
  ) {

    for (
      c in seq_along(
        fig6_sites_ordered
      )
    ) {

      sel_row <- fig6_selected %>%
        dplyr::filter(
          row_group == fig6_rows[r],
          site == fig6_sites_ordered[c]
        ) %>%
        dplyr::slice(1)

      dt_min_panel <- if (
        exists(
          "dt_min",
          inherits = TRUE
        )
      ) {

        suppressWarnings(
          as.numeric(
            get(
              "dt_min",
              inherits = TRUE
            )
          )[1]
        )

      } else {

        NA_real_
      }

      draw_hydro_panel_final(
        sel_row = sel_row,
        dt_min = dt_min_panel,

        show_site_title = (
          r == 1
        ),

        show_xlab = (
          r == 3
        ),

        show_rain_title = (
          c == 3
        ),

        # Discharge TITLE only in first/NF column.
        # Numeric discharge scale remains on every panel.
        show_discharge_title = (
          c == 1
        ),

        column_index = c
      )
    }
  }

  draw_hydro_legend_final()

  invisible(NULL)
}

# 13. EXPORT PNG AND TIFF

if (
  exists("fig6_selected") &&
  exists("fig6_rows") &&
  exists("fig6_sites_ordered") &&
  exists("get_event_hydro_data") &&
  exists("get_event_series_for_solute") &&
  exists("get_event_year")
) {

  dir.create(
    DIR_MAIN_FIG_PNG,
    recursive = TRUE,
    showWarnings = FALSE
  )

  dir.create(
    DIR_MAIN_FIG_ALT,
    recursive = TRUE,
    showWarnings = FALSE
  )

  # PNG

  FIG5_PNG_FILE <- file.path(
    DIR_MAIN_FIG_PNG,
    "Figure5.png"
  )

  png(
    filename = FIG5_PNG_FILE,

    # Increased horizontal length of the nine rectangular panels.
    width = 62,
    height = 43,

    units = "cm",
    res = 900
  )

  draw_complete_figure5()

  dev.off()

  # TIFF

  FIG5_TIFF_FILE <- file.path(
    DIR_MAIN_FIG_ALT,
    "Figure5.tiff"
  )

  tiff(
    filename = FIG5_TIFF_FILE,

    width = 62,
    height = 43,

    units = "cm",
    res = 900,
    compression = "lzw"
  )

  draw_complete_figure5()

  dev.off()

  message(
    "Updated Figure 5 PNG: ",
    FIG5_PNG_FILE
  )

  message(
    "Updated Figure 5 TIFF: ",
    FIG5_TIFF_FILE
  )

} else {

  warning(
    paste(
      "Figure 5 was not rendered because one or more",
      "required upstream objects/functions are missing."
    ),
    call. = FALSE
  )
}

# 2. MAIN FIGURE 6 - 3 x 3 HYSTERESIS LOOPS
#    Final publication version with selective annotation repositioning
#    Output: Figure6.png

if (exists("fig6_selected") && exists("fig6_rows") && exists("fig6_sites_ordered") &&
    exists("get_fig6_loop_data") && exists("get_event_year")) {

  draw_loop_panel_final <- function(sel_row, show_site_title = FALSE,
                                    show_xlab = FALSE, show_ylab = FALSE) {

    mar_use <- c(if (show_xlab) 5.4 else 2.6,
                 if (show_ylab) 5.8 else 2.6,
                 if (show_site_title) 3.0 else 1.4, 1.4)
    par(mar = mar_use)

    if (is.null(sel_row) || nrow(sel_row) == 0L) {
      plot.new(); plot.window(xlim = c(0, 1), ylim = c(0, 1))
      text(0.5, 0.5, "No eligible event", cex = 1.25, col = "grey35")
      box(lwd = 1.1); return(invisible(NULL))
    }

    site_name  <- as.character(sel_row$site[1])
    solute_v   <- toupper(as.character(sel_row$solute[1]))
    event_id   <- suppressWarnings(as.integer(sel_row$event_id[1]))
    loop_type  <- as.character(sel_row$row_group[1])
    event_year <- get_event_year(site_name, event_id)

    solute_col <- final_solute_colour(solute_v)
    solute_lab <- final_solute_label(solute_v)
    pts <- get_fig6_loop_data(site_name, event_id, solute_v)

    if (is.null(pts) || nrow(pts) < 2L) {
      plot.new(); plot.window(xlim = c(0, 1), ylim = c(0, 1))
      text(0.5, 0.5, "Insufficient paired Q-C data", cex = 1.20, col = "grey35")
      box(lwd = 1.1); return(invisible(NULL))
    }

    plot(pts$Qn, pts$Cn, type = "n",
         xlim = c(-0.02, 1.02), ylim = c(-0.02, 1.02),
         xlab = if (show_xlab) "Normalized discharge" else "",
         ylab = if (show_ylab) "Normalized solute concentration" else "",
         xaxt = if (show_xlab) "s" else "n",
         yaxt = if (show_ylab) "s" else "n",
         cex.lab = 1.80,            # font size of the marked axis values: 0.0, 0.2, 0.4, ...
         cex.axis = 1.60,            # font size of the x- and y-axis titles
         xaxs = "i", yaxs = "i")

    # Loop curve and start/end markers
    lines(pts$Qn, pts$Cn, col = solute_col, lwd = 5.2,
          lend = "round", ljoin = "round")

    points(pts$Qn[1], pts$Cn[1], pch = 21, bg = "white",
           col = "black", cex = 1.45, lwd = 1.25)

    points(tail(pts$Qn, 1), tail(pts$Cn, 1), pch = 24, bg = "black",
           col = "black", cex = 1.50, lwd = 1.15)

    if (show_site_title)
      mtext(site_name, side = 3, line = 0.75, font = 2, cex = 1.65)

    usr <- par("usr"); xr <- diff(usr[1:2]); yr <- diff(usr[3:4])

    top_left     <- c(usr[1] + 0.03*xr, usr[4] - 0.04*yr)
    top_right    <- c(usr[2] - 0.03*xr, usr[4] - 0.04*yr)
    bottom_left  <- c(usr[1] + 0.03*xr, usr[3] + 0.04*yr)
    bottom_right <- c(usr[2] - 0.03*xr, usr[3] + 0.04*yr)

    # Defaults
    loop_xy  <- top_left;     loop_adj  <- c(0, 1)
    event_xy <- bottom_right; event_adj <- c(1, 0)

    # SHA / DOC / Figure-8: event annotation -> bottom-left
    if (site_name == "SHA" && solute_v == "DOC" && loop_type == "Figure-8") {
      event_xy <- bottom_left; event_adj <- c(0, 0)
    }

    # NF / DOC / Anti-clockwise: loop title -> top-right
    if (site_name == "NF" && solute_v == "DOC" && loop_type == "Anti-clockwise") {
      loop_xy <- top_right; loop_adj <- c(1, 1)
    }

    # SHA / NO3 / Clockwise: loop title -> top-right; event -> bottom-left
    if (site_name == "SHA" && solute_v == "NO3" && loop_type == "Clockwise") {
      loop_xy <- top_right; loop_adj <- c(1, 1)
      event_xy <- bottom_left; event_adj <- c(0, 0)
    }

    # TTP / NO3 / Clockwise: loop title -> bottom-left
    if (site_name == "TTP" && solute_v == "NO3" && loop_type == "Clockwise") {
      loop_xy <- bottom_left; loop_adj <- c(0, 0)
    }

    # Loop type and event details
    text(loop_xy[1], loop_xy[2], labels = loop_type,
         adj = loop_adj, cex = 1.35, font = 2)

    text(event_xy[1], event_xy[2],
         labels = paste0(solute_lab, " | event ", event_id, " | ", event_year),
         adj = event_adj, cex = 1.35, col = solute_col, font = 2)

    box(lwd = 1.2)
    invisible(NULL)
  }

  draw_loop_legend_final <- function() {
    par(mar = c(0.2, 0.4, 0.2, 0.4))
    plot.new(); plot.window(xlim = c(0, 1), ylim = c(0, 1))

    y <- 0.52
    sol_seq <- c("NO3", "DOC", "EC", "TSS")
    x_seq   <- c(0.07, 0.22, 0.36, 0.49)

    for (ii in seq_along(sol_seq)) {
      segments(x_seq[ii], y, x_seq[ii] + 0.050, y,
               col = final_solute_colour(sol_seq[ii]), lwd = 4.0)
      text(x_seq[ii] + 0.060, y, final_solute_label(sol_seq[ii]),
           adj = c(0, 0.5), cex = 1.15)
    }

    points(0.71, y, pch = 21, bg = "white", col = "black",
           cex = 1.45, lwd = 1.15)
    text(0.735, y, "Start", adj = c(0, 0.5), cex = 1.15)

    points(0.84, y, pch = 24, bg = "black", col = "black",
           cex = 1.50, lwd = 1.15)
    text(0.865, y, "End", adj = c(0, 0.5), cex = 1.15)

    invisible(NULL)
  }

  FIG6_LOOP_FILE_FINAL <- file.path(DIR_MAIN_FIG_PNG, "Figure6.png")

  png(FIG6_LOOP_FILE_FINAL, width = 36, height = 32, units = "cm", res = 900)

  layout(rbind(matrix(1:9, nrow = 3, byrow = TRUE), c(10, 10, 10)),
         heights = c(1, 1, 1, 0.22))

  for (r in seq_along(fig6_rows)) {
    for (c in seq_along(fig6_sites_ordered)) {

      sel_row <- fig6_selected %>%
        dplyr::filter(row_group == fig6_rows[r],
                      site == fig6_sites_ordered[c]) %>%
        dplyr::slice(1)

      draw_loop_panel_final(sel_row,
                            show_site_title = (r == 1),
                            show_xlab = (r == 3),
                            show_ylab = (c == 1))
    }
  }

  draw_loop_legend_final()
  grDevices::dev.off()

  message("Updated Figure 6 loops: ", FIG6_LOOP_FILE_FINAL)
}

###############################################################################
# FINAL AUTHORITATIVE RENDERING, PUBLICATION TABLES, AND OUTPUT AUDIT
###############################################################################
################################################################################
# AUTHORITATIVE PALETTE ALIASES FOR FINAL RENDERERS
################################################################################
FINAL_CLUSTER_COLS <- IR33_CLUSTER_PALETTE
FINAL_CLUSTER_COLS_ACTIVE <- IR33_CLUSTER_PALETTE_ACTIVE

message(
  "Corrected Section 3.3 ready for final rendering: k = ",
  IR33_SELECTED_K,
  "; n = ",
  nrow(ir33_data),
  "; silhouette = ",
  sprintf("%.3f", ir33_selected_silhouette)
)



################################################################################
# MAIN FIGURE 3 — HI–FI GRID FOR ALL CONSTITUENTS
# Promoted unchanged from the former Supplementary Figure S3.

################################################################################


# ==============================================================================
# 1. PREPARE AUTHORITATIVE HI–FI DATA
# ==============================================================================

fig7_prepare_hi_fi_data_vaughan <- function(solute_name) {
  
  raw_data  <- EVS2
  raw_names <- names(raw_data)
  
  hi_col <- c("HI_use", "HI", "HI_Lloyd")
  hi_col <- hi_col[hi_col %in% raw_names][1]
  if (is.na(hi_col)) stop("Main Figure 3 requires HI_use/HI/HI_Lloyd.", call.=FALSE)
  
  status_col <- c("chem_status", "event_chemical_status", "Chemical_Status")
  status_col <- status_col[status_col %in% raw_names][1]
  if (is.na(status_col))
    stop("Main Figure 3 requires the authoritative event chemical-status column; status will not be inferred from FI.", call.=FALSE)
  
  if (!"loop_type" %in% raw_names)
    stop("Main Figure 3 requires loop_type.", call.=FALSE)
  
  status_raw <- tolower(trimws(as.character(raw_data[[status_col]])))
  chemical_status <- dplyr::case_when(
    status_raw %in% c("mobilization","mobilisation","mobilized","mobilised","flushing") ~ "Mobilization",
    status_raw %in% c("dilution","diluted") ~ "Dilution",
    status_raw %in% c("chemostasis","chemostatic","no response","non-responsive","nonresponsive") ~ "Chemostasis",
    TRUE ~ NA_character_
  )
  
  loop_raw <- tolower(trimws(as.character(raw_data$loop_type)))
  loop_group <- dplyr::case_when(
    grepl("figure|mixed|eight|complex", loop_raw) ~ "Figure-8 / Mixed",
    grepl("anti|counter", loop_raw)               ~ "Anti-clockwise",
    grepl("clockwise", loop_raw)                  ~ "Clockwise",
    grepl("direct|linear|synchronous", loop_raw)  ~ "Direct",
    TRUE ~ NA_character_
  )
  
  tibble::tibble(
    site=trimws(as.character(raw_data$site)),
    event_id=suppressWarnings(as.integer(raw_data$ID)),
    solute=toupper(trimws(as.character(raw_data$solute))),
    HI_plot=suppressWarnings(as.numeric(raw_data[[hi_col]])),
    FI_plot=suppressWarnings(as.numeric(raw_data$FI_peak)),
    chemical_status=chemical_status,
    loop_group=loop_group
  ) %>%
    dplyr::filter(
      solute==toupper(solute_name), site %in% MANUSCRIPT_SITES,
      is.finite(HI_plot), is.finite(FI_plot),
      FI_plot >= -1-1e-10, FI_plot <= 1+1e-10,
      !is.na(chemical_status), !is.na(loop_group)
    ) %>%
    dplyr::distinct(site, event_id, solute, .keep_all=TRUE) %>%
    dplyr::mutate(
      site=factor(site, levels=MANUSCRIPT_SITES),
      chemical_status=factor(chemical_status, levels=c("Mobilization","Dilution","Chemostasis")),
      loop_group=factor(loop_group, levels=c("Clockwise","Anti-clockwise","Figure-8 / Mixed","Direct"))
    ) %>%
    dplyr::arrange(site, event_id)
}


# ==============================================================================
# 2. CHECK REQUIRED OBJECTS / PACKAGES
# ==============================================================================

for (pkg in c("ggplot2","dplyr","tidyr","tibble","cowplot"))
  if (!requireNamespace(pkg, quietly=TRUE))
    stop("Package '", pkg, "' is required for Main Figure 3.", call.=FALSE)

if (!exists("EVS2")) stop("EVS2 is not available in the current R session.", call.=FALSE)
if (!exists("MANUSCRIPT_SITES")) stop("MANUSCRIPT_SITES is not available.", call.=FALSE)
if (!exists("DIR_MAIN_FIG_PNG")) stop("DIR_MAIN_FIG_PNG is not available.", call.=FALSE)

dir.create(DIR_MAIN_FIG_PNG, recursive=TRUE, showWarnings=FALSE)


# ==============================================================================
# 3. BUILD MAIN FIGURE 3
# ==============================================================================

make_fig7_allsolutes_grid <- function() {
  
  if (!exists("FIG7_FONT_FAMILY", inherits=TRUE)) FIG7_FONT_FAMILY <- "sans"
  
  solute_order <- c("NO3","DOC","EC","TSS")
  site_order   <- c("NF","SHA","TTP")
  
  # Combine all four constituent datasets
  plot_data_all <- dplyr::bind_rows(lapply(solute_order, function(z)
    fig7_prepare_hi_fi_data_vaughan(solute_name=z))) %>%
    dplyr::mutate(solute=factor(solute, levels=solute_order),
                  site=factor(site, levels=site_order)) %>%
    dplyr::filter(solute %in% solute_order, site %in% site_order,
                  is.finite(HI_plot), is.finite(FI_plot),
                  HI_plot >= -0.75, HI_plot <= 0.75,
                  FI_plot >= -1, FI_plot <= 1)
  
  if (nrow(plot_data_all)==0L)
    return(cowplot::ggdraw() + cowplot::draw_label("No valid HI-FI storm-event data available.", size=12))
  
  # Chemical-status colours and C-Q loop shapes
  status_colours <- c("Mobilization"="#1F78B4",
                      "Dilution"="#E31A1C",
                      "Chemostasis"="#33A02C")
  
  loop_shapes <- c("Clockwise"=16,
                   "Anti-clockwise"=17,
                   "Figure-8 / Mixed"=15,
                   "Direct"=3)
  
  # Retain the constituent colours already used elsewhere in the manuscript
  fig7_solute_colour <- function(z) {
    if (exists("final_solute_colour", mode="function", inherits=TRUE))
      return(final_solute_colour(z))
    c("NO3"="#E41A1C","DOC"="#E69F00","EC"="#AA55FF","TSS"="#2EAD45")[[z]]
  }
  
  
  # ---------------------------------------------------------------------------
  # One constituent row containing NF, SHA and TTP
  # ---------------------------------------------------------------------------
  
  fig7_row_plot <- function(sol_name, show_x=FALSE, show_legend=FALSE, show_strip=TRUE) {
    
    pd <- plot_data_all %>% dplyr::filter(solute==sol_name)
    
    # Quadrant labels
    qlab <- tidyr::expand_grid(
      site=factor(site_order, levels=site_order),
      quadrant=c("ACW / positive FI","CW / positive FI",
                 "ACW / negative FI","CW / negative FI")
    ) %>%
      dplyr::mutate(
        x=ifelse(grepl("^ACW", quadrant), -0.63, 0.63),
        y=ifelse(grepl("positive", quadrant), 0.87, -0.87),
        hjust=ifelse(grepl("^ACW", quadrant), 0, 1),
        vjust=ifelse(grepl("positive", quadrant), 1, 0)
      )
    
    # Event-count label, deliberately above the lower-right quadrant text
    nlab <- pd %>%
      dplyr::count(site, name="n_events") %>%
      dplyr::mutate(site=factor(site, levels=site_order),
                    x=0.68, y=-0.68, label=paste0("n = ", n_events))
    
    ggplot2::ggplot(pd, ggplot2::aes(HI_plot, FI_plot)) +
      
      # Reference axes
      ggplot2::geom_hline(yintercept=0, colour="grey35", linewidth=0.65, linetype="dashed") +
      ggplot2::geom_vline(xintercept=0, colour="grey35", linewidth=0.65, linetype="dashed") +
      
      # Event points
      ggplot2::geom_point(
        ggplot2::aes(colour=chemical_status, shape=loop_group),
        size=3.15, stroke=0.60, alpha=0.95, na.rm=TRUE
      ) +
      
      # Enlarged quadrant labels
      ggplot2::geom_text(
        data=qlab,
        ggplot2::aes(x=x, y=y, label=quadrant, hjust=hjust, vjust=vjust),
        inherit.aes=FALSE, family=FIG7_FONT_FAMILY,
        fontface="italic", size=5.8, colour="black"
      ) +
      
      # Enlarged event counts
      ggplot2::geom_text(
        data=nlab, ggplot2::aes(x=x, y=y, label=label),
        inherit.aes=FALSE, hjust=1, vjust=0,
        family=FIG7_FONT_FAMILY, size=4.8, colour="black"
      ) +
      
      # Three catchments
      ggplot2::facet_grid(cols=ggplot2::vars(site)) +
      
      # Common HI and FI scales
      ggplot2::scale_x_continuous(
        limits=c(-0.75,0.75), breaks=seq(-0.75,0.75,0.25),
        expand=ggplot2::expansion(mult=c(0.035,0.035))
      ) +
      ggplot2::scale_y_continuous(
        limits=c(-1,1), breaks=c(-1,-0.5,0,0.5,1),
        expand=ggplot2::expansion(mult=c(0.02,0.02))
      ) +
      
      ggplot2::scale_colour_manual(
        values=status_colours, limits=names(status_colours),
        drop=FALSE, na.translate=FALSE, name="Chemical status"
      ) +
      ggplot2::scale_shape_manual(
        values=loop_shapes, limits=names(loop_shapes),
        drop=FALSE, na.translate=FALSE, name="C-Q loop type"
      ) +
      
      # Enlarged and centred common legend
      ggplot2::guides(
        colour=ggplot2::guide_legend(
          order=1, nrow=1, byrow=TRUE, title.position="left",
          override.aes=list(shape=16, size=5.2, alpha=1)
        ),
        shape=ggplot2::guide_legend(
          order=2, nrow=1, byrow=TRUE, title.position="left",
          override.aes=list(colour="black", size=5.2, alpha=1)
        )
      ) +
      
      ggplot2::labs(x=if(show_x) "Hysteresis index (HI)" else NULL, y=NULL) +
      
      ggplot2::theme_bw(base_family=FIG7_FONT_FAMILY, base_size=11) +
      ggplot2::theme(
        
        # Site titles shown only for the upper NO3 row
        strip.background=if(show_strip)
          ggplot2::element_rect(fill="grey94", colour="grey30", linewidth=0.8)
        else ggplot2::element_blank(),
        
        strip.text.x=if(show_strip)
          ggplot2::element_text(face="bold", size=15.2, colour="black",
                                margin=ggplot2::margin(4,4,4,4))
        else ggplot2::element_blank(),
        
        strip.text.y=ggplot2::element_blank(),
        strip.background.y=ggplot2::element_blank(),
        
        # Panels
        panel.border=ggplot2::element_rect(colour="black", fill=NA, linewidth=0.9),
        panel.grid.major=ggplot2::element_line(colour="grey90", linewidth=0.32),
        panel.grid.minor=ggplot2::element_blank(),
        panel.spacing.x=grid::unit(0.42,"cm"),
        panel.spacing.y=grid::unit(0.12,"cm"),
        
        # Axes
        axis.title.x=ggplot2::element_text(size=16.2, colour="black",
                                           margin=ggplot2::margin(t=7)),
        axis.text.x=if(show_x)
          ggplot2::element_text(size=12.5, colour="black")
        else ggplot2::element_blank(),
        axis.ticks.x=if(show_x)
          ggplot2::element_line(colour="black", linewidth=0.65)
        else ggplot2::element_blank(),
        axis.text.y=ggplot2::element_text(size=12.3, colour="black"),
        axis.ticks.y=ggplot2::element_line(colour="black", linewidth=0.65),
        
        # Legend
        legend.position=if(show_legend) "bottom" else "none",
        legend.direction="horizontal",
        legend.box="horizontal",
        legend.justification="center",
        legend.box.just="center",
        legend.title=ggplot2::element_text(face="bold", size=14.5),
        legend.text=ggplot2::element_text(size=13.5),
        legend.key.width=grid::unit(0.78,"cm"),
        legend.key.height=grid::unit(0.58,"cm"),
        legend.spacing.x=grid::unit(0.24,"cm"),
        legend.box.margin=ggplot2::margin(0,0,0,0),
        
        # Extra right-side breathing room
        plot.margin=ggplot2::margin(t=3, r=18, b=if(show_x) 1 else 0, l=3)
      )
  }
  
  
  # ---------------------------------------------------------------------------
  # Coloured constituent label + line beside each row
  # ---------------------------------------------------------------------------
  
  fig7_constituent_label <- function(z) {
    cc <- fig7_solute_colour(z)
    
    cowplot::ggdraw() +
      cowplot::draw_line(x=c(0.79,0.79), y=c(0.05,0.95),
                         size=1.10, colour=cc) +
      cowplot::draw_label(z, x=0.43, y=0.50, angle=90,
                          fontfamily=FIG7_FONT_FAMILY,
                          fontface="bold", colour=cc, size=14.5)
  }
  
  
  # ---------------------------------------------------------------------------
  # Extract one common legend
  # ---------------------------------------------------------------------------
  
  legend_grob <- cowplot::get_legend(
    fig7_row_plot("NO3", show_x=TRUE, show_legend=TRUE, show_strip=TRUE)
  )
  
  
  # ---------------------------------------------------------------------------
  # Construct the four constituent rows
  # Only the first row retains NF / SHA / TTP strip titles
  # ---------------------------------------------------------------------------
  
  row_list <- lapply(seq_along(solute_order), function(i) {
    
    p <- fig7_row_plot(
      solute_order[i],
      show_x=(i==length(solute_order)),
      show_legend=FALSE,
      show_strip=(i==1)
    )
    
    cowplot::plot_grid(
      fig7_constituent_label(solute_order[i]), p,
      ncol=2, rel_widths=c(0.060,1),
      align="h", axis="tb"
    )
  })
  
  
  # Combine NO3, DOC, EC and TSS
  rows_combined <- cowplot::plot_grid(
    plotlist=row_list, ncol=1,
    rel_heights=c(1.04,1,1,1.04),
    align="v", axis="lr"
  )
  
  
  # ---------------------------------------------------------------------------
  # Common y-axis title and long vertical line
  # ---------------------------------------------------------------------------
  
  global_y_axis <- cowplot::ggdraw() +
    cowplot::draw_line(x=c(0.84,0.84), y=c(0.015,0.985),
                       size=0.95, colour="black") +
    cowplot::draw_label(
      "Flushing index (FI)",
      x=0.34, y=0.50, angle=90,
      fontfamily=FIG7_FONT_FAMILY, size=15.5
    )
  
  
  # ---------------------------------------------------------------------------
  # Main body with explicit blank space on the far right
  # ---------------------------------------------------------------------------
  
  right_spacer <- cowplot::ggdraw()
  
  fig_body <- cowplot::plot_grid(
    global_y_axis, rows_combined, right_spacer,
    ncol=3, rel_widths=c(0.067,1,0.040)
  )
  
  
  # ---------------------------------------------------------------------------
  # Final arrangement:
  # small top margin + full figure + compact legend
  # IMPORTANT: three objects require three relative heights
  # ---------------------------------------------------------------------------
  
  top_spacer <- cowplot::ggdraw()
  
  cowplot::plot_grid(
    top_spacer, fig_body, legend_grob,
    ncol=1, rel_heights=c(0.045,1,0.050)
  )
}


# ==============================================================================
# 4. GENERATE, DISPLAY AND EXPORT MAIN FIGURE 3
# ==============================================================================

message("=== GENERATING MAIN FIGURE 3 HI-FI GRID ===")

FIG7_GRID_DPI       <- 1200
FIG7_GRID_WIDTH_IN  <- 19.2
FIG7_GRID_HEIGHT_IN <- 18.8

FIG3_HIFI_FILE <- file.path(DIR_MAIN_FIG_PNG, "Figure3.png")

fig7_allsolutes_grid <- make_fig7_allsolutes_grid()

# Display in R/RStudio plot window
print(fig7_allsolutes_grid)

# Prefer ragg when installed for sharper text rendering
fig7_png_device <- if (requireNamespace("ragg", quietly=TRUE)) ragg::agg_png else "png"

ggplot2::ggsave(
  filename=FIG3_HIFI_FILE,
  plot=fig7_allsolutes_grid,
  device=fig7_png_device,
  width=FIG7_GRID_WIDTH_IN,
  height=FIG7_GRID_HEIGHT_IN,
  units="in",
  dpi=FIG7_GRID_DPI,
  bg="white",
  limitsize=FALSE
)

if (!file.exists(FIG3_HIFI_FILE))
  stop("Main Figure 3 was not created.", call.=FALSE)

cat("\nMain Figure 3 saved to:\n",
    normalizePath(FIG3_HIFI_FILE, winslash="/", mustWork=TRUE), "\n")





# SUPPLEMENTARY FIGURES S1 AND S2
# Rebuilt directly from the locked 2015-2020 manuscript population.

message("=== GENERATING SUPPLEMENTARY FIGURES S1 AND S2 ===")

# Long-term daily-discharge thresholds defining low/mid/high initial-flow class.
flow_thresholds <- purrr::map_dfr(MANUSCRIPT_SITES, function(s) {
  q_col <- detect_q_col(names(df_manuscript), s)
  if (is.na(q_col) || !(q_col %in% names(df_manuscript))) {
    stop("Missing discharge column for ", s, call. = FALSE)
  }

  daily_q <- tibble::tibble(
    date = as.Date(df_manuscript$date, tz = TZ_USE),
    Q = to_num(df_manuscript[[q_col]])
  ) %>%
    dplyr::filter(!is.na(date), is.finite(Q), Q > 0) %>%
    dplyr::group_by(date) %>%
    dplyr::summarise(Q_daily = mean(Q, na.rm = TRUE), .groups = "drop") %>%
    dplyr::pull(Q_daily)

  qq <- stats::quantile(
    daily_q,
    probs = c(0.33, 0.66),
    na.rm = TRUE,
    names = FALSE
  )

  tibble::tibble(
    site = s,
    thresh_low_mid = qq[[1]],
    thresh_mid_high = qq[[2]]
  )
})

# Authoritative qStart register from the locked accepted-event table.
flow_qstart_register <- event_metrics %>%
  dplyr::transmute(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    qStart = suppressWarnings(as.numeric(qStart))
  ) %>%
  dplyr::distinct(site, ID, .keep_all = TRUE)

# Event-solute population used by Figure S1.
# One row is retained for each responsive combination with finite HI_Lloyd.
s1_event_solute <- EVS2 %>%
  dplyr::transmute(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    solute = toupper(trimws(as.character(solute))),
    response = as.logical(response),
    HI_Lloyd = suppressWarnings(as.numeric(HI_use))
  ) %>%
  dplyr::filter(
    site %in% MANUSCRIPT_SITES,
    solute %in% MANUSCRIPT_SOLUTES,
    response %in% TRUE,
    is.finite(HI_Lloyd)
  ) %>%
  dplyr::left_join(flow_qstart_register, by = c("site", "ID")) %>%
  dplyr::left_join(flow_thresholds, by = "site") %>%
  dplyr::mutate(
    Flow_Class = dplyr::case_when(
      qStart <= thresh_low_mid ~ "Low Flow",
      qStart > thresh_low_mid & qStart <= thresh_mid_high ~ "Mid Flow",
      qStart > thresh_mid_high ~ "High Flow",
      TRUE ~ NA_character_
    ),
    Flow_Class = factor(
      Flow_Class,
      levels = c("Low Flow", "Mid Flow", "High Flow")
    )
  ) %>%
  dplyr::filter(is.finite(qStart), !is.na(Flow_Class))

# Event population used by Figure S2: each event counted only once.
s2_event_population <- s1_event_solute %>%
  dplyr::distinct(site, ID, qStart, Flow_Class)

flow_condition_summary_by_site <- s2_event_population %>%
  dplyr::count(site, Flow_Class, name = "n_events") %>%
  tidyr::complete(
    site = MANUSCRIPT_SITES,
    Flow_Class = factor(
      c("Low Flow", "Mid Flow", "High Flow"),
      levels = c("Low Flow", "Mid Flow", "High Flow")
    ),
    fill = list(n_events = 0L)
  ) %>%
  dplyr::group_by(site) %>%
  dplyr::mutate(
    percent = 100 * n_events / sum(n_events)
  ) %>%
  dplyr::ungroup()

# Reproducibility guard against accidental changes in the S1/S2 event population.
expected_s2_counts <- tibble::tribble(
  ~site, ~Flow_Class, ~n_events,
  "NF",  "Low Flow",  96L,
  "NF",  "Mid Flow",  88L,
  "NF",  "High Flow", 62L,
  "SHA", "Low Flow",  48L,
  "SHA", "Mid Flow",  59L,
  "SHA", "High Flow", 63L,
  "TTP", "Low Flow",  93L,
  "TTP", "Mid Flow",  62L,
  "TTP", "High Flow", 45L
)

s2_count_check <- flow_condition_summary_by_site %>%
  dplyr::mutate(Flow_Class = as.character(Flow_Class)) %>%
  dplyr::select(site, Flow_Class, n_events) %>%
  dplyr::arrange(site, Flow_Class) %>%
  dplyr::left_join(
    expected_s2_counts %>%
      dplyr::rename(expected_n = n_events),
    by = c("site", "Flow_Class")
  )

if (any(is.na(s2_count_check$expected_n)) ||
    any(s2_count_check$n_events != s2_count_check$expected_n)) {
  stop(
    "Figure S1/S2 population check failed. Expected event counts are ",
    "NF 246, SHA 170, TTP 200 with the manuscript low/mid/high breakdown.",
    call. = FALSE
  )
}

# Figure S1. Initial Q histograms and HI_Lloyd by initial-flow class.

S1_DISCHARGE_COL <- "#0057FF"
S1_SOLUTE_COLS <- c(
  NO3 = "#FF3030",
  DOC = "#D89B16",
  EC  = "#A64CFF",
  TSS = "#2CA02C"
)
S1_SOLUTE_TITLES <- c(
  NO3 = "Nitrate (NO3)",
  DOC = "DOC",
  EC  = "EC",
  TSS = "TSS"
)

safe_box_ylim <- function(x, expansion = 0.08) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) return(c(-1, 1))
  r <- range(c(x, 0), na.rm = TRUE)
  if (diff(r) == 0) r <- r + c(-0.1, 0.1)
  pad <- diff(r) * expansion
  r + c(-pad, pad)
}

FIG_S1_FINAL <- file.path(DIR_SUPP_FIG_PNG, "FigureS1.png")

grDevices::png(
  FIG_S1_FINAL,
  width = 36,
  height = 35,
  units = "cm",
  res = 600
)

graphics::par(
  mfrow = c(5, 3),
  mar = c(5.6, 5.4, 3.0, 1.8),
  oma = c(3.2, 2.2, 1.0, 1.0)
)

# Row 1: initial-discharge distributions.
for (s in MANUSCRIPT_SITES) {
  d <- s2_event_population %>%
    dplyr::filter(site == s, is.finite(qStart))

  graphics::hist(
    d$qStart,
    main = paste(s, "- Discharge (Q)"),
    col = S1_DISCHARGE_COL,
    border = "white",
    xlab = "",
    ylab = "Storm Frequency",
    las = 1,
    cex.main = 1.28,
    cex.axis = 1.10,
    cex.lab = 1.12
  )
  graphics::mtext(
    expression("Initial Q [m"^3*" s"^-1*"]"),
    side = 1,
    line = 3.0,
    cex = 1.06
  )
}

# Rows 2-5: one constituent per row; common y range across catchments in a row.
for (solute_i in c("NO3", "DOC", "EC", "TSS")) {
  row_data <- s1_event_solute %>%
    dplyr::filter(solute == solute_i)

  row_ylim <- safe_box_ylim(row_data$HI_Lloyd)

  for (s in MANUSCRIPT_SITES) {
    d <- row_data %>%
      dplyr::filter(site == s, !is.na(Flow_Class), is.finite(HI_Lloyd))

    graphics::boxplot(
      HI_Lloyd ~ Flow_Class,
      data = d,
      main = paste(s, "-", S1_SOLUTE_TITLES[[solute_i]]),
      col = unname(S1_SOLUTE_COLS[[solute_i]]),
      border = "grey25",
      xaxt = "n",
      xlab = "",
      ylab = expression("Hysteresis Index (" * italic(HI)[Lloyd] * ")"),
      ylim = row_ylim,
      las = 1,
      notch = FALSE,
      cex.axis = 1.08,
      cex.lab = 1.10,
      cex.main = 1.26
    )

    graphics::abline(h = 0, lty = 2, col = "grey42", lwd = 1.25)
    graphics::axis(
      side = 1,
      at = 1:3,
      labels = c("Low Flow", "Mid Flow", "High Flow"),
      cex.axis = 1.02,
      padj = 0.55
    )
  }
}

grDevices::dev.off()

# Figure S2. Initial-flow conditions relative to the six-year daily FDC.

FLOW_CLASS_COLS <- c(
  "Low Flow"  = "#92C5DE",
  "Mid Flow"  = "#FDAE61",
  "High Flow" = "#D73027"
)

flow_plot_dat <- flow_condition_summary_by_site %>%
  dplyr::mutate(
    site = factor(site, levels = MANUSCRIPT_SITES),
    Flow_Class = factor(
      as.character(Flow_Class),
      levels = c("Low Flow", "Mid Flow", "High Flow")
    ),
    label = paste0(
      n_events,
      " events\n",
      round(percent),
      "%"
    )
  )

p_flow_condition <- ggplot2::ggplot(
  flow_plot_dat,
  ggplot2::aes(
    x = site,
    y = percent,
    fill = Flow_Class
  )
) +
  ggplot2::geom_col(
    width = 0.58,
    colour = "black",
    linewidth = 0.55
  ) +
  ggplot2::geom_text(
    ggplot2::aes(label = label),
    position = ggplot2::position_stack(vjust = 0.5),
    size = 4.0,
    colour = "black",
    lineheight = 0.92
  ) +
  ggplot2::scale_y_continuous(
    breaks = seq(0, 100, by = 20),
    labels = function(x) paste0(x, "%"),
    expand = c(0, 0)
  ) +
  ggplot2::coord_cartesian(ylim = c(0, 100)) +
  ggplot2::scale_fill_manual(
    values = FLOW_CLASS_COLS,
    breaks = c("Low Flow", "Mid Flow", "High Flow"),
    labels = c("Low flow", "Mid flow", "High flow"),
    name = "Initial-flow class",
    drop = FALSE
  ) +
  ggplot2::labs(
    title = "Initial-flow conditions relative to the long-term flow-duration curve",
    x = "Catchment",
    y = "Proportion of valid events (%)"
  ) +
  ggplot2::theme_bw(base_size = 14) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    panel.border = ggplot2::element_rect(
      colour = "black",
      fill = NA,
      linewidth = 1.2
    ),
    axis.text.x = ggplot2::element_text(
      colour = "black",
      face = "bold",
      size = 12.4
    ),
    axis.text.y = ggplot2::element_text(
      colour = "black",
      size = 12.4
    ),
    axis.title.x = ggplot2::element_text(
      face = "plain",
      size = 13.8,
      margin = ggplot2::margin(t = 8)
    ),
    axis.title.y = ggplot2::element_text(
      face = "plain",
      size = 13.8,
      margin = ggplot2::margin(r = 10)
    ),
    plot.title = ggplot2::element_text(
      face = "bold",
      size = 14.8,
      hjust = 0
    ),
    legend.position = "bottom",
    legend.justification = "center",
    legend.box.just = "center",
    legend.box = "horizontal",
    legend.title = ggplot2::element_text(face = "bold")
  )

ggplot2::ggsave(
  filename = file.path(DIR_SUPP_FIG_PNG, "FigureS2.png"),
  plot = p_flow_condition,
  width = 6.8,
  height = 5.7,
  units = "in",
  dpi = 800,
  bg = "white",
  limitsize = FALSE
)

message("Supplementary Figures S1 and S2 generated.")

# 5. MAIN FIGURE 6 - ADJUSTED RESPONSE-GROUP PROBABILITIES

#    Corrected Vaughan-FI version.
#
# The target response group for each hydrological signature is selected
# objectively from the corrected clustering as the successfully fitted group
# with the largest adjusted probability range. See:
# Table_Adjusted_Probability_Panel_Selection.csv

if (
  exists("ir33_probability_panel_selection") &&
  exists("ir33_probability_curves_continuous") &&
  exists("ir33_probability_curve_discrete") &&
  exists("ir33_transition_ranges") &&
  exists("ir33_probability_model_data") &&
  exists("ir33_probability_predictor_labels")
) {

  cluster_prevalence_final <- ir33_probability_model_data %>%
    dplyr::count(Cluster_short, name = "n") %>%
    dplyr::mutate(prevalence = n / sum(n))

  probability_panel_titles <- c(
    a = "Antecedent dry period",
    b = "Discharge-wave recurrence",
    c = "Event rainfall",
    d = "Maximum rainfall intensity"
  )

  make_probability_panel_final <- function(selection_row) {
    panel_i <- as.character(selection_row$panel[[1]])
    predictor_i <- as.character(selection_row$predictor[[1]])
    target_i <- as.character(selection_row$target_cluster[[1]])
    kind_i <- as.character(selection_row$model_kind[[1]])

    panel_title_i <- paste0(
      panel_i, ") ", target_i, " and ",
      unname(probability_panel_titles[panel_i])
    )

    if (
      is.na(target_i) ||
      !nzchar(target_i) ||
      !(target_i %in% names(FINAL_CLUSTER_COLS_ACTIVE))
    ) {
      return(
        ggplot2::ggplot() +
          ggplot2::annotate(
            "text", x = 0, y = 0,
            label = paste0(
              panel_i,
              ") No adjusted model available for ",
              predictor_i
            )
          ) +
          ggplot2::theme_void(base_size = 11)
      )
    }

    cluster_col_i <- unname(FINAL_CLUSTER_COLS_ACTIVE[target_i])
    prevalence_i <- cluster_prevalence_final %>%
      dplyr::filter(as.character(Cluster_short) == target_i) %>%
      dplyr::pull(prevalence)

    if (length(prevalence_i) == 0L) prevalence_i <- NA_real_

    if (identical(kind_i, "continuous")) {
      data_i <- ir33_probability_curves_continuous %>%
        dplyr::filter(
          panel == panel_i,
          target_cluster == target_i,
          predictor == predictor_i
        )

      transition_i <- ir33_transition_ranges %>%
        dplyr::filter(
          panel == panel_i,
          target_cluster == target_i,
          predictor == predictor_i
        )

      if (nrow(data_i) == 0L) {
        return(
          ggplot2::ggplot() +
            ggplot2::annotate(
              "text", x = 0, y = 0,
              label = paste("Model unavailable:", target_i, predictor_i)
            ) +
            ggplot2::labs(title = panel_title_i) +
            ggplot2::theme_void(base_size = 11)
        )
      }

      p <- ggplot2::ggplot(
        data_i,
        ggplot2::aes(x = driver_value, y = probability)
      ) +
        ggplot2::geom_hline(
          yintercept = prevalence_i,
          linetype = 3,
          colour = "grey45",
          linewidth = 0.50
        ) +
        ggplot2::geom_ribbon(
          ggplot2::aes(ymin = lower, ymax = upper),
          fill = cluster_col_i,
          alpha = 0.18
        ) +
        ggplot2::geom_line(
          colour = cluster_col_i,
          linewidth = 1.15
        ) +
        ggplot2::scale_y_continuous(
          limits = c(0, 1),
          labels = scales::label_percent(accuracy = 1),
          expand = ggplot2::expansion(mult = c(0.01, 0.03))
        ) +
        ggplot2::labs(
          title = panel_title_i,
          x = unname(ir33_probability_predictor_labels[predictor_i]),
          y = paste0("Adjusted probability of ", target_i)
        ) +
        ggplot2::theme_bw(base_size = 11) +
        ggplot2::theme(
          plot.title = ggplot2::element_text(face = "bold", size = 11),
          panel.grid.minor = ggplot2::element_blank()
        )

      if (
        nrow(transition_i) > 0L &&
        is.finite(transition_i$transition_lower[[1]]) &&
        is.finite(transition_i$transition_upper[[1]])
      ) {
        p <- p +
          ggplot2::annotate(
            "rect",
            xmin = transition_i$transition_lower[[1]],
            xmax = transition_i$transition_upper[[1]],
            ymin = -Inf,
            ymax = Inf,
            fill = "grey70",
            alpha = 0.16
          ) +
          ggplot2::geom_vline(
            xintercept = transition_i$transition_point[[1]],
            linetype = 2,
            colour = "grey35",
            linewidth = 0.60
          )
      }

      return(p)
    }

    data_i <- ir33_probability_curve_discrete %>%
      dplyr::filter(
        panel == panel_i,
        target_cluster == target_i,
        predictor == predictor_i
      )

    if (nrow(data_i) == 0L) {
      return(
        ggplot2::ggplot() +
          ggplot2::annotate(
            "text", x = 0, y = 0,
            label = paste("Model unavailable:", target_i, predictor_i)
          ) +
          ggplot2::labs(title = panel_title_i) +
          ggplot2::theme_void(base_size = 11)
      )
    }

    ggplot2::ggplot(
      data_i,
      ggplot2::aes(x = driver_level, y = probability)
    ) +
      ggplot2::geom_hline(
        yintercept = prevalence_i,
        linetype = 3,
        colour = "grey45",
        linewidth = 0.50
      ) +
      ggplot2::geom_errorbar(
        ggplot2::aes(ymin = lower, ymax = upper),
        width = 0.12,
        colour = cluster_col_i,
        linewidth = 0.75
      ) +
      ggplot2::geom_line(
        ggplot2::aes(group = 1),
        colour = cluster_col_i,
        linewidth = 1.05
      ) +
      ggplot2::geom_point(
        colour = cluster_col_i,
        size = 3.1
      ) +
      ggplot2::scale_y_continuous(
        limits = c(0, 1),
        labels = scales::label_percent(accuracy = 1),
        expand = ggplot2::expansion(mult = c(0.01, 0.03))
      ) +
      ggplot2::labs(
        title = panel_title_i,
        x = unname(ir33_probability_predictor_labels[predictor_i]),
        y = paste0("Adjusted probability of ", target_i)
      ) +
      ggplot2::theme_bw(base_size = 11) +
      ggplot2::theme(
        plot.title = ggplot2::element_text(face = "bold", size = 11),
        panel.grid.minor = ggplot2::element_blank()
      )
  }

  probability_panels_final <- lapply(
    c("a", "b", "c", "d"),
    function(panel_i) {
      sel_i <- ir33_probability_panel_selection %>%
        dplyr::filter(panel == panel_i) %>%
        dplyr::slice(1L)

      if (nrow(sel_i) == 0L) {
        return(
          ggplot2::ggplot() +
            ggplot2::annotate(
              "text", x = 0, y = 0,
              label = paste("No selection available for panel", panel_i)
            ) +
            ggplot2::theme_void(base_size = 11)
        )
      }

      make_probability_panel_final(sel_i)
    }
  )

  adjusted_probability_final <-
    (probability_panels_final[[1]] | probability_panels_final[[2]]) /
    (probability_panels_final[[3]] | probability_panels_final[[4]])

  ir33_save_plot(
    adjusted_probability_final,
    file.path(DIR_MAIN_FIG_PNG, "Figure7.png"),
    width_mm = 225,
    height_mm = 175
  )

  message("Updated main Figure 7 probability curves using corrected Vaughan FI clusters.")
}

# 6. SUPPLEMENTARY FIGURE S4 - PAM CLUSTER DIAGNOSTICS

if (
  exists("ir33_k_table") &&
  exists("ir33_selected_silhouette_table") &&
  exists("ir33_cluster_stability")
) {

  diagnostic_palette_final <- FINAL_CLUSTER_COLS_ACTIVE

  p_diag_k_final <- ggplot2::ggplot(
    ir33_k_table,
    ggplot2::aes(x = k, y = average_silhouette)
  ) +
    ggplot2::geom_line(linewidth = 0.9, colour = "grey25") +
    ggplot2::geom_point(size = 3.0, colour = "grey25") +
    ggplot2::geom_point(
      data = ir33_k_table %>% dplyr::filter(k == IR33_SELECTED_K),
      size = 4.3,
      shape = 21,
      fill = "white",
      stroke = 1.1
    ) +
    ggplot2::scale_x_continuous(breaks = IR33_K_CANDIDATES) +
    ggplot2::labs(
      title = "a) Candidate cluster solutions",
      x = "Number of clusters (k)",
      y = "Average silhouette width"
    ) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))

  p_diag_sil_final <- ir33_selected_silhouette_table %>%
    dplyr::mutate(
      Cluster_short = factor(
        paste0("C", Cluster_number),
        levels = names(diagnostic_palette_final)
      )
    ) %>%
    ggplot2::ggplot(
      ggplot2::aes(
        x = Cluster_short,
        y = silhouette_width,
        fill = Cluster_short
      )
    ) +
    ggplot2::geom_hline(yintercept = 0, linetype = 2, colour = "grey45") +
    # Explicit min/max whisker caps (not the default 1.5 x IQR whiskers).
    ggplot2::stat_boxplot(
      geom = "errorbar",
      coef = Inf,
      width = 0.34,
      linewidth = 0.55
    ) +
    ggplot2::geom_boxplot(
      width = 0.62,
      coef = Inf,
      outlier.shape = NA,
      linewidth = 0.55
    ) +
    ggplot2::scale_fill_manual(values = diagnostic_palette_final, guide = "none") +
    ggplot2::labs(
      title = "b) Selected-solution silhouette widths",
      x = NULL,
      y = "Silhouette width"
    ) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))

  p_diag_jac_final <- ir33_cluster_stability %>%
    dplyr::mutate(
      Cluster_short = factor(
        paste0("C", Cluster),
        levels = names(diagnostic_palette_final)
      )
    ) %>%
    ggplot2::ggplot(
      ggplot2::aes(
        x = Cluster_short,
        y = mean_bootstrap_jaccard,
        fill = Cluster_short
      )
    ) +
    ggplot2::geom_hline(yintercept = 0.60, linetype = 2, colour = "grey45") +
    ggplot2::geom_col(width = 0.62) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("%.3f", mean_bootstrap_jaccard)),
      vjust = -0.35,
      size = 3.4
    ) +
    ggplot2::scale_fill_manual(values = diagnostic_palette_final, guide = "none") +
    ggplot2::scale_y_continuous(
      limits = c(0, 1.05),
      expand = ggplot2::expansion(mult = c(0, 0.02))
    ) +
    ggplot2::labs(
      title = "c) Bootstrap-Jaccard stability",
      x = NULL,
      y = "Mean Jaccard similarity"
    ) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))

  pam_diagnostics_final <-
    (p_diag_k_final | p_diag_sil_final | p_diag_jac_final) +
    patchwork::plot_annotation(
      title = "PAM response-group selection and stability diagnostics",
      theme = ggplot2::theme(
        plot.title = ggplot2::element_text(
          face = "bold",
          hjust = 0.5,
          size = 13.5
        )
      )
    )

  ir33_save_plot(
    pam_diagnostics_final,
    file.path(DIR_SUPP_FIG_PNG, "FigureS4.png"),
    width_mm = 255,
    height_mm = 98
  )

  message("Updated Supplementary Figure S4 PAM diagnostics.")
}

# 7. SUPPLEMENTARY FIGURE S5 - RESPONSE-GROUP HYDROLOGICAL DISTRIBUTIONS

if (
  exists("ir33_hydrological_distribution_data") &&
  is.data.frame(ir33_hydrological_distribution_data) &&
  nrow(ir33_hydrological_distribution_data) > 0L
) {

  ir33_hydrological_distribution_data_final <-
    ir33_hydrological_distribution_data %>%
    dplyr::mutate(
      Cluster_short = factor(
        as.character(Cluster_short),
        levels = names(FINAL_CLUSTER_COLS_ACTIVE)
      )
    )

  hydrological_distributions_final <- ggplot2::ggplot(
    ir33_hydrological_distribution_data_final,
    ggplot2::aes(
      x = Cluster_short,
      y = Value,
      fill = Cluster_short,
      colour = Cluster_short
    )
  ) +
    ggplot2::geom_violin(
      scale = "width",
      trim = FALSE,
      alpha = 0.20,
      linewidth = 0.45
    ) +
    ggplot2::geom_boxplot(
      width = 0.18,
      outlier.shape = NA,
      alpha = 0.72,
      linewidth = 0.45
    ) +
    ggplot2::geom_jitter(
      width = 0.10,
      height = 0,
      alpha = 0.10,
      size = 0.55,
      show.legend = FALSE
    ) +
    ggplot2::facet_wrap(
      ~facet_label,
      scales = "free_y",
      ncol = 2
    ) +
    ggplot2::scale_fill_manual(
      values = FINAL_CLUSTER_COLS_ACTIVE,
      guide = "none"
    ) +
    ggplot2::scale_colour_manual(
      values = FINAL_CLUSTER_COLS_ACTIVE,
      guide = "none"
    ) +
    ggplot2::labs(
      title = "Hydrological distributions across response groups",
      subtitle = NULL,
      x = "Response group",
      y = NULL
    ) +
    ggplot2::theme_bw(base_size = 10.5) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", hjust = 0.5),
      strip.text = ggplot2::element_text(face = "bold"),
      axis.text.x = ggplot2::element_text(face = "bold")
    )

  ir33_save_plot(
    hydrological_distributions_final,
    file.path(DIR_SUPP_FIG_PNG, "FigureS5.png"),
    width_mm = 205,
    height_mm = 172
  )

  message("Updated Supplementary Figure S5 hydrological distributions.")
}

# 8. SUPPLEMENTARY FIGURE S3 - INTEGRATED RESPONSE PATTERNS
#    - no global title/subtitle
#    - C1-C3 legend horizontal and unboxed above panel b
#    - panel d legend unboxed below panel d
#    - panel c colourbar and panel d legend share one bottom legend row
#    - all four rectangular panel frames are aligned to matched heights

if (
  exists("ir33_data_plot") &&
  exists("ir33_medoid_plot") &&
  exists("profile_long") &&
  exists("ir33_enrichment_plot") &&
  exists("compound_long") &&
  exists("theme_ir33") &&
  exists("hydrograph_palette")
) {

  cluster_levels_final <- names(FINAL_CLUSTER_COLS_ACTIVE)

  # Panel a --------------------------------------------------------------------
  panel_a_final <- ggplot2::ggplot(
    ir33_data_plot,
    ggplot2::aes(
      x = HI_use,
      y = loop_area,
      colour = Cluster_short,
      size = abs(FI_peak)
    )
  ) +
    ggplot2::geom_point(alpha = 0.42, stroke = 0) +
    ggplot2::geom_point(
      data = ir33_medoid_plot,
      ggplot2::aes(x = HI_use, y = loop_area),
      inherit.aes = FALSE,
      shape = 23,
      size = 3.3,
      stroke = 0.8,
      fill = "white",
      colour = "black"
    ) +
    ggplot2::geom_text(
      data = ir33_medoid_plot,
      ggplot2::aes(x = HI_use, y = loop_area, label = Cluster_short),
      inherit.aes = FALSE,
      nudge_y = 0.035,
      size = 3.2,
      fontface = "bold"
    ) +
    ggplot2::geom_vline(
      xintercept = 0,
      linetype = 2,
      colour = "grey45",
      linewidth = 0.55
    ) +
    ggplot2::scale_colour_manual(
      values = FINAL_CLUSTER_COLS_ACTIVE,
      drop = FALSE,
      guide = "none"
    ) +
    ggplot2::scale_size_continuous(
      range = c(0.9, 4.2),
      guide = "none"
    ) +
    ggplot2::labs(
      title = "a) Joint event-response space",
      x = expression(HI[Lloyd]),
      y = expression(A[loop])
    ) +
    theme_ir33

  # Panel b --------------------------------------------------------------------
  panel_b_final <- ggplot2::ggplot(
    profile_long,
    ggplot2::aes(
      x = Response,
      y = Standardized_mean,
      group = Cluster_short,
      colour = Cluster_short
    )
  ) +
    ggplot2::geom_hline(
      yintercept = 0,
      colour = "grey55",
      linetype = 2,
      linewidth = 0.55
    ) +
    ggplot2::geom_line(linewidth = 1.15) +
    ggplot2::geom_point(size = 3.0) +
    ggplot2::scale_colour_manual(
      values = FINAL_CLUSTER_COLS_ACTIVE,
      breaks = cluster_levels_final,
      drop = FALSE,
      name = NULL
    ) +
    ggplot2::scale_x_discrete(
      limits = c("HI_Lloyd", "A_loop", "FI_Vaughan"),
      drop = FALSE,
      expand = ggplot2::expansion(add = 0.35)
    ) +
    ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(0.06, 0.20))
    ) +
    ggplot2::guides(
      colour = ggplot2::guide_legend(
        nrow = 1,
        byrow = TRUE,
        title = NULL,
        override.aes = list(linetype = 0, shape = 16, size = 3.5)
      )
    ) +
    ggplot2::labs(
      title = "b) Standardized multivariate profiles",
      x = NULL,
      y = "Robust standardized mean"
    ) +
    theme_ir33 +
    ggplot2::theme(
      # Only C1, C2 and C3 are shown: no "Response group" legend title,
      # no enclosing legend rectangle, and one horizontal legend line.
      legend.position = c(0.50, 0.985),
      legend.justification = c(0.50, 1.00),
      legend.direction = "horizontal",
      legend.title = ggplot2::element_blank(),
      legend.background = ggplot2::element_blank(),
      legend.box.background = ggplot2::element_blank(),
      legend.key = ggplot2::element_blank(),
      legend.margin = ggplot2::margin(0, 0, 0, 0),
      legend.spacing.x = grid::unit(2.0, "mm"),
      legend.key.width = grid::unit(7, "mm"),
      legend.key.height = grid::unit(4, "mm")
    )

  # Panel c --------------------------------------------------------------------
  panel_c_with_legend_final <- ggplot2::ggplot(
    ir33_enrichment_plot,
    ggplot2::aes(
      x = site_solute,
      y = Cluster_short,
      fill = standardized_residual
    )
  ) +
    ggplot2::geom_tile(colour = "white", linewidth = 0.45) +
    ggplot2::scale_fill_gradient2(
      low = "#6C63C7",
      mid = "white",
      high = "#C62828",
      midpoint = 0,
      name = "Standardized residual"
    ) +
    ggplot2::labs(
      title = "c) Catchment-constituent enrichment",
      x = "Catchment-constituent combination",
      y = NULL
    ) +
    ggplot2::guides(
      fill = ggplot2::guide_colourbar(
        direction = "horizontal",
        title.position = "top",
        title.hjust = 0.5,
        barwidth = grid::unit(58, "mm"),
        barheight = grid::unit(4, "mm")
      )
    ) +
    theme_ir33 +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(
        angle = 45,
        hjust = 1,
        vjust = 1,
        size = 8.0
      ),
      axis.title.x = ggplot2::element_text(size = 9.2),
      axis.text.y = ggplot2::element_text(size = 11.0),
      legend.position = "bottom",
      legend.justification = "center",
      legend.background = ggplot2::element_blank(),
      legend.box.background = ggplot2::element_blank(),
      legend.margin = ggplot2::margin(0, 0, 0, 0)
    )

  legend_c_final <- cowplot::get_legend(panel_c_with_legend_final)
  panel_c_final <- panel_c_with_legend_final +
    ggplot2::theme(legend.position = "none")

  # Panel d --------------------------------------------------------------------
  panel_d_with_legend_final <- ggplot2::ggplot(
    compound_long,
    ggplot2::aes(
      x = Cluster_short,
      y = Percent,
      fill = Hydrograph_feature
    )
  ) +
    ggplot2::geom_col(
      position = ggplot2::position_dodge(width = 0.78),
      width = 0.68
    ) +
    ggplot2::scale_fill_manual(
      values = hydrograph_palette,
      drop = FALSE,
      name = NULL
    ) +
    ggplot2::scale_x_discrete(
      limits = cluster_levels_final,
      drop = FALSE
    ) +
    ggplot2::scale_y_continuous(
      limits = c(0, 100),
      expand = ggplot2::expansion(mult = c(0, 0.03))
    ) +
    ggplot2::labs(
      title = "d) Compound rainfall-runoff structure",
      x = NULL,
      y = "Event combinations (%)"
    ) +
    ggplot2::guides(
      fill = ggplot2::guide_legend(
        nrow = 1,
        byrow = TRUE,
        title = NULL
      )
    ) +
    theme_ir33 +
    ggplot2::theme(
      legend.position = "bottom",
      legend.justification = "center",
      legend.direction = "horizontal",
      legend.title = ggplot2::element_blank(),
      legend.background = ggplot2::element_blank(),
      legend.box.background = ggplot2::element_blank(),
      legend.key = ggplot2::element_blank(),
      legend.margin = ggplot2::margin(0, 0, 0, 0),
      legend.text = ggplot2::element_text(size = 8.6),
      legend.spacing.x = grid::unit(1.4, "mm"),
      legend.key.width = grid::unit(4.5, "mm"),
      legend.key.height = grid::unit(3.8, "mm")
    )

  legend_d_final <- cowplot::get_legend(panel_d_with_legend_final)
  panel_d_final <- panel_d_with_legend_final +
    ggplot2::theme(legend.position = "none")

  # Align all four plotting panels together. This is deliberately done before
  # composing the 2 x 2 grid so the true rectangular frames in c and d match
  # the frame heights used in a and b.
  aligned_s4_final <- cowplot::align_plots(
    panel_a_final,
    panel_b_final,
    panel_c_final,
    panel_d_final,
    align = "hv",
    axis = "tblr"
  )

  integrated_response_core_final <- cowplot::plot_grid(
    aligned_s4_final[[1]],
    aligned_s4_final[[2]],
    aligned_s4_final[[3]],
    aligned_s4_final[[4]],
    ncol = 2,
    rel_widths = c(1.10, 0.90),
    rel_heights = c(1.00, 1.00)
  )

  # Colourbar for c and the unboxed legend for d share exactly one bottom row.
  bottom_legends_final <- cowplot::plot_grid(
    legend_c_final,
    legend_d_final,
    ncol = 2,
    rel_widths = c(1.10, 0.90),
    align = "h"
  )

  # No patchwork::plot_annotation(): therefore no global S4 title or subtitle.
  integrated_response_final <- cowplot::plot_grid(
    integrated_response_core_final,
    bottom_legends_final,
    ncol = 1,
    rel_heights = c(1.00, 0.11)
  )

  ir33_save_plot(
    integrated_response_final,
    file.path(DIR_SUPP_FIG_PNG, "FigureS3.png"),
    width_mm = 265,
    height_mm = 220
  )

  message("Updated Supplementary Figure S3 integrated response patterns.")
}

message("=== FINAL REVIEWER HARMONIZATION PATCH COMPLETED ===")
################################################################################

################################################################################
# PUBLICATION TABLES - EXACT PAPER/SUPPLEMENTARY STRUCTURE
################################################################################
message("=== WRITING PUBLICATION TABLES ===")

# Rebuild the three analytical populations from the locked 2015-2020 EVS2 so
# publication tables cannot inherit stale pre-lock population objects.
status_levels <- c("mobilization", "dilution", "chemostasis")
publication_status_col <- c("chem_status", "event_chemical_status", "Chemical_Status")
publication_status_col <- publication_status_col[publication_status_col %in% names(EVS2)][1]
if (is.na(publication_status_col)) {
  stop("Cannot rebuild publication populations: chemical-status column is missing from EVS2.", call. = FALSE)
}

fig2a_population <- EVS2 %>%
  dplyr::mutate(
    site = trimws(as.character(site)),
    ID = suppressWarnings(as.integer(ID)),
    solute = toupper(trimws(as.character(solute))),
    chem_status = stringr::str_to_lower(trimws(as.character(.data[[publication_status_col]])))
  ) %>%
  dplyr::filter(
    site %in% MANUSCRIPT_SITES,
    solute %in% MANUSCRIPT_SOLUTES,
    chem_status %in% status_levels
  ) %>%
  dplyr::distinct(site, ID, solute, .keep_all = TRUE)

responsive_population <- fig2a_population %>%
  dplyr::filter(ir33_as_true(response))

fig2d_population <- responsive_population %>%
  dplyr::filter(
    is.finite(HI_use),
    is.finite(loop_area),
    loop_area >= 0,
    !is.na(loop_type),
    nzchar(trimws(as.character(loop_type)))
  )

EVS2_prox <- fig2d_population

fmt1 <- function(x) format(round(as.numeric(x), 1), nsmall = 1, trim = TRUE, scientific = FALSE)
fmt2 <- function(x) format(round(as.numeric(x), 2), nsmall = 2, trim = TRUE, scientific = FALSE)
fmt3 <- function(x) format(round(as.numeric(x), 3), nsmall = 3, trim = TRUE, scientific = FALSE)
pct1 <- function(n, d) ifelse(d > 0, paste0(n, " (", fmt1(100*n/d), "%)"), paste0(n, " (NA)"))

# Table 1. Catchment-scale summary statistics used in the manuscript.
#
# These values are the approved full-record 2015-2020 statistics already used
# by the upstream manuscript Figure 2 annotation workflow. Scientific symbols
# are constructed from Unicode code points so the R source remains encoding-safe.

U_MINUS1 <- intToUtf8(c(0x207B, 0x00B9))
U_SUP3   <- intToUtf8(0x00B3)
U_SUB3   <- intToUtf8(0x2083)
U_ENDASH <- intToUtf8(0x2013)
U_MICRO  <- intToUtf8(0x00B5)
U_PM     <- intToUtf8(0x00B1)

T1_LABEL_PREC <- paste0("Precipitation (mm 10 min", U_MINUS1, ")")
T1_LABEL_Q    <- paste0("Discharge (m", U_SUP3, " s", U_MINUS1, ")")
T1_LABEL_NO3  <- paste0("NO", U_SUB3, U_ENDASH, "N (mg N L", U_MINUS1, ")")
T1_LABEL_DOC  <- paste0("DOC (mg L", U_MINUS1, ")")
T1_LABEL_EC   <- paste0("EC (", U_MICRO, "S cm", U_MINUS1, ")")
T1_LABEL_TSS  <- paste0("TSS (mg L", U_MINUS1, ")")

Table1 <- tibble::tribble(
  ~Variable,
  ~NF_Min, ~NF_Mean_SD, ~NF_Max, ~NF_CV,
  ~SHA_Min, ~SHA_Mean_SD, ~SHA_Max, ~SHA_CV,
  ~TTP_Min, ~TTP_Mean_SD, ~TTP_Max, ~TTP_CV,

  T1_LABEL_PREC,
  "0", paste0("0.04 ", U_PM, " 0.29"), "21.9", "788.8",
  "0", paste0("0.03 ", U_PM, " 0.22"), "12.2", "745.6",
  "0", paste0("0.04 ", U_PM, " 0.28"), "20.1", "789.4",

  T1_LABEL_Q,
  "0.07", paste0("0.84 ", U_PM, " 0.96"), "6.22", "114.7",
  "0.01", paste0("0.52 ", U_PM, " 0.64"), "5.63", "122.3",
  "0.05", paste0("0.71 ", U_PM, " 0.67"), "4.36", "94.9",

  T1_LABEL_NO3,
  "0", paste0("0.38 ", U_PM, " 0.14"), "5.64", "36.4",
  "0", paste0("0.97 ", U_PM, " 0.37"), "2.88", "38.0",
  "0.08", paste0("1.74 ", U_PM, " 0.47"), "3.55", "26.9",

  T1_LABEL_DOC,
  "0.4", paste0("2.91 ", U_PM, " 1.59"), "8.57", "54.6",
  "0", paste0("2.54 ", U_PM, " 1.79"), "24.5", "70.5",
  "0.01", paste0("2.13 ", U_PM, " 1.46"), "23.5", "68.6",

  T1_LABEL_EC,
  "14.8", paste0("33.1 ", U_PM, " 8.16"), "84.3", "24.7",
  "6.28", paste0("59.7 ", U_PM, " 14.9"), "284.0", "24.9",
  "23.8", paste0("42.9 ", U_PM, " 3.71"), "81.7", "8.6",

  T1_LABEL_TSS,
  "0.0", paste0("31.7 ", U_PM, " 23.0"), "1,266", "72.6",
  "0.9", paste0("120.1 ", U_PM, " 171.9"), "3,358", "143.2",
  "2.1", paste0("43.9 ", U_PM, " 71.0"), "2,848", "161.7"
)

names(Table1) <- c(
  "Variable",
  "NF Min", "NF Mean ± SD", "NF Max", "NF CV (%)",
  "SHA Min", "SHA Mean ± SD", "SHA Max", "SHA CV (%)",
  "TTP Min", "TTP Mean ± SD", "TTP Max", "TTP CV (%)"
)

# Excel-friendly UTF-8 CSV.
if (requireNamespace("readr", quietly = TRUE)) {
  readr::write_excel_csv(
    Table1,
    file.path(DIR_MAIN_TAB, "Table1.csv"),
    na = ""
  )
} else {
  utils::write.csv(
    Table1,
    file.path(DIR_MAIN_TAB, "Table1.csv"),
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
}

# Table S1. Nested populations and time-integrated chemical status.
status_order <- c("chemostasis","mobilization","dilution")
status_text <- function(dat) {
  cc <- table(factor(dat$chem_status, levels = status_order))
  n <- sum(cc)
  if (n == 0L) return("C 0 (NA); M 0 (NA); D 0 (NA)")
  paste0(
    "C ", cc[[1]], " (", fmt1(100 * cc[[1]] / n), "%); ",
    "M ", cc[[2]], " (", fmt1(100 * cc[[2]] / n), "%); ",
    "D ", cc[[3]], " (", fmt1(100 * cc[[3]] / n), "%)"
  )
}
dominant_text <- function(dat) {
  cc <- table(factor(dat$chem_status, levels = status_order))
  if (sum(cc) == 0L) return(NA_character_)
  c("Chemostasis", "Mobilization", "Dilution")[[which.max(cc)]]
}
response_class_map <- c(
  "NF_DOC"="Intermediate response","NF_EC"="Low response","NF_NO3"="Intermediate response","NF_TSS"="High response",
  "SHA_DOC"="Intermediate response","SHA_EC"="Low response","SHA_NO3"="Intermediate response","SHA_TSS"="High response",
  "TTP_DOC"="High response","TTP_EC"="Low response","TTP_NO3"="Intermediate response","TTP_TSS"="High response"
)

make_s1_row <- function(site_value, solute_value, pooled=FALSE) {
  all_dat <- fig2a_population %>% dplyr::filter(solute==solute_value)
  resp_dat <- responsive_population %>% dplyr::filter(solute==solute_value)
  geo_dat <- fig2d_population %>% dplyr::filter(solute==solute_value)
  if (!pooled) {
    all_dat <- all_dat %>% dplyr::filter(site==site_value)
    resp_dat <- resp_dat %>% dplyr::filter(site==site_value)
    geo_dat <- geo_dat %>% dplyr::filter(site==site_value)
  }
  n_all <- nrow(all_dat); n_resp <- nrow(resp_dat); n_geo <- nrow(geo_dat); n_non <- n_all-n_resp
  tibble::tibble(
    `Site/scale`=ifelse(pooled,"All catchments",site_value),
    Solute=ifelse(solute_value=="NO3","NO3-N",solute_value),
    `All n`=n_all,
    `Nonresponsive n (% all)`=pct1(n_non,n_all),
    `Responsive n (% all)`=pct1(n_resp,n_all),
    `Geometry n (% all)`=pct1(n_geo,n_all),
    `All-event C/M/D, n (%)`=status_text(all_dat),
    `All dominant`=dominant_text(all_dat),
    `Responsive C/M/D, n (%)`=status_text(resp_dat),
    `Responsive dominant`=dominant_text(resp_dat),
    `Response class`=ifelse(pooled,"Pooled",unname(response_class_map[paste(site_value,solute_value,sep="_")]))
  )
}
TableS1 <- dplyr::bind_rows(
  purrr::map_dfr(c("DOC","EC","NO3","TSS"), ~make_s1_row(NA,.x,TRUE)),
  purrr::map_dfr(sites, function(s) purrr::map_dfr(c("DOC","EC","NO3","TSS"), ~make_s1_row(s,.x,FALSE)))
)

if (requireNamespace("readr", quietly = TRUE)) {
  readr::write_excel_csv(
    TableS1,
    file.path(DIR_SUPP_TAB, "TableS1.csv"),
    na = ""
  )
} else {
  utils::write.csv(
    TableS1,
    file.path(DIR_SUPP_TAB, "TableS1.csv"),
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
}

# Table S2. Hysteresis timing, pathway complexity and loop structure.
normalize_loop_s2 <- function(x) {
  z <- tolower(trimws(as.character(x)))
  dplyr::case_when(
    grepl("figure|mixed|eight|complex",z) ~ "Figure-8/mixed",
    grepl("anti|counter",z) ~ "Anticlockwise",
    grepl("clockwise",z) ~ "Clockwise",
    grepl("direct|linear",z) ~ "Direct",
    TRUE ~ as.character(x)
  )
}
site_solute_loop_medians <- fig2d_population %>% dplyr::group_by(site,solute) %>%
  dplyr::summarise(med=median(loop_area,na.rm=TRUE),.groups="drop")
loop_cut <- stats::quantile(site_solute_loop_medians$med, c(1/3,2/3), na.rm=TRUE, names=FALSE)
versus_nf_map <- c(
  "NF_DOC"="Reference","NF_EC"="Reference","NF_NO3"="Reference","NF_TSS"="Reference",
  "SHA_DOC"="Lower than NF","SHA_EC"="Similar to NF","SHA_NO3"="Similar to NF","SHA_TSS"="Similar to NF",
  "TTP_DOC"="Similar to NF","TTP_EC"="Similar to NF","TTP_NO3"="Lower than NF","TTP_TSS"="Similar to NF"
)
make_s2_row <- function(s, sol) {

  z <- fig2d_population %>%
    dplyr::filter(
      site == s,
      solute == sol
    ) %>%
    dplyr::mutate(
      loop_norm = normalize_loop_s2(loop_type)
    )

  n <- nrow(z)

  hm    <- median(z$HI_use, na.rm = TRUE)
  hmean <- mean(z$HI_use, na.rm = TRUE)

  pos  <- sum(z$HI_use > 0.05, na.rm = TRUE)
  neg  <- sum(z$HI_use < -0.05, na.rm = TRUE)
  zero <- sum(abs(z$HI_use) <= 0.05, na.rm = TRUE)

  am    <- median(z$loop_area, na.rm = TRUE)
  amean <- mean(z$loop_area, na.rm = TRUE)

  lct <- sort(
    table(z$loop_norm),
    decreasing = TRUE
  )

  loopfmt <- function(i) {

    if (length(lct) >= i) {

      paste0(
        names(lct)[i],
        ": ",
        as.integer(lct[i]),
        " (",
        fmt1(
          100 * as.integer(lct[i]) / n
        ),
        "%)"
      )

    } else {

      ""
    }
  }

  timing <- if (hm > 0.05) {

    "Rising-limb dominant"

  } else if (hm < -0.05) {

    "Falling-limb dominant"

  } else {

    "Balanced/mixed"
  }

  complexity <- if (am <= loop_cut[1]) {

    "Low"

  } else if (am <= loop_cut[2]) {

    "Moderate"

  } else {

    "High"
  }

  tibble::tibble(
    Site = s,

    Solute = ifelse(
      sol == "NO3",
      "NO3-N",
      sol
    ),

    n = n,

    `HI_Lloyd median (mean)` = paste0(
      fmt3(hm),
      " (",
      fmt3(hmean),
      ")"
    ),

    # ASCII-safe temporary column name
    `HI_Lloyd +/-/~0 (%)` = paste0(
      fmt1(100 * pos / n),
      "/",
      fmt1(100 * neg / n),
      "/",
      fmt1(100 * zero / n)
    ),

    `A_loop median (mean)` = paste0(
      fmt3(am),
      " (",
      fmt3(amean),
      ")"
    ),

    `Limb dominance` = timing,

    Complexity = complexity,

    `Dominant loop, n (%)` = loopfmt(1),

    `Secondary loop, n (%)` = loopfmt(2),

    `Versus NF` = unname(
      versus_nf_map[
        paste(
          s,
          sol,
          sep = "_"
        )
      ]
    )
  )
}

TableS2 <- purrr::map_dfr(
  sites,
  function(s) {
    purrr::map_dfr(
      c(
        "DOC",
        "EC",
        "NO3",
        "TSS"
      ),
      ~make_s2_row(
        s,
        .x
      )
    )
  }
)

# Restore exact publication header safely.
# Unicode characters are generated at runtime rather than typed
# directly inside an R backticked variable name.

hi_dir_header <- paste0(
  "HI_Lloyd +/",
  intToUtf8(0x2212),   # Unicode minus sign
  "/",
  intToUtf8(0x2248),   # Unicode approximately equal sign
  "0 (%)"
)

names(TableS2)[
  names(TableS2) == "HI_Lloyd +/-/~0 (%)"
] <- hi_dir_header

if (requireNamespace("readr", quietly = TRUE)) {
  readr::write_excel_csv(
    TableS2,
    file.path(DIR_SUPP_TAB, "TableS2.csv"),
    na = ""
  )
} else {
  utils::write.csv(
    TableS2,
    file.path(DIR_SUPP_TAB, "TableS2.csv"),
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
}

# Table 2. Integrated response-group profiles, enrichment and hydrology.
# Corrected Vaughan-FI version. All values are calculated directly from the
# corrected in-memory analysis objects; no manuscript values are hard-coded.

cluster_short <- function(x) sub(":.*$", "", as.character(x))
cluster_levels <- paste0("C", seq_len(IR33_SELECTED_K))

get_cluster_label <- function(cshort) {
  lv <- unique(as.character(ir33_data$Cluster_label))
  hit <- lv[startsWith(lv, paste0(cshort, ":"))]
  if (length(hit) == 0L) return(NA_character_)
  hit[[1]]
}

stab_lookup <- function(cshort) {
  k_i <- suppressWarnings(as.integer(sub("C", "", cshort)))
  z <- ir33_cluster_stability %>%
    dplyr::filter(
      suppressWarnings(as.integer(as.character(Cluster))) == k_i
    )
  if (nrow(z) == 0L) NA_real_ else z$mean_bootstrap_jaccard[[1]]
}

loop_pct <- function(cshort, patt) {
  lab <- get_cluster_label(cshort)
  if (is.na(lab)) return(NA_real_)
  z <- ir33_data %>%
    dplyr::filter(as.character(Cluster_label) == lab) %>%
    dplyr::mutate(loop_norm = normalize_loop_s2(loop_type))
  if (nrow(z) == 0L) return(NA_real_)
  100 * mean(grepl(patt, z$loop_norm, ignore.case = TRUE), na.rm = TRUE)
}

prof <- function(cshort) {
  lab <- get_cluster_label(cshort)
  if (is.na(lab)) return(tibble::tibble())
  ir33_cluster_profiles %>%
    dplyr::filter(as.character(Cluster_label) == lab) %>%
    dplyr::slice(1L)
}

cluster_title_lookup <- setNames(
  vapply(
    cluster_levels,
    function(cn) {
      lab <- get_cluster_label(cn)
      if (is.na(lab)) return(cn)
      sub("^C[0-9]+:\\s*", "", lab)
    },
    character(1)
  ),
  cluster_levels
)

panelA_title <- paste0(
  "Panel A. Multivariate response profiles (n = ",
  format(nrow(ir33_data), big.mark = ","),
  "; PAM k = ", IR33_SELECTED_K,
  "; mean silhouette = ", fmt3(ir33_selected_silhouette), ")"
)

site_solute_test_row <- ir33_categorical_tests %>%
  dplyr::filter(Variable == "site_solute") %>%
  dplyr::slice(1L)

site_solute_df <- (
  length(unique(ir33_data$Cluster_label)) - 1L
) * (
  length(unique(ir33_data$site_solute)) - 1L
)

panelB_title <- if (nrow(site_solute_test_row) > 0L) {
  paste0(
    "Panel B. Catchment-constituent enrichment (chi-square_",
    site_solute_df, " = ",
    fmt1(site_solute_test_row$Statistic[[1]]), "; q ",
    ifelse(
      site_solute_test_row$q_value_BH[[1]] < 0.001,
      "< 0.001",
      paste0("= ", fmt3(site_solute_test_row$q_value_BH[[1]]))
    ),
    ")"
  )
} else {
  "Panel B. Catchment-constituent enrichment"
}

panelA <- purrr::map_dfr(
  cluster_levels,
  function(cn) {
    p <- prof(cn)
    if (nrow(p) == 0L) return(tibble::tibble())

    n_i <- p$n[[1]]
    pct_i <- 100 * n_i / nrow(ir33_data)

    txt <- c(
      cluster_title_lookup[[cn]],
      paste0("n = ", n_i, " combinations (", round(pct_i), "%)"),
      paste0("Mean Jaccard = ", fmt3(stab_lookup(cn))),
      paste0(
        "Median HI_Lloyd = ",
        ifelse(p$HI_median[[1]] >= 0, "+", ""),
        fmt3(p$HI_median[[1]])
      ),
      paste0("Median A_loop = ", fmt3(p$loop_area_median[[1]])),
      paste0("Median FI_Vaughan = ", fmt3(p$FI_peak_median[[1]])),
      paste0("Figure-8/mixed: ", round(loop_pct(cn, "Figure-8")), "%"),
      paste0("Anticlockwise: ", round(loop_pct(cn, "Anticlockwise")), "%"),
      paste0("Clockwise: ", round(loop_pct(cn, "^Clockwise$")), "%"),
      paste0(
        "Profile: ",
        p$timing_label[[1]], "; ",
        p$complexity_label[[1]], "; ",
        p$flushing_label[[1]]
      )
    )

    tibble::tibble(
      Panel = panelA_title,
      Row = seq_along(txt),
      Cluster = cn,
      Text = txt
    )
  }
)

pretty_site_solute <- function(x) {
  x <- as.character(x)
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub(intToUtf8(0x2013L), " ", x, fixed = TRUE)
  x <- sub(" NO3$", " NO3-N", x)
  x
}

panelB <- purrr::map_dfr(
  cluster_levels,
  function(cn) {
    lab <- get_cluster_label(cn)
    if (is.na(lab)) return(tibble::tibble())

    z_cluster <- ir33_data %>%
      dplyr::filter(as.character(Cluster_label) == lab)

    dominant_solute <- z_cluster %>%
      dplyr::count(solute, sort = TRUE, name = "n") %>%
      dplyr::slice(1L)

    dominant_line <- if (nrow(dominant_solute) > 0L) {
      paste0(
        "Dominant constituent: ",
        dominant_solute$solute[[1]],
        " = ", dominant_solute$n[[1]], "/", nrow(z_cluster),
        " (", round(100 * dominant_solute$n[[1]] / nrow(z_cluster)), "%)"
      )
    } else {
      ""
    }

    e <- ir33_site_solute_enrichment %>%
      dplyr::filter(
        as.character(Cluster_label) == lab,
        is.finite(standardized_residual),
        standardized_residual > 0
      ) %>%
      dplyr::arrange(dplyr::desc(standardized_residual)) %>%
      dplyr::slice_head(n = 4L)

    enrichment_lines <- if (nrow(e) > 0L) {
      paste0(
        pretty_site_solute(e$site_solute),
        ": n = ", e$observed_n,
        "; residual = ", sprintf("%+.2f", e$standardized_residual),
        "; O/E = ", sprintf("%.2f", e$observed_expected_ratio)
      )
    } else {
      "No positive catchment-constituent enrichment identified."
    }

    txt <- c(
      "Positive catchment-constituent enrichment",
      dominant_line,
      enrichment_lines
    )
    txt <- txt[nzchar(txt)]

    tibble::tibble(
      Panel = panelB_title,
      Row = seq_along(txt),
      Cluster = cn,
      Text = txt
    )
  }
)

summ_hydro <- function(cn, var) {
  lab <- get_cluster_label(cn)
  if (is.na(lab) || !(var %in% names(ir33_data))) {
    return(c(median = NA_real_, q1 = NA_real_, q3 = NA_real_, mean = NA_real_))
  }

  x <- ir33_data %>%
    dplyr::filter(as.character(Cluster_label) == lab) %>%
    dplyr::pull(dplyr::all_of(var))

  x <- x[is.finite(x)]
  if (length(x) == 0L) {
    return(c(median = NA_real_, q1 = NA_real_, q3 = NA_real_, mean = NA_real_))
  }

  c(
    median = stats::median(x),
    q1 = stats::quantile(x, 0.25, names = FALSE),
    q3 = stats::quantile(x, 0.75, names = FALSE),
    mean = mean(x)
  )
}

panelC <- purrr::map_dfr(
  cluster_levels,
  function(cn) {
    lab <- get_cluster_label(cn)
    p <- prof(cn)
    if (is.na(lab) || nrow(p) == 0L) return(tibble::tibble())

    z <- ir33_data %>%
      dplyr::filter(as.character(Cluster_label) == lab)

    rain <- summ_hydro(cn, "event_rainfall")
    imax <- summ_hydro(cn, "maximum_rainfall_intensity")
    dry <- summ_hydro(cn, "antecedent_dry_period")
    sep <- summ_hydro(cn, "discharge_peak_separation_h")

    tss <- z %>%
      dplyr::filter(
        solute == "TSS",
        is.finite(pre_event_concentration)
      ) %>%
      dplyr::pull(pre_event_concentration)

    if (length(tss) > 0L) {
      tss_median <- stats::median(tss)
      tss_q <- stats::quantile(tss, c(0.25, 0.75), names = FALSE)
    } else {
      tss_median <- NA_real_
      tss_q <- c(NA_real_, NA_real_)
    }

    txt <- c(
      paste0(
        p$timing_label[[1]], " / ",
        p$flushing_label[[1]], " tendency"
      ),
      paste0(
        "Multiple rain pulses: ",
        round(100 * mean(z$multiple_rainfall_pulses %in% TRUE, na.rm = TRUE)),
        "%"
      ),
      paste0(
        "Multiple discharge peaks: ",
        round(100 * mean(z$multiple_discharge_peaks %in% TRUE, na.rm = TRUE)),
        "%"
      ),
      paste0(
        "Either compound feature: ",
        round(100 * mean(z$compound_hydrograph %in% TRUE, na.rm = TRUE)),
        "%"
      ),
      paste0(
        "Mean Q_peak count: ",
        fmt2(mean(z$discharge_peak_count, na.rm = TRUE))
      ),
      paste0(
        "Median peak separation: ",
        fmt1(sep[["median"]]), " h"
      ),
      paste0(
        "Rain: ", fmt1(rain[["median"]]),
        " mm (IQR ", fmt2(rain[["q1"]]), "-",
        fmt2(rain[["q3"]]), ")"
      ),
      paste0(
        "I_max: ", fmt1(imax[["median"]]),
        " mm h^-1 (IQR ", fmt2(imax[["q1"]]), "-",
        fmt2(imax[["q3"]]), ")"
      ),
      paste0(
        "Dry period: ", fmt1(dry[["median"]]),
        " h (IQR ", fmt2(dry[["q1"]]), "-",
        fmt2(dry[["q3"]]), ")"
      ),
      paste0(
        "Pre-event TSS: ", fmt1(tss_median),
        " mg L^-1 (IQR ", fmt2(tss_q[[1]]), "-",
        fmt2(tss_q[[2]]), ")"
      )
    )

    tibble::tibble(
      Panel = "Panel C. Hydrograph structure and hydrological context",
      Row = seq_along(txt),
      Cluster = cn,
      Text = txt
    )
  }
)

Table2_long <- dplyr::bind_rows(panelA, panelB, panelC)

Table2 <- Table2_long %>%
  tidyr::pivot_wider(
    names_from = Cluster,
    values_from = Text
  ) %>%
  dplyr::arrange(
    factor(
      Panel,
      levels = unique(Table2_long$Panel)
    ),
    Row
  )

if (requireNamespace("readr", quietly = TRUE)) {
  readr::write_excel_csv(
    Table2,
    file.path(DIR_MAIN_TAB, "Table2.csv"),
    na = ""
  )
} else {
  utils::write.csv(
    Table2,
    file.path(DIR_MAIN_TAB, "Table2.csv"),
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
}

################################################################################
# FINAL PUBLICATION-OUTPUT CHECK
################################################################################

# Remove only obsolete files left by the previous numbering scheme so rerunning
# this script cannot leave a misleading old Figure S6 or old Figure 4 TIFF.
obsolete_renumbered_outputs <- c(
  file.path(DIR_SUPP_FIG_PNG, "FigureS6.png"),
  file.path(DIR_MAIN_FIG_ALT, "Figure4.tiff")
)
invisible(unlink(obsolete_renumbered_outputs[file.exists(obsolete_renumbered_outputs)]))

publication_outputs <- c(
  file.path(DIR_MAIN_FIG_PNG, paste0("Figure", 2:7, ".png")),
  file.path(DIR_MAIN_TAB, "Table1.csv"),
  file.path(DIR_MAIN_TAB, "Table2.csv"),
  file.path(DIR_SUPP_FIG_PNG, paste0("FigureS", 1:5, ".png")),
  file.path(DIR_SUPP_TAB, c("TableS1.csv", "TableS2.csv"))
)

missing_publication_outputs <- publication_outputs[!file.exists(publication_outputs)]

if (length(missing_publication_outputs) > 0L) {
  stop(
    "Final manuscript tail completed with missing publication output(s):\n",
    paste(missing_publication_outputs, collapse = "\n"),
    call. = FALSE
  )
}

message(
  "\nFINAL MANUSCRIPT TAIL COMPLETED.\n",
  "Created only the downstream files cited in the manuscript/Supplementary Information:\n",
  "  Main article: Figure2.png-Figure7.png, Table1.csv, Table2.csv\n",
  "  Supplementary: FigureS1.png-FigureS5.png, TableS1.csv, TableS2.csv"
)

