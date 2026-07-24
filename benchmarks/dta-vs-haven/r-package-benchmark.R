args <- commandArgs(trailingOnly = TRUE)
rows <- if (length(args) >= 1) as.integer(args[[1]]) else 100000L
warmup <- if (length(args) >= 2) as.integer(args[[2]]) else 2L
iterations <- if (length(args) >= 3) as.integer(args[[3]]) else 5L
if (any(is.na(c(rows, warmup, iterations))) || any(c(rows, warmup, iterations) < 1)) {
    stop("usage: r-package-benchmark.R [rows] [warmup] [iterations]")
}
if (!requireNamespace("haven", quietly = TRUE)) stop("haven is required")

file_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(file_argument)) {
    sub("^--file=", "", file_argument[[1]])
} else {
    "benchmarks/dta-vs-haven/r-package-benchmark.R"
}
root <- normalizePath(file.path(dirname(script_path), "../.."))
package_dir <- file.path(root, "r-package", "dtaparser")
library_dir <- tempfile("dtaparser-library-")
data_dir <- tempfile("dtaparser-data-")
dir.create(library_dir)
dir.create(data_dir)
on.exit(unlink(c(library_dir, data_dir), recursive = TRUE), add = TRUE)

status <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", "--no-multiarch", "-l", shQuote(library_dir),
      shQuote(package_dir)),
    stdout = TRUE, stderr = TRUE
)
if (!is.null(attr(status, "status")) && attr(status, "status") != 0) {
    stop(paste(status, collapse = "\n"))
}
.libPaths(c(library_dir, .libPaths()))
library(dtaparser)

set.seed(20260724)
numeric_data <- as.data.frame(replicate(
    20, stats::runif(rows), simplify = FALSE
))
names(numeric_data) <- sprintf("num%02d", seq_len(20))
mixed_data <- data.frame(
    id = as.double(seq_len(rows)),
    measure = stats::rnorm(rows),
    fraction = stats::runif(rows),
    group = haven::labelled(
        as.double((seq_len(rows) - 1L) %% 5L),
        c(control = 0, alpha = 1, beta = 2, gamma = 3, delta = 4)
    ),
    tagged = replace(
        as.double(seq_len(rows)),
        seq.int(1L, rows, by = 101L), haven::tagged_na("a")
    ),
    text_short = sprintf("s%07d", seq_len(rows)),
    text_repeated = rep(
        c("north", "south", "east", "west"), length.out = rows
    ),
    stringsAsFactors = FALSE
)
files <- c(
    numeric = file.path(data_dir, "numeric.dta"),
    mixed = file.path(data_dir, "mixed.dta")
)
haven::write_dta(numeric_data, files[["numeric"]], version = 14)
haven::write_dta(mixed_data, files[["mixed"]], version = 14)

elapsed <- function(read_once) {
    for (index in seq_len(warmup)) read_once()
    vapply(seq_len(iterations), function(index) {
        start <- as.numeric(Sys.time())
        result <- read_once()
        stopifnot(nrow(result) == rows)
        (as.numeric(Sys.time()) - start) * 1000
    }, numeric(1))
}
elapsed_stage <- function(operation) {
    for (index in seq_len(warmup)) operation()
    vapply(seq_len(iterations), function(index) {
        start <- as.numeric(Sys.time())
        invisible(operation())
        (as.numeric(Sys.time()) - start) * 1000
    }, numeric(1))
}
median_ms <- function(values) stats::median(values)

cat("dataset\treader\tmedian ms\traw samples (ms)\n")
for (name in names(files)) {
    dta_samples <- elapsed(function() dtaparser::read_dta(files[[name]]))
    haven_samples <- elapsed(function() haven::read_dta(files[[name]]))
    cat(sprintf(
        "%s\tdtaparser R package\t%.2f\t%s\n",
        name, median_ms(dta_samples), paste(round(dta_samples, 2), collapse = ",")
    ))
    cat(sprintf(
        "%s\thaven\t%.2f\t%s\n",
        name, median_ms(haven_samples), paste(round(haven_samples, 2), collapse = ",")
    ))
    cat(sprintf(
        "%s\trelative throughput\t%.2fx\t\n",
        name, median_ms(haven_samples) / median_ms(dta_samples)
    ))

    file <- files[[name]]
    size <- file.info(file)$size
    bytes <- readBin(file, what = "raw", n = size)
    context <- dtaparser:::.dtaparser_context()
    context$assign("__dtaparser_input", bytes)
    context$assign("__dtaparser_skip", 0L)
    context$assign("__dtaparser_n_max", -1L)
    parse_expression <- paste0(
        "__dtaparser_result = dtaParserRead(",
        "__dtaparser_input, __dtaparser_skip, __dtaparser_n_max)"
    )
    context$eval(parse_expression)
    parsed <- context$get(
        "__dtaparser_result", simplifyVector = FALSE
    )
    stages <- list(
        file_read = elapsed_stage(function() {
            readBin(file, what = "raw", n = size)
        }),
        r_to_v8_bytes = elapsed_stage(function() {
            context$assign("__dtaparser_input", bytes)
        }),
        javascript_parse = elapsed_stage(function() {
            context$eval(parse_expression)
        }),
        v8_to_r_result = elapsed_stage(function() {
            context$get("__dtaparser_result", simplifyVector = FALSE)
        }),
        r_tibble = elapsed_stage(function() {
            dtaparser:::.dtaparser_as_tibble(parsed)
        })
    )
    stage_medians <- vapply(stages, median_ms, numeric(1))
    residual <- median_ms(dta_samples) - sum(stage_medians)
    cat("stage\tmedian ms\t% of package read\n")
    for (stage in names(stage_medians)) {
        cat(sprintf(
            "%s\t%.2f\t%.1f%%\n", stage, stage_medians[[stage]],
            stage_medians[[stage]] / median_ms(dta_samples) * 100
        ))
    }
    cat(sprintf(
        "composition/noise residual\t%.2f\t%.1f%%\n",
        residual, residual / median_ms(dta_samples) * 100
    ))
}
