suppressPackageStartupMessages({library(dplyr); library(dtaparser); library(vctrs); library(bench)})
tag <- function(v) { t <- na_tag(v); ifelse(is.na(v) & !is.na(t), paste0(".", t), ifelse(is.na(v), ".", format(v))) }
set.seed(1); n <- 1e7
x <- as.double(sample.int(1000, n, TRUE)); x[sample.int(n, n/10)] <- tagged_na(sample(letters[1:3], n/10, TRUE)); x[sample.int(n, n/20)] <- NA
d <- tibble::tibble(x = x, w = runif(n))
# A: the column plus its letter, no class
by_a <- function(x) { nm <- "x"; tibble::tibble(x = x, x_letter = na_tag(x)) }
s <- d |> group_by(by_a(x)) |> summarise(n = n(), .groups = "drop")
cat("A groups:", nrow(s), " columns:", paste(names(s), collapse = ","), " letters kept in x:", paste(tag(tail(s$x, 4)), collapse = " "), "\n")
cat("A columns of the grouped frame:", paste(names(group_by(d, by_a(x))), collapse = ","), "\n")
cat("A count():", nrow(count(d, by_a(x))), " distinct():", nrow(distinct(d, by_a(x))), "\n")
ms <- function(e) sprintf("%.0f ms", median(as.numeric(mark(e, iterations = 3, check = FALSE)$time[[1]])) * 1e3)
cat("plain group_by(x):", ms(summarise(group_by(d, x), n = n())), "\n")
cat("A group_by(by_a(x)):", ms(summarise(group_by(d, by_a(x)), n = n())), "\n")
cat("na_tag(x) alone:", ms(na_tag(x)), "\n")
# B: one column with a proxy class
keys <- getFromNamespace("dta_keys", "dtatools")
by_b <- function(x) structure(x, class = "datakit_by")
registerS3method("vec_proxy_equal", "datakit_by", function(x, ...) keys(unclass(x)), envir = asNamespace("vctrs"))
sb <- d |> group_by(x = by_b(x)) |> summarise(n = n(), .groups = "drop")
cat("B groups:", nrow(sb), " class of x after:", class(sb$x), "\n")
gb <- group_by(d, x = by_b(x)); cat("B class of x in grouped frame:", class(gb$x), "\n")
cat("B group_by:", ms(summarise(group_by(d, x = by_b(x)), n = n())), "\n")
