# Add a deterministic wide fixture without modifying an existing manifest.
# Usage: prepare-wide.R EXISTING_MANIFEST NEW_DIRECTORY [COLUMNS ROWS]
args <- commandArgs(TRUE)
stopifnot(length(args) %in% c(2L, 4L))
columns <- if (length(args) == 4L) as.integer(args[[3L]]) else 4096L
rows <- if (length(args) == 4L) as.integer(args[[4L]]) else 128L
stopifnot(!is.na(columns), columns >= 5L, columns <= 32767L,
    !is.na(rows), rows >= 1L, rows <= 1e6)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
script_dir <- dirname(normalizePath(script))
source(file.path(script_dir, "common.R"))
activate_library()
for (package in c("jsonlite", "dtatools", "arrow"))
    stopifnot(requireNamespace(package, quietly = TRUE))
stopifnot(identical(normalizePath(find.package("dtatools")),
    normalizePath(file.path(Sys.getenv("DTATOOLS_BENCH_LIB"), "dtatools"))))
original_sha256 <- unname(tools::sha256sum(args[[1L]]))
manifest <- jsonlite::fromJSON(args[[1L]], simplifyVector = FALSE)
stopifnot(is.list(manifest$reads),
    !"wide" %in% vapply(manifest$reads, function(item) item$id, character(1L)),
    !dir.exists(args[[2L]]))
dir.create(args[[2L]], recursive = TRUE, mode = "0700")
directory <- normalizePath(args[[2L]])
index <- seq_len(rows)
storage <- rep(c("byte", "int", "long", "float", "double"), length.out = columns)
plain <- setNames(lapply(seq_len(columns), function(j) {
    x <- switch(storage[[j]],
        byte = as.double((index + j) %% 101L),
        int = as.double((as.double(index) * 31 + j) %% 60001L - 30000L),
        long = as.double((as.double(index) * 32771 + j) %% 2000000001),
        as.double((as.double(index) * (j * 2L + 1L) + j * 97L) %% 1000003L) / 8)
    x[(index + j) %% 31L == 0L] <- NA_real_
    x
}), sprintf("value_%05d", seq_len(columns)))
value <- as.data.frame(plain, check.names = FALSE)
declared <- value
for (j in seq_along(declared)) {
    column <- getExportedValue("dtatools", paste0("dta_", storage[[j]]))(declared[[j]])
    group <- (j - 1L) %% 16L + 1L
    attr(column, "label") <- sprintf("Benchmark attribute group %02d", group)
    attr(column, "labels") <- setNames(as.double(1:4), sprintf("Group %02d level %d", group, 1:4))
    attr(column, "value.label.name") <- sprintf("label_group_%02d", group)
    attr(column, "format.stata") <- c("%9.0g", "%12.0g", "%12.3f")[(j - 1L) %% 3L + 1L]
    declared[[j]] <- column
}
paths <- setNames(file.path(directory, paste0("wide", c(".csv", ".rds", ".dta", ".arrow", ".feather"))),
    c("csv", "rds", "dta", "arrow", "feather"))
options(digits = 15L)
write.table(value, paths[["csv"]], sep = ",", row.names = FALSE, na = "NA", qmethod = "double")
saveRDS(value, paths[["rds"]], compress = FALSE, version = 3L)
dtatools::save_dta(declared, paths[["dta"]], version = 19L)
imported <- dtatools::read_dta(paths[["dta"]], output = "tibble")
stopifnot(identical(plain_values(imported), plain_values(value)))
dtatools::save_arrow(imported, paths[["arrow"]], compression = "uncompressed", checksums = TRUE)
restored <- dtatools::read_arrow(paths[["arrow"]], output = "tibble")
stopifnot(identical(dtatools::datasig(imported), dtatools::datasig(restored)))
arrow::write_feather(value, paths[["feather"]], compression = "uncompressed", chunk_size = 65536L)
if (requireNamespace("fst", quietly = TRUE)) {
    paths[["fst"]] <- file.path(directory, "wide.fst")
    fst::write_fst(value, paths[["fst"]])
}
if (requireNamespace("qs2", quietly = TRUE)) {
    paths[["qs2"]] <- file.path(directory, "wide.qs2")
    qs2::qs_save(value, paths[["qs2"]], compress_level = 3L, shuffle = TRUE, nthreads = 1L)
}
manifest$reads[[length(manifest$reads) + 1L]] <- c(list(id = "wide", rows = rows,
    columns = columns, reference = paths[["rds"]], qualification = "values"), as.list(paths))
manifest$generation$wide <- list(rows = rows, columns = columns,
    values = "cycling byte/int/long/float/double, exact binary fractions, periodic NA",
    metadata = "16 shared value-label groups and variable labels; three repeated numeric formats",
    serialization = "dtatools DTA version19; other formats match original fixture preparation",
    original_manifest_sha256 = original_sha256,
    source_sha256 = as.list(setNames(unname(tools::sha256sum(c(normalizePath(script),
        file.path(script_dir, "common.R")))), c("prepare-wide.R", "common.R"))),
    package_versions = as.list(vapply(c("dtatools", "arrow", "fst", "qs2"),
        function(package) if (requireNamespace(package, quietly = TRUE))
            as.character(packageVersion(package)) else "unavailable", character(1L))))
stopifnot(identical(original_sha256, unname(tools::sha256sum(args[[1L]]))))
jsonlite::write_json(manifest, file.path(directory, "fixtures.json"), pretty = TRUE, auto_unbox = TRUE)
message("Prepared wide: ", rows, " rows x ", columns, " columns")
