args <- commandArgs(TRUE)
stopifnot(length(args) == 5L)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                    file.path(normalizePath(args[[1L]]), "dtatools")))
round <- as.integer(args[[2L]])
variant <- args[[4L]]
qualify <- identical(args[[5L]], "qualify")
hash <- function(x) digest::digest(writeBin(as.double(x), raw(), 8L, endian="little"),
                                  algo="sha256", serialize=FALSE)
state <- function(x) c(compact=dtatools:::.is_unmaterialized_numeric_altrep(x),
                      materialized=.Call(dtatools:::C_dtatools_is_materialized_numeric_altrep, x))
encode <- function(values, minimum) {
    if (identical(minimum, "")) return(list(values=values, storage=""))
    values[!is.finite(values) | abs(values) > (2^53 - 1) * 2^970] <- NA_real_
    observed <- values[!is.na(values)]
    whole <- all(observed == trunc(observed))
    fits <- function(lo, hi) all(observed >= lo & observed <= hi)
    kind <- "double"
    if (minimum == "byte" && whole && fits(-127, 100)) kind <- "byte"
    else if (minimum %in% c("byte", "int") && whole && fits(-32767, 32740)) kind <- "int"
    else if (minimum %in% c("byte", "int", "long") && whole && fits(-2147483647, 2147483620)) kind <- "long"
    else if (minimum %in% c("byte", "int", "float") && fits(-(2^24 - 1) * 2^103, (2^24 - 1) * 2^103)) kind <- "float"
    if (kind == "float") {
        positions <- !is.na(values)
        values[positions] <- readBin(writeBin(values[positions], raw(), 4L, endian="little"),
                                    double(), sum(positions), 4L, endian="little")
    }
    list(values=values, storage=kind)
}
construct <- function(values, width) switch(width, int=dta_int(values),
                                            long=dta_long(values), float=dta_float(values),
                                            double=dta_double(values))
operations <- list(scale_binary=function(x,y) x * 2,
                   scale_general=function(x,y) x * 1.01,
                   pair_compact_double=function(x,y) x + y,
                   add_scalar=function(x,y) x + 0.1,
                   subtract_scalar=function(x,y) x - 0.1,
                   reverse_subtract=function(x,y) 0.1 - x,
                   reverse_divide=function(x,y) 1.01 / x,
                   mixed_add=function(x,y) x + y,
                   mixed_multiply=function(x,y) x * y,
                   mixed_subtract=function(x,y) x - y,
                   mixed_divide=function(x,y) x / y,
                   float_multiply=function(x,y) x * y,
                   long_float_add=function(x,y) x + y)
rows <- list()
case <- 0L
n <- 1000000L
for (width in c("int", "float", "long")) for (missing in c(FALSE, TRUE)) {
    plain <- as.double((seq_len(n) * 13) %% 10001L - 5000L)
    if (width == "float") plain <- plain / 8
    yplain <- as.double((seq_len(n) * 19) %% 1001L - 500L) / 8
    if (missing) {
        plain[seq.int(13L, n, by=997L)] <- NA_real_
        yplain[seq.int(19L, n, by=991L)] <- NA_real_
    }
    selected <- switch(width, int = c("scale_binary", "mixed_add", "mixed_multiply", "mixed_subtract", "mixed_divide"),
                       float = c("scale_binary", "scale_general", "float_multiply"), long = "long_float_add")
    for (operation in selected) {
        case <- case + 1L
        call <- operations[[operation]]
        mixed <- operation %in% c("mixed_add", "mixed_multiply", "mixed_subtract", "mixed_divide", "float_multiply", "long_float_add")
        ywidth <- if (mixed) "float" else "double"
        values <- list(compact=construct(plain, width), typed_double=dta_double(plain), ordinary=plain)
        ys <- list(compact=construct(yplain, ywidth), typed_double=dta_double(yplain), ordinary=yplain)
        expected_input <- hash(plain)
        expected_y <- hash(yplain)
        reference <- call(plain, yplain)
        order <- names(values)[(seq_len(3L) + round + case - 1L) %% 3L + 1L]
        if (round %% 2L == 0L) order <- rev(order)
        for (representation in order) {
            x <- values[[representation]]; y <- ys[[representation]]
            before <- state(x); before_y <- state(y)
            minimum <- if (representation == "ordinary") "" else if (representation == "typed_double" ||
                operation %in% c("pair_compact_double", "long_float_add")) "double" else if (mixed) "float" else width
            expected <- encode(reference, minimum)
            expected_hash <- hash(expected$values)
            expected_missing <- is.na(expected$values)
            expected_missing_hash <- hash(as.double(expected_missing))
            if (representation == "compact") stopifnot(before[["compact"]], !before[["materialized"]])
            stopifnot(identical(hash(x), expected_input), identical(hash(y), expected_y),
                      identical(state(x), before), identical(state(y), before_y))
            check <- function(result) {
                actual_storage <- if (inherits(result, "dta_numeric")) dta_storage_type(result) else ""
                stopifnot(identical(actual_storage, expected$storage),
                          identical(hash(result), expected_hash),
                          identical(is.na(result), expected_missing),
                          identical(anyNA(result), any(expected_missing)),
                          identical(state(x), before), identical(state(y), before_y),
                          identical(hash(x), expected_input), identical(hash(y), expected_y),
                          identical(state(x), before), identical(state(y), before_y))
                if (representation != "ordinary" && expected$storage != "double")
                    stopifnot(dtatools:::.is_unmaterialized_numeric_altrep(result))
            }
            # The first call can settle lazy dependencies before native admission.
            check(call(x, y))
            entries <- .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
            result <- call(x, y)
            qualification_calls <- .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[["scalar"]] - entries
            check(result)
            if (variant == "candidate" && qualification_calls != if (representation == "ordinary") 0 else 1)
                stop(paste("unexpected qualification entry count", width, missing, operation, representation, qualification_calls))
            reps <- 1L
            timing <- c(user.self=NA_real_, sys.self=NA_real_, elapsed=NA_real_)
            native_calls <- qualification_calls
            if (!qualify) {
                repeat {
                    gc(); start <- proc.time()[["elapsed"]]
                    for (i in seq_len(reps)) result <- call(x, y)
                    duration <- proc.time()[["elapsed"]] - start
                    if (duration >= 0.025 || reps >= 100000L) break
                    reps <- reps * 5L
                }
                reps <- min(1000000L, max(reps, as.integer(ceiling(reps * .15 / max(duration, .001)))))
                gc(); entries <- .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
                start <- proc.time()
                for (i in seq_len(reps)) result <- call(x, y)
                timing <- proc.time() - start
                native_calls <- .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[["scalar"]] - entries
                if (variant == "candidate") stopifnot(native_calls == if (representation == "ordinary") 0 else reps)
                check(result)
            }
            rows[[length(rows) + 1L]] <- data.frame(round, case, n, width, missing, operation,
                ywidth, representation, order=match(representation, order), iterations=reps,
                cpu=unname(timing[["user.self"]] + timing[["sys.self"]]), wall=unname(timing[["elapsed"]]),
                result_sha256=expected_hash, missing_sha256=expected_missing_hash,
                missing_count=sum(expected_missing), result_storage=expected$storage,
                native_calls, compact_before=before[["compact"]], compact_after=state(x)[["compact"]],
                materialized_before=before[["materialized"]], materialized_after=state(x)[["materialized"]],
                y_compact_before=before_y[["compact"]], y_compact_after=state(y)[["compact"]],
                y_materialized_before=before_y[["materialized"]], y_materialized_after=state(y)[["materialized"]],
                input_sha256=expected_input, y_sha256=expected_y)
        }
    }
}
write.csv(do.call(rbind, rows), args[[3L]], row.names=FALSE)
cat(length(rows), if (qualify) "qualified cases\n" else "qualified observations\n")
