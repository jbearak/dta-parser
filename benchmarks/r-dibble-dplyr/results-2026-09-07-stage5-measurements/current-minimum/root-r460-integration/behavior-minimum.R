# Independent, small Stage 5 behavior oracles against an exact installed source.
# No implementation code is sourced. These cases use public dtatools/dplyr calls.
source(Sys.getenv("DTA_ORACLE_HELPER"))
lib <- Sys.getenv("DTA_ORACLE_LIBRARY")
sha <- Sys.getenv("DTA_ORACLE_SOURCE")
out <- Sys.getenv("DTA_ORACLE_OUTPUT")
validate_benchmark_install(lib, sha)
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = lib))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                    normalizePath(file.path(lib, "dtatools"))))
cases <- list()
equal <- function(actual, expected) {
    if (!identical(actual, expected)) {
        stop(paste(c("Values differ:", capture.output(dput(actual)),
                     "Expected:", capture.output(dput(expected))), collapse = "\n"))
    }
}
case <- function(name, expr) {
    warnings <- character()
    record <- tryCatch(withCallingHandlers({
        value <- force(expr)
        list(passed = TRUE, observations = value)
    }, warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
    }), error = function(e) list(passed = FALSE, error = conditionMessage(e)))
    record$warnings <- warnings
    cases[[name]] <<- record
    cat(name, if (record$passed) "PASS" else paste("FAIL", record$error), "\n")
}

case("sequential missing typing", {
    data <- dibble(id = 1:2)
    result <- dplyr::mutate(data, y = c(NA_real_, 1), z = y > 0,
                            s = c(NA_character_, ""), missing = s == "")
    equal(result$z, c(TRUE, TRUE))
    equal(result$missing, c(TRUE, TRUE))
    equal(dta_storage_type(result$y), "double")
    equal(names(data), "id")
    TRUE
})

case("repeated output preserves current metadata then deletion clears it", {
    narrow <- dta_byte(1:2)
    var_label(narrow) <- "original"
    wide <- dta_double(c(3, 4))
    var_label(wide) <- "replacement"
    data <- dibble(x = narrow)
    captured <- NULL
    result <- dplyr::mutate(data, x = wide,
        saved = { captured <<- x; x },
        x = c(5, 6), observed = var_label(x),
        x = NULL, x = c(7, 8))
    equal(as.double(captured), c(3, 4))
    equal(var_label(captured), "replacement")
    equal(as.character(result$observed), rep("replacement", 2L))
    equal(var_label(result$x), NULL)
    equal(as.double(result$x), c(7, 8))
    equal(as.double(data$x), c(1, 2))
    equal(var_label(data$x), "original")
    repl(result, saved = 9, where = 1L)
    equal(as.double(captured), c(3, 4))
    TRUE
})

case("captured input and both table aliases isolate later writes", {
    data <- dibble(x = dta_double(c(1, 2)), s = c("a", "b"))
    source_alias <- data
    captured <- NULL
    result <- dplyr::mutate(data, y = { captured <<- x; x }, x = x + 10)
    result_alias <- result
    repl(data, x = 90, where = 1L)
    equal(as.double(source_alias$x), c(90, 2))
    equal(as.double(captured), c(1, 2))
    equal(as.double(result$x), c(11, 12))
    repl(result, y = 80, where = 2L)
    equal(as.double(result_alias$y), c(1, 80))
    equal(as.double(captured), c(1, 2))
    equal(as.double(data$x), c(90, 2))
    repl(result, s = "longer", where = 1L)
    equal(as.character(data$s), c("a", "b"))
    TRUE
})

case("group values remain stable across groups and later expressions", {
    data <- dplyr::group_by(dibble(g = c(2L, 1L, 2L, 1L),
                                  x = dta_double(c(10, 20, 30, 40))), g)
    values <- list()
    keys <- list()
    result <- dplyr::mutate(data,
        y = {
            values[[length(values) + 1L]] <<- x
            keys[[length(keys) + 1L]] <<- dplyr::cur_group()
            x
        }, x = x + 100)
    equal(lapply(values, as.double), list(c(20, 40), c(10, 30)))
    equal(vapply(keys, function(k) as.integer(k$g), integer(1)), 1:2)
    equal(as.double(result$y), c(10, 20, 30, 40))
    repl(result, y = 500, where = 1L)
    equal(lapply(values, as.double), list(c(20, 40), c(10, 30)))
    equal(as.double(data$x), c(10, 20, 30, 40))
    TRUE
})

case("rowwise list extraction and captured vectors", {
    data <- dplyr::rowwise(dibble(id = 1:2, x = list(c(1, 2), c(3, 4, 5))))
    saved <- list()
    result <- dplyr::mutate(data, total = {
        saved[[length(saved) + 1L]] <<- x
        sum(x)
    }, x = list(c(9, 10)))
    equal(saved, list(c(1, 2), c(3, 4, 5)))
    equal(as.double(result$total), c(3, 12))
    equal(result$x, list(c(9, 10), c(9, 10)))
    equal(data$x, list(c(1, 2), c(3, 4, 5)))
    TRUE
})

case("arbitrary helper reads contribute to keep used", {
    data <- dibble(x = 1:2, y = 3:4, unused = 5:6)
    read_name <- function(mask, name) mask[[name]]
    result <- dplyr::mutate(data, z = read_name(.data, "y") + 1,
                            .keep = "used")
    equal(names(result), c("y", "z"))
    equal(as.double(result$z), c(4, 5))
    TRUE
})

case("foreign data table result is captured", {
    foreign <- data.table::data.table(x = c(1, 2), s = c("a", "b"))
    take_numeric <- function() foreign$x
    take_string <- function() foreign$s
    data <- dibble(id = 1:2)
    result <- dplyr::mutate(data, x = take_numeric(), s = take_string())
    data.table::set(foreign, i = 1L, j = "x", value = 99)
    data.table::set(foreign, i = 2L, j = "s", value = "changed")
    equal(as.double(result$x), c(1, 2))
    equal(as.character(result$s), c("a", "b"))
    repl(result, x = 42, where = 2L)
    equal(foreign$x, c(99, 2))
    TRUE
})

case("late promises and mask closures are characterized without parity assumption", {
    data <- dplyr::group_by(dibble(g = c(1L, 2L), x = c(10, 20)), g)
    delayed <- new.env(parent = emptyenv())
    closures <- list()
    capture <- function(value, name) {
        delayedAssign(name, value, eval.env = environment(), assign.env = delayed)
        0L
    }
    result <- dplyr::mutate(data, y = {
        closures[[length(closures) + 1L]] <<- function() x
        capture(x, paste0("g", dplyr::cur_group_id()))
    }, x = x + 1)
    observe <- function(f) tryCatch(
        list(kind = "value", value = as.double(f())),
        error = function(e) list(kind = "error", classes = class(e),
                                 message = conditionMessage(e)))
    list(promises = lapply(c("g1", "g2"), function(name) {
        observe(function() get(name, envir = delayed, inherits = FALSE))
    }), closures = lapply(closures, observe))
})

validate_benchmark_install(lib, sha)
identity <- list(source = sha, R = R.version.string,
    R_home = R.home(), package = getNamespaceInfo(asNamespace("dtatools"), "path"),
    DLL = getLoadedDLLs()[["dtatools"]][["path"]],
    DLL_md5 = unname(tools::md5sum(getLoadedDLLs()[["dtatools"]][["path"]])),
    namespaces = sort(loadedNamespaces()),
    versions = vapply(sort(loadedNamespaces()), function(x) {
        as.character(utils::packageVersion(x))
    }, character(1)))
saveRDS(list(identity = identity, cases = cases), file.path(out, "results.rds"))
dput(list(identity = identity, cases = cases), file = file.path(out, "results.R"))
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) {
    getNamespaceInfo(asNamespace(name), "path")
}, character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(out, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
if (!all(vapply(cases, `[[`, logical(1), "passed"))) stop("Public behavior cases failed")
