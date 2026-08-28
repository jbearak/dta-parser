args <- commandArgs(TRUE)

parse_count <- function(value, default, argument) {
    if (length(value) == 0L || is.na(value[[1L]])) return(default)
    if (!grepl("^[1-9][0-9]*$", value[[1L]])) {
        stop(argument, " must be a positive decimal integer", call. = FALSE)
    }
    as.integer(value[[1L]])
}

iterations <- parse_count(args[1L], 9L, "iterations")
base_iterations <- parse_count(args[2L], 5L, "base_iterations")

bench_library <- Sys.getenv("DTAPARSER_BENCH_LIB", unset = "")
if (!nzchar(bench_library)) {
    stop("DTAPARSER_BENCH_LIB must name the isolated package library",
         call. = FALSE)
}
bench_library <- normalizePath(bench_library, mustWork = TRUE)
.libPaths(c(bench_library, .libPaths()))

suppressMessages({
    library(bench)
    library(dplyr)
    library(dtaparser)
})

loaded_library <- normalizePath(
    dirname(system.file(package = "dtaparser")), mustWork = TRUE
)
if (!identical(loaded_library, bench_library)) {
    stop("dtaparser was not loaded from DTAPARSER_BENCH_LIB", call. = FALSE)
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
        stata_int(sample.int(500, n_master, replace = TRUE))
    }), shared_names),
    setNames(lapply(seq_len(90L), function(index) {
        rnorm(n_master)
    }), sprintf("m%d", seq_len(90L)))
), nrow = n_master)

using <- tibble::new_tibble(c(
    list(
        caseid = rep(caseid[mothers], births_per),
        bidx = stata_byte(unlist(lapply(births_per, seq_len)))
    ),
    setNames(lapply(seq_len(60L), function(index) {
        stata_int(sample.int(500, n_using, replace = TRUE))
    }), shared_names),
    setNames(lapply(seq_len(48L), function(index) {
        rnorm(n_using)
    }), sprintf("u%d", seq_len(48L)))
), nrow = n_using)

write_dta(master, master_path)
write_dta(using, using_path)
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

validate_result <- function(result, columns) {
    stopifnot(nrow(result) == 440044L, ncol(result) == columns)
    invisible(NULL)
}

validate_result(suppressWarnings(dta_merge(
    master_stata, using_stata, by = "caseid", relationship = "1:m"
)), 201L)
validate_result(full_join(
    master_standard, using_standard, by = join_by(caseid)
), 260L)
validate_result(merge(
    master_standard, using_standard, by = "caseid", all = TRUE
), 260L)
stopifnot(dtaparser:::.is_unmaterialized_numeric_altrep(master_stata$s1))
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
