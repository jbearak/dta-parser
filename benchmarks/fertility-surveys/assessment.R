script_path <- normalizePath(sub("^--file=", "", grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]), winslash = "/")
script_dir <- dirname(script_path)
source(file.path(script_dir, "common.R"))
source(file.path(script_dir, "accepted.R"))
source(file.path(script_dir, "runner.R"))
source(file.path(script_dir, "runtime.R"))

fertility_assert_manual_run()
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L ||
    sum(startsWith(arguments, "--assessment-family-id=")) != 1L ||
    sum(startsWith(arguments, "--accepted-family-id=")) != 1L) {
    stop(paste(
        "usage: assessment.R --assessment-family-id=FULL_ID",
        "--accepted-family-id=ACCEPTED_ID"
    ))
}
value <- function(prefix) sub("^[^=]+=", "", arguments[startsWith(arguments, prefix)])
full_family_id <- value("--assessment-family-id=")
accepted_family_id <- value("--accepted-family-id=")
if (any(!grepl("^[0-9a-f]{64}$", c(full_family_id, accepted_family_id))) ||
    identical(full_family_id, accepted_family_id)) {
    stop("assessment family IDs are invalid")
}
checkout_root <- fertility_checkout_root(script_path)
raw_root <- fertility_assert_checkout_raw_root(
    file.path(checkout_root, "target", "fertility-surveys", "raw"), checkout_root
)
invisible(fertility_assert_tempdir(raw_root))

load_family <- function(family_id, inventory, role = c("original", "accepted")) {
    role <- match.arg(role)
    merged_root <- fertility_assert_direct_child(
        file.path(raw_root, "merged"), raw_root, "merged output directory"
    )
    parent <- fertility_assert_direct_child(
        file.path(merged_root, family_id), merged_root,
        "assessment merged-family parent"
    )
    common_files <- fertility_assessment_bundle_files("legacy-original")
    current <- fertility_current_bundle_paths(
        parent, common_files, "assessment merged-family"
    )
    entries <- list.files(
        current$bundle, all.files = TRUE, no.. = TRUE, full.names = TRUE,
        recursive = FALSE, include.dirs = TRUE
    )
    format <- fertility_assessment_bundle_format(basename(entries), role)
    files <- if (identical(format, "current-merged-report-v2")) {
        fertility_assessment_bundle_files("current")
    } else common_files
    paths <- setNames(file.path(current$bundle, unname(files)), names(files))
    for (index in seq_along(paths)) {
        paths[[index]] <- fertility_assert_existing_file(
            paths[[index]], current$bundle,
            paste("assessment merged-family", names(paths)[[index]])
        )
        if (!file_test("-f", paths[[index]]) || fertility_path_is_symlink(paths[[index]])) {
            stop("assessment merged-family must contain only regular nonsymlink files")
        }
    }
    bundle <- lapply(paths, function(path) read.delim(
        path, colClasses = "character", check.names = FALSE
    ))
    validated <- if (identical(format, "current-merged-report-v2")) {
        fertility_validate_merged_bundle(bundle, family_id, inventory)
    } else {
        fertility_validate_assessment_legacy_original_bundle(
            bundle, family_id, inventory
        )
    }
    snapshot_schema <- if (identical(format, "legacy-original-merged-report-v2")) {
        fertility_report_schema_version
    } else if (identical(
        validated$provenance$evidence_origin[[1L]],
        "historical-schema-10-replay"
    )) fertility_legacy_report_schema_version else fertility_report_schema_version
    framework_inventory <- fertility_framework_inventory(
        file.path(raw_root, "framework", validated$provenance$framework_id[[1L]]),
        inventory = inventory,
        framework_id = validated$provenance$framework_id[[1L]],
        report_schema_version = snapshot_schema
    )
    if (!identical(validated$provenance$inventory_id[[1L]],
                   framework_inventory$provenance$inventory_id[[1L]]) ||
        (identical(role, "original") &&
         !is.null(framework_inventory$acceptance_provenance))) {
        stop("assessment merged-family inventory provenance changed")
    }
    validated$run_name <- current$run_name
    validated
}

load_sources <- function() {
    inventory <- fertility_build_inventory()
    full <- load_family(full_family_id, inventory, "original")
    accepted <- load_family(accepted_family_id, inventory, "accepted")
    gates <- fertility_validate_assessment_families(full, accepted)
    publication <- fertility_revalidate_accepted_publication(
        raw_root, accepted$provenance, inventory
    )
    list(inventory = inventory, full = full, accepted = accepted,
         gates = gates, acceptance = publication$acceptance)
}

sources <- load_sources()
full <- sources$full
accepted <- sources$accepted
assessment_source_snapshot <- function(source) list(
    run_name = source$run_name, source_format = source$source_format,
    source_id = source$source_id, results = source$results,
    summary = source$summary, family_manifest = source$family_manifest,
    input_attestation = source$input_attestation, provenance = source$provenance,
    full_default = source$full_default,
    evidence_family_id = source$evidence_family_id,
    family_input_attestation_id = source$family_input_attestation_id,
    merge_id = source$merge_id
)
full_snapshot <- assessment_source_snapshot(full)
accepted_snapshot <- assessment_source_snapshot(accepted)
revalidate_assessment_sources <- function() {
    current <- load_sources()
    if (!identical(assessment_source_snapshot(current$full), full_snapshot) ||
        !identical(assessment_source_snapshot(current$accepted), accepted_snapshot) ||
        !identical(current$acceptance$artifact_sha256,
                   sources$acceptance$artifact_sha256) ||
        !identical(current$gates, sources$gates)) {
        stop("assessment source evidence changed before publication")
    }
    invisible(current)
}
gates <- sources$gates
authority <- gates$acceptance_authority
commitment_id <- gates$acceptance_commitment_id
assessment_id <- fertility_stable_id(list(
    assessment_contract = "derived-dual-gate-source-identity-v2",
    original_family_id = full_family_id,
    original_source_format = full$source_format,
    original_source_id = full$source_id,
    original_evidence_family_id = full$evidence_family_id,
    original_family_input_attestation_id = full$family_input_attestation_id,
    original_merge_id = full$merge_id,
    accepted_family_id = accepted_family_id,
    accepted_source_format = accepted$source_format,
    accepted_source_id = accepted$source_id,
    accepted_evidence_family_id = accepted$evidence_family_id,
    accepted_merge_id = accepted$merge_id,
    acceptance_authority = authority,
    acceptance_commitment_id = commitment_id,
    manifest_gate = gates$manifest_gate,
    explicit_local_evidence_gate = gates$explicit_local_evidence_gate
))
assessment <- data.frame(
    assessment_id = assessment_id,
    assessment_contract = "derived-dual-gate-source-identity-v2",
    original_family_id = full_family_id,
    original_source_format = full$source_format,
    original_source_id = full$source_id,
    original_evidence_family_id = full$evidence_family_id,
    original_family_input_attestation_id = full$family_input_attestation_id,
    original_merge_id = full$merge_id,
    accepted_family_id = accepted_family_id,
    accepted_source_format = accepted$source_format,
    accepted_source_id = accepted$source_id,
    accepted_evidence_family_id = accepted$evidence_family_id,
    accepted_merge_id = accepted$merge_id,
    acceptance_authority = authority,
    acceptance_commitment_id = commitment_id,
    original_family_preserved = TRUE,
    accepted_family_preserved = TRUE,
    manifest_gate = gates$manifest_gate,
    explicit_local_evidence_gate = gates$explicit_local_evidence_gate,
    original_files = nrow(full$results),
    accepted_files = nrow(accepted$results),
    created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    stringsAsFactors = FALSE, check.names = FALSE
)
invisible(fertility_assert_checkout_raw_root(raw_root, checkout_root))
parent <- fertility_assert_output_parent(
    raw_root, "assessments", assessment_id, create = TRUE
)
Sys.chmod(c(file.path(raw_root, "assessments"), parent), mode = "0700")
stage <- tempfile(".assessment.", tmpdir = parent)
dir.create(stage, mode = "0700")
invisible(fertility_assert_direct_child(
    stage, parent, "assessment staging directory"
))
on.exit(unlink(stage, recursive = TRUE), add = TRUE)
fertility_atomic_write_table(assessment, file.path(stage, "assessment.tsv"))
validate_assessment_bundle <- function(path) {
    fertility_validate_exact_table_bundle(
        path, c(assessment = "assessment.tsv"),
        list(assessment = assessment), "assessment publication bundle"
    )
    invisible(TRUE)
}
run_name <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", Sys.getpid())
destination <- file.path(parent, run_name)
fertility_publication_test_hook(
    "assessment-before-bundle-revalidation",
    list(parent = parent, stage = stage, destination = destination)
)
invisible(revalidate_assessment_sources())
invisible(validate_assessment_bundle(stage))
invisible(fertility_assert_checkout_raw_root(raw_root, checkout_root))
parent <- fertility_assert_output_parent(raw_root, "assessments", assessment_id)
invisible(fertility_assert_existing_directory(
    stage, parent, "assessment staging directory"
))
destination <- fertility_assert_new_destination(
    destination, parent, "assessment publication bundle"
)
fertility_atomic_rename_noreplace(
    stage, destination, "assessment publication bundle"
)
pointer <- tempfile("CURRENT.", tmpdir = parent)
writeLines(run_name, pointer, useBytes = TRUE)
Sys.chmod(pointer, mode = "0600")
pointer_ready <- tryCatch({
    fertility_publication_test_hook(
        "assessment-before-current-revalidation",
        list(parent = parent, bundle = destination,
             pointer = file.path(parent, "CURRENT"))
    )
    revalidate_assessment_sources()
    validate_assessment_bundle(destination)
    fertility_assert_checkout_raw_root(raw_root, checkout_root)
    parent <- fertility_assert_output_parent(
        raw_root, "assessments", assessment_id
    )
    fertility_assert_existing_directory(
        destination, parent, "assessment publication bundle"
    )
    fertility_assert_existing_file(
        pointer, parent, "temporary assessment pointer"
    )
    fertility_assert_direct_child(
        file.path(parent, "CURRENT"), parent,
        "assessment CURRENT pointer", must_work = FALSE
    )
    TRUE
}, error = function(error) {
    fertility_remove_confirmed_new_path(
        destination, parent, "new assessment publication bundle"
    )
    stop(error)
})
if (!isTRUE(pointer_ready) ||
    !file.rename(pointer, file.path(parent, "CURRENT"))) {
    fertility_remove_confirmed_new_path(
        destination, parent, "new assessment publication bundle"
    )
    stop("could not publish derived assessment pointer")
}
message("validated merged manifest-gated family and explicit local five-ID evidence")
