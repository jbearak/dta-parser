# Original metadata-only inventory block from 9a4ec764, run.R. No readers run.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: recover-matched-inventory.R CACHE_ROOT NEW_OUTPUT_DIR")
cache_root <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
output_dir <- args[[2L]]
if (file.exists(output_dir) || dir.exists(output_dir)) stop("output directory must be new")
max_files <- Inf

walk_dta <- function(directory) {
    entries <- list.files(
        directory, all.files = TRUE, full.names = TRUE,
        no.. = TRUE, recursive = FALSE
    )
    result <- character()
    for (path in entries) {
        if (nzchar(Sys.readlink(path))) next
        info <- file.info(path, extra_cols = FALSE)
        if (is.na(info$isdir)) stop(sprintf("cannot inspect %s", path))
        if (isTRUE(info$isdir)) {
            result <- c(result, walk_dta(path))
        } else if (grepl("[.]dta$", basename(path), ignore.case = TRUE)) {
            result <- c(result, normalizePath(path, winslash = "/"))
        }
    }
    result
}

corpus_names <- c("DHS", "MICS", "NSFG")
corpus_roots <- setNames(file.path(cache_root, corpus_names), corpus_names)
if (!all(dir.exists(corpus_roots))) {
    stop("CACHE_ROOT must contain DHS, MICS, and NSFG directories")
}
inventory_rows <- lapply(names(corpus_roots), function(corpus) {
    paths <- walk_dta(corpus_roots[[corpus]])
    relative_paths <- substring(paths, nchar(cache_root, type = "chars") + 2L)
    info <- file.info(paths, extra_cols = TRUE)
    order_index <- order(relative_paths, method = "radix")
    paths <- paths[order_index]
    relative_paths <- relative_paths[order_index]
    info <- info[order_index, , drop = FALSE]
    data.frame(
        corpus = corpus,
        id = sprintf("%s-%04d", corpus, seq_along(paths)),
        relative_path = relative_paths,
        path = paths,
        bytes = as.double(info$size),
        mtime = as.numeric(info$mtime),
        stringsAsFactors = FALSE
    )
})
inventory <- do.call(rbind, inventory_rows)

# Largest inputs are visited first. Alternating reader order then distributes
# first-reader cache effects across the files that dominate aggregate time.
inventory <- inventory[order(-inventory$bytes, inventory$relative_path, method = "radix"), ]
inventory <- do.call(rbind, lapply(split(inventory, inventory$corpus), function(items) {
    if (is.finite(max_files)) head(items, max_files) else items
}))
rownames(inventory) <- NULL
if (anyDuplicated(inventory$id)) stop("inventory ID collision")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
raw_path <- file.path(output_dir, "raw.tsv")
inventory_path <- file.path(output_dir, "inventory.tsv")
write.table(
    inventory[c("corpus", "id", "relative_path", "bytes", "mtime")],
    inventory_path, sep = "\t", row.names = FALSE, quote = TRUE
)
