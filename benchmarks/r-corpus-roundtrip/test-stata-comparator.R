script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_dir <- dirname(normalizePath(
    sub("^--file=", "", script_argument), winslash = "/"
))
source(file.path(script_dir, "common.R"), local = TRUE)

if (!requireNamespace("processx", quietly = TRUE)) stop("processx is required")
if (!requireNamespace("dtatools", quietly = TRUE)) stop("dtatools is required")

stata <- find_stata()
comparator <- Sys.getenv(
    "DTATOOLS_STATA_COMPARATOR",
    file.path(script_dir, "stata-compare.do")
)
fixture_root <- normalizePath(
    file.path(script_dir, "..", "..", "tests", "fixtures", "dta"),
    winslash = "/", mustWork = TRUE
)
root <- tempfile("stata-comparator-")
dir.create(root)
on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

run_stata <- function(arguments, work_dir) {
    processx::run(
        stata, c("-q", "-b", "do", arguments), wd = work_dir,
        error_on_status = FALSE, echo = FALSE
    )
}

compare <- function(source, candidate, kind, release, work_dir) {
    result_path <- file.path(work_dir, "stata-compare-result.tsv")
    unlink(result_path)
    run_stata(
        c(comparator, source, candidate, kind, as.character(release)),
        work_dir
    )
    if (!file.exists(result_path)) stop("Stata comparator wrote no result")
    strsplit(
        readLines(result_path, n = 1L, warn = FALSE), "\t", fixed = TRUE
    )[[1L]]
}

for (release in c(115L, 117L, 118L)) {
    work_dir <- file.path(root, paste0("release-", release))
    dir.create(work_dir)
    fixture <- file.path(fixture_root, paste0("all_types_v", release, ".dta"))
    result <- compare(fixture, fixture, "direct", release, work_dir)
    stopifnot(identical(result, c("pass", "direct", ".", ".", ".")))
}
for (release in c(115L, 118L)) {
    work_dir <- file.path(root, paste0("empty-release-", release))
    dir.create(work_dir)
    fixture <- file.path(fixture_root, paste0("empty_v", release, ".dta"))
    result <- compare(fixture, fixture, "direct", release, work_dir)
    stopifnot(identical(result, c("pass", "direct", ".", ".", ".")))
}

guard_source <- file.path(root, "cf-guard-source.dta")
guard_candidate <- file.path(root, "cf-guard-candidate.dta")
dtatools::save_dta(
    data.frame("__1" = 1:3, check.names = FALSE),
    guard_source, version = 18L
)
stopifnot(file.copy(guard_source, guard_candidate))
work_dir <- file.path(root, "cf-guard")
dir.create(work_dir)
result <- compare(guard_source, guard_candidate, "direct", 118L, work_dir)
stopifnot(identical(result, c("pass", "direct", ".", ".", ".")))

fixture <- file.path(fixture_root, "auto_v118.dta")
mutations <- c(
    "dimensions", "variable-names", "storage-type", "display-format",
    "dataset-label", "variable-label", "value-label-assignment",
    "value-label-definitions", "dataset-notes", "stored-values"
)
for (mutation in mutations) {
    work_dir <- file.path(root, mutation)
    dir.create(work_dir)
    candidate <- file.path(work_dir, "candidate.dta")
    run_stata(
        c(file.path(script_dir, "stata-compare-mutate.do"), fixture,
          candidate, mutation),
        work_dir
    )
    result <- compare(fixture, candidate, "direct", 118L, work_dir)
    stopifnot(
        identical(result[[1L]], "mismatch"),
        identical(result[[3L]], mutation)
    )
}

value <- seq_len(10000L)
wide <- as.data.frame(
    setNames(rep(list(value), 1000L), sprintf("v%04d", seq_len(1000L))),
    optional = TRUE
)
wide_source <- file.path(root, "wide-source.dta")
wide_candidate <- file.path(root, "wide-candidate.dta")
dtatools::save_dta(wide, wide_source, version = 18L)
stopifnot(file.copy(wide_source, wide_candidate))
work_dir <- file.path(root, "wide-comparison")
dir.create(work_dir)
elapsed <- system.time({
    result <- compare(
        wide_source, wide_candidate, "direct", 118L, work_dir
    )
})[["elapsed"]]
limit <- suppressWarnings(as.double(Sys.getenv(
    "DTATOOLS_COMPARATOR_MAX_SECONDS", "2.5"
)))
stopifnot(
    identical(result, c("pass", "direct", ".", ".", ".")),
    is.finite(limit), limit > 0, elapsed <= limit
)
message("Stata comparator tests passed in ", sprintf("%.2f", elapsed),
        " seconds for the wide performance fixture")
