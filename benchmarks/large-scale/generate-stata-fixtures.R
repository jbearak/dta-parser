args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
    stop("usage: generate-stata-fixtures.R SIZES_TSV MANIFEST_TSV")
}

sizes_path <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
manifest_path <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
script_dir <- dirname(script_path)
checkout_root <- normalizePath(file.path(script_dir, "..", ".."), winslash = "/")
target_root <- normalizePath(
    file.path(checkout_root, "target", "large-scale"), winslash = "/",
    mustWork = TRUE
)
expected_sizes_path <- file.path(script_dir, "stata-write-sizes.tsv")
if (!identical(sizes_path, expected_sizes_path) ||
    !identical(dirname(manifest_path), target_root)) {
    stop("Stata fixture inputs and outputs must use their canonical paths")
}
sys.source(file.path(script_dir, "stata-fixture.R"), envir = environment())
if (!requireNamespace("processx", quietly = TRUE)) stop("processx is required")

sizes <- read.delim(
    sizes_path, check.names = FALSE, stringsAsFactors = FALSE,
    colClasses = "character"
)
if (!identical(names(sizes), c("dataset", "target_bytes", "rows")) ||
    !identical(sizes$dataset, c("100mb", "1gb"))) {
    stop("Stata fixture size specification is invalid")
}
sizes$target_bytes <- suppressWarnings(as.numeric(sizes$target_bytes))
sizes$rows <- suppressWarnings(as.numeric(sizes$rows))
if (!identical(sizes$target_bytes, c(100000000, 1000000000)) ||
    any(!is.finite(sizes$rows) | sizes$rows <= 0 |
        sizes$rows != floor(sizes$rows))) {
    stop("Stata fixture sizes contain invalid values")
}

stata <- find_stata()
generator <- file.path(script_dir, "stata-generate-fixture.do")
generator_sha256 <- tolower(unname(tools::sha256sum(generator))[[1L]])
outputs <- file.path(
    target_root, c("synthetic-100mb.dta", "synthetic-1gb.dta")
)
rows <- vector("list", nrow(sizes))
staged_outputs <- character(nrow(sizes))
for (index in seq_len(nrow(sizes))) {
    work_dir <- tempfile(
        pattern = paste0("stata-fixture-", sizes$dataset[[index]], "-"),
        tmpdir = target_root
    )
    dir.create(work_dir)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    if (!file.copy(generator, file.path(work_dir, basename(generator)))) {
        stop("could not stage the Stata fixture generator")
    }
    process <- processx::run(
        stata,
        c("-q", "-b", "do", basename(generator), "output.dta",
          as.character(sizes$rows[[index]]), sizes$dataset[[index]],
          "result.tsv"),
        wd = work_dir, error_on_status = FALSE, echo = FALSE
    )
    result_path <- file.path(work_dir, "result.tsv")
    if (process$status != 0L || !file.exists(result_path)) {
        stop("Stata fixture process failed: ", process$stderr)
    }
    result <- read_stata_fixture_result(result_path)
    if (result$rows != sizes$rows[[index]]) {
        stop("Stata fixture row count differs from its size specification")
    }
    staged <- file.path(work_dir, "output.dta")
    if (!file.exists(staged) || file.info(staged)$size[[1L]] != result$bytes) {
        stop("Stata fixture output is missing or has an unexpected size")
    }
    staged_outputs[[index]] <- staged
    rows[[index]] <- data.frame(
        dataset = sizes$dataset[[index]], path = outputs[[index]],
        target_bytes = sizes$target_bytes[[index]],
        actual_bytes = file.info(staged)$size[[1L]],
        sha256 = tolower(unname(tools::sha256sum(staged))[[1L]]),
        rows = sizes$rows[[index]], columns = stata_fixture_columns,
        obs_bytes = stata_fixture_row_bytes,
        base_rows = stata_fixture_calibration_rows,
        creator = "stata-first-save", generator_sha256 = generator_sha256,
        stringsAsFactors = FALSE
    )
}
manifest <- do.call(rbind, rows)
overhead <- manifest$actual_bytes - manifest$rows * manifest$obs_bytes
if (length(unique(overhead)) != 1L || overhead[[1L]] <= 0 ||
    any(abs(manifest$actual_bytes - manifest$target_bytes) >
        stata_fixture_row_bytes / 2 + 0.5)) {
    stop("Stata fixture size does not match the declared fixed-width schema")
}
for (index in seq_along(outputs)) {
    if (!file.rename(staged_outputs[[index]], outputs[[index]])) {
        stop("could not publish Stata fixture ", outputs[[index]])
    }
}
temporary <- paste0(manifest_path, ".partial")
on.exit(unlink(temporary), add = TRUE)
write.table(
    manifest, temporary, sep = "\t", row.names = FALSE, quote = FALSE
)
if (!file.rename(temporary, manifest_path)) {
    stop("could not publish Stata fixture manifest")
}
print(manifest, row.names = FALSE)
