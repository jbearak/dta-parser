#!/usr/bin/env Rscript

script <- grep("^--file=", commandArgs(FALSE), value = TRUE)
dir <- dirname(normalizePath(sub("^--file=", "", script[[1L]]), winslash = "/"))
source(file.path(dir, "common.R"))
source(file.path(dir, "compare.R"))
source(file.path(dir, "stata.R"))
source(file.path(dir, "worker.R"))

root <- tempfile("aww-inventory-")
dir.create(file.path(root, "nested"), recursive = TRUE)
fixture <- normalizePath(file.path(dir, "..", "..", "r-package", "dtaparser", "inst", "extdata", "all_types_v118.dta"))
invisible(file.copy(fixture, file.path(root, "nested", "included.DTA")))
invisible(file.copy(fixture, file.path(root, "ignored.dta.gz")))
invisible(file.symlink(file.path(root, "nested"), file.path(root, "linked-directory")))
invisible(file.symlink(file.path(root, "nested", "included.DTA"), file.path(root, "linked.dta")))
fifo <- file.path(root, "named-pipe.dta")
if (nzchar(Sys.which("mkfifo"))) system2("mkfifo", fifo)
inventory <- aww_inventory(root)
stopifnot(nrow(inventory) == 1L)
stopifnot(identical(inventory$relative_path, "nested/included.DTA"))
stopifnot(identical(inventory$release, 118L))
stopifnot(identical(inventory$id, aww_file_id("nested/included.DTA")))

root_link <- tempfile("aww-root-link-")
invisible(file.symlink(root, root_link))
root_error <- tryCatch(aww_parse_arguments(paste0("--root=", root_link)), error = identity)
stopifnot(inherits(root_error, "aww_error"), grepl("symlink", root_error$message))
unlink(root_link)

unreadable <- file.path(root, "unreadable")
dir.create(unreadable)
Sys.chmod(unreadable, "0000")
if (file.access(unreadable, 4L) != 0L) {
    traversal_error <- tryCatch(aww_inventory(root), error = identity)
    stopifnot(inherits(traversal_error, "aww_error"))
}
Sys.chmod(unreadable, "0700")
unlink(unreadable, recursive = TRUE)

selection_options <- list(ids = "Dunknown", max_files = Inf)
selection_error <- tryCatch(aww_select_inventory(inventory, selection_options), error = identity)
stopifnot(inherits(selection_error, "aww_error"), grepl("unknown --id", selection_error$message))

left <- data.frame(x = c(1, haven::tagged_na("a"), 3), check.names = FALSE)
right <- left
attr(left$x, "label") <- "value"
attr(right$x, "label") <- "value"
stopifnot(nrow(aww_compare_metadata(left[0, , drop = FALSE], right[0, , drop = FALSE])) == 0L)
stopifnot(nrow(aww_compare_values(left, right, 0L, 0, storage = "long")) == 0L)
right$x[[2L]] <- haven::tagged_na("b")
disputes <- aww_compare_values(left, right, 0L, 0, storage = "long")
stopifnot(nrow(disputes) == 1L)
stopifnot(disputes$category[[1L]] == "missing", disputes$row[[1L]] == 2)
right <- left
right$x[[3L]] <- 3 + 5e-8
stopifnot(nrow(aww_compare_values(left, right, 0L, 0, storage = "long")) == 1L)
stopifnot(nrow(aww_compare_values(left, right, 0L, 0, storage = "float")) == 0L)
right$x[[3L]] <- 3 + 2e-7
stopifnot(nrow(aww_compare_values(left, right, 0L, 0, storage = "float")) == 1L)

kind_vectors <- list(
    c(0, -0, 1, NA_real_, NaN, Inf, -Inf, haven::tagged_na("a")),
    c(1L, NA_integer_),
    c("", "value", NA_character_),
    as.Date(c("1960-01-01", NA_character_))
)
for (values in kind_vectors) {
    scalar_kinds <- vapply(seq_along(values), function(index) {
        aww_cell_kind(values[index])
    }, character(1))
    stopifnot(identical(aww_cell_kinds(values), scalar_kinds))
}

for (count in c(0L, 1L, 2L, 73L, 1000L)) {
    counted <- aww_count_columns(function(index) index <= count)
    stopifnot(is.null(counted$error), identical(counted$count, count))
}
probe_error <- simpleError("reader failed")
counted_error <- aww_count_columns(function(index) probe_error)
stopifnot(identical(counted_error$error, probe_error), is.na(counted_error$count))

parent_tile <- list(skip = 0, n_max = 100L, column_start = 1L, column_count = 2L)
column_leaves <- list(
    list(tile = list(skip = 0, n_max = 100L, column_start = 1L, column_count = 1L),
         reader_rows = c(dtaparser = 75, haven = 75)),
    list(tile = list(skip = 0, n_max = 100L, column_start = 2L, column_count = 1L),
         reader_rows = c(dtaparser = 75, haven = 75))
)
column_coverage <- aww_leaf_reader_rows(column_leaves, parent_tile, "dtaparser")
stopifnot(column_coverage$rows == 75, column_coverage$consistent)
row_leaves <- list(
    list(tile = list(skip = 0, n_max = 50L, column_start = 1L, column_count = 2L),
         reader_rows = c(dtaparser = 50, haven = 50)),
    list(tile = list(skip = 50, n_max = 50L, column_start = 1L, column_count = 2L),
         reader_rows = c(dtaparser = 25, haven = 25))
)
row_coverage <- aww_leaf_reader_rows(row_leaves, parent_tile, "dtaparser")
stopifnot(row_coverage$rows == 75, row_coverage$consistent)
early_eof_leaves <- row_leaves
early_eof_leaves[[1L]]$reader_rows[] <- 25
early_eof_leaves[[2L]]$reader_rows[] <- 0
early_eof <- aww_leaf_reader_rows(early_eof_leaves, parent_tile, "dtaparser")
stopifnot(early_eof$rows == 25, early_eof$consistent)
inconsistent_leaves <- column_leaves
inconsistent_leaves[[2L]]$reader_rows[["dtaparser"]] <- 70
inconsistent <- aww_leaf_reader_rows(inconsistent_leaves, parent_tile, "dtaparser")
stopifnot(inconsistent$rows == 75, !inconsistent$consistent)

terminated <- c(dtaparser = NA_real_, haven = NA_real_)
first_end <- aww_update_terminations(
    terminated, c(dtaparser = 0, haven = 25), requested = 25L, skip = 100
)
stopifnot(identical(first_end$counts, c(dtaparser = 100, haven = NA_real_)))
second_end <- aww_update_terminations(
    first_end$counts, c(dtaparser = 0, haven = 10), requested = 25L, skip = 125
)
stopifnot(identical(second_end$counts, c(dtaparser = 100, haven = 135)))
stopifnot(identical(second_end$newly_terminated, c(dtaparser = FALSE, haven = TRUE)))
stopifnot(identical(
    aww_beyond_row_ceiling(first_end$counts, skip = 125, ceiling = 100),
    "haven"
))
stopifnot(length(aww_beyond_row_ceiling(
    first_end$counts, skip = 75, ceiling = 100
)) == 0L)
stopifnot(!identical(
    aww_tile_id("value", 1L, 0, 10L, 1L, 1L),
    aww_tile_id("value", 1L, 0, 10L, 2L, 1L)
))

labels <- c(Domestic = 0, Foreign = 1)
canonical <- aww_canonical_labels(labels)
stopifnot(length(canonical) == 2L, canonical[[2L]]$text == "Foreign")

metadata_disputes <- do.call(rbind, replicate(
    2001L, aww_dispute("metadata", "label", column = 1L, attribute = "label"),
    simplify = FALSE
))
cell_disputes <- do.call(rbind, lapply(c(1:80, 1001:1080), function(row) {
    aww_dispute("cell", "value", column = 1L, row = row,
                dtaparser = list(kind = "value", value = row),
                haven = list(kind = "value", value = row + 1))
}))
batch_disputes <- aww_bind_disputes(list(metadata_disputes, cell_disputes))
batches <- aww_stata_batches(batch_disputes, maximum_requests = 1000L, maximum_rows = 25L)
stopifnot(all(lengths(batches) <= 1000L))
stopifnot(identical(sort(unlist(batches)), seq_len(nrow(batch_disputes))))
for (indices in batches) {
    rows <- batch_disputes$row[indices][batch_disputes$kind[indices] == "cell"]
    if (length(rows)) stopifnot(max(rows) - min(rows) < 25L)
}

dimension_dispute <- aww_dispute(
    "metadata", "dimension", row = 91, skip = 90, n_max = 25L,
    attribute = "tile-nrow", dtaparser = 10, haven = 9
)
stopifnot(aww_matches_stata(10, 100, dimension_dispute,
                            list(formats = character(), storage = character())))
stopifnot(!aww_matches_stata(9, 100, dimension_dispute,
                             list(formats = character(), storage = character())))

empty_label_class <- aww_dispute(
    "metadata", "class", column = 1L, attribute = "class",
    dtaparser = c("haven_labelled", "vctrs_vctr", "double"), haven = NULL
)
stopifnot(identical(aww_stata_kind(empty_label_class), "value_label_name"))
stopifnot(aww_matches_stata(
    empty_label_class$dtaparser[[1L]], "labels111", empty_label_class,
    list(formats = "%6.3f", storage = "float")
))
stopifnot(!aww_matches_stata(
    empty_label_class$haven[[1L]], "labels111", empty_label_class,
    list(formats = "%6.3f", storage = "float")
))

changed_item <- list(path = fixture, sha256 = paste(rep("0", 64L), collapse = ""))
changed <- aww_adjudicate(
    aww_dispute("metadata", "dimension", attribute = "ncol", dtaparser = 1, haven = 2),
    list(columns = 1L, formats = "", storage = "long"), changed_item,
    list(stata = "", timeout = 1L, stata_requests = 10L, stata_row_window = 10L),
    tempfile("aww-changed-"), dir
)
stopifnot(identical(changed$state, "input-changed"))

fake_dir <- tempfile("aww-fake-stata-")
dir.create(fake_dir)
fake_stata <- file.path(fake_dir, "stata")
writeLines(c("#!/bin/sh", "printf '17.0\\n' > stata-version.txt", "exit 0"), fake_stata)
Sys.chmod(fake_stata, "0700")
fake_run <- file.path(fake_dir, "run")
dir.create(fake_run)
fake_info <- aww_stata_info(
    list(stata = fake_stata, timeout = 10L), fake_run, dir
)
stopifnot(identical(fake_info$state, "stata-unsupported-version"))

probe_item <- list(id = "Dprobe", path = fixture, sha256 = aww_file_sha256(fixture))
probe_options <- list(timeout = 10L)
probe_info <- list(state = "available", path = fake_stata)
stopifnot(identical(
    aww_stata_open(probe_item, probe_options, fake_run, dir, probe_info),
    "stata-source-error"
))
writeLines(c("#!/bin/sh", "printf 'ok\\n' > open-ok.txt", "exit 0"), fake_stata)
Sys.chmod(fake_stata, "0700")
stopifnot(identical(
    aww_stata_open(probe_item, probe_options, fake_run, dir, probe_info), "open"
))

stata_setting <- Sys.getenv("DTAPARSER_TEST_STATA", unset = "")
stata <- if (nzchar(stata_setting)) aww_resolve_stata(stata_setting) else NA_character_
if (!is.na(stata)) {
    work <- tempfile("aww-stata-")
    dir.create(work)
    make <- file.path(work, "make.do")
    writeLines(c(
        "version 18", "set more off", "sysuse auto, clear", "note: hello",
        "save source.dta, replace", "exit, clear"
    ), make)
    processx::run(stata, c("-q", "-b", "do", "make.do"), wd = work,
                  timeout = 120000, error_on_status = TRUE)
    source_path <- file.path(work, "source.dta")
    disputes <- aww_bind_disputes(list(
        aww_dispute(
            "cell", "value", column = 2L, row = 1,
            dtaparser = list(kind = "value", value = 4099),
            haven = list(kind = "value", value = 4000)
        ),
        aww_dispute(
            "metadata", "label", column = 12L, attribute = "labels:2",
            dtaparser = list(code = "1", text = "Foreign"),
            haven = list(code = "1", text = "Wrong")
        ),
        aww_dispute(
            "metadata", "label", attribute = "notes:2",
            dtaparser = "hello", haven = "wrong"
        )
    ))
    stata_options <- list(
        stata = stata, timeout = 120L, stata_requests = 1000L,
        stata_row_window = 25000L
    )
    stata_metadata <- list(
        columns = 12L, formats = rep("%8.0g", 12L), storage = rep("int", 12L)
    )
    stata_item <- list(
        id = "Dtest", path = source_path, sha256 = aww_file_sha256(source_path)
    )
    stata_info <- aww_stata_info(stata_options, work, dir)
    row_probe <- aww_stata_row_count(
        stata_item, stata_metadata, stata_options, work, dir, stata_info, 1L
    )
    stopifnot(identical(row_probe$state, "complete"), row_probe$rows == 74)
    result <- aww_adjudicate(
        disputes, stata_metadata, stata_item, stata_options, work, dir, stata_info
    )
    stopifnot(identical(result$state, "complete"))
    stopifnot(identical(result$ownership, rep("haven-wrong", 3L)))

    malformed_source <- file.path(work, "malformed.dta")
    malformed <- readBin(fixture, "raw", file.info(fixture)$size)
    source_label <- "All Stata storage types"
    needle <- charToRaw(source_label)
    starts <- which(vapply(seq_len(length(malformed) - length(needle) + 1L), function(index) {
        identical(malformed[index:(index + length(needle) - 1L)], needle)
    }, logical(1)))
    stopifnot(length(starts) >= 1L)
    malformed[[starts[[1L]]]] <- as.raw(0xff)
    writeBin(malformed, malformed_source)
    malformed_dispute <- aww_dispute(
        "metadata", "label", attribute = "label",
        dtaparser = paste0("\ufffd", substring(source_label, 2L)),
        haven = "wrong"
    )
    malformed_item <- list(
        id = "Dmalformed", path = malformed_source,
        sha256 = aww_file_sha256(malformed_source)
    )
    malformed_result <- aww_adjudicate(
        malformed_dispute,
        list(columns = 8L, formats = rep("%8.0g", 8L), storage = rep("long", 8L)),
        malformed_item, stata_options, work, dir, stata_info
    )
    stopifnot(identical(malformed_result$state, "complete"))
    stopifnot(identical(malformed_result$ownership, "haven-wrong"))
}

unlink(root, recursive = TRUE)
unlink(fake_dir, recursive = TRUE)
cat("aww-cache-differential framework tests: PASS\n")
