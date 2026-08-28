args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L || !args[[1L]] %in% c("quick", "full", "india", "all")) {
    stop("usage: run.R quick|full|india|all REPETITIONS OUTPUT_DIR")
}
profile <- args[[1L]]
repetitions <- as.integer(args[[2L]])
output_dir <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)
if (is.na(repetitions) || repetitions < 1L) stop("REPETITIONS must be positive")
if (!requireNamespace("processx", quietly = TRUE)) stop("processx is required")

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument), winslash = "/"))
sys.source(file.path(script_dir, "..", "benchmark-common.R"), envir = environment())
benchmark_library <- benchmark_library_path()
benchmark_activate_library("dtaparser", benchmark_library = benchmark_library)
stata <- find_stata()
rscript <- Sys.which("Rscript")

synthetic_cases <- if (profile == "quick") {
    data.frame(
        case = c("tall", "wide"), rows = c(100000, 25000),
        columns = c(100, 500), source = "synthetic"
    )
} else if (profile %in% c("full", "all")) {
    data.frame(
        case = c("tall", "wide", "tall-wide"),
        rows = c(500000, 50000, 250000), columns = c(100, 1000, 500),
        source = "synthetic"
    )
} else NULL
real_cases <- if (profile %in% c("india", "all")) {
    data.frame(
        case = "india-2021-wm", rows = NA_real_, columns = NA_real_,
        source = "india-2021-wm"
    )
} else NULL
cases <- rbind(synthetic_cases, real_cases)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

raw_rows <- list()
fixtures <- list()
for (index in seq_len(nrow(cases))) {
    item <- cases[index, ]
    case_dir <- file.path(output_dir, item$case)
    dir.create(case_dir, recursive = TRUE, showWarnings = FALSE)
    input <- file.path(case_dir, "input.dta")
    if (item$source == "synthetic") {
        generation_result <- file.path(case_dir, "generation.tsv")
        generated <- processx::run(
            stata,
            c("-q", "-b", "do", file.path(script_dir, "generate.do"), input,
              as.character(item$rows), as.character(item$columns), generation_result),
            wd = case_dir, error_on_status = FALSE, echo = FALSE
        )
        if (generated$status != 0L || !file.exists(generation_result) || !file.exists(input)) {
            stop("fixture generation failed for ", item$case, ": ", generated$stderr)
        }
        generation <- scan(generation_result, what = character(), sep = "\t", quiet = TRUE)
        if (length(generation) != 4L || generation[[1L]] != "ok") {
            stop("invalid generation result for ", item$case)
        }
        item$bytes <- as.numeric(generation[[4L]])
        present <- sprintf("v%05d", seq_len(10L))
        union <- c(present, sprintf("absent%05d", seq_len(90L)))
    } else {
        private_input <- Sys.getenv(
            "INDIA_2021_WM",
            unset = "/opt/aww_cache/DHS/Original_Data/India 2021/wm.dta"
        )
        private_input <- normalizePath(private_input, winslash = "/", mustWork = TRUE)
        if (!file.symlink(private_input, input)) {
            stop("could not create a private India fixture alias")
        }
        metadata_names <- dtaparser:::.dta_metadata(input)
        if (length(metadata_names) < 100L) stop("India fixture has fewer than 100 columns")
        indices <- unique(as.integer(round(seq(1, length(metadata_names), length.out = 100L))))
        if (length(indices) != 100L) stop("could not choose 100 distinct India columns")
        present <- as.character(metadata_names[indices])
        absent <- sprintf("_dtaparser_absent_%05d", seq_len(100L))
        if (any(absent %in% metadata_names)) stop("absent-name sentinel exists in India fixture")
        union <- c(present, absent)
        item$columns <- length(metadata_names)
        item$bytes <- as.numeric(file.info(private_input, extra_cols = FALSE)$size)
    }
    present_path <- file.path(case_dir, "present.txt")
    union_path <- file.path(case_dir, "union.txt")
    writeLines(paste(present, collapse = " "), present_path)
    writeLines(paste(union, collapse = " "), union_path)

    r_output <- file.path(case_dir, "r.tsv")
    r_run <- processx::run(
        rscript,
        c("--vanilla", file.path(script_dir, "r-worker.R"), input,
          present_path, union_path, as.character(repetitions), r_output),
        env = c(
            DTAPARSER_BENCH_LIB = benchmark_library,
            R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null"
        ),
        error_on_status = FALSE, echo = FALSE
    )
    if (r_run$status != 0L || !file.exists(r_output)) {
        stop("R worker failed for ", item$case, ": ", r_run$stderr)
    }
    r_raw <- read.delim(
        r_output, header = FALSE,
        col.names = c("method", "iteration", "elapsed_seconds", "rows", "columns")
    )

    stata_output <- file.path(case_dir, "stata.tsv")
    stata_run <- processx::run(
        stata,
        c("-q", "-b", "do", file.path(script_dir, "stata-worker.do"), input,
          present_path, union_path, as.character(repetitions), stata_output),
        wd = case_dir, error_on_status = FALSE, echo = FALSE
    )
    if (stata_run$status != 0L || !file.exists(stata_output)) {
        stop("Stata worker failed for ", item$case, ": ", stata_run$stderr)
    }
    stata_raw <- read.delim(
        stata_output, header = FALSE,
        col.names = c("method", "iteration", "elapsed_seconds", "rows", "columns")
    )
    combined <- rbind(r_raw, stata_raw)
    if (is.na(item$rows)) item$rows <- unique(combined$rows)
    if (length(unique(combined$rows)) != 1L ||
        any(combined$rows != item$rows) ||
        any(combined$columns != length(present))) {
        stop("worker result dimensions differ for ", item$case)
    }
    fixtures[[index]] <- data.frame(
        case = item$case, source = item$source, rows = item$rows,
        columns = item$columns, selected_columns = length(present),
        union_columns = length(union), bytes = item$bytes,
        stringsAsFactors = FALSE
    )
    combined$case <- item$case
    raw_rows[[index]] <- combined[c("case", "method", "iteration", "elapsed_seconds", "rows", "columns")]
    message(index, "/", nrow(cases), ": ", item$case)
}

raw <- do.call(rbind, raw_rows)
fixture_table <- do.call(rbind, fixtures)
write.table(raw, file.path(output_dir, "raw.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
write.table(fixture_table, file.path(output_dir, "fixtures.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
groups <- split(raw, interaction(raw$case, raw$method, drop = TRUE))
summary <- do.call(rbind, lapply(groups, function(group) data.frame(
    case = group$case[[1L]], method = group$method[[1L]],
    median_seconds = median(group$elapsed_seconds),
    min_seconds = min(group$elapsed_seconds),
    max_seconds = max(group$elapsed_seconds), stringsAsFactors = FALSE
)))
summary <- summary[order(match(summary$case, cases$case), summary$median_seconds), ]
rownames(summary) <- NULL
write.table(summary, file.path(output_dir, "summary.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
print(merge(summary, fixture_table, by = "case", sort = FALSE), row.names = FALSE)
