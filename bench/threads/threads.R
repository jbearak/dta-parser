# Wall and CPU time of one task in R, with one thread and with the
# default (plan 0007): the median of five runs, CPU from system.time.
#
#   Rscript bench/threads/threads.R FILE.dta [read|columns|write] ...
#
# dtatools' read_dta and save_dta; reads in Stata mode (doubles), as the
# benchmark does.
suppressMessages(library(dtatools))
args <- commandArgs(trailingOnly = TRUE)
path <- args[[1]]
tasks <- args[-1]
out <- tempfile(fileext = ".dta")
data <- if ("write" %in% tasks) read_dta(path)
first5 <- head(names(read_dta(path, n_max = 0)), 5)
run <- function(task) switch(task,
  read = read_dta(path),
  columns = read_dta(path, col_select = dplyr::all_of(first5)),
  write = save_dta(data, out)
)
for (task in tasks) {
  cat(path, task, "\n")
  cat("threads  wall s  user s  sys s  cpu/1-thread  speedup\n")
  base <- NULL
  for (threads in list(1, 2, 3, 4, NULL)) {
    options(dtaparser.threads = threads)
    times <- t(vapply(1:5, function(i) {
      gc()
      t <- system.time(run(task))
      c(t[["elapsed"]], t[["user.self"]], t[["sys.self"]])
    }, numeric(3)))
    m <- times[order(times[, 1])[3], ]
    if (is.null(base)) base <- c(m[[1]], m[[2]] + m[[3]])
    cat(sprintf("%7s  %6.3f  %6.3f  %5.3f  %12.2f  %7.2f\n", if (is.null(threads)) "default" else threads,
                m[[1]], m[[2]], m[[3]], (m[[2]] + m[[3]]) / base[[2]], base[[1]] / m[[1]]))
  }
}
unlink(out)
