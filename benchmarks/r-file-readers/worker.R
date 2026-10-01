# Exactly one reader invocation in a fresh process. No reporting packages load.
args <- commandArgs(TRUE)
stopifnot(length(args) == 7L)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
source(file.path(dirname(normalizePath(script)), "common.R"))
activate_library()
mode <- args[[1L]]
method <- args[[2L]]
threads <- as.integer(args[[4L]])
stopifnot(mode %in% c("read", "consume", "qualify-values", "qualify-signature"),
    !is.na(threads), threads >= 0L)
reader <- make_reader(method, normalizePath(args[[3L]], mustWork = TRUE), threads)
# Methods and full-consumption bytecode are compiled before timing. JIT effects
# in package code remain part of its first public call, as in an ordinary read.
reader <- compiler::cmpfun(reader)
consume_all <- compiler::cmpfun(consume_all)
expected_rows <- as.integer(args[[5L]])
expected_columns <- as.integer(args[[6L]])
shape <- function(value) stopifnot(nrow(value) == expected_rows, ncol(value) == expected_columns)
if (startsWith(method, "dtatools_")) {
    assert_container <- function(value) {
        if (endsWith(method, "_dibble")) stopifnot(inherits(value, "dibble"))
        else stopifnot(inherits(value, "tbl_df"), !inherits(value, "dibble"))
    }
} else assert_container <- function(value) {
    stopifnot(inherits(value, "tbl_df"), !inherits(value, "dibble"))
}
if (startsWith(mode, "qualify")) {
    value <- withCallingHandlers(reader(), warning = function(condition)
        stop("Unexpected qualification warning: ", conditionMessage(condition)))
    shape(value)
    assert_container(value)
    consumed <- consume_all(value)
    consumption_sha256 <- unname(tools::sha256sum(bytes = serialize(consumed, NULL, version = 3L)))
    if (mode == "qualify-values") {
        reference <- readRDS(args[[7L]])
        stopifnot(identical(plain_values(value), plain_values(reference)),
            identical(consumed, consume_all(reference)))
        # Parser problems can otherwise silently replace values with missing.
        if (method == "readr") stopifnot(nrow(readr::problems(value)) == 0L)
        if (startsWith(method, "vroom")) stopifnot(nrow(vroom::problems(value)) == 0L)
        cat("QUALIFIED\t", if (startsWith(method, "dtatools_")) dtatools::datasig(value) else "values",
            "\t", consumption_sha256, "\n", sep = "")
    } else {
        stopifnot(requireNamespace("dtatools", quietly = TRUE))
        cat("QUALIFIED\t", dtatools::datasig(value), "\t", consumption_sha256, "\n", sep = "")
    }
    quit(status = 0L)
}
invisible(gc(full = TRUE))
started <- proc.time()
value <- reader()
read_finished <- proc.time()
if (mode == "consume") {
    consumption <- consume_all(value)
    finished <- proc.time()
    stopifnot(length(consumption) == expected_columns)
} else finished <- read_finished
read_duration <- read_finished - started
consume_duration <- finished - read_finished
total_duration <- finished - started
shape(value)
assert_container(value)
cat("MEASURE\t", paste(sprintf("%.9f", c(
    read_duration[["elapsed"]], read_duration[["user.self"]], read_duration[["sys.self"]],
    consume_duration[["elapsed"]], consume_duration[["user.self"]], consume_duration[["sys.self"]],
    total_duration[["elapsed"]], total_duration[["user.self"]], total_duration[["sys.self"]]
)), collapse = "\t"), "\t", nrow(value), "\t", ncol(value), "\n", sep = "")
