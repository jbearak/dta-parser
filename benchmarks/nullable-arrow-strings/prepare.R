args <- commandArgs(TRUE)
stopifnot(length(args) == 2L, !dir.exists(args[[2L]]))
.libPaths(c(normalizePath(args[[1L]], mustWork = TRUE), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(find.package("dtatools")),
                    file.path(normalizePath(args[[1L]]), "dtatools")))
dir.create(args[[2L]], recursive = TRUE)
n <- 250000L
columns <- 4L
positions <- sort(unique(c(seq.int(997L, n, by = 997L), n)))
manifest <- list()
for (cardinality in c("low", "high")) {
    set.seed(77119L)
    base <- lapply(seq_len(columns), function(j) {
        ids <- if (cardinality == "low") sample.int(32L, n, replace = TRUE) else seq_len(n)
        value <- enc2utf8(sprintf("caf\u00e9-\u6771\u4eac-%d-%06d", j, ids))
        # Zero/one/sparse differ only in validity: every possible null has an
        # empty payload in every fixture, preserving values/offset bytes.
        value[positions] <- ""
        value
    })
    for (nulls in c("zero", "one", "sparse")) {
        frame <- as.data.frame(setNames(lapply(seq_len(columns), function(j) {
            value <- base[[j]]
            if (nulls == "one") value[[n]] <- NA_character_
            if (nulls == "sparse") value[positions] <- NA_character_
            attr(value, "label") <- paste("UTF-8 column", j)
            attr(value, "format.stata") <- "%24s"
            value
        }), paste0("text", seq_len(columns))), check.names = FALSE)
        attr(frame, "label") <- "nullable string boundary probe"
        id <- paste(cardinality, nulls, sep = "-")
        saveRDS(frame, file.path(args[[2L]], paste0(id, ".rds")), compress = FALSE)
        save_arrow(frame, file.path(args[[2L]], paste0(id, ".arrow")),
                   compression = "uncompressed", checksums = TRUE, threads = 1L)
        manifest[[length(manifest) + 1L]] <- data.frame(id, cardinality, nulls, n,
            columns, expected_na_per_column = if (nulls == "zero") 0L else
                if (nulls == "one") 1L else length(positions))
    }
}
frame <- as.data.frame(setNames(lapply(seq_len(columns), function(j)
    as.double((seq_len(n) * (2 * j + 1)) %% 65521) / 8), paste0("number", seq_len(columns))))
attr(frame, "label") <- "finite numeric control"
saveRDS(frame, file.path(args[[2L]], "finite.rds"), compress = FALSE)
save_arrow(frame, file.path(args[[2L]], "finite.arrow"), compression = "uncompressed",
           checksums = TRUE, threads = 1L)
manifest[[length(manifest) + 1L]] <- data.frame(id = "finite", cardinality = "numeric",
    nulls = "zero", n, columns, expected_na_per_column = 0L)
write.csv(do.call(rbind, manifest), file.path(args[[2L]], "fixtures.csv"), row.names = FALSE)
