# Time dta_group_tag, dta_group_id, tab, unique and == over 10M rows.
#   Rscript bench/group_case.R
set.seed(1)
n <- 1e7
a <- dtatools::dta_num(sample(c(1:50, NA), n, TRUE))
s <- sample(sprintf("survey %03d", 1:300), n, TRUE)
cat(sprintf("dta_group_tag %.2f\n", system.time(dtatools::dta_group_tag(a, s, missing = TRUE))[["elapsed"]]))
cat(sprintf("dta_group_id %.2f\n", system.time(dtatools::dta_group_id(a, s, missing = TRUE))[["elapsed"]]))
cat(sprintf("tab %.2f\n", system.time(dtatools::tab(a, missing = TRUE))[["elapsed"]]))
cat(sprintf("unique %.2f\n", system.time(unique(a))[["elapsed"]]))
cat(sprintf("== %.2f\n", system.time(a == 3)[["elapsed"]]))
