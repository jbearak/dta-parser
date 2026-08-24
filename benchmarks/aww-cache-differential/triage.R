#!/usr/bin/env Rscript

Sys.umask("0077")

arguments <- commandArgs(TRUE)
run_argument <- grep("^--run=", arguments, value = TRUE)
if (length(run_argument) != 1L || length(arguments) != 1L) {
    stop("usage: triage.R --run=/absolute/or/relative/run-directory", call. = FALSE)
}
run_dir <- normalizePath(sub("^--run=", "", run_argument), winslash = "/", mustWork = TRUE)
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument[[1L]]),
                                    winslash = "/", mustWork = TRUE))

old_source_only <- Sys.getenv("AWW_SOURCE_ONLY", unset = NA_character_)
Sys.setenv(AWW_SOURCE_ONLY = "1")
source(file.path(script_dir, "run.R"), local = globalenv())
if (is.na(old_source_only)) Sys.unsetenv("AWW_SOURCE_ONLY") else
    Sys.setenv(AWW_SOURCE_ONLY = old_source_only)

inventory <- readRDS(file.path(run_dir, "inventory.rds"))
summary <- read.delim(file.path(run_dir, "results.tsv"), check.names = FALSE)
config_path <- file.path(run_dir, "config.rds")
options <- if (file.exists(config_path)) {
    readRDS(config_path)$options
} else {
    aww_parse_arguments(character())
}
options$retry <- FALSE
config_id <- basename(run_dir)

# Old runs did not persist final per-file results. Seed Stata's version cache
# from their immutable adjudication checkpoint so reconstruction does not run
# a new version probe.
stata_files <- list.files(file.path(run_dir, "checkpoints"),
                          pattern = "^stata-.*[.]rds$", recursive = TRUE,
                          full.names = TRUE)
if (length(stata_files)) {
    sample <- readRDS(stata_files[[1L]])
    stata <- aww_resolve_stata(options$stata)
    if (!is.na(stata)) {
        info <- file.info(stata, extra_cols = FALSE)
        executable_id <- aww_sha256_raw(paste(
            stata, info$size, as.numeric(info$mtime), sep = "\037"
        ))
        version <- sub("^[^:]+:([^:]+):.*$", "\\1", sample$stata_id)
        assign(executable_id, list(
            state = "available", path = stata, version = version,
            id = sample$stata_id
        ), envir = .aww_stata_cache)
    }
}

read_final <- function(item) {
    path <- file.path(run_dir, "checkpoints", item$id, "file-result.rds")
    saved <- aww_read_result(path)
    if (!is.null(saved) && identical(saved$config_id, config_id) &&
        identical(saved$file_sha256, item$sha256)) return(saved$result)
    aww_file(item, options, "", "", run_dir, config_id)
}

response_map <- function(item, result) {
    mapped <- vector("list", nrow(result$disputes))
    if (!nrow(result$disputes)) return(mapped)
    path <- file.path(
        run_dir, "checkpoints", item$id,
        paste0("stata-", aww_dispute_id(item$sha256, result$disputes), ".rds")
    )
    saved <- aww_read_result(path)
    if (is.null(saved) || is.null(saved$result$responses)) return(mapped)
    batches <- aww_stata_batches(
        result$disputes, options$stata_requests, options$stata_row_window
    )
    for (batch_index in seq_along(batches)) {
        response <- saved$result$responses[[batch_index]]
        indices <- batches[[batch_index]]
        for (local_index in seq_along(indices)) {
            mapped[[indices[[local_index]]]] <- response[
                response$id == local_index, , drop = FALSE
            ]
        }
    }
    mapped
}

object_hex <- function(value) {
    paste(format(serialize(value, NULL, version = 3L)), collapse = "")
}
object_text <- function(value) {
    paste(capture.output(dput(value, control = c("keepNA", "keepInteger"))),
          collapse = " ")
}

selected <- summary[summary$disputes > 0L, , drop = FALSE]
parts <- vector("list", nrow(selected))
for (file_index in seq_len(nrow(selected))) {
    item <- as.list(inventory[inventory$id == selected$id[[file_index]], , drop = FALSE])
    result <- read_final(item)
    if (!nrow(result$disputes)) next
    responses <- response_map(item, result)
    disputes <- result$disputes
    disputes$file_id <- item$id
    disputes$relative_path <- item$relative_path
    disputes$release <- item$release
    disputes$dispute_index <- seq_len(nrow(disputes))
    disputes$owner <- result$ownership
    disputes$stata <- I(responses)
    parts[[file_index]] <- disputes[, c(
        "file_id", "relative_path", "release", "dispute_index", "kind",
        "category", "reader", "column", "row", "skip", "n_max",
        "attribute", "dtaparser", "haven", "stata", "owner"
    )]
}
parts <- parts[vapply(parts, Negate(is.null), logical(1))]
triage <- if (length(parts)) do.call(rbind, parts) else data.frame()
rownames(triage) <- NULL
triage_rds <- file.path(run_dir, "triage.rds")
aww_atomic_save_rds(triage, triage_rds)
Sys.chmod(triage_rds, "0600")

view <- triage
if (nrow(view)) {
    view$dtaparser_text <- vapply(view$dtaparser, object_text, character(1))
    view$haven_text <- vapply(view$haven, object_text, character(1))
    view$stata_text <- vapply(view$stata, object_text, character(1))
    view$dtaparser_rds_hex <- vapply(view$dtaparser, object_hex, character(1))
    view$haven_rds_hex <- vapply(view$haven, object_hex, character(1))
    view$stata_rds_hex <- vapply(view$stata, object_hex, character(1))
    view$dtaparser <- view$haven <- view$stata <- NULL
}
triage_tsv <- file.path(run_dir, "triage.tsv")
write.table(view, triage_tsv, sep = "\t", quote = TRUE,
            row.names = FALSE, na = "")
Sys.chmod(triage_tsv, "0600")
cat(sprintf("triage: %d disputes across %d files\n", nrow(triage),
            length(unique(triage$file_id))))
