script_path <- normalizePath(sub("^--file=", "", grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]), winslash = "/")
script_dir <- dirname(script_path)
source(file.path(script_dir, "common.R"))
source(file.path(script_dir, "provenance.R"))
source(file.path(script_dir, "runner.R"))
source(file.path(script_dir, "runtime.R"))

fertility_assert_manual_run()
checkout_root <- fertility_checkout_root(script_path)
raw_root <- normalizePath(file.path(checkout_root, "target", "fertility-surveys", "raw"),
                          winslash = "/", mustWork = TRUE)
invisible(fertility_assert_tempdir(raw_root))
library <- normalizePath(Sys.getenv("DTAPARSER_FERTILITY_LIBRARY"), winslash = "/",
                         mustWork = TRUE)
provenance_path <- normalizePath(
    Sys.getenv("DTAPARSER_FERTILITY_PROVENANCE"), winslash = "/", mustWork = TRUE
)
provenance <- fertility_verify_provenance(checkout_root, library, provenance_path)
inventory <- fertility_build_inventory()
framework_id <- fertility_framework_id(
    provenance$provenance_id[[1L]], fertility_required_paths()$datasigs
)
invisible(fertility_prepare_framework_snapshot(
    script_dir, raw_root, framework_id, inventory
))
cat(framework_id)
