script_path <- normalizePath(sub("^--file=", "", grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]), winslash = "/")
script_dir <- dirname(script_path)
source(file.path(script_dir, "common.R"))
source(file.path(script_dir, "runner.R"))
source(file.path(script_dir, "runtime.R"))

fertility_assert_manual_run()
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L || !startsWith(arguments, "--family-id=")) {
    stop("usage: merge.R --family-id=ID")
}
family_id <- sub("^[^=]+=", "", arguments[[1L]])
if (!grepl("^[0-9a-f]{64}$", family_id)) stop("invalid family ID")
checkout_root <- fertility_checkout_root(script_path)
raw_root <- normalizePath(file.path(checkout_root, "target", "fertility-surveys", "raw"),
                          winslash = "/", mustWork = TRUE)
invisible(fertility_assert_tempdir(raw_root))
reports_root <- file.path(raw_root, "reports")
parents <- if (dir.exists(reports_root))
    list.dirs(reports_root, recursive = FALSE, full.names = TRUE) else character()

bundles <- list()
for (parent in parents) {
    pointer <- file.path(parent, "CURRENT")
    if (!file.exists(pointer)) next
    run_name <- tryCatch(readLines(pointer, warn = FALSE, n = 1L),
                         error = function(error) character())
    if (length(run_name) != 1L || !grepl("^[A-Za-z0-9._-]+$", run_name)) next
    bundle <- file.path(parent, run_name)
    provenance_path <- file.path(bundle, "run-provenance.tsv")
    results_path <- file.path(bundle, "results.tsv")
    family_manifest_path <- file.path(bundle, "family-manifest.tsv")
    if (!file.exists(provenance_path) || !file.exists(results_path) ||
        !file.exists(family_manifest_path)) next
    provenance <- tryCatch(read.delim(
        provenance_path, colClasses = "character", check.names = FALSE
    ), error = function(error) NULL)
    if (is.null(provenance) || nrow(provenance) != 1L ||
        !"family_id" %in% names(provenance) ||
        !identical(provenance$family_id[[1L]], family_id)) next
    results <- read.delim(results_path, colClasses = "character", check.names = FALSE)
    family_manifest <- read.delim(
        family_manifest_path, colClasses = "character", check.names = FALSE
    )
    bundles[[length(bundles) + 1L]] <- list(
        provenance = provenance, results = results,
        family_manifest = family_manifest
    )
}
if (!length(bundles)) stop("no current shard reports found for family ID")
framework_ids <- unique(vapply(
    bundles, function(bundle) bundle$provenance$framework_id[[1L]], character(1)
))
if (length(framework_ids) != 1L || !grepl("^[0-9a-f]{64}$", framework_ids)) {
    stop("shard reports have invalid framework provenance")
}
candidate_provenance <- do.call(rbind, lapply(bundles, `[[`, "provenance"))
snapshot_report_schema_version <- fertility_snapshot_report_schema_version(
    candidate_provenance
)
framework_inventory <- fertility_framework_inventory(
    file.path(raw_root, "framework", framework_ids[[1L]]),
    framework_id = framework_ids[[1L]],
    report_schema_version = snapshot_report_schema_version
)
inventory_ids <- unique(vapply(
    bundles, function(bundle) bundle$provenance$inventory_id[[1L]], character(1)
))
if (length(inventory_ids) != 1L ||
    !identical(inventory_ids[[1L]],
               framework_inventory$provenance$inventory_id[[1L]])) {
    stop("shard reports do not match canonical inventory provenance")
}
validated <- fertility_validate_shard_bundles(
    bundles, family_id, framework_inventory$manifest
)
results <- validated$results
provenance <- validated$provenance
shard_count <- validated$shard_count
full_default <- validated$full_default
summary <- fertility_classification_summary(results)
family_input_attestation_id <- fertility_family_input_attestation_id(provenance)
evidence_family_id <- fertility_evidence_family_id(
    family_id, family_input_attestation_id, provenance$evidence_origin[[1L]],
    as.integer(provenance$source_corpus_schema_version[[1L]]),
    provenance$report_schema_id[[1L]]
)
merge_provenance <- data.frame(
    schema_version = fertility_schema_version,
    report_schema_version = fertility_report_schema_version,
    evidence_origin = provenance$evidence_origin[[1L]],
    source_corpus_schema_version = provenance$source_corpus_schema_version[[1L]],
    replayed_at_utc = provenance$replayed_at_utc[[1L]],
    family_id = family_id, evidence_family_id = evidence_family_id,
    family_input_attestation_id = family_input_attestation_id,
    framework_id = provenance$framework_id[[1L]],
    config_id = provenance$config_id[[1L]],
    build_provenance_id = provenance$build_provenance_id[[1L]],
    inventory_id = provenance$inventory_id[[1L]],
    family_manifest_id = provenance$family_manifest_id[[1L]],
    report_schema_id = fertility_report_schema_id(),
    shard_count = shard_count,
    files = nrow(results),
    full_default_family = full_default,
    created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    stringsAsFactors = FALSE, check.names = FALSE
)
merge_parent <- file.path(raw_root, "merged", family_id)
dir.create(merge_parent, recursive = TRUE, showWarnings = FALSE, mode = "0700")
Sys.chmod(c(file.path(raw_root, "merged"), merge_parent), mode = "0700")
stage <- tempfile(".merge.", tmpdir = merge_parent)
dir.create(stage, mode = "0700")
on.exit(unlink(stage, recursive = TRUE), add = TRUE)
fertility_atomic_write_table(results, file.path(stage, "results.tsv"))
fertility_atomic_write_table(summary, file.path(stage, "summary.tsv"))
fertility_atomic_write_table(
    validated$family_manifest, file.path(stage, "family-manifest.tsv")
)
fertility_atomic_write_table(merge_provenance,
                             file.path(stage, "merge-provenance.tsv"))
run_name <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", Sys.getpid())
merge_dir <- file.path(merge_parent, run_name)
if (!file.rename(stage, merge_dir)) stop("could not publish merged report bundle")
pointer <- tempfile("CURRENT.", tmpdir = merge_parent)
writeLines(run_name, pointer, useBytes = TRUE)
Sys.chmod(pointer, mode = "0600")
if (!file.rename(pointer, file.path(merge_parent, "CURRENT"))) {
    stop("could not publish merged report pointer")
}
message("merged ", nrow(results), " files from ", shard_count, " shards")
