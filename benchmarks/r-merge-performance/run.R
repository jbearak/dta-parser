args <- commandArgs(TRUE)

parse_count <- function(value, default, argument) {
    if (length(value) == 0L || is.na(value[[1L]])) return(default)
    if (!grepl("^[1-9][0-9]*$", value[[1L]])) {
        stop(argument, " must be a positive decimal integer", call. = FALSE)
    }
    parsed <- suppressWarnings(as.double(value[[1L]]))
    if (!is.finite(parsed) || parsed > .Machine$integer.max) {
        stop(argument, " must be a positive decimal integer", call. = FALSE)
    }
    as.integer(parsed)
}

iterations <- parse_count(args[1L], 9L, "iterations")
base_iterations <- parse_count(args[2L], 5L, "base_iterations")

bench_library <- Sys.getenv("DTATOOLS_BENCH_LIB", unset = "")
if (!nzchar(bench_library)) {
    stop("DTATOOLS_BENCH_LIB must name the isolated package library",
         call. = FALSE)
}
bench_library <- normalizePath(bench_library, mustWork = TRUE)
.libPaths(c(bench_library, .libPaths()))

suppressMessages({
    library(bench)
    library(dplyr)
    library(dtatools)
})

loaded_library <- normalizePath(
    dirname(system.file(package = "dtatools")), mustWork = TRUE
)
if (!identical(loaded_library, bench_library)) {
    stop("dtatools was not loaded from DTATOOLS_BENCH_LIB", call. = FALSE)
}

fixture_dir <- file.path("target", "r-merge-performance")
dir.create(fixture_dir, recursive = TRUE, showWarnings = FALSE)
master_path <- file.path(fixture_dir, "master.dta")
using_path <- file.path(fixture_dir, "using.dta")

set.seed(7)
n_master <- 200000L
mothers <- sample.int(n_master, 120000L)
births_per <- sample(1:5, length(mothers), replace = TRUE)
n_using <- sum(births_per)
caseid <- sprintf(
    "%04d %06d %02d",
    sample.int(9999, n_master, replace = TRUE),
    seq_len(n_master),
    sample.int(20, n_master, replace = TRUE)
)
shared_names <- sprintf("s%d", 1:60)

master <- tibble::new_tibble(c(
    list(caseid = caseid),
    setNames(lapply(seq_len(60L), function(index) {
        dta_int(sample.int(500, n_master, replace = TRUE))
    }), shared_names),
    setNames(lapply(seq_len(90L), function(index) {
        rnorm(n_master)
    }), sprintf("m%d", seq_len(90L)))
), nrow = n_master)

using <- tibble::new_tibble(c(
    list(
        caseid = rep(caseid[mothers], births_per),
        bidx = dta_byte(unlist(lapply(births_per, seq_len)))
    ),
    setNames(lapply(seq_len(60L), function(index) {
        dta_int(sample.int(500, n_using, replace = TRUE))
    }), shared_names),
    setNames(lapply(seq_len(48L), function(index) {
        rnorm(n_using)
    }), sprintf("u%d", seq_len(48L)))
), nrow = n_using)

save_dta(master, master_path)
save_dta(using, using_path)
rm(master, using)
invisible(gc())

to_standard_column <- function(value) {
    if (inherits(value, c("stata_byte", "stata_int", "stata_long"))) {
        return(as.integer(as.vector(value)))
    }
    if (inherits(value, c("stata_float", "stata_double"))) {
        return(as.double(as.vector(value)))
    }
    if (is.character(value)) return(as.character(value))
    if (is.integer(value)) return(as.integer(value))
    if (is.double(value)) return(as.double(value))
    stop("unsupported fixture column: ", paste(class(value), collapse = "/"))
}

master_standard <- as.data.frame(
    lapply(read_dta(master_path), to_standard_column),
    optional = TRUE, stringsAsFactors = FALSE, check.names = FALSE
)
using_standard <- as.data.frame(
    lapply(read_dta(using_path), to_standard_column),
    optional = TRUE, stringsAsFactors = FALSE, check.names = FALSE
)
saveRDS(master_standard, file.path(fixture_dir, "master-standard.rds"),
        compress = FALSE)
saveRDS(using_standard, file.path(fixture_dir, "using-standard.rds"),
        compress = FALSE)
invisible(gc())

master_stata <- read_dta(master_path)
using_stata <- read_dta(using_path)
stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(master_stata$s1),
    dtatools:::.is_unmaterialized_numeric_altrep(using_stata$s1)
)

master_s1_by_key <- setNames(
    as.double(master_standard$s1), master_standard$caseid
)
using_s1_by_row <- setNames(
    as.double(using_standard$s1),
    paste(using_standard$caseid, using_standard$bidx, sep = "\034")
)

numeric_values <- function(value) unname(as.double(value))

validate_values <- function(actual, expected, label) {
    if (!identical(numeric_values(actual), unname(as.double(expected)))) {
        stop(label, " values differ from the fixture", call. = FALSE)
    }
}

validate_shape <- function(result, columns) {
    stopifnot(
        nrow(result) == 440044L,
        ncol(result) == columns,
        !anyNA(result$caseid),
        length(unique(result$caseid)) == 200000L,
        sum(duplicated(result$caseid)) == 240044L
    )
}

validate_dta_result <- function(result, direction) {
    validate_shape(result, 201L)
    codes <- as.integer(numeric_values(result$`_merge`))
    expected_counts <- if (direction == "1:m") {
        c(80000L, 0L, 360044L)
    } else {
        c(0L, 80000L, 360044L)
    }
    stopifnot(identical(tabulate(codes, nbins = 3L), expected_counts))

    if (direction == "1:m") {
        validate_values(
            result$s1, master_s1_by_key[result$caseid],
            paste("dta_merge", direction, "s1")
        )
    } else {
        matched <- codes == 3L
        y_only <- codes == 2L
        using_rows <- paste(
            result$caseid[matched],
            as.integer(numeric_values(result$bidx)[matched]),
            sep = "\034"
        )
        validate_values(
            result$s1[matched], using_s1_by_row[using_rows],
            paste("dta_merge", direction, "matched s1")
        )
        validate_values(
            result$s1[y_only], master_s1_by_key[result$caseid[y_only]],
            paste("dta_merge", direction, "y-only s1")
        )
    }
    invisible(NULL)
}

validate_join_result <- function(result, direction, method) {
    validate_shape(result, 260L)
    bidx <- numeric_values(result$bidx)
    using_rows <- !is.na(bidx)
    using_keys <- paste(
        result$caseid[using_rows], as.integer(bidx[using_rows]), sep = "\034"
    )
    master_expected <- master_s1_by_key[result$caseid]
    using_expected <- using_s1_by_row[using_keys]

    if (direction == "1:m") {
        validate_values(result$s1.x, master_expected,
                        paste(method, direction, "x s1"))
        validate_values(result$s1.y[using_rows], using_expected,
                        paste(method, direction, "y s1"))
        stopifnot(all(is.na(result$s1.y[!using_rows])))
    } else {
        validate_values(result$s1.x[using_rows], using_expected,
                        paste(method, direction, "x s1"))
        stopifnot(all(is.na(result$s1.x[!using_rows])))
        validate_values(result$s1.y, master_expected,
                        paste(method, direction, "y s1"))
    }
    invisible(NULL)
}

validate_dta_result(suppressWarnings(dta_merge(
    master_stata, using_stata, by = "caseid", relationship = "1:m"
)), "1:m")
validate_dta_result(suppressWarnings(dta_merge(
    master_standard, using_standard, by = "caseid", relationship = "1:m"
)), "1:m")
validate_dta_result(suppressWarnings(dta_merge(
    using_stata, master_stata, by = "caseid", relationship = "m:1"
)), "m:1")
validate_dta_result(suppressWarnings(dta_merge(
    using_standard, master_standard, by = "caseid", relationship = "m:1"
)), "m:1")

validate_join_result(full_join(
    master_stata, using_stata, by = join_by(caseid)
), "1:m", "dplyr")
validate_join_result(full_join(
    master_standard, using_standard, by = join_by(caseid)
), "1:m", "dplyr")
validate_join_result(full_join(
    using_stata, master_stata, by = join_by(caseid)
), "m:1", "dplyr")
validate_join_result(full_join(
    using_standard, master_standard, by = join_by(caseid)
), "m:1", "dplyr")

validate_join_result(merge(
    master_stata, using_stata, by = "caseid", all = TRUE
), "1:m", "base")
validate_join_result(merge(
    master_standard, using_standard, by = "caseid", all = TRUE
), "1:m", "base")
validate_join_result(merge(
    using_stata, master_stata, by = "caseid", all = TRUE
), "m:1", "base")
validate_join_result(merge(
    using_standard, master_standard, by = "caseid", all = TRUE
), "m:1", "base")

stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(master_stata$s1),
    dtatools:::.is_unmaterialized_numeric_altrep(using_stata$s1)
)
invisible(gc())

primary <- mark(
    dta_stata_1m = suppressWarnings(dta_merge(
        master_stata, using_stata, by = "caseid", relationship = "1:m"
    )),
    dplyr_stata_1m = full_join(
        master_stata, using_stata, by = join_by(caseid)
    ),
    dta_standard_1m = suppressWarnings(dta_merge(
        master_standard, using_standard, by = "caseid", relationship = "1:m"
    )),
    dplyr_standard_1m = full_join(
        master_standard, using_standard, by = join_by(caseid)
    ),
    dta_stata_m1 = suppressWarnings(dta_merge(
        using_stata, master_stata, by = "caseid", relationship = "m:1"
    )),
    dplyr_stata_m1 = full_join(
        using_stata, master_stata, by = join_by(caseid)
    ),
    dta_standard_m1 = suppressWarnings(dta_merge(
        using_standard, master_standard, by = "caseid", relationship = "m:1"
    )),
    dplyr_standard_m1 = full_join(
        using_standard, master_standard, by = join_by(caseid)
    ),
    iterations = iterations,
    check = FALSE,
    memory = TRUE,
    filter_gc = FALSE
)

base <- mark(
    base_stata_1m = merge(
        master_stata, using_stata, by = "caseid", all = TRUE
    ),
    base_standard_1m = merge(
        master_standard, using_standard, by = "caseid", all = TRUE
    ),
    base_stata_m1 = merge(
        using_stata, master_stata, by = "caseid", all = TRUE
    ),
    base_standard_m1 = merge(
        using_standard, master_standard, by = "caseid", all = TRUE
    ),
    iterations = base_iterations,
    check = FALSE,
    memory = TRUE,
    filter_gc = FALSE
)

summarize <- function(result, count) {
    data.frame(
        expression = as.character(result$expression),
        iterations = count,
        median_seconds = as.numeric(result$median),
        mem_alloc_bytes = as.numeric(result$mem_alloc),
        stringsAsFactors = FALSE
    )
}

summary <- rbind(
    summarize(primary, iterations),
    summarize(base, base_iterations)
)
print(summary, row.names = FALSE)
write.csv(
    summary,
    file.path(fixture_dir, "r-summary.csv"),
    row.names = FALSE
)
