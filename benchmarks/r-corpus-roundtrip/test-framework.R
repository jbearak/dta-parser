script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument), winslash = "/"))
source(file.path(script_dir, "common.R"), local = TRUE)

root <- tempfile("r-corpus-roundtrip-")
dir.create(root)
on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
for (corpus in roundtrip_corpora) dir.create(file.path(root, corpus))

fixture <- normalizePath(
    file.path(script_dir, "..", "..", "r-package", "dtaparser", "inst",
              "extdata", "all_types_v118.dta"),
    winslash = "/", mustWork = TRUE
)
stopifnot(file.copy(fixture, file.path(root, "DHS", "ordinary.DTA")))
writeBin(raw(), file.path(root, "MICS", "empty.dta"))
stopifnot(file.symlink(
    file.path(root, "DHS", "ordinary.DTA"),
    file.path(root, "NSFG", "ignored.dta")
))

inventory <- roundtrip_inventory(root, progress = FALSE)
stopifnot(
    nrow(inventory) == 2L,
    identical(sort(inventory$corpus), c("DHS", "MICS")),
    identical(inventory$release[inventory$corpus == "DHS"], 118L),
    is.na(inventory$release[inventory$corpus == "MICS"]),
    any(inventory$sha256 == benchmark_file_sha256(fixture)),
    !anyDuplicated(inventory$id)
)
invalid_hash <- tryCatch(
    benchmark_validate_sha256("not-a-hash", 1L, "test file"),
    error = identity
)
stopifnot(
    inherits(invalid_hash, "error"),
    identical(conditionMessage(invalid_hash), "test file could not be hashed")
)
ordinary_item <- inventory[inventory$corpus == "DHS", , drop = FALSE]
ordinary <- ordinary_item$path[[1L]]
ordinary_info <- file.info(ordinary, extra_cols = FALSE)
ordinary_bytes <- readBin(ordinary, "raw", n = ordinary_info$size[[1L]])
snapshot_dir <- file.path(root, "snapshots")
dir.create(snapshot_dir)
snapshot <- benchmark_snapshot_file(
    ordinary, file.path(snapshot_dir, "input.dta"),
    ordinary_item$bytes, ordinary_item$sha256
)
changed_bytes <- ordinary_bytes
changed_bytes[[length(changed_bytes)]] <- as.raw(
    bitwXor(as.integer(changed_bytes[[length(changed_bytes)]]), 1L)
)
writeBin(changed_bytes, ordinary)
Sys.setFileTime(ordinary, ordinary_info$mtime[[1L]])
stale_snapshot <- tryCatch(
    benchmark_snapshot_file(
        ordinary, file.path(snapshot_dir, "stale.dta"),
        ordinary_item$bytes, ordinary_item$sha256
    ),
    error = identity
)
stopifnot(
    inherits(stale_snapshot, "error"),
    grepl("differs from its inventory identity",
          conditionMessage(stale_snapshot), fixed = TRUE),
    identical(benchmark_file_sha256(snapshot), ordinary_item$sha256)
)
writeBin(ordinary_bytes, ordinary)
Sys.setFileTime(ordinary, ordinary_info$mtime[[1L]])
empty <- inventory[inventory$corpus == "MICS", , drop = FALSE]
stopifnot(identical(roundtrip_exclusion_reason(empty), "empty-source"))
stopifnot(
    identical(benchmark_hash_workers(NA_integer_), 1L),
    identical(benchmark_hash_workers(integer()), 1L),
    identical(benchmark_hash_workers(8L), 4L)
)
qualification_rows <- data.frame(
    id = c("pass", "excluded", "r-failure", "stata-failure"),
    status = c(
        "pass",
        "expected-exclusion",
        "r-worker-error",
        "stata-worker-error"
    ),
    stringsAsFactors = FALSE
)
stopifnot(
    identical(
        roundtrip_qualification_successes(qualification_rows)$id,
        c("pass", "excluded")
    ),
    identical(roundtrip_qualification_status(0L, "pass"), "complete"),
    identical(roundtrip_qualification_status(1L, "pass"), "failed"),
    identical(roundtrip_qualification_status(0L, "stata-worker-error"), "failed")
)
complete_qualification <- data.frame(
    id = inventory$id,
    status = vapply(seq_len(nrow(inventory)), function(index) {
        if (is.na(roundtrip_exclusion_reason(
            inventory[index, , drop = FALSE]
        ))) "pass" else "expected-exclusion"
    }, character(1L)),
    stringsAsFactors = FALSE
)
stopifnot(identical(
    roundtrip_validate_complete_qualification(
        complete_qualification, inventory
    )$id,
    inventory$id
))
truncated_qualification <- tryCatch(
    roundtrip_validate_complete_qualification(
        complete_qualification[-1L, , drop = FALSE], inventory
    ),
    error = identity
)
stopifnot(
    inherits(truncated_qualification, "error"),
    grepl(
        "exact corpus inventory",
        conditionMessage(truncated_qualification), fixed = TRUE
    )
)

matrix_inputs <- data.frame(
    id = c("one", "two"),
    sha256 = c(strrep("a", 64L), strrep("b", 64L)),
    stringsAsFactors = FALSE
)
matrix_rows <- data.frame(
    id = rep(matrix_inputs$id, each = 2L),
    writer = rep(c("dtaparser", "stata"), 2L),
    status = "ok",
    input_sha256 = rep(matrix_inputs$sha256, each = 2L),
    stringsAsFactors = FALSE
)
stopifnot(is.null(roundtrip_validate_benchmark_matrix(
    matrix_rows, matrix_inputs, c("dtaparser", "stata")
)))
incomplete_matrix <- tryCatch(
    roundtrip_validate_benchmark_matrix(
        matrix_rows[-1L, , drop = FALSE], matrix_inputs,
        c("dtaparser", "stata")
    ),
    error = identity
)
wrong_input <- matrix_rows
wrong_input$input_sha256[[1L]] <- strrep("c", 64L)
input_mismatch <- tryCatch(
    roundtrip_validate_benchmark_matrix(
        wrong_input, matrix_inputs, c("dtaparser", "stata")
    ),
    error = identity
)
stopifnot(
    inherits(incomplete_matrix, "error"),
    grepl("exact input-by-writer matrix", conditionMessage(incomplete_matrix),
          fixed = TRUE),
    inherits(input_mismatch, "error"),
    grepl("bound input identities", conditionMessage(input_mismatch),
          fixed = TRUE)
)

manifest <- file.path(root, "manifest.tsv")
write.table(inventory[c("corpus", "id", "sha256")], manifest, sep = "\t",
            row.names = FALSE, quote = TRUE)
stopifnot(grepl("^[0-9a-f]{64}$", benchmark_file_sha256(manifest)))

cached_inventory_path <- file.path(root, "cached-inventory.tsv")
write.table(
    inventory[c(
        "corpus", "id", "relative_path", "release", "bytes", "modified",
        "sha256"
    )],
    cached_inventory_path,
    sep = "\t",
    row.names = FALSE,
    quote = TRUE
)
ordinary <- file.path(root, "DHS", "ordinary.DTA")
ordinary_mtime <- file.info(ordinary)$mtime
ordinary_bytes <- readBin(ordinary, "raw", n = file.info(ordinary)$size)
ordinary_bytes[[length(ordinary_bytes)]] <- as.raw(
    bitwXor(as.integer(ordinary_bytes[[length(ordinary_bytes)]]), 1L)
)
writeBin(ordinary_bytes, ordinary)
Sys.setFileTime(ordinary, ordinary_mtime)
cached_error <- tryCatch(
    roundtrip_cached_inventory(root, cached_inventory_path),
    error = identity
)
stopifnot(
    inherits(cached_error, "error"),
    grepl("corpus files changed", conditionMessage(cached_error), fixed = TRUE)
)

rows <- file.path(root, "rows.tsv")
append_tsv(data.frame(id = "one", status = "pass"), rows)
append_tsv(data.frame(id = "two", status = "pass"), rows)
stopifnot(identical(read.delim(rows)$id, c("one", "two")))

if (identical(Sys.info()[["sysname"]], "Darwin")) {
    memory_output <- paste(
        "12345  maximum resident set size",
        "67890  peak memory footprint",
        sep = "\n"
    )
    expected_memory <- list(
        rss_bytes = 12345,
        footprint_bytes = 67890
    )
} else {
    memory_output <- "Maximum resident set size (kbytes): 12"
    expected_memory <- list(
        rss_bytes = 12 * 1024,
        footprint_bytes = NA_real_
    )
}
stopifnot(
    identical(parse_memory_metrics(memory_output), expected_memory),
    identical(parse_memory(memory_output), expected_memory$rss_bytes),
    identical(
        parse_memory_metrics(memory_output)$footprint_bytes,
        expected_memory$footprint_bytes
    )
)

harness_root <- file.path(root, "harness")
harness_suite <- file.path(harness_root, "suite")
dir.create(harness_suite, recursive = TRUE)
writeLines("shared", file.path(harness_root, "benchmark-common.R"))
writeLines("first", file.path(harness_suite, "run.R"))
writeLines("ignored", file.path(harness_suite, "notes.md"))
first_harness_hash <- benchmark_harness_sha256(harness_suite)
writeLines("second", file.path(harness_suite, "run.R"))
second_harness_hash <- benchmark_harness_sha256(harness_suite)
stopifnot(
    grepl("^[0-9a-f]{64}$", first_harness_hash),
    !identical(first_harness_hash, second_harness_hash)
)

package_tree <- file.path(root, "package-tree")
dir.create(file.path(package_tree, "nested"), recursive = TRUE)
writeLines("one", file.path(package_tree, "one"))
writeLines("two", file.path(package_tree, "nested", "two"))
stopifnot(
    identical(
        benchmark_directory_files(package_tree),
        c("nested/two", "one")
    ),
    grepl("^[0-9a-f]{64}$", benchmark_directory_sha256(package_tree))
)
r_executable <- file.path(root, "R")
stata_executable <- file.path(root, "stata")
writeLines("R runtime", r_executable)
writeLines("Stata runtime", stata_executable)
runtime_binding <- benchmark_runtime_binding(
    stata_executable,
    r_executable = r_executable,
    rscript_executable = r_executable,
    time_executable = r_executable,
    haven_package = package_tree,
    processx_package = package_tree
)
stopifnot(
    identical(
        names(runtime_binding),
        c(
            "r_version", "r_platform", "r_executable_sha256",
            "rscript_executable_sha256", "time_executable_sha256",
            "haven_sha256", "processx_sha256", "stata_sha256"
        )
    ),
    all(grepl(
        "^[0-9a-f]{64}$",
        unlist(runtime_binding[c(
            "r_executable_sha256", "rscript_executable_sha256",
            "time_executable_sha256", "haven_sha256",
            "processx_sha256", "stata_sha256"
        )], use.names = FALSE)
    ))
)
unlink(root, recursive = TRUE, force = TRUE)
cat("R corpus round-trip framework: PASS\n")
