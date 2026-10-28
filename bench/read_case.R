# One timed read in R: print elapsed seconds.
#   Rscript bench/read_case.R <tool> <task> <file>
# task: full (every variable) or five (V1, V100, V200, V300, V400).
args <- commandArgs(trailingOnly = TRUE)
tool <- args[[1]]; task <- args[[2]]; file <- args[[3]]
cols <- c("V1", "V100", "V200", "V300", "V400")
elapsed <- system.time(switch(paste(tool, task),
  "dtatools full" = dtatools::read_dta(file),
  "dtatools five" = dtatools::read_dta(file, col_select = cols),
  "haven full" = haven::read_dta(file),
  "haven five" = haven::read_dta(file, col_select = tidyselect::all_of(cols)),
  "readstata13 full" = readstata13::read.dta13(file, convert.factors = FALSE, convert.dates = FALSE),
  "readstata13 five" = readstata13::read.dta13(file, select.cols = cols, convert.factors = FALSE, convert.dates = FALSE)
))[["elapsed"]]
cat(sprintf("%.2f\n", elapsed))
