# Deterministic generated inputs and paths stay in a private directory.
args <- commandArgs(TRUE)
stopifnot(length(args) %in% 2:3)
rows <- as.integer(args[[2L]])
compact_rows <- if (length(args) == 3L) as.integer(args[[3L]]) else rows
stopifnot(!is.na(rows), rows >= 1L, rows <= 1e7,
    !is.na(compact_rows), compact_rows >= 1L, compact_rows <= 1e7)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
source(file.path(dirname(normalizePath(script)), "common.R"))
activate_library()
for (package in c("jsonlite", "haven", "arrow", "dtatools")) {
    stopifnot(requireNamespace(package, quietly = TRUE))
}
stopifnot(!dir.exists(args[[1L]]))
dir.create(args[[1L]], recursive = TRUE, mode = "0700")
directory <- normalizePath(args[[1L]])
index <- seq_len(rows)
make_numeric <- function(j) {
    x <- as.double((as.double(index) * (j * 2L + 1L) + j * 97L) %% 1000003L) / 8
    x[(index + j) %% 997L == 0L] <- NA_real_
    x
}
numeric <- setNames(lapply(seq_len(32L), make_numeric), sprintf("number_%02d", seq_len(32L)))
mixed <- setNames(lapply(seq_len(16L), make_numeric), sprintf("number_%02d", seq_len(16L)))
for (j in seq_len(8L)) mixed[[sprintf("category_%02d", j)]] <-
    c("alpha", "beta", "gamma", "delta", "caf\u00e9", "\u6771\u4eac")[(index + j) %% 6L + 1L]
for (j in seq_len(8L)) mixed[[sprintf("text_%02d", j)]] <-
    sprintf("record-%07d-group-%02d", (index * (j + 1L)) %% 999983L, (index + j) %% 31L)
index <- seq_len(compact_rows)
storage <- c(rep("byte", 8L), rep("int", 8L), rep("long", 8L), rep("float", 6L), rep("double", 2L))
compact <- setNames(lapply(seq_along(storage), function(j) {
    kind <- storage[[j]]
    x <- switch(kind,
        byte = as.double((index + j) %% 101L),
        int = as.double((as.double(index) * 31 + j) %% 60001L - 30000L),
        long = as.double((as.double(index) * 32771 + j) %% 2000000001),
        float = make_numeric(j), double = make_numeric(j))
    x[(index + j) %% 997L == 0L] <- NA_real_
    x
}), sprintf("compact_%02d", seq_along(storage)))
fixtures <- list(numeric = as.data.frame(numeric, check.names = FALSE),
    compact = as.data.frame(compact, check.names = FALSE),
    mixed = as.data.frame(mixed, check.names = FALSE))
manifest <- list(reads = list(), generation = list(rows = rows, compact_rows = compact_rows, columns = 32L,
    numeric = "32 exact binary-fraction double columns with periodic NA",
    compact = "eight byte, eight int, eight long, six float, two double; periodic NA",
    mixed = "16 doubles, eight repeated UTF-8 categories, eight varied ASCII strings",
    csv = "base write.table decimal precision 15; quoted strings; NA sentinel NA",
    rds = "version 3, uncompressed", dta = "haven version 15; compact uses dtatools version19 declared Stata storage",
    arrow = "dtatools profile, uncompressed, checksums enabled",
    fst = "default compression 50", qs2 = "compress_level=3, shuffle=TRUE, nthreads=1",
    feather = "Arrow IPC v2, uncompressed, 65536-row record batches, no dtatools checksums"))
old <- options(digits = 15L)
for (id in names(fixtures)) {
    value <- fixtures[[id]]
    paths <- setNames(file.path(directory, paste0(id, c(".csv", ".rds", ".dta", ".arrow", ".feather"))),
        c("csv", "rds", "dta", "arrow", "feather"))
    write.table(value, paths[["csv"]], sep = ",", row.names = FALSE, na = "NA", qmethod = "double")
    saveRDS(value, paths[["rds"]], compress = FALSE, version = 3L)
    if (id == "compact") {
        declared <- value
        for (j in seq_along(declared)) declared[[j]] <-
            getExportedValue("dtatools", paste0("dta_", storage[[j]]))(declared[[j]])
        dtatools::save_dta(declared, paths[["dta"]], version = 19L)
    } else haven::write_dta(value, paths[["dta"]], version = 15L)
    imported <- dtatools::read_dta(paths[["dta"]], output = "tibble")
    stopifnot(identical(plain_values(imported), plain_values(value)))
    dtatools::save_arrow(imported, paths[["arrow"]], compression = "uncompressed", checksums = TRUE)
    restored <- dtatools::read_arrow(paths[["arrow"]], output = "tibble")
    stopifnot(identical(dtatools::datasig(imported), dtatools::datasig(restored)))
    arrow::write_feather(value, paths[["feather"]], compression = "uncompressed", chunk_size = 65536L)
    if (requireNamespace("fst", quietly = TRUE)) {
        paths[["fst"]] <- file.path(directory, paste0(id, ".fst"))
        fst::write_fst(value, paths[["fst"]])
    }
    if (requireNamespace("qs2", quietly = TRUE)) {
        paths[["qs2"]] <- file.path(directory, paste0(id, ".qs2"))
        qs2::qs_save(value, paths[["qs2"]], compress_level = 3L, shuffle = TRUE, nthreads = 1L)
    }
    manifest$reads[[length(manifest$reads) + 1L]] <- c(list(id = id,
        rows = nrow(value), columns = ncol(value), reference = paths[["rds"]],
        qualification = "values"), as.list(paths))
    message("Prepared ", id, ": ", nrow(value), " rows x ", ncol(value), " columns")
}
manifest$generation$source_sha256 <- as.list(setNames(unname(tools::sha256sum(
    c(normalizePath(script), file.path(dirname(normalizePath(script)), "common.R")))),
    c("prepare.R", "common.R")))
manifest$generation$package_versions <- as.list(vapply(c("dtatools", "haven", "arrow", "fst", "qs2"),
    function(package) if (requireNamespace(package, quietly = TRUE))
        as.character(packageVersion(package)) else "unavailable", character(1L)))
jsonlite::write_json(manifest, file.path(directory, "fixtures.json"), pretty = TRUE, auto_unbox = TRUE)

options(old)
