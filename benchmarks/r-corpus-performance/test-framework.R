script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
source(file.path(dirname(script_path), "common.R"), local = TRUE)

root <- tempfile("r-corpus-performance-")
dir.create(root)
on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
write_fixture <- function(name, bytes) {
    path <- file.path(root, name)
    writeBin(bytes, path)
    path
}

legacy <- write_fixture("legacy.dta", as.raw(c(111L, 0L, 0L)))
modern <- write_fixture(
    "modern.dta",
    charToRaw("<stata_dta><header><release>118<tail>")
)
modern_119 <- write_fixture(
    "modern-119.dta",
    charToRaw("<stata_dta><header><release>119<tail>")
)
unknown <- write_fixture("unknown.dta", as.raw(c(1L, 2L, 3L)))
empty <- write_fixture("empty.dta", raw())
stopifnot(
    identical(corpus_dta_release(legacy), 111L),
    identical(corpus_dta_release(modern), 118L),
    identical(corpus_dta_release(modern_119), 119L),
    is.na(corpus_dta_release(unknown)),
    is.na(corpus_dta_release(empty)),
    is.na(corpus_dta_release(file.path(root, "missing.dta")))
)

inventory <- data.frame(
    corpus = rep("DHS", 4L),
    id = c("DHS-0001", "DHS-0002", "DHS-0003", "DHS-0004"),
    release = c(117L, 118L, 118L, NA_integer_),
    stringsAsFactors = FALSE
)
inventory$bytes <- c(1e9, 2e9, 4e9, 0.5e9)
raw <- data.frame(
    corpus = rep("DHS", 9L),
    id = rep(c("DHS-0001", "DHS-0002", "DHS-0003"), each = 3L),
    reader = rep(c("dtaparser", "haven", "stata"), 3L),
    reader_order = rep(1:3, 3L),
    status = c(rep("ok", 8L), "error"),
    elapsed_seconds = c(2, 8, 1, 1, 6, 0.25, 5, 9, NA),
    rows = rep(10, 9L),
    columns = rep(2, 9L),
    rss_bytes = c(4e9, 5e9, 2e9, 3e9, 4e9, 1e9, 6e9, 7e9, NA),
    footprint_bytes = rep(NA_real_, 9L),
    stringsAsFactors = FALSE
)
paired <- corpus_pair_results(raw, inventory)
stopifnot(
    identical(paired$id, c("DHS-0001", "DHS-0002")),
    identical(paired$release, c(117L, 118L))
)
summary <- corpus_performance_summary(inventory, paired, c("DHS", "MICS"))
stopifnot(
    identical(summary$corpus, c("DHS", "DHS", "DHS", "DHS", "MICS")),
    identical(summary$release, c("117", "118", "unknown", "all", "all")),
    identical(summary$files, c(1L, 1L, 0L, 2L, 0L)),
    identical(summary$excluded_files, c(0L, 1L, 1L, 2L, 0L)),
    isTRUE(all.equal(summary$input_gb, c(1, 2, 0, 3, 0))),
    isTRUE(all.equal(
        summary$dtaparser_to_haven_time_ratio[c(1:2, 4)],
        c(0.25, 1 / 6, 3 / 14)
    )),
    isTRUE(all.equal(
        summary$dtaparser_to_stata_time_ratio[c(1:2, 4)],
        c(2, 4, 3 / 1.25)
    )),
    all(is.na(summary$dtaparser_seconds[c(3, 5)])),
    all(is.na(summary$dtaparser_peak_rss_gb[c(3, 5)]))
)

cat("R corpus performance framework: PASS\n")
