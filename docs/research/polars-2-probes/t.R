suppressPackageStartupMessages({library(dplyr); library(dtaparser); library(vctrs); library(bench)})
set.seed(1); n <- 1e7
x <- as.double(sample.int(1000, n, TRUE)); x[sample.int(n, n/10)] <- tagged_na(sample(letters[1:3], n/10, TRUE)); x[sample.int(n, n/20)] <- NA
d <- tibble::tibble(x = x, w = runif(n))
by_a <- function(x) tibble::tibble(x = x, x_letter = na_tag(x))
keys <- getFromNamespace("dta_keys", "dtatools")
registerS3method("vec_proxy_equal", "datakit_by", function(x, ...) keys(unclass(x)), envir = asNamespace("vctrs"))
b <- mark(plain = summarise(group_by(d, x), n = n(), .groups = "drop"),
          A_letter_column = summarise(group_by(d, by_a(x)), n = n(), .groups = "drop"),
          B_proxy_class = summarise(group_by(d, x = structure(x, class = "datakit_by")), n = n(), .groups = "drop"),
          na_tag_alone = na_tag(x), iterations = 5, check = FALSE)
print(data.frame(expr = as.character(b$expression), median_ms = round(as.numeric(b$median) * 1e3)))
