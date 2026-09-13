# Matched warm reads across worker limits, defaulting to eight versus automatic.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) %in% c(5L, 6L))
input <- normalizePath(args[[1L]], mustWork = TRUE)
present_path <- normalizePath(args[[2L]], mustWork = TRUE)
union_path <- normalizePath(args[[3L]], mustWork = TRUE)
repetitions <- as.integer(args[[4L]])
output <- args[[5L]]
thread_counts <- if (length(args) == 6L) {
    as.integer(strsplit(args[[6L]], ",", fixed = TRUE)[[1L]])
} else c(8L, 0L)
stopifnot(length(thread_counts) >= 2L, !anyNA(thread_counts),
          all(thread_counts >= 0L), !anyDuplicated(thread_counts))
stopifnot(repetitions >= 1L, !file.exists(paste0(output, "-observations.csv")))
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
script <- normalizePath(sub("^--file=", "", script_arg), mustWork = TRUE)
source(file.path(dirname(script), "workers", "benchmark-common.R"))
benchmark_activate_library(c("dtatools", "tidyselect", "jsonlite"))
present <- scan(present_path, what = character(), quiet = TRUE)
union <- scan(union_path, what = character(), quiet = TRUE)
stopifnot(length(present) > 0L, !anyDuplicated(present), all(present %in% union))
binding <- function() list(
    input_sha256 = unname(benchmark_file_sha256(input)),
    present_sha256 = unname(benchmark_file_sha256(present_path)),
    union_sha256 = unname(benchmark_file_sha256(union_path)),
    worker_sha256 = unname(benchmark_file_sha256(script)),
    shared_worker_sha256 = unname(benchmark_file_sha256(
        file.path(dirname(script), "workers", "benchmark-common.R")
    )),
    installed_tree_sha256 = benchmark_directory_sha256(
        benchmark_installed_package_path(benchmark_library_path())
    )
)
before <- binding()
configs <- expand.grid(threads = thread_counts, method = c("any_of", "all_of"),
                       stringsAsFactors = FALSE)
read_one <- function(config) {
    if (config$method == "any_of") {
        dtatools::read_dta(input, col_select = tidyselect::any_of(union),
                          threads = config$threads)
    } else {
        dtatools::read_dta(input, col_select = tidyselect::all_of(present),
                          threads = config$threads)
    }
}
validate <- function(value) stopifnot(identical(names(value), present))
signatures <- character(nrow(configs))
for (index in seq_len(nrow(configs))) {
    value <- read_one(configs[index, ])
    validate(value)
    signatures[[index]] <- dtatools::datasig(value)
    rm(value)
}
stopifnot(length(unique(signatures)) == 1L)
observations <- vector("list", repetitions * nrow(configs))
position <- 0L
for (iteration in seq_len(repetitions)) {
    order <- seq_len(nrow(configs))
    if (iteration %% 2L == 0L) order <- rev(order)
    for (index in order) {
        gc()
        started <- proc.time()
        value <- read_one(configs[index, ])
        duration <- proc.time() - started
        elapsed <- duration[["elapsed"]]
        validate(value)
        position <- position + 1L
        observations[[position]] <- data.frame(
            iteration = iteration, position = position, configs[index, ],
            elapsed_seconds = elapsed, rows = nrow(value), columns = ncol(value),
            user_cpu_seconds = duration[["user.self"]], system_cpu_seconds = duration[["sys.self"]],
            cpu_seconds = duration[["user.self"]] + duration[["sys.self"]]
        )
    }
}
after <- binding()
stopifnot(identical(before, after))
write.csv(do.call(rbind, observations), paste0(output, "-observations.csv"),
          row.names = FALSE)
jsonlite::write_json(list(
    before = before, after = after, configs = configs, signatures = signatures,
    repetitions = repetitions, protocol = "One process; one warmup and untimed signature per configuration; alternate configuration order each round; GC before each timed call; retain result until next read.",
    r_version = R.version.string, session = capture.output(sessionInfo())
), paste0(output, "-provenance.json"), pretty = TRUE, auto_unbox = TRUE)
