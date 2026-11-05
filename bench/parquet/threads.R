# Parquet reads and writes at 1 to 16 threads (plan 0018, "Threads"), to
# set the default by plan 0007's rule: CPU time at most 1.15 times one
# thread's, and each thread added at least half efficient.
#
#   Rscript bench/parquet/threads.R DATA_DIR OUT.json KEY ...
#
# For each KEY, reads DATA_DIR/ours/KEY.parquet whole and five columns of
# it, and writes what it read, with options(dtaparser.threads = n). Each
# case runs once to warm up, then nine times; the median wall and CPU
# (user plus system) time are kept. Run on a quiet machine.
# THREAD_COUNTS (default 1,2,3,4,6,8,12,16), THREAD_RUNS (9) and
# THREAD_TASKS (read,five,write) narrow a run, to measure close cases
# again.
args <- commandArgs(trailingOnly = TRUE)
dir <- args[[1]]; out <- args[[2]]; keys <- args[-(1:2)]
suppressPackageStartupMessages({library(dtaparser); library(datakit)})
env <- function(name, default) strsplit(Sys.getenv(name, default), ",", fixed = TRUE)[[1]]
counts <- as.numeric(env("THREAD_COUNTS", "1,2,3,4,6,8,12,16"))
runs <- as.integer(env("THREAD_RUNS", "9"))
tasks <- env("THREAD_TASKS", "read,five,write")
cpu <- function() { t <- proc.time(); t[["user.self"]] + t[["sys.self"]] }
time_it <- function(f) {
  f()
  times <- replicate(runs, {
    invisible(gc())
    w <- as.numeric(Sys.time()); c0 <- cpu()
    f()
    c(as.numeric(Sys.time()) - w, cpu() - c0)
  })
  c(wall = stats::median(times[1, ]), cpu = stats::median(times[2, ]))
}
results <- list()
for (key in keys) {
  p <- file.path(dir, "ours", paste0(key, ".parquet"))
  info <- read_parquet_info(p)
  names <- info$columns$name
  five <- names[unique(round(seq(1, length(names), length.out = 5)))]
  options(dtaparser.threads = 1)
  data <- if ("write" %in% tasks) read_parquet(p)
  for (i in seq_along(data)) if (is.character(data[[i]])) { s <- character(length(data[[i]])); s[] <- data[[i]]; data[[i]] <- s }
  dst <- tempfile(fileext = ".parquet")
  for (n in counts) {
    options(dtaparser.threads = n)
    for (task in tasks) {
      f <- switch(task,
        read = function() read_parquet(p),
        five = function() read_parquet(p, col_select = five),
        write = function() save_parquet(data, dst))
      r <- time_it(f)
      results[[length(results) + 1]] <- list(key = key, task = task, threads = n, wall = r[["wall"]], cpu = r[["cpu"]],
                                             load = unname(utils::tail(as.numeric(strsplit(system("uptime", intern = TRUE), "[ ,]+")[[1]]), 3)[1]))
      cat(sprintf("%-26s %-5s %2d threads: %.3f s wall, %.3f s CPU\n", key, task, n, r[["wall"]], r[["cpu"]]))
    }
  }
  unlink(dst)
  rm(data); invisible(gc())
}
writeLines(jsonlite::toJSON(results, auto_unbox = TRUE, digits = NA), out)
