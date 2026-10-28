# One timed read in R: print elapsed seconds.
#   Rscript bench/read_case.R <tool> <task> <file>
# task: full (every variable), five (V1, V100, V200, V300, V400),
# touch (full, then compare every value of every string column, which
# makes all of dtatools' packed strings) or head (full, then head() and
# a filter on a numeric column).
args <- commandArgs(trailingOnly = TRUE)
tool <- args[[1]]; task <- args[[2]]; file <- args[[3]]
cols <- c("V1", "V100", "V200", "V300", "V400")
# Load packages before the clock starts, as the Python and JS runs do.
invisible(loadNamespace(tool))
invisible(loadNamespace("tidyselect"))
touch <- function(d) for (x in d) if (is.character(x)) sum(x == "x")
elapsed <- system.time(switch(paste(tool, task),
  "dtatools full" = dtatools::read_dta(file),
  "dtatools touch" = touch(dtatools::read_dta(file)),
  "dtatools head" = { d <- dtatools::read_dta(file); print(head(d)); d[d$i > 29990, ] },
  "dtatools five" = dtatools::read_dta(file, col_select = cols),
  "haven full" = haven::read_dta(file),
  "haven five" = haven::read_dta(file, col_select = tidyselect::all_of(cols)),
  "readstata13 full" = readstata13::read.dta13(file, convert.factors = FALSE, convert.dates = FALSE),
  "readstata13 five" = readstata13::read.dta13(file, select.cols = cols, convert.factors = FALSE, convert.dates = FALSE)
))[["elapsed"]]
cat(sprintf("%.2f\n", elapsed))
