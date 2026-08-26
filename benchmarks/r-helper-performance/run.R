parse_positive_integer <- function(value, argument, default) {
    if (is.null(value)) return(default)
    if (!grepl("^[1-9][0-9]*$", value)) {
        stop(argument, " must be a positive decimal integer", call. = FALSE)
    }
    result <- suppressWarnings(as.numeric(value))
    if (!is.finite(result) || result > .Machine$integer.max) {
        stop(argument, " exceeds R's integer range", call. = FALSE)
    }
    as.integer(result)
}

arguments <- commandArgs(trailingOnly = TRUE)
iterations <- parse_positive_integer(
    if (length(arguments) >= 1L) arguments[[1L]] else NULL,
    "iterations",
    12L
)
rows <- parse_positive_integer(
    if (length(arguments) >= 2L) arguments[[2L]] else NULL,
    "rows",
    5000000L
)

benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) {
    stop(
        "set DTAPARSER_BENCH_LIB to an isolated library containing dtaparser",
        call. = FALSE
    )
}
benchmark_library <- normalizePath(benchmark_library, winslash = "/")
.libPaths(c(benchmark_library, .libPaths()))

required <- c("dtaparser", "foreign", "haven")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0L) {
    stop("Missing benchmark dependencies: ", paste(missing, collapse = ", "),
         call. = FALSE)
}
loaded_library <- normalizePath(
    dirname(find.package("dtaparser")), winslash = "/"
)
if (!identical(loaded_library, benchmark_library)) {
    stop("dtaparser was not loaded from DTAPARSER_BENCH_LIB", call. = FALSE)
}

workspace <- tempfile("dtaparser-helper-benchmark-")
dir.create(workspace)
on.exit(unlink(workspace, recursive = TRUE), add = TRUE)
fixture <- file.path(workspace, "labelled-integers.dta")
foreign::write.dta(
    data.frame(x = factor(
        rep(c("One", "Two", "One", "Four"), length.out = rows),
        levels = c("One", "Two", "Four")
    )),
    fixture,
    version = 10L
)

fresh_source <- function() {
    source <- dtaparser::read_dta(fixture)$x
    stopifnot(dtaparser:::.is_unmaterialized_numeric_altrep(source))
    source
}

ours_source <- fresh_source()
ours_factor <- dtaparser::factor_from_labels(
    ours_source,
    drop_unused = TRUE
)
haven_source <- fresh_source()
haven_factor <- haven::as_factor(haven_source)
stopifnot(
    identical(as.character(ours_factor), as.character(haven_factor)),
    identical(levels(ours_factor), levels(haven_factor)),
    dtaparser:::.is_unmaterialized_numeric_altrep(ours_source),
    !dtaparser:::.is_unmaterialized_numeric_altrep(haven_source)
)

ours_source <- fresh_source()
ours_table <- dtaparser::tab(ours_source)
haven_source <- fresh_source()
haven_table <- table(haven::as_factor(haven_source))
stopifnot(
    identical(as.vector(ours_table), as.vector(haven_table)),
    identical(dimnames(ours_table)[[1L]], dimnames(haven_table)[[1L]]),
    dtaparser:::.is_unmaterialized_numeric_altrep(ours_source),
    !dtaparser:::.is_unmaterialized_numeric_altrep(haven_source)
)

time_case <- function(operation) {
    vapply(seq_len(iterations), function(index) {
        source <- fresh_source()
        invisible(gc(FALSE))
        started <- proc.time()[["elapsed"]]
        result <- operation(source)
        elapsed <- proc.time()[["elapsed"]] - started
        stopifnot(length(result) > 0L)
        elapsed
    }, numeric(1))
}

timings <- list(
    factor_from_labels = time_case(function(source) {
        dtaparser::factor_from_labels(source, drop_unused = TRUE)
    }),
    haven_as_factor = time_case(haven::as_factor),
    tab = time_case(dtaparser::tab),
    table_haven_factor = time_case(function(source) {
        table(haven::as_factor(source))
    })
)

script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_directory <- dirname(normalizePath(
    sub("^--file=", "", script_argument), winslash = "/"
))
memory_worker <- file.path(script_directory, "memory-worker.R")

extract_memory_value <- function(lines, label) {
    match <- grep(paste0(label, "$"), lines, value = TRUE)
    if (length(match) != 1L) {
        stop("Could not read `", label, "` from /usr/bin/time", call. = FALSE)
    }
    as.numeric(sub(paste0("[[:space:]]+", label, "$"), "", trimws(match)))
}

measure_memory <- function(operation) {
    output <- tempfile("dtaparser-helper-memory-")
    on.exit(unlink(output), add = TRUE)
    status <- system2(
        "/usr/bin/time",
        c(
            "-l",
            shQuote(file.path(R.home("bin"), "Rscript")),
            "--vanilla",
            shQuote(memory_worker),
            shQuote(fixture),
            operation
        ),
        stdout = output,
        stderr = output
    )
    lines <- readLines(output, warn = FALSE)
    if (status != 0L) stop(paste(lines, collapse = "\n"), call. = FALSE)

    materialized <- grep("^source_materialized ", lines, value = TRUE)
    if (length(materialized) != 1L) {
        stop("Memory worker did not report source state", call. = FALSE)
    }
    list(
        maximum_rss_bytes = extract_memory_value(
            lines, "maximum resident set size"
        ),
        peak_footprint_bytes = extract_memory_value(
            lines, "peak memory footprint"
        ),
        source_materialized = identical(
            sub("^source_materialized ", "", materialized), "TRUE"
        )
    )
}

expected_materialization <- c(
    factor_from_labels = FALSE,
    haven_as_factor = TRUE,
    tab = FALSE,
    table_haven_factor = TRUE
)
memory <- if (identical(Sys.info()[["sysname"]], "Darwin")) {
    lapply(names(timings), measure_memory)
} else {
    lapply(names(timings), function(operation) {
        list(
            maximum_rss_bytes = NA_real_,
            peak_footprint_bytes = NA_real_,
            source_materialized = expected_materialization[[operation]]
        )
    })
}

summary <- data.frame(
    operation = names(timings),
    median_seconds = vapply(timings, median, numeric(1)),
    minimum_seconds = vapply(timings, min, numeric(1)),
    maximum_rss_mb = vapply(memory, `[[`, numeric(1), "maximum_rss_bytes") /
        1024 ^ 2,
    peak_footprint_mb = vapply(
        memory, `[[`, numeric(1), "peak_footprint_bytes"
    ) / 1024 ^ 2,
    materializes_source = vapply(
        memory, `[[`, logical(1), "source_materialized"
    ),
    row.names = NULL
)

cat("dtaparser ", as.character(utils::packageVersion("dtaparser")), "\n",
    "haven ", as.character(utils::packageVersion("haven")), "\n",
    "R ", as.character(getRversion()), "\n",
    "platform ", R.version$platform, "\n",
    "rows ", rows, "\n",
    "iterations ", iterations, "\n",
    sep = "")
print(summary, row.names = FALSE)
