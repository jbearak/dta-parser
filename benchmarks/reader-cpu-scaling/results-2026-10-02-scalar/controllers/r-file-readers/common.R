# Setup is outside every measured interval. This file loads no packages itself.
activate_library <- function() {
    path <- Sys.getenv("DTATOOLS_BENCH_LIB")
    if (nzchar(path)) .libPaths(c(normalizePath(path, mustWork = TRUE), .libPaths()))
    invisible(path)
}

reader_package <- function(method) switch(method,
    dtatools_dta_tibble =, dtatools_dta_dibble =,
    dtatools_arrow_tibble =, dtatools_arrow_dibble = "dtatools",
    haven = "haven", arrow = "arrow", fread = "data.table",
    readr = "readr", vroom_eager =, vroom_lazy = "vroom",
    fst = "fst", qs2 = "qs2", "base")

make_reader <- function(method, path, threads) {
    package <- reader_package(method)
    if (package != "base") stopifnot(requireNamespace(package, quietly = TRUE))
    if (package == "dtatools") {
        stopifnot(identical(normalizePath(find.package(package)),
            normalizePath(file.path(Sys.getenv("DTATOOLS_BENCH_LIB"), package))))
        output <- sub("^.*_", "", method)
        if (startsWith(method, "dtatools_dta")) return(function()
            dtatools::read_dta(path, output = output, threads = threads))
        return(function() dtatools::read_arrow(path, output = output,
            threads = threads, verify = TRUE))
    }
    stopifnot(requireNamespace("tibble", quietly = TRUE))
    if (package == "arrow" && threads > 0L) arrow::set_cpu_count(threads)
    native <- switch(method,
        base_csv = function() utils::read.csv(path, stringsAsFactors = FALSE,
            check.names = FALSE),
        base_rds = function() readRDS(path),
        fread = function() data.table::fread(path, showProgress = FALSE,
            nThread = if (threads > 0L) threads else data.table::getDTthreads()),
        readr = function() readr::read_csv(path, lazy = FALSE,
            num_threads = if (threads > 0L) threads else readr::readr_threads(),
            show_col_types = FALSE, progress = FALSE),
        vroom_eager = function() vroom::vroom(path, delim = ",", altrep = FALSE,
            num_threads = if (threads > 0L) threads else eval(formals(vroom::vroom)$num_threads, environment(vroom::vroom)),
            show_col_types = FALSE, progress = FALSE),
        vroom_lazy = function() vroom::vroom(path, delim = ",", altrep = TRUE,
            num_threads = if (threads > 0L) threads else eval(formals(vroom::vroom)$num_threads, environment(vroom::vroom)),
            show_col_types = FALSE, progress = FALSE),
        haven = function() haven::read_dta(path),
        arrow = function() arrow::read_feather(path, as_data_frame = TRUE),
        fst = {
            if (threads > 0L) fst::threads_fst(threads)
            function() fst::read_fst(path, as.data.table = FALSE)
        },
        qs2 = function() qs2::qs_read(path, validate_checksum = TRUE, nthreads = if (threads > 0L) threads else 1L),
        stop("Unknown reader"))
    function() {
        value <- native()
        if (inherits(value, "tbl_df")) value else tibble::as_tibble(value)
    }
}

# A full traversal forces lazy values. It neither loads a reference nor makes
# a dataset copy. Every value contributes to a finite aggregate or NA count.
consume_all <- function(value) {
    result <- numeric(ncol(value))
    for (j in seq_along(value)) {
        column <- value[[j]]
        if (is.factor(column)) column <- as.character(column)
        if (is.character(column)) {
            result[[j]] <- sum(nchar(column, type = "bytes"), na.rm = TRUE) + sum(is.na(column))
        } else if (is.raw(column)) {
            result[[j]] <- sum(as.integer(column))
        } else if (typeof(column) %in% c("double", "integer", "logical")) {
            # Cast before aggregation so dta_float Summary methods do not round
            # the aggregate back to single precision. This is ordinary R traversal.
            column <- as.double(column)
            result[[j]] <- sum(column, na.rm = TRUE) + sum(is.na(column))
        } else stop("Unsupported full-consumption column type")
    }
    result
}

# Compare every value, with numeric storage and container metadata removed.
# Synthetic inputs use exact binary fractions and no tagged/temporal values.
plain_values <- function(value) {
    result <- lapply(seq_along(value), function(j) {
        column <- value[[j]]
        if (is.factor(column)) column <- as.character(column)
        if (is.character(column)) {
            attributes(column) <- NULL
            return(enc2utf8(column))
        }
        if (typeof(column) %in% c("double", "integer", "logical")) return(unname(as.double(column)))
        if (is.raw(column)) return(unname(column))
        stop("Unsupported qualification column type")
    })
    names(result) <- names(value)
    result
}
