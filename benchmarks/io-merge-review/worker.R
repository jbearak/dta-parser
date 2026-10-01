# One isolated call. Input preparation, warmup and qualification are untimed.
args <- commandArgs(TRUE)
stopifnot(length(args) >= 4L)
task <- args[[1L]]
kind <- args[[2L]]
input <- args[[3L]]
output <- args[[4L]]
root <- Sys.getenv("DTATOOLS_REVIEW_ROOT")
stopifnot(nzchar(root))
source(file.path(root, "benchmarks/reader-refresh/workers/benchmark-common.R"))
benchmark_activate_library("dtatools", verify_dtatools = TRUE)
stopifnot(!"jsonlite" %in% loadedNamespaces())

emit <- function(...) cat(paste(..., sep = "\t"), "\n", sep = "")
ordinary <- function(value) {
    if (inherits(value, c("dta_byte", "dta_int", "dta_long"))) return(as.integer(as.vector(value)))
    if (inherits(value, c("dta_float", "dta_double"))) return(as.double(as.vector(value)))
    if (is.character(value)) return(as.character(value))
    if (is.integer(value)) return(as.integer(value))
    if (is.double(value)) return(as.double(value))
    stop("unsupported ordinary merge column")
}
load_merge <- function(kind, directory) {
    if (kind == "ordinary") {
        list(master = readRDS(file.path(directory, "master-standard.rds")),
             using = readRDS(file.path(directory, "using-standard.rds")))
    } else {
        value <- list(master = dtatools::read_dta(file.path(directory, "master.dta")),
                      using = dtatools::read_dta(file.path(directory, "using.dta")))
        stopifnot(dtatools:::.is_unmaterialized_numeric_altrep(value$master$s1),
                  dtatools:::.is_unmaterialized_numeric_altrep(value$using$s1))
        if (kind == "one-column") {
            value <- lapply(value, function(x) x[c("caseid", "s1")])
        }
        value
    }
}
validate_merge <- function(value, frames, direction, kind) {
    stopifnot(nrow(value) == 440044L,
              ncol(value) == if (kind == "one-column") 3L else 201L,
              !anyNA(value$caseid), length(unique(value$caseid)) == 200000L,
              sum(duplicated(value$caseid)) == 240044L)
    codes <- as.integer(as.double(value$`_merge`))
    expected <- if (direction == "1:m") c(80000L, 0L, 360044L) else c(0L, 80000L, 360044L)
    stopifnot(identical(tabulate(codes, nbins = 3L), expected))
    if (direction == "1:m") {
        expected <- as.double(frames$master$s1)[match(value$caseid, frames$master$caseid)]
    } else if (kind != "one-column") {
        keys <- paste(frames$using$caseid, as.integer(as.double(frames$using$bidx)), sep = "\034")
        result_keys <- paste(value$caseid, as.integer(as.double(value$bidx)), sep = "\034")
        expected <- as.double(frames$using$s1)[match(result_keys, keys)]
        unmatched <- codes == 2L
        expected[unmatched] <- as.double(frames$master$s1)[match(value$caseid[unmatched], frames$master$caseid)]
    } else {
        expected <- c(as.double(frames$using$s1),
                      as.double(frames$master$s1)[!frames$master$caseid %in% frames$using$caseid])
    }
    stopifnot(identical(as.double(value$s1), unname(expected)))
}

if (task %in% c("save_dta", "save_arrow", "qualify-save_dta", "qualify-save_arrow")) {
    qualification <- startsWith(task, "qualify-")
    method <- sub("^qualify-", "", task)
    if (kind == "primary") {
        data <- dtatools::read_dta(input)
    } else {
        source(file.path(root, "benchmarks/large-scale/standard-r-write-fixture.R"))
        data <- make_standard_r_write_fixture(as.integer(input))
        standard_r_write_schema(data)
    }
    before_shape <- dim(data)
    before_signature <- if (qualification) dtatools::datasig(data) else NULL
    invisible(gc(full = TRUE))
    warnings <- character()
    started <- proc.time()
    result <- withCallingHandlers(
        if (method == "save_dta") dtatools::save_dta(data, output, version = 19L)
        else dtatools::save_arrow(data, output),
        warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }
    )
    elapsed <- proc.time() - started
    stopifnot(identical(result, data), identical(dim(data), before_shape))
    if (qualification) stopifnot(identical(before_signature, dtatools::datasig(data)))
    emit("RESULT", task, kind, elapsed[["elapsed"]], elapsed[["user.self"]],
         elapsed[["sys.self"]], nrow(data), ncol(data), file.info(output)$size)
    for (warning in warnings) emit("WARNING", warning)
} else if (task == "merge") {
    frames <- load_merge(kind, input)
    direction <- output
    stopifnot(direction %in% c("1:m", "m:1"))
    call <- function() {
        if (direction == "1:m") suppressWarnings(dtatools::dta_merge(frames$master, frames$using, by = "caseid", relationship = direction))
        else suppressWarnings(dtatools::dta_merge(frames$using, frames$master, by = "caseid", relationship = direction))
    }
    warmup <- call()
    stopifnot(nrow(warmup) == 440044L, ncol(warmup) == if (kind == "one-column") 3L else 201L)
    rm(warmup)
    if (kind != "ordinary") {
        stopifnot(dtatools:::.is_unmaterialized_numeric_altrep(frames$master$s1),
                  dtatools:::.is_unmaterialized_numeric_altrep(frames$using$s1))
    }
    invisible(gc(full = TRUE))
    started <- proc.time()
    result <- call()
    elapsed <- proc.time() - started
    stopifnot(nrow(result) == 440044L, ncol(result) == if (kind == "one-column") 3L else 201L)
    emit("RESULT", task, kind, elapsed[["elapsed"]], elapsed[["user.self"]],
         elapsed[["sys.self"]], nrow(result), ncol(result), NA)
} else if (task == "qualify-read") {
    warnings <- character()
    result <- withCallingHandlers(
        if (kind == "read_dta") dtatools::read_dta(input) else dtatools::read_arrow(input),
        warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }
    )
    stopifnot(length(warnings) == 0L)
    emit("QUALIFIED", kind, nrow(result), ncol(result), dtatools::datasig(result))
} else if (task == "qualify-merge") {
    frames <- load_merge(kind, input)
    before <- vapply(frames, dtatools::datasig, character(1))
    direction <- output
    warnings <- character()
    result <- withCallingHandlers(
        if (direction == "1:m") dtatools::dta_merge(frames$master, frames$using, by = "caseid", relationship = direction)
        else dtatools::dta_merge(frames$using, frames$master, by = "caseid", relationship = direction),
        warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }
    )
    validate_merge(result, frames, direction, kind)
    stopifnot(identical(before, vapply(frames, dtatools::datasig, character(1))))
    emit("QUALIFIED", kind, nrow(result), ncol(result), dtatools::datasig(result))
    emit("WARNINGS", paste(warnings, collapse = " | "))
} else if (task == "prepare-arrow") {
    stopifnot(!file.exists(output))
    data <- dtatools::read_dta(input)
    dtatools::save_arrow(data, output)
    restored <- dtatools::read_arrow(output)
    stopifnot(identical(dtatools::datasig(data), dtatools::datasig(restored)))
    emit("PREPARED", kind, nrow(data), ncol(data), dtatools::datasig(data))
} else stop("unknown task")
stopifnot(!"jsonlite" %in% loadedNamespaces())
