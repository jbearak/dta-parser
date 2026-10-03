# Fixture construction is excluded from every retained measurement.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L, !dir.exists(args[[2L]]))
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(find.package("dtatools")), file.path(library_path, "dtatools")))
dir.create(args[[2L]], recursive = TRUE)
destination <- normalizePath(args[[2L]], mustWork = TRUE)
n <- 2000000L
columns <- 8L
batch_rows <- 65536L
null_positions <- sort(unique(c(seq.int(1L, n, by = batch_rows), n)))
metadata <- function(frame) list(label = attr(frame, "label", exact = TRUE),
    names = names(frame), columns = lapply(frame, function(x)
        list(label = attr(x, "label", exact = TRUE),
             format = attr(x, "format.stata", exact = TRUE),
             storage = attr(x, "stata.storage", exact = TRUE),
             class = attr(x, "class", exact = TRUE), labels = attr(x, "labels", exact = TRUE))))
frame_from <- function(values) as.data.frame(setNames(values, paste0("x", seq_len(columns))),
                                             check.names = FALSE)
plain <- function(x) { x <- as.double(x); attributes(x) <- NULL; x }
manifest <- list()
physical_batches <- list()
schema_facts <- list()
inspect_file <- function(id, filename) {
    connection <- arrow::ReadableFile$create(file.path(destination, filename))
    on.exit(connection$close(), add = TRUE)
    reader <- arrow::RecordBatchFileReader$create(connection)
    schema <- reader$schema
    expected_type <- if (id %in% c("integer_i32", "nullable_i32")) "int32" else
        if (id == "widen_f32") "float" else if (id == "compact_i16") "int16" else "double"
    fields <- lapply(schema$fields, function(field) list(name = field$name,
        type = field$type$ToString(), nullable = field$nullable, metadata = field$metadata))
    stopifnot(length(fields) == columns,
              all(vapply(fields, function(field) field$type, character(1)) == expected_type))
    schema_facts[[id]] <<- list(filename = filename, text = schema$ToString(),
        metadata = schema$metadata, fields = fields)
    lengths <- numeric()
    for (batch in seq_len(reader$num_record_batches)) {
        value <- reader$get_batch(batch - 1L)
        lengths <- c(lengths, value$num_rows)
        stopifnot(value$num_columns == columns)
        for (name in names(value)) {
            array <- value$GetColumnByName(name)
            nulls <- array$null_count
            stopifnot(array$length() == value$num_rows, array$type$ToString() == expected_type)
            if (id %in% c("nullable_f64", "nullable_i32")) stopifnot(nulls > 0)
            else stopifnot(nulls == 0)
            physical_batches[[length(physical_batches) + 1L]] <<- data.frame(
                id, filename, batch, column = name, rows = value$num_rows,
                nulls, type = array$type$ToString(), stringsAsFactors = FALSE)
        }
    }
    # Verify the observed geometry; do not infer it merely from writer defaults.
    expected_lengths <- pmin(batch_rows, n - seq.int(0L, n - 1L, by = batch_rows))
    stopifnot(length(lengths) == length(expected_lengths),
              all(lengths == expected_lengths), sum(lengths) == n)
    length(lengths)
}
record <- function(id, filename, frame, reference, profile, route, retained = FALSE) {
    stopifnot(nrow(frame) == n, ncol(frame) == columns)
    actual_batches <- inspect_file(id, filename)
    oracle <- list(values = lapply(reference, plain), metadata = metadata(frame),
                   types = vapply(frame, typeof, character(1)), retained = retained,
                   actual_batches = actual_batches)
    saveRDS(oracle, file.path(destination, paste0(id, ".rds")), compress = FALSE)
    manifest[[length(manifest) + 1L]] <<- data.frame(id, filename, profile, route,
        n, columns, batch_rows, actual_batches, retained, expected_na_per_column =
            sum(is.na(oracle$values[[1L]])), stringsAsFactors = FALSE)
}
base <- lapply(seq_len(columns), function(j)
    as.double((seq_len(n) * (2L * j + 1L)) %% 10007L - 5003L) / 8)
special <- c(-0, 0, 1, -1, Inf, -Inf, NaN, NA_real_, tagged_missing(letters),
             readBin(as.raw(c(1, rep(0, 7))), "double", n = 1L, endian = "little"))
payload <- frame_from(lapply(base, function(x) { x[seq_along(special)] <- special; x }))
attr(payload, "label") <- "compatible double payload"
for (j in seq_len(columns)) attr(payload[[j]], "label") <- paste("Double", j)
save_arrow(payload, file.path(destination, "double.arrow"), compression = "uncompressed",
           checksums = TRUE, threads = 1L)
record("payload_f64", "double.arrow", payload, payload, TRUE, "PayloadDouble")
semantic <- frame_from(lapply(payload, plain))
record("semantic_f64", "double.arrow", semantic, payload, FALSE, "SemanticDouble")

integers <- frame_from(lapply(seq_len(columns), function(j) {
    x <- (seq_len(n) * (2L * j + 1L)) %% 60001L - 30000L
    x[1:4] <- c(-2147483647L, 2147483647L, -1L, 0L)
    x
}))
attr(integers, "label") <- "compatible integer"
save_arrow(integers, file.path(destination, "integer.arrow"), compression = "uncompressed",
           checksums = TRUE, threads = 1L)
record("integer_i32", "integer.arrow", integers, integers, TRUE, "Integer")

nullable_double <- frame_from(lapply(base, function(x) { x[null_positions] <- NA_real_; x }))
arrow::write_ipc_file(nullable_double, file.path(destination, "nullable-double.arrow"),
                      chunk_size = batch_rows, compression = "uncompressed")
record("nullable_f64", "nullable-double.arrow", nullable_double, nullable_double,
       TRUE, "SemanticDouble")
nullable_integer <- integers
attr(nullable_integer, "label") <- "nullable integer control"
for (j in seq_len(columns)) nullable_integer[[j]][null_positions] <- NA_integer_
save_arrow(nullable_integer, file.path(destination, "nullable-integer.arrow"),
           compression = "uncompressed", checksums = TRUE, threads = 1L)
record("nullable_i32", "nullable-integer.arrow", nullable_integer, nullable_integer,
       TRUE, "Integer")

widened <- frame_from(base)
arrays <- lapply(widened, arrow::Array$create, type = arrow::float32())
table <- do.call(arrow::Table$create, arrays)
arrow::write_ipc_file(table, file.path(destination, "widen-float.arrow"),
                      chunk_size = batch_rows, compression = "uncompressed")
record("widen_f32", "widen-float.arrow", widened, widened, TRUE, "SemanticDouble")

compact_values <- frame_from(lapply(seq_len(columns), function(j) {
    x <- as.double((seq_len(n) * (2L * j + 1L)) %% 60001L - 30000L)
    x[null_positions] <- rep(c(NA_real_, tagged_missing(letters)), length.out = length(null_positions))
    x
}))
compact <- frame_from(lapply(compact_values, dta_int))
for (j in seq_len(columns)) {
    # Make the profile's default format/storage explicit in the source oracle.
    attr(compact[[j]], "format.stata") <- "%8.0g"
    attr(compact[[j]], "stata.storage") <- "int"
}
attr(compact, "label") <- "retained compact control"
save_arrow(compact, file.path(destination, "compact-int.arrow"), compression = "uncompressed",
           checksums = TRUE, threads = 1L)
record("compact_i16", "compact-int.arrow", compact, compact_values, TRUE,
       "ProfiledCompact", retained = TRUE)
write.csv(do.call(rbind, manifest), file.path(destination, "fixtures.csv"), row.names = FALSE)
write.csv(do.call(rbind, physical_batches), file.path(destination, "physical-batches.csv"), row.names = FALSE)
jsonlite::write_json(schema_facts, file.path(destination, "schema-facts.json"),
                    auto_unbox = TRUE, pretty = TRUE, null = "null")
writeLines(c(paste("R:", getRversion()), paste("arrow:", packageVersion("arrow")),
             paste("dtatools:", packageVersion("dtatools"))), file.path(destination, "versions.txt"))
