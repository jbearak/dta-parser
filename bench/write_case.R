# Make one benchmark dataset and write it with one tool, printing the
# write's elapsed seconds. Run by bench/write.sh under /usr/bin/time, so
# peak RSS covers making the data plus the write; tool "none" measures
# making the data alone.
#   Rscript bench/write_case.R <case> <tool: none|haven|dtatools> <out.dta>
args <- commandArgs(trailingOnly = TRUE)
case <- args[[1]]; tool <- args[[2]]; out <- args[[3]]
set.seed(1)

texts <- function(n, len, distinct) {
  pool <- vapply(seq_len(distinct), function(i) {
    paste(sample(c(letters, " "), len, replace = TRUE), collapse = "")
  }, "")
  pool[sample.int(distinct, n, replace = TRUE)]
}

data <- switch(case,
  # 5M rows of numbers in every storage type, with some missing values.
  numeric = {
    n <- 5e6
    data.frame(
      b = sample(c(0:100, NA), n, TRUE), i = sample.int(30000L, n, TRUE),
      l = sample.int(2e9, n, TRUE), f = round(runif(n), 3),
      d1 = rnorm(n), d2 = rnorm(n), d3 = ifelse(runif(n) < 0.1, NA, rnorm(n)),
      d4 = rnorm(n), d5 = rnorm(n), d6 = rnorm(n)
    )
  },
  # 5M rows of three short strings.
  strn = {
    n <- 5e6
    data.frame(a = texts(n, 8, 1000), b = texts(n, 20, 50), c = texts(n, 3, 26))
  },
  # 200k rows of a 3000-byte strL drawn from 20 texts.
  strl_repeated = data.frame(id = seq_len(2e5), s = texts(2e5, 3000, 20)),
  # 100k rows of distinct 3000-byte strLs.
  strl_distinct = data.frame(id = seq_len(1e5), s = texts(1e5, 3000, 1e5)),
  # 100k rows of three strL columns, each drawn from 50 texts.
  strl_several = data.frame(a = texts(1e5, 3000, 50), b = texts(1e5, 2500, 50), c = texts(1e5, 4000, 50)),
  stop("unknown case ", case)
)
if (case == "numeric") {
  # Give dtatools the storage types haven picks, so both write the same file.
  attr(data$b, "storage") <- "byte"; attr(data$i, "storage") <- "int"
  attr(data$l, "storage") <- "long"; attr(data$f, "storage") <- "double"
}
invisible(gc())
elapsed <- switch(tool,
  none = 0,
  haven = system.time(haven::write_dta(data, out))[["elapsed"]],
  dtatools = system.time(dtatools::save_dta(data, out))[["elapsed"]]
)
cat(sprintf("%s %s %.2f\n", case, tool, elapsed))
