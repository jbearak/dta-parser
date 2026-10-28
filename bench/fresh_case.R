# One timed operation on a freshly read groups.dta (from make_large.R),
# so its strings are not made yet: print elapsed seconds.
#   Rscript bench/fresh_case.R <task> <file>
# task: read (read_dta alone), group (read, then dta_group_id(s, a)),
# tab (read, then tab(s)), again (read and dta_group_id untimed, then a
# second dta_group_id).
args <- commandArgs(trailingOnly = TRUE)
task <- args[[1]]; file <- args[[2]]
invisible(loadNamespace("dtatools"))
group <- function(d) dtatools::dta_group_id(d$s, d$a, missing = TRUE)
if (task == "again") {
  d <- dtatools::read_dta(file)
  invisible(group(d))
}
elapsed <- system.time(switch(task,
  read = dtatools::read_dta(file),
  group = group(dtatools::read_dta(file)),
  tab = dtatools::tab(dtatools::read_dta(file)$s),
  again = group(d)
))[["elapsed"]]
cat(sprintf("%.2f\n", elapsed))
