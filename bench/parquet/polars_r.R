# R's read_parquet_pl() against polars' own reader and datakit's tibble
# read_parquet(), on one DHS file (plan 0025, stage 4). Small, with no
# target: it records what the polars path costs.
#
#   Rscript bench/parquet/polars_r.R SURVEY RECODE DATA_DIR [RUNS]
#
# reads DTA_DHS_DIR/SURVEY/RECODE.dta (read only, ADR 0013), writes it
# as Parquet into DATA_DIR with datakit's defaults, as convert.R does
# (never committed), then times each reader RUNS times (default 10) in
# this process, after one warm-up call each, with gc() before every
# call; the file is in the page cache. Cases: the whole file, and five
# columns spread over it (bench/parquet/run.py's rule). Each cell is
# the best wall time of the runs, with the median beside it, and the CPU
# time (user plus system, this process and its threads) of the best run.
# Every library uses its default thread count. Writes
# bench/results/parquet-polars-r.md.
#
# Needs dtaparser, datakit, polars and nanoarrow (R_LIBS may point at a
# scratch library holding them).

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) >= 3)
survey <- args[[1]]
recode <- args[[2]]
data_dir <- args[[3]]
runs <- if (length(args) >= 4) as.integer(args[[4]]) else 10L
dhs <- Sys.getenv("DTA_DHS_DIR")
if (!nzchar(dhs)) stop("set DTA_DHS_DIR", call. = FALSE)

suppressPackageStartupMessages({
  library(datakit)
  library(polars)
})

dta <- file.path(dhs, survey, paste0(recode, ".dta"))
label <- paste("DHS", survey, recode)
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
pq <- file.path(data_dir, paste0("dhs-", gsub(" ", "-", tolower(survey)), "-", recode, ".parquet"))
if (!file.exists(pq)) {
  save_parquet(dtaparser::read_dta(dta), paste0(pq, ".tmp"))
  invisible(file.rename(paste0(pq, ".tmp"), pq))
}
info <- read_parquet_info(pq)
names <- info$columns$name
# Five columns spread over the file.
cols <- names[unique(round(seq(1, length(names), length.out = 5)))]

readers <- list(
  "datakit read_parquet_pl()" = list(
    full = function() read_parquet_pl(pq),
    five = function() read_parquet_pl(pq, col_select = cols)
  ),
  "polars pl$read_parquet()" = list(
    full = function() pl$read_parquet(pq),
    five = function() pl$scan_parquet(pq)$select(cols)$collect()
  ),
  "datakit read_parquet() (tibble)" = list(
    full = function() read_parquet(pq),
    five = function() read_parquet(pq, col_select = cols)
  )
)

cpu <- function() {
  t <- proc.time()
  t[["user.self"]] + t[["sys.self"]]
}
time_one <- function(f) {
  gc()
  c0 <- cpu()
  w0 <- Sys.time()
  x <- f()
  w <- as.numeric(Sys.time() - w0, units = "secs")
  c <- cpu() - c0
  rm(x)
  c(wall = w, cpu = c)
}

load_before <- tryCatch(as.numeric(sub(",", ".", strsplit(trimws(sub(".*load averages?: ", "", system("uptime", intern = TRUE))),
                                                    "[ ,]+")[[1]][[1]])), error = function(e) NA_real_)
cases <- c(full = "whole file", five = "five columns")
results <- list()
for (case in names(cases)) {
  for (r in names(readers)) {
    f <- readers[[r]][[case]]
    invisible(f())  # warm-up: first-call costs and the page cache
    times <- t(vapply(seq_len(runs), function(i) time_one(f), c(wall = 0, cpu = 0)))
    best <- which.min(times[, "wall"])
    results[[length(results) + 1]] <- data.frame(case = cases[[case]], reader = r, best = times[best, "wall"],
                                                 median = stats::median(times[, "wall"]), cpu = times[best, "cpu"])
  }
}
results <- do.call(rbind, results)

ms <- function(s) formatC(s * 1000, format = "f", digits = 1)
cpu_name <- tryCatch(system("sysctl -n machdep.cpu.brand_string", intern = TRUE), error = function(e) "unknown",
                     warning = function(w) "unknown")
lines <- c(
  "# Parquet benchmark: R's polars reader (plan 0025, stage 4; after plan 0027)",
  "",
  "Written by `bench/parquet/polars_r.R`. No target: this records what `read_parquet_pl()` costs beside polars' own reader and datakit's tibble `read_parquet()`.",
  "",
  sprintf("File: %s, %s rows and %s columns, written as Parquet by datakit's `save_parquet()` with its defaults (%.1f MB).",
          label, format(info$rows, big.mark = ","), format(length(names), big.mark = ","), file.size(pq) / 1e6),
  sprintf("Five columns: %s.", paste0("`", cols, "`", collapse = ", ")),
  "",
  sprintf("Method: each reader once to warm up, then %d runs in one R process, `gc()` before each; the best wall time, the median wall time, and the CPU time (user plus system) of the best run. Default thread counts. One-minute load average before the runs: %s.",
          runs, format(load_before)),
  "",
  sprintf("R %s, datakit %s, dtaparser %s, polars %s, nanoarrow %s; %s.", getRversion(), packageVersion("datakit"),
          packageVersion("dtaparser"), packageVersion("polars"), packageVersion("nanoarrow"), cpu_name),
  "",
  "| case | reader | best wall ms | median wall ms | CPU ms (best run) |",
  "|---|---|---|---|---|",
  sprintf("| %s | %s | %s | %s | %s |", results$case, gsub("|", "\\|", results$reader, fixed = TRUE), ms(results$best),
          ms(results$median), ms(results$cpu))
)
writeLines(lines, "bench/results/parquet-polars-r.md")
writeLines(lines)
