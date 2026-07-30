script_path <- normalizePath(sub("^--file=", "", grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]), winslash = "/")
script_dir <- dirname(script_path)
source(file.path(script_dir, "common.R"))
source(file.path(script_dir, "accepted.R"))
source(file.path(script_dir, "provenance.R"))
source(file.path(script_dir, "runner.R"))
source(file.path(script_dir, "runtime.R"))

fertility_assert_manual_run()
options <- fertility_validate_source_arguments(
    fertility_parse_arguments(commandArgs(trailingOnly = TRUE))
)
checkout_root <- fertility_checkout_root(script_path)
raw_root <- fertility_assert_checkout_raw_root(
    file.path(checkout_root, "target", "fertility-surveys", "raw"), checkout_root
)
invisible(fertility_assert_tempdir(raw_root))
library_value <- Sys.getenv("DTAPARSER_FERTILITY_LIBRARY")
provenance_value <- Sys.getenv("DTAPARSER_FERTILITY_PROVENANCE")
if (!nzchar(library_value) || !nzchar(provenance_value)) {
    stop("immutable corpus build library and provenance are required")
}
selected_build_id <- basename(dirname(path.expand(provenance_value)))
build_bundle <- fertility_resolve_build_bundle(
    raw_root, selected_build_id, require_current = TRUE
)
if (!identical(path.expand(library_value), build_bundle$library) ||
    !identical(path.expand(provenance_value), build_bundle$provenance)) {
    stop("immutable corpus build paths escaped the selected build generation")
}
library <- build_bundle$library
provenance_path <- build_bundle$provenance
provenance <- fertility_verify_provenance(checkout_root, library, provenance_path)
if (!identical(provenance$provenance_id[[1L]], selected_build_id)) {
    stop("selected build provenance identity is invalid")
}
inventory <- fertility_build_selected_inventory(options, raw_root)
acceptance <- if (nzchar(options$accepted_current_hashes)) {
    fertility_load_acceptance(raw_root, options$accepted_current_hashes, inventory)
} else NULL
family <- fertility_family_selection(inventory, options)
fertility_validate_accepted_selection(options, family)
invisible(fertility_validate_acceptance_current(acceptance, inventory))
framework_id <- fertility_framework_id(
    provenance$provenance_id[[1L]], fertility_required_paths(options, raw_root)$datasigs, acceptance
)
invisible(fertility_prepare_framework_snapshot(
    script_dir, raw_root, framework_id, inventory, acceptance
))
cat(framework_id)
