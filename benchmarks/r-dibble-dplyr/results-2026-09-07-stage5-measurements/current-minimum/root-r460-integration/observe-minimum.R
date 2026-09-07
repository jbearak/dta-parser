# Read-only baseline characterization of public expression behavior.
source(Sys.getenv("DTA_ORACLE_HELPER"))
lib <- Sys.getenv("DTA_ORACLE_LIBRARY")
sha <- Sys.getenv("DTA_ORACLE_SOURCE")
output <- Sys.getenv("DTA_ORACLE_OUTPUT")
validate_benchmark_install(lib, sha)
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = lib))
if (!identical(normalizePath(find.package("dtatools")),
               normalizePath(file.path(lib, "dtatools")))) stop("Wrong installed package")

observe <- function(container, expression_kind) {
    raw <- tibble::tibble(g = c(1L, 1L, 2L), x = 1:3, y = 4:6)
    data <- if (container == "dibble") as_dibble(raw) else raw
    data <- dplyr::group_by(data, g)
    events <- character()
    factories <- 0L
    callback <- function(value) {
        events <<- c(events, paste(dplyr::cur_column(),
                                   dplyr::cur_group_id(), sep = ":"))
        value
    }
    factory <- function() {
        factories <<- factories + 1L
        callback
    }
    alias <- dplyr::across
    result <- switch(expression_kind,
        expanded = dplyr::mutate(data, dplyr::across(x:y, factory())),
        aliased = dplyr::mutate(data, alias(x:y, factory())),
        named = dplyr::mutate(data, packed = dplyr::across(x:y, factory())),
        unpacked = dplyr::mutate(data, dplyr::across(x:y,
            function(value) tibble::tibble(value = callback(value)), .unpack = TRUE)),
        stop("Unknown expression shape"))
    if (!identical(as.integer(data$x), 1:3) ||
        !identical(as.integer(data$y), 4:6)) stop("Source values changed")
    list(events = events, factories = factories,
         names = names(result),
         columns = lapply(result, function(value) {
             if (is.data.frame(value)) lapply(value, as.integer)
             else as.integer(value)
         }))
}

records <- list()
for (kind in c("expanded", "aliased", "named", "unpacked")) {
    records[[kind]] <- list(tibble = observe("tibble", kind),
                            dibble = observe("dibble", kind))
    cat(kind, "\n")
    for (container in c("tibble", "dibble")) {
        record <- records[[kind]][[container]]
        cat(" ", container, "factories", record$factories,
            "events", paste(record$events, collapse = ","), "\n")
    }
}

# Expanded expressions must all read the input values for the same across call.
data <- dibble(x = 1:2, y = 10:11)
result <- dplyr::mutate(data, dplyr::across(x:y, ~ x + y))
if (!identical(as.integer(result$x), c(11L, 13L)) ||
    !identical(as.integer(result$y), c(11L, 13L))) stop("Across installation order changed")
records$within_across_input_values <- list(x = as.integer(result$x), y = as.integer(result$y))

validate_benchmark_install(lib, sha)
records$identity <- list(source = sha, R = R.version.string,
    library = normalizePath(find.package("dtatools")),
    DLL = normalizePath(getLoadedDLLs()[["dtatools"]][["path"]]),
    dplyr = as.character(utils::packageVersion("dplyr")),
    namespace_paths = vapply(setdiff(loadedNamespaces(), "base"), function(name) {
        getNamespaceInfo(asNamespace(name), "path")
    }, character(1)))
write.table(data.frame(name = names(records$identity$namespace_paths),
                       path = unname(records$identity$namespace_paths)),
            file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE,
            row.names = FALSE)
saveRDS(records, file.path(output, "observations.rds"))
dput(records, file = file.path(output, "observations.R"))
