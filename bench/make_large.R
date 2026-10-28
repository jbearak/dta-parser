# Write the read benchmarks' files with dtatools, from data made here
# with a fixed seed (they are generated, not committed).
#   Rscript bench/make_large.R <dir>
#   long.dta: 10M rows, 12 variables of every storage type (about 0.6 GB)
#   wide.dta: 1.5M rows, 400 doubles (about 4.8 GB, past 4 GiB)
#   groups.dta: 15M rows shaped like survey data: a str20 column of 300
#   values in random order and a byte column of 5 values plus `.`
dir <- commandArgs(trailingOnly = TRUE)[[1]]
dir.create(dir, showWarnings = FALSE)
set.seed(1)
n <- 1e7
long <- data.frame(
  b = sample(c(0:100, NA), n, TRUE), i = sample.int(30000L, n, TRUE),
  l = sample.int(2e9, n, TRUE), f = round(runif(n), 3),
  d1 = rnorm(n), d2 = rnorm(n), d3 = ifelse(runif(n) < 0.1, NA, rnorm(n)),
  d4 = rnorm(n), d5 = rnorm(n), d6 = rnorm(n),
  s1 = sample(c("alpha", "beta", "gamma", "delta"), n, TRUE),
  s2 = sprintf("id%07d", sample.int(n))
)
attr(long$b, "storage") <- "byte"; attr(long$i, "storage") <- "int"
attr(long$f, "storage") <- "float"
dtatools::save_dta(long, file.path(dir, "long.dta"))
rm(long); invisible(gc())

n <- 1.5e6
wide <- as.data.frame(matrix(rnorm(n * 400), n, 400))
dtatools::save_dta(wide, file.path(dir, "wide.dta"))
rm(wide); invisible(gc())

set.seed(2)
n <- 1.5e7
groups <- dtatools::dibble(
  s = sample(sprintf("survey %03d of 300", 1:300), n, TRUE),
  a = dtatools::dta_num(sample(c(1:5, NA), n, TRUE), storage = "byte")
)
dtatools::save_dta(groups, file.path(dir, "groups.dta"))
