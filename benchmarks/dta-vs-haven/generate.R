suppressPackageStartupMessages(library(haven))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
    stop("usage: generate.R <output-directory> <rows>")
}

output_dir <- args[[1]]
rows <- as.integer(args[[2]])
if (is.na(rows) || rows < 1) stop("rows must be a positive integer")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

set.seed(20260724)

numeric_data <- as.data.frame(replicate(
    20, stats::runif(rows), simplify = FALSE
))
names(numeric_data) <- sprintf("num%02d", seq_len(20))
attr(numeric_data, "label") <- "Deterministic numeric benchmark"
write_dta(
    numeric_data,
    file.path(output_dir, "numeric-v118.dta"),
    version = 14
)

group <- labelled(
    as.double((seq_len(rows) - 1L) %% 5L),
    c(control = 0, alpha = 1, beta = 2, gamma = 3, delta = 4),
    label = "Study group"
)
tagged <- as.double(seq_len(rows)) / 10
tagged[seq.int(1L, rows, by = 101L)] <- tagged_na("a")
tagged[seq.int(51L, rows, by = 103L)] <- NA_real_
mixed_data <- data.frame(
    id = as.double(seq_len(rows)),
    measure = stats::rnorm(rows),
    fraction = stats::runif(rows),
    group = group,
    tagged = tagged,
    text_short = sprintf("s%07d", seq_len(rows)),
    text_repeated = rep(c("north", "south", "east", "west"),
                        length.out = rows),
    stringsAsFactors = FALSE
)
attr(mixed_data, "label") <- "Deterministic mixed benchmark"
attr(mixed_data$id, "label") <- "Row identifier"
attr(mixed_data$measure, "label") <- "Normal measurement"
write_dta(
    mixed_data,
    file.path(output_dir, "mixed-v118.dta"),
    version = 14
)
