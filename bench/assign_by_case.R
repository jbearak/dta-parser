# Time how datakit's := groups its by columns, over 10M rows, on two
# builds of datakit: with no tagged NA (.a to .z) it should cost what
# it did; with them, it groups NA and each letter apart.
#   R CMD INSTALL -l <main-lib> <main's r/datakit>
#   R CMD INSTALL -l <branch-lib> r/datakit
#   Rscript bench/assign_by_case.R <main-lib> <branch-lib> [processes]
# Each case runs in fresh R processes, alternating the two builds and
# which goes first, and prints the median of their medians in ms.
args <- commandArgs(trailingOnly = TRUE)

cases <- c("double", "double_na", "integer_na", "character_na", "two_doubles_na",
           "dense_na", "many_groups_na", "tagged", "tagged_many_groups")

make_case <- function(case, n = 1e7) {
  set.seed(1)
  some_na <- function(k, share = 1 / 51) {
    v <- as.double(sample(k, n, TRUE))
    v[runif(n) < share] <- NA
    v
  }
  switch(case,
    double = data.frame(g = as.double(sample(50, n, TRUE))),
    double_na = data.frame(g = some_na(50)),
    integer_na = data.frame(g = as.integer(some_na(50))),
    character_na = data.frame(g = sample(c(letters, NA), n, TRUE)),
    two_doubles_na = data.frame(g = some_na(50), h = some_na(5, 1 / 6)),
    dense_na = data.frame(g = some_na(50, 1 / 3)),
    many_groups_na = data.frame(g = some_na(1e6)),
    tagged = {
      g <- some_na(50)
      g[is.na(g)][c(TRUE, FALSE)] <- dtaparser::tagged_na("a")
      data.frame(g = g)
    },
    tagged_many_groups = {
      g <- some_na(3, 0.9)
      g[is.na(g)][c(TRUE, FALSE)] <- dtaparser::tagged_na("a")
      data.frame(id = as.double(sample(1e6, n, TRUE)), g = g)
    })
}

# The grouping step of :=: datakit's by_groups() where it has one, and
# otherwise the vctrs call it replaced.
time_case <- function(case) {
  keys <- vctrs::new_data_frame(as.list(make_case(case)))
  ns <- asNamespace("datakit")
  group <- if (exists("by_groups", ns)) get("by_groups", ns) else function(k) vctrs::vec_group_loc(k)$loc
  # Each run allocates hundreds of MB, so R collects garbage in every
  # one, at points that shift with any other allocation; collecting
  # first keeps that from deciding the comparison.
  ms <- vapply(1:11, function(r) {
    gc()
    start <- bench::hires_time()
    group(keys)
    as.numeric(bench::hires_time() - start) * 1000
  }, 0)
  median(ms)
}

if (length(args) >= 2 && args[[1]] == "--case") {
  cat(time_case(args[[2]]), "\n")
} else {
  libs <- c(main = args[[1]], branch = args[[2]])
  processes <- if (length(args) >= 3) as.integer(args[[3]]) else 5L
  script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)))
  rscript <- file.path(R.home("bin"), "Rscript")
  for (case in cases) {
    ms <- list(main = numeric(), branch = numeric())
    for (p in seq_len(processes)) {
      for (build in if (p %% 2) names(libs) else rev(names(libs))) {
        out <- system2(rscript, c(shQuote(script), "--case", case), stdout = TRUE, stderr = FALSE,
                       env = paste0("R_LIBS=", libs[[build]]))
        ms[[build]] <- c(ms[[build]], as.numeric(out[length(out)]))
      }
    }
    cat(sprintf("%-20s main %7.1f ms (%5.1f-%5.1f)  branch %7.1f ms (%5.1f-%5.1f)\n", case,
                median(ms$main), min(ms$main), max(ms$main), median(ms$branch), min(ms$branch), max(ms$branch)))
  }
}
