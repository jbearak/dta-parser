#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
mode <- args[[1L]]
.libPaths(c(args[[2L]], .libPaths()))
library(dtatools)
options(dtatools.output = "dibble", dtatools.alloccol = 1024L,
        dtatools.numeric_altrep = TRUE, dtatools.threads = 0L)

if (mode == "generate") {
    directory <- args[[3L]]
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
    cases <- data.frame(
        case = c("double-small", "double-wide", "double-tall", "mixed",
                 "string-low", "string-high", "strL", "ordinary-arrow"),
        rows = c(1000L, 1000L, 250000L, 10000L, 10000L, 10000L, 1000L, 10000L),
        columns = c(8L, 1024L, 16L, 128L, 128L, 128L, 32L, 128L)
    )
    manifest <- list()
    for (i in seq_len(nrow(cases))) {
        case <- cases$case[[i]]
        rows <- cases$rows[[i]]
        width <- cases$columns[[i]]
        index <- seq_len(rows)
        columns <- lapply(seq_len(width), function(j) {
            if (startsWith(case, "double")) return(dta_double(index / 8 + j))
            if (case == "string-low") return(dta_string(sprintf("v%02d", index %% 16)))
            if (case == "string-high") return(dta_string(sprintf("value%06d", index)))
            if (case == "strL") return(dta_string(
                paste0(sprintf("%04d", index %% 100), strrep("x", 2100)), storage = "strL"))
            if (case == "ordinary-arrow") return(switch(as.character(j %% 6),
                "0" = index, "1" = index / 8, "2" = index %% 2 == 0,
                "3" = sprintf("s%03d", index %% 100),
                "4" = factor(index %% 4), "5" = as.Date("2000-01-01") + index))
            switch(as.character(j %% 6),
                "0" = dta_byte(index %% 100), "1" = dta_int(index %% 30000),
                "2" = dta_long(index), "3" = dta_float(index / 8),
                "4" = dta_double(index / 8), "5" = dta_string(sprintf("s%03d", index %% 100)))
        })
        names(columns) <- sprintf("v%04d", seq_len(width))
        data <- tibble::new_tibble(columns, nrow = rows)
        for (format in if (case == "ordinary-arrow") "arrow" else c("dta", "arrow")) {
            path <- file.path(directory, paste0(case, ".", format))
            if (format == "dta") save_dta(data, path) else save_arrow(data, path)
            manifest[[length(manifest) + 1L]] <- data.frame(
                case = case, format = format, rows = rows, columns = width,
                file = basename(path), file_bytes = file.info(path)$size)
        }
    }
    write.csv(do.call(rbind, manifest), file.path(directory, "fixtures.csv"), row.names = FALSE)
    quit(status = 0L)
}

path <- args[[3L]]
output <- args[[4L]]
reader <- if (endsWith(path, ".dta")) read_dta else read_arrow
read <- function() reader(path, output = "dibble")
if (mode == "validate") {
    value <- read()
    # A plain serialized snapshot allows a separate cross-install oracle.
    value <- dtatools:::.reference_snapshot(value)
    attributes(value) <- attributes(value)[sort(names(attributes(value)))]
    saveRDS(value, output, version = 3L)
} else if (mode == "memory") {
    gc()
    value <- read()
    # No reader warmup or full value traversal in this process. Peak RSS
    # includes R startup, package loading, GC, the read and this small record.
    write.csv(data.frame(rows = nrow(value), columns = ncol(value)), output, row.names = FALSE)
} else if (mode == "time") {
    invisible(read())
    invisible(read())
    batch <- function(n) {
        start <- proc.time()[["elapsed"]]
        for (i in seq_len(n)) value <- read()
        proc.time()[["elapsed"]] - start
    }
    count <- 1L
    repeat {
        gc()
        elapsed <- batch(count)
        if (elapsed >= 0.15) break
        count <- count * 2L
    }
    samples <- lapply(seq_len(7L), function(i) {
        gc()
        elapsed <- batch(count)
        data.frame(sample = i, iterations = count, elapsed_seconds = elapsed,
                   milliseconds = elapsed * 1000 / count)
    })
    write.csv(do.call(rbind, samples), output, row.names = FALSE)
} else stop("unknown mode")
