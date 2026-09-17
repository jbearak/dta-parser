args <- commandArgs(trailingOnly = TRUE)
update_baseline <- "--update-baseline" %in% args
args <- setdiff(args, "--update-baseline")
if (length(args) < 3L || length(args) > 4L ||
    !(args[[1L]] %in% c("record", "compare"))) {
    stop(paste0(
        "usage: mutation-gate.R record|compare CACHE_ROOT OUTPUT_DIR ",
        "[MAX_FILES] [--update-baseline]"
    ))
}
if (!requireNamespace("processx", quietly = TRUE)) stop("processx is required")

mode <- args[[1L]]
cache_root <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
output_dir <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)
max_files <- if (length(args) == 4L) as.integer(args[[4L]]) else Inf
if (length(max_files) != 1L || is.na(max_files) || max_files < 1L) {
    stop("MAX_FILES must be a positive integer")
}
if (update_baseline && !identical(mode, "record")) {
    stop("--update-baseline applies to record mode only")
}
script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument), winslash = "/"))
source(file.path(script_dir, "common.R"), local = TRUE)

benchmark_library <- benchmark_library_path()
installed_package <- benchmark_installed_package_path(benchmark_library)
rscript <- normalizePath(Sys.which("Rscript"), winslash = "/", mustWork = TRUE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# MAX_FILES keeps the smallest files of each corpus: a signature gate needs
# every verb's code path, not the corpus' largest inputs, and a smoke pass
# should finish in minutes. Selection happens before hashing so a smoke pass
# does not hash the whole corpus.
select_smallest <- function(files, max_files) {
    if (!is.finite(max_files)) return(files)
    kept <- lapply(roundtrip_corpora, function(corpus) {
        items <- files[files$corpus == corpus & files$bytes > 0, , drop = FALSE]
        items <- roundtrip_order_smallest(items)
        items[seq_len(min(max_files, nrow(items))), , drop = FALSE]
    })
    result <- do.call(rbind, kept)
    rownames(result) <- NULL
    result
}
files <- select_smallest(roundtrip_inventory_files(cache_root), max_files)
sha256 <- benchmark_files_sha256(files$path, progress = !is.finite(max_files))
inventory <- data.frame(
    corpus = files$corpus,
    id = mapply(
        roundtrip_stable_id, files$corpus, files$relative_path, sha256,
        USE.NAMES = FALSE
    ),
    relative_path = files$relative_path,
    path = files$path,
    bytes = files$bytes,
    sha256 = sha256,
    stringsAsFactors = FALSE
)
if (anyDuplicated(inventory$id)) stop("stable corpus ID collision")

baseline_path <- file.path(script_dir, "mutation-gate-baseline.tsv")
baseline_columns <- c("id", "verb", "container", "datasig")
read_baseline <- function() {
    if (!file.exists(baseline_path)) {
        return(stats::setNames(
            data.frame(character(), character(), character(), character(),
                       stringsAsFactors = FALSE),
            baseline_columns
        ))
    }
    baseline <- read.delim(
        baseline_path, colClasses = "character", check.names = FALSE,
        na.strings = character(), quote = ""
    )
    if (!identical(names(baseline), baseline_columns)) {
        stop("mutation gate baseline has unexpected columns")
    }
    baseline
}


baseline <- read_baseline()
if (!(identical(mode, "record") && update_baseline)) {
    # Fail before any worker runs when the baseline cannot cover the
    # selection; a full-corpus compare against a smoke baseline would
    # otherwise sign every file and fail only at the end.
    missing_ids <- setdiff(inventory$id, baseline$id)
    if (length(missing_ids)) {
        stop(
            length(missing_ids), " of ", nrow(inventory),
            " selected datasets have no baseline rows; run ",
            "`record --update-baseline` on the reference build with the ",
            "same MAX_FILES first"
        )
    }
}
message(nrow(inventory), " corpus files selected")

worker_script <- file.path(script_dir, "mutation-gate-worker.R")
run_worker <- function(item) {
    process <- processx::run(
        rscript, c("--vanilla", worker_script, item$path),
        env = c(
            "current",
            DTATOOLS_BENCH_LIB = benchmark_library,
            R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null"
        ),
        error_on_status = FALSE, echo = FALSE
    )
    lines <- strsplit(process$stdout, "\n", fixed = TRUE)[[1L]]
    markers <- grep("^DTATOOLS_MUTATION_GATE\t", lines, value = TRUE)
    fields <- strsplit(markers, "\t", fixed = TRUE)
    rows <- data.frame(
        id = rep(item$id, length(fields)),
        verb = vapply(fields, `[[`, character(1L), 2L),
        container = vapply(fields, `[[`, character(1L), 3L),
        datasig = vapply(fields, `[[`, character(1L), 4L),
        stringsAsFactors = FALSE
    )
    if (process$status != 0L) {
        rows <- rbind(rows, data.frame(
            id = item$id, verb = "worker", container = "process",
            datasig = "worker-error", stringsAsFactors = FALSE
        ))
        writeLines(process$stderr, file.path(
            output_dir, paste0(item$id, ".stderr")
        ), useBytes = TRUE)
    }
    rows
}

signature_one <- function(index) {
    item <- inventory[index, , drop = FALSE]
    exclusion <- roundtrip_exclusion_reason(item)
    if (!is.na(exclusion)) {
        return(data.frame(
            id = item$id, verb = "dataset", container = "source",
            datasig = paste0("expected-exclusion:", exclusion),
            stringsAsFactors = FALSE
        ))
    }
    tryCatch(run_worker(item), error = function(condition) {
        data.frame(
            id = item$id, verb = "worker", container = "process",
            datasig = paste0("orchestrator-error: ", conditionMessage(condition)),
            stringsAsFactors = FALSE
        )
    })
}

# mclapply() forks, which Windows R does not support; there each wave runs
# its workers one after another.
fork_available <- !identical(.Platform$OS.type, "windows")
limits <- roundtrip_verification_limits()
waves <- roundtrip_verification_waves(
    inventory$bytes, limits$jobs, limits$memory_bytes
)
message(
    "schedule: ", length(waves), " size-aware waves, up to ", limits$jobs,
    " processes"
)
rows <- vector("list", nrow(inventory))
completed <- 0L
partial_path <- file.path(output_dir, "signatures.partial.tsv")
for (wave_number in seq_along(waves)) {
    indices <- waves[[wave_number]]
    wave_rows <- if (length(indices) == 1L || !fork_available) {
        lapply(indices, signature_one)
    } else {
        parallel::mclapply(
            indices, signature_one, mc.cores = length(indices),
            mc.preschedule = FALSE, mc.set.seed = FALSE
        )
    }
    wave_rows <- Map(function(row, index) {
        if (inherits(row, "try-error") || !is.data.frame(row)) {
            return(data.frame(
                id = inventory$id[[index]], verb = "worker",
                container = "process", datasig = "dataset-process-error",
                stringsAsFactors = FALSE
            ))
        }
        row
    }, wave_rows, indices)
    rows[indices] <- wave_rows
    checkpoint <- do.call(rbind, rows[seq_len(max(indices))])
    rownames(checkpoint) <- NULL
    atomic_tsv(checkpoint, partial_path)
    completed <- completed + length(indices)
    message(completed, "/", nrow(inventory), " datasets signed")
}
observed <- do.call(rbind, rows)
rownames(observed) <- NULL
observed <- observed[order(observed$id, observed$verb, observed$container,
                           method = "radix"), , drop = FALSE]
atomic_tsv(observed, file.path(output_dir, "signatures.tsv"))
unlink(partial_path)

errors <- observed[observed$verb == "worker", , drop = FALSE]
if (nrow(errors)) {
    message(nrow(errors), " datasets failed in the worker:")
    message(paste0("  ", errors$id, ": ", errors$datasig, collapse = "\n"))
    stop("mutation gate worker failures; see *.stderr in ", output_dir)
}

if (identical(mode, "record") && update_baseline) {
    kept <- baseline[!(baseline$id %in% observed$id), , drop = FALSE]
    merged <- rbind(kept, observed)
    merged <- merged[order(merged$id, merged$verb, merged$container,
                           method = "radix"), , drop = FALSE]
    rownames(merged) <- NULL
    atomic_tsv(merged, baseline_path)
    message(
        "baseline updated: ", nrow(observed), " rows for ",
        length(unique(observed$id)), " datasets written to ", baseline_path
    )
    quit(status = 0L)
}

differences_path <- file.path(output_dir, "differences.tsv")
unlink(differences_path)
key <- function(table) paste(table$id, table$verb, table$container, sep = "\t")
expected <- baseline[baseline$id %in% inventory$id, , drop = FALSE]
expected_lookup <- stats::setNames(expected$datasig, key(expected))
observed_lookup <- stats::setNames(observed$datasig, key(observed))
all_keys <- sort(union(names(expected_lookup), names(observed_lookup)))
differences <- all_keys[
    is.na(expected_lookup[all_keys]) | is.na(observed_lookup[all_keys]) |
        expected_lookup[all_keys] != observed_lookup[all_keys]
]
if (length(differences)) {
    parts <- do.call(rbind, strsplit(differences, "\t", fixed = TRUE))
    report <- data.frame(
        id = parts[, 1L], verb = parts[, 2L], container = parts[, 3L],
        baseline = unname(expected_lookup[differences]),
        observed = unname(observed_lookup[differences]),
        stringsAsFactors = FALSE
    )
    atomic_tsv(report, differences_path)
    message(nrow(report), " signature differences; first rows:")
    message(paste(utils::capture.output(print(utils::head(report, 20L))),
                  collapse = "\n"))
    stop("mutation gate: data signatures differ from the baseline")
}
message(
    "mutation gate clean: ", nrow(observed), " signatures over ",
    length(unique(observed$id)), " datasets match the baseline"
)
