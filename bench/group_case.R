# Time dta_group_tag and dta_group_id over 10M rows of two columns.
#   Rscript bench/group_case.R
set.seed(1)
n <- 1e7
a <- dtatools::dta_num(sample(c(1:50, NA), n, TRUE))
s <- sample(sprintf("survey %03d", 1:300), n, TRUE)
cat(sprintf("dta_group_tag %.2f\n", system.time(dtatools::dta_group_tag(a, s, missing = TRUE))[["elapsed"]]))
cat(sprintf("dta_group_id %.2f\n", system.time(dtatools::dta_group_id(a, s, missing = TRUE))[["elapsed"]]))
