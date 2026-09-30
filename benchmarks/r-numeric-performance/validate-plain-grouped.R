#!/usr/bin/env Rscript
# Run from any directory; fixtures and verification are outside the timer.
args <- commandArgs(TRUE)
if (length(args) != 5L) stop("Usage: validate-plain-grouped.R LIBRARY LABEL OUTPUT SAMPLES SEED")
lib <- normalizePath(args[[1L]])
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = lib))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(data.table))
stopifnot(normalizePath(find.package("dtatools")) == normalizePath(file.path(lib, "dtatools")))
label <- args[[2L]]
out <- args[[3L]]
samples <- as.integer(args[[4L]])
seed <- as.integer(args[[5L]])
stopifnot(samples > 0L, !is.na(seed))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
options(dtatools.generate_type = "double")
data.table::setDTthreads(1L)
ns <- asNamespace("dtatools")
cc <- function(name, ...) .Call(get(name, ns), ...)
operation <- function(engine, scenario, grouped) {
    rhs <- switch(scenario, scalar = quote(3), call = quote(abs(-3)),
                  arithmetic = quote(x + 1), create = quote(x + 1),
                  five = quote(x + 1))
    create <- scenario %in% c("create", "five")
    target <- if (create) "y" else "x"
    assignments <- if (scenario == "five") setNames(rep(list(rhs), 5L), paste0("y", 1:5)) else setNames(list(rhs), target)
    if (engine %in% c("repl", "gen")) {
        call <- as.call(c(list(if (engine == "repl") quote(dtatools::replace_values) else quote(dtatools::gen), quote(d)), assignments,
                         if (grouped) list(by = quote(g))))
    } else if (engine == "dibble_bracket" || startsWith(engine, "data_table")) {
        j <- if (length(assignments) == 1L) call(":=", as.name(target), rhs) else
            as.call(c(list(as.name(":=")), assignments))
        call <- as.call(c(list(as.name("["), quote(d), quote(expr = ), j),
                         if (grouped) list(by = quote(g))))
    } else {
        call <- as.call(c(list(quote(dplyr::mutate), quote(d)), assignments,
                         if (grouped) list(.by = quote(g))))
    }
    call
}

verify <- function(result, original, n, width, groups, scenario, engine, expected_attributes) {
    expected <- if (scenario %in% c("scalar", "call")) rep(3, n) else rep(c(1, 2, 3, 4), length.out = n) + 1
    targets <- if (scenario == "five") paste0("y", 1:5) else if (scenario == "create") "y" else "x"
    for (name in targets) stopifnot(identical(as.double(result[[name]]), expected))
    stopifnot(nrow(result) == n)
    original_names <- c("x", "g", if (width > 2L) paste0("v", 3:width))
    stopifnot(identical(names(result), c(original_names, setdiff(targets, original_names))))
    for (name in setdiff(original_names, targets)) {
        expected <- if (name == "x") rep(c(1, 2, 3, 4), length.out = n) else
            if (name == "g") as.double(rep(seq_len(groups), length.out = n)) else rep(as.double(substring(name, 2L)), n)
        stopifnot(identical(as.double(result[[name]]), expected))
        stopifnot(identical(attributes(result[[name]]), expected_attributes[[name]]))
    }
    typed <- engine %in% c("repl", "gen", "dibble_bracket", "dplyr_dibble", "data_table_typed") ||
        (engine == "dplyr_typed" && !scenario %in% c("scalar", "call"))
    if (typed) for (name in targets) {
        stopifnot(identical(dta_storage_type(result[[name]]), "double"))
        # Replacements preserve the entire input attribute list. New columns
        # use the ordinary generated double's complete canonical attributes.
        wanted <- if (name %in% original_names && engine %in% c("repl", "dibble_bracket"))
            expected_attributes[[name]] else attributes(dta_double(double()))
        stopifnot(identical(attributes(result[[name]]), wanted))
    }
    if (engine == "dplyr_typed" && scenario %in% c("scalar", "call"))
        for (name in targets) stopifnot(is.null(dta_storage_type(result[[name]])))
    if (startsWith(engine, "dplyr")) {
        stopifnot(identical(names(original), original_names),
                  identical(as.double(original$x), rep(c(1, 2, 3, 4), length.out = n)))
    }
}

fixture <- function(engine, mode, n, width, groups) {
    env <- new.env(parent = globalenv())
    values <- list(x = rep(c(1, 2, 3, 4), length.out = n),
                   g = as.double(rep(seq_len(groups), length.out = n)))
    if (width > 2L) for (i in 3:width) values[[paste0("v", i)]] <- rep(as.double(i), n)
    if (engine %in% c('gen', 'repl', 'dibble_bracket', 'dplyr_dibble')) {
        env$d <- as_dibble(tibble::as_tibble(lapply(values, dta_double)))
        for (i in seq_along(env$d)) {
            column <- cc('C_dtatools_capture_column', dta_double(values[[i]]))
            stopifnot(cc('C_dtatools_is_owned_double', column))
            if (mode == 'plain') column <- cc('C_dtatools_owned_plain_snapshot', column)
            cc('C_dtatools_set_data_column', env$d, as.integer(i), column)
        }
        for (i in seq_along(env$d)) {
            column <- .subset2(env$d, i)
            stopifnot(identical(cc('C_dtatools_is_owned_double', column), mode == 'owned'))
            stopifnot(!get('.is_numeric_altrep', ns)(column))
        }
    } else env$d <- if (engine == 'data_table_plain') as.data.table(values) else tibble::as_tibble(values)
    env$expected_attributes <- lapply(seq_along(env$d), function(i) attributes(.subset2(env$d, i)))
    names(env$expected_attributes) <- names(env$d)
    env
}
writeLines(trimws(capture.output(sessionInfo()), which = "right"), file.path(out, "session.txt"))
writeLines(c(label, getLoadedDLLs()[["dtatools"]][["path"]]), file.path(out, "build.txt"))
invisible(gc.time(TRUE))
utils::Rprofmem(NULL)
set.seed(seed)
records <- list()
admissions <- list()
counter_names <- c(repl = "C_dtatools_probe_unique_repl_stats",
    gen = "C_dtatools_probe_direct_final_stats", bracket = "C_dtatools_probe_bracket_step_stats",
    grouped_bracket = "C_dtatools_probe_grouped_bracket_stats",
    grouped_gen = "C_dtatools_probe_grouped_gen_stats",
    mutate = "C_dtatools_probe_dplyr_early_stats",
    grouped_mutate = "C_dtatools_grouped_stats")
read_counters <- function() lapply(counter_names, function(name) {
    if (!exists(name, ns, inherits = FALSE)) return(NULL)
    tryCatch(cc(name, FALSE), error = function(e) NULL)
})
shapes <- data.frame(n = c(100L, 100L, 100000L, 100000L, 10000L, 10000L),
                     width = c(2L, 100L, 2L, 100L, 2L, 100L),
                     groups = c(1L, 1L, 1L, 1L, 100L, 100L))
for (s in seq_len(nrow(shapes))) {
    shape <- shapes[s, ]
    scenarios <- if (shape$groups > 1L) c("create", "five") else
        c("scalar", "call", "arithmetic", "create", "five")
    for (mode in c("plain", "owned")) for (scenario in scenarios) {
        engines <- c(if (scenario == "create") "gen" else if (scenario != "five") "repl", "dibble_bracket",
                     "dplyr_dibble", "data_table_plain", "dplyr_plain")
        calls <- setNames(lapply(engines, operation, scenario = scenario,
                                grouped = shape$groups > 1L), engines)
        for (engine in engines) {
            env <- fixture(engine, mode, shape$n, shape$width, shape$groups)
            before_counts <- read_counters()
            result <- eval(calls[[engine]], env)
            after_counts <- read_counters()
            admissions[[length(admissions) + 1L]] <- list(n = shape$n, width = shape$width,
                groups = shape$groups, mode = mode, scenario = scenario, engine = engine,
                counters = Map(function(a, b) if (is.numeric(a) && is.numeric(b)) b - a else NULL,
                               before_counts, after_counts))
            verify(result, env$d, shape$n, shape$width, shape$groups, scenario,
                   engine, env$expected_attributes)
        }
        for (sample in seq_len(samples)) for (engine in sample(engines)) {
            env <- fixture(engine, mode, shape$n, shape$width, shape$groups)
            invisible(gc(FALSE))
            before <- sum(gc.time()[1:3])
            elapsed <- bench::system_time(result <- eval(calls[[engine]], env))
            gc_seconds <- sum(gc.time()[1:3]) - before
            verify(result, env$d, shape$n, shape$width, shape$groups, scenario,
                   engine, env$expected_attributes)
            records[[length(records) + 1L]] <- data.frame(label, n = shape$n,
                width = shape$width, groups = shape$groups, mode, scenario,
                engine, sample, us = as.numeric(elapsed[["real"]]) * 1e6, gc_seconds)
            rm(env, result)
        }
        write.csv(do.call(rbind, records), file.path(out, "raw.csv"), row.names = FALSE)
        cat(shape$n, shape$width, shape$groups, mode, scenario, "verified\n")
        flush.console()
    }
}
saveRDS(admissions, file.path(out, "admissions.rds"))
raw <- do.call(rbind, records)
summary <- aggregate(cbind(us, gc_seconds) ~ n + width + groups + mode + scenario + engine,
                     raw, median)
write.csv(summary, file.path(out, "summary.csv"), row.names = FALSE)
cat("Verified", nrow(raw), "timed calls, with", sum(raw$gc_seconds > 0), "timed collections\n")
