# Bounded high-cardinality follow-up. Group counts are fixed below, not args[5].
# Uses unchanged accepted-install wrapper and fixed predecessor safe reference.
args <- commandArgs(TRUE)
stopifnot(length(args) == 5L)
source("benchmarks/r-dibble-dplyr/owned-atomic-helpers.R")
library_path <- atomic_start(args[[1L]], args[[3L]], "candidate")
output <- normalizePath(args[[2L]], mustWork = TRUE)
iterations <- as.integer(args[[4L]])
stopifnot(iterations == 7L, capabilities("profmem"))
support <- Sys.getenv("DTA_STAGE7_SUPPORT")
source(file.path(support, "reference-v1.R"))
source(file.path(support, "validation-v2.R"))
routes <- strsplit(Sys.getenv("DTA_STAGE7_ROUTES"), ",", fixed = TRUE)[[1L]]
stopifnot(identical(routes, "public") ||
    identical(routes, c("public", "predecessor_safe_reference")))
if ("predecessor_safe_reference" %in% routes) stage7_reference_start(library_path)
suppressPackageStartupMessages(library(bench))
writeLines(c(atomic_identity(args[[3L]], library_path, "candidate"),
    "groups: 1024,4096; rows: two per group; one integer payload plus integer key",
    "whole group_nest and nest_by calls; setup/checks outside timed/profiled work",
    "seven GC-inclusive elapsed samples; one warmed Rprofmem profile",
    "public predecessor is a weaker foreign-write control; fixed safe reference is unchanged",
    "source/output values and metadata checked outside measurement; schemas saved for cross-source comparison",
    "no foreign writes, native-state sweep, retained-heap or RSS claim"),
    file.path(output, "session.txt"))

# Compare exact numeric values without truncating fractional errors. The
# constructor may represent Stata integer storage through a double wrapper.
# Full public type/metadata parity is checked using the saved cross-source schemas.
check_values <- function(value, expected) {
    if (!typeof(value) %in% c("integer", "double")) return(FALSE)
    actual <- stage7_plain_values(value)
    length(actual) == length(expected) && !anyNA(actual) && all(actual == expected)
}
stopifnot(check_values(c(1, 2), 1:2), !check_values(c(1.5, 2), 1:2),
    !check_values(logical(), integer()))

records <- list()
for (groups in c(1024L, 4096L)) {
    rows <- 2L * groups
    for (workload in c("group_nest", "nest_by")) for (route in routes) {
        input <- dtatools::dibble(g = rep(seq_len(groups), each = 2L), x = seq_len(rows))
        attr(input, "label") <- "High-cardinality nesting fixture"
        input <- dplyr::group_by(input, g)
        source_schema <- stage7_schema(input)
        invoke <- function() {
            if (identical(route, "predecessor_safe_reference")) {
                return(stage7_safe_reference(input, workload, arguments =
                    if (workload == "group_nest") list(keep = FALSE) else list(.keep = FALSE)))
            }
            if (workload == "group_nest") dplyr::group_nest(input, keep = FALSE) else
                dplyr::nest_by(input, .keep = FALSE)
        }
        check <- function(value) {
            stopifnot(dtatools::is_dibble(value), nrow(value) == groups,
                identical(names(value), c("g", "data")),
                check_values(value$g, seq_len(groups)),
                length(value$data) == groups,
                check_values(input$g, rep(seq_len(groups), each = 2L)),
                check_values(input$x, seq_len(rows)),
                identical(stage7_schema(input), source_schema),
                identical(dplyr::group_vars(input), "g"))
            source_groups <- attr(input, "groups", exact = TRUE)
            stopifnot(nrow(source_groups) == groups,
                check_values(source_groups$g, seq_len(groups)))
            for (i in seq_len(groups)) {
                expected <- seq.int(2L * i - 1L, 2L * i)
                chunk <- .subset2(value$data, i)
                stopifnot(is.data.frame(chunk), nrow(chunk) == 2L,
                    identical(names(chunk), "x"),
                    check_values(chunk$x, expected),
                    identical(.subset2(source_groups$.rows, i), expected))
            }
            prototype <- attr(value$data, "ptype", exact = TRUE)
            stopifnot(is.data.frame(prototype), nrow(prototype) == 0L,
                identical(names(prototype), "x"), check_values(prototype$x, integer()))
            if (workload == "nest_by") {
                stopifnot(inherits(value, "rowwise_df"),
                    identical(dplyr::group_vars(value), "g"))
                result_groups <- attr(value, "groups", exact = TRUE)
                stopifnot(nrow(result_groups) == groups,
                    check_values(result_groups$g, seq_len(groups)))
                for (i in seq_len(groups)) stopifnot(
                    identical(.subset2(result_groups$.rows, i), i))
            } else stopifnot(!inherits(value, "rowwise_df"),
                identical(dplyr::group_vars(value), character()))
            invisible(NULL)
        }
        stem <- paste(groups, workload, route, sep = "-")
        warmup <- invoke()
        check(warmup)
        result_schema <- stage7_schema(warmup)
        rm(warmup)
        invisible(gc())
        profile_path <- file.path(output, paste0(stem, "-Rprofmem.log"))
        Rprofmem(profile_path)
        profiled <- tryCatch(invoke(), finally = Rprofmem(NULL))
        check(profiled)
        stopifnot(identical(stage7_schema(profiled), result_schema))
        lines <- readLines(profile_path, warn = FALSE)
        events <- grepl("^[0-9]+ :", lines)
        stopifnot(all(events | grepl("^new page:", lines)))
        sizes <- as.numeric(sub(" .*", "", lines[events]))
        rm(profiled)
        invisible(gc())
        mark <- bench::mark(invoke(), iterations = iterations, check = TRUE, filter_gc = FALSE)
        check(mark$result[[1L]])
        stopifnot(identical(stage7_schema(mark$result[[1L]]), result_schema))
        times <- as.numeric(mark$time[[1L]])
        gc_events <- as.data.frame(mark$gc[[1L]])
        stopifnot(length(times) == iterations, mark$n_itr == iterations,
            nrow(gc_events) == iterations)
        write.csv(cbind(data.frame(iteration = seq_along(times), seconds = times), gc_events),
            file.path(output, paste0(stem, "-times.csv")), row.names = FALSE)
        dput(list(source = source_schema, result = result_schema),
            file.path(output, paste0(stem, "-schemas.R")))
        record <- data.frame(rows, groups, payload_columns = 1L, workload, route,
            median_ms = as.numeric(mark$median) * 1000, iterations = mark$n_itr,
            gc_count = mark$n_gc, warm_r_allocated_bytes = sum(sizes),
            warm_r_largest_allocation_bytes = max(c(0, sizes)),
            values_groups_source = TRUE)
        records[[length(records) + 1L]] <- record
        write.csv(do.call(rbind, records), file.path(output, "operations.csv"), row.names = FALSE)
        print(record)
    }
}
stopifnot(length(records) == 4L * length(routes))
writeLines("complete", file.path(output, "complete.txt"))
