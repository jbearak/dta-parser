script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument), winslash = "/"))
source(file.path(script_dir, "common.R"))
source(file.path(script_dir, "accepted.R"))
source(file.path(script_dir, "compare.R"))
source(file.path(script_dir, "runner.R"))
source(file.path(script_dir, "worker.R"))
source(file.path(script_dir, "runtime.R"))
source(file.path(script_dir, "provenance.R"))

expect_error <- function(expression, pattern) {
    error <- tryCatch({ force(expression); NULL }, error = identity)
    if (!inherits(error, "error")) stop("expected error matching: ", pattern)
    if (!grepl(pattern, conditionMessage(error))) {
        stop("expected error matching '", pattern, "', got: ", conditionMessage(error))
    }
    invisible(error)
}

root <- tempfile("fertility-framework-")
dir.create(root)
root <- normalizePath(root, winslash = "/", mustWork = TRUE)
on.exit(unlink(root, recursive = TRUE), add = TRUE)

# The output walk includes only regular case-insensitive DTA files and fails
# closed when a potentially relevant entry cannot be safely inventoried.
local({
    fixture <- file.path(root, "output-inventory")
    outside <- file.path(root, "output-inventory-outside")
    dir.create(file.path(fixture, "nested"), recursive = TRUE)
    dir.create(outside)
    writeBin(as.raw(1:3), file.path(fixture, "regular.dta"))
    writeBin(as.raw(4:6), file.path(fixture, "nested", "upper.DTA"))
    writeLines("ignored", file.path(fixture, "notes.txt"))
    writeLines("outside", file.path(outside, "outside.txt"))
    stopifnot(file.symlink(
        file.path(outside, "outside.txt"), file.path(fixture, "ignored-link.txt")
    ))
    old_root <- fertility_output_root
    old_hook <- getOption("dtaparser.fertility.output_inventory_test_hook")
    on.exit({
        assign("fertility_output_root", old_root, envir = .GlobalEnv)
        options(dtaparser.fertility.output_inventory_test_hook = old_hook)
    }, add = TRUE)
    assign(
        "fertility_output_root",
        normalizePath(fixture, winslash = "/", mustWork = TRUE),
        envir = .GlobalEnv
    )
    expected <- sort(c(
        file.path(fertility_output_root, "regular.dta"),
        file.path(fertility_output_root, "nested", "upper.DTA")
    ), method = "radix")
    stopifnot(identical(fertility_output_entries(fertility_output_root), expected))

    dta_link <- file.path(fixture, "linked.dta")
    stopifnot(file.symlink(file.path(outside, "outside.txt"), dta_link))
    expect_error(
        fertility_output_entries(fertility_output_root), "refuses DTA symlinks"
    )
    unlink(dta_link)

    directory_link <- file.path(fixture, "linked-directory")
    stopifnot(file.symlink(outside, directory_link))
    expect_error(
        fertility_output_entries(fertility_output_root), "symlinked directories"
    )
    unlink(directory_link)

    unavailable <- file.path(fixture, "unavailable.dta")
    writeBin(as.raw(7:9), unavailable)
    options(dtaparser.fertility.output_inventory_test_hook = function(
        boundary, context
    ) {
        if (identical(boundary, "before-entry-info") &&
            identical(context$entry, unavailable)) unlink(unavailable)
    })
    expect_error(
        fertility_output_entries(fertility_output_root), "metadata is unavailable"
    )
    options(dtaparser.fertility.output_inventory_test_hook = NULL)

    raced <- file.path(fixture, "raced.dta")
    writeBin(as.raw(10:12), raced)
    options(dtaparser.fertility.output_inventory_test_hook = function(
        boundary, context
    ) {
        if (identical(boundary, "after-entry-info") &&
            identical(context$entry, raced)) {
            unlink(raced)
            stopifnot(file.symlink(file.path(outside, "outside.txt"), raced))
        }
    })
    expect_error(
        fertility_output_entries(fertility_output_root),
        "changed to a symlink|must not be a symlink"
    )
    options(dtaparser.fertility.output_inventory_test_hook = NULL)
    unlink(raced)

    mkfifo <- Sys.which("mkfifo")
    if (nzchar(mkfifo)) {
        fifo <- file.path(fixture, "nonregular.dta")
        stopifnot(system2(mkfifo, shQuote(fifo)) == 0L)
        expect_error(
            fertility_output_entries(fertility_output_root), "attest regular files"
        )
        unlink(fifo)
    }
})

# Output confinement rejects symlinked roots, publication descendants, CURRENT
# pointers, selected bundles, and consumed files before any private publication.
confinement_checkout <- file.path(root, "confinement-checkout")
dir.create(confinement_checkout)
confinement_raw <- file.path(
    confinement_checkout, "target", "fertility-surveys", "raw"
)
stopifnot(identical(
    fertility_assert_checkout_raw_root(
        confinement_raw, confinement_checkout, create = TRUE
    ),
    confinement_raw
))
confinement_outside <- file.path(root, "confinement-outside")
dir.create(confinement_outside, mode = "0755")
outside_mode <- file.info(confinement_outside)$mode[[1L]]
raw_symlink_checkout <- file.path(root, "raw-symlink-checkout")
dir.create(file.path(raw_symlink_checkout, "target", "fertility-surveys"),
           recursive = TRUE)
stopifnot(file.symlink(
    confinement_outside,
    file.path(raw_symlink_checkout, "target", "fertility-surveys", "raw")
))
expect_error(fertility_assert_checkout_raw_root(
    file.path(raw_symlink_checkout, "target", "fertility-surveys", "raw"),
    raw_symlink_checkout
), "must not be symlinks")
for (name in c(
    "tmp", "reports", "merged", "assessments", "checkpoints", "framework",
    ".locks", "builds", "accepted-current-hashes"
)) {
    path <- file.path(confinement_raw, name)
    stopifnot(file.symlink(confinement_outside, path))
    expect_error(fertility_assert_direct_child(
        path, confinement_raw, paste(name, "test path")
    ), "symlink")
    unlink(path)
}
destination_parent <- file.path(root, "destination-confinement")
dir.create(destination_parent)
for (with_content in c(FALSE, TRUE)) {
    destination <- file.path(
        destination_parent, paste0("existing-", as.integer(with_content))
    )
    dir.create(destination)
    sentinel <- file.path(destination, "sentinel")
    if (with_content) writeLines("untouched", sentinel)
    before <- list.files(destination, all.files = TRUE, no.. = TRUE)
    expect_error(fertility_assert_new_destination(
        destination, destination_parent, "publication destination"
    ), "already exists")
    stopifnot(identical(
        list.files(destination, all.files = TRUE, no.. = TRUE), before
    ))
    if (with_content) stopifnot(identical(readLines(sentinel), "untouched"))
}
atomic_parent <- file.path(root, "atomic-publication")
dir.create(atomic_parent)
atomic_source <- file.path(atomic_parent, "source")
atomic_destination <- file.path(atomic_parent, "destination")
dir.create(atomic_source)
writeLines("source", file.path(atomic_source, "value"))
fertility_atomic_rename_noreplace(
    atomic_source, atomic_destination, "synthetic atomic publication"
)
stopifnot(
    !dir.exists(atomic_source),
    identical(readLines(file.path(atomic_destination, "value")), "source")
)
atomic_competitor <- file.path(atomic_parent, "competitor")
atomic_race_destination <- file.path(atomic_parent, "race-destination")
dir.create(atomic_competitor)
writeLines("competitor", file.path(atomic_competitor, "value"))
old_atomic_hook <- getOption("dtaparser.fertility.publication_test_hook")
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(boundary, "atomic-noreplace-before-operation")) {
        dir.create(context$to)
        writeLines("winner", file.path(context$to, "value"))
    }
})
expect_error(fertility_atomic_rename_noreplace(
    atomic_competitor, atomic_race_destination,
    "synthetic atomic race publication"
), "destination already exists")
options(dtaparser.fertility.publication_test_hook = old_atomic_hook)
stopifnot(
    identical(readLines(file.path(atomic_competitor, "value")), "competitor"),
    identical(readLines(file.path(atomic_race_destination, "value")), "winner")
)
revalidation_fixture <- file.path(root, "publication-revalidation")
dir.create(revalidation_fixture)
framework_source_fixture <- file.path(revalidation_fixture, "framework.tsv")
checkpoint_source_fixture <- file.path(revalidation_fixture, "checkpoint.rds")
writeLines("framework-v1", framework_source_fixture)
saveRDS("checkpoint-v1", checkpoint_source_fixture)
source_attestation <- fertility_attest_existing_files(
    c(framework_source_fixture, checkpoint_source_fixture),
    "publication source"
)
old_publication_hook <- getOption(
    "dtaparser.fertility.publication_test_hook"
)
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(boundary, "synthetic-before-current")) {
        writeLines("framework-v2", framework_source_fixture)
    }
})
fertility_publication_test_hook("synthetic-before-current")
expect_error(fertility_revalidate_existing_files(
    source_attestation, "publication source"
), "identity changed")
writeLines("framework-v1", framework_source_fixture)
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(boundary, "synthetic-before-current")) {
        saveRDS("checkpoint-v2", checkpoint_source_fixture)
    }
})
fertility_publication_test_hook("synthetic-before-current")
expect_error(fertility_revalidate_existing_files(
    source_attestation, "publication source"
), "identity changed")
saveRDS("checkpoint-v1", checkpoint_source_fixture)
options(dtaparser.fertility.publication_test_hook = old_publication_hook)
stopifnot(isTRUE(fertility_revalidate_existing_files(
    source_attestation, "publication source"
)))
for (boundary in c("staged", "renamed")) {
    exact_bundle <- file.path(root, paste0("exact-report-", boundary))
    dir.create(exact_bundle)
    exact_results <- data.frame(
        id = "F0001", classification = "pass",
        stringsAsFactors = FALSE, check.names = FALSE
    )
    exact_summary <- data.frame(
        classification = "pass", files = 1L,
        stringsAsFactors = FALSE, check.names = FALSE
    )
    fertility_atomic_write_table(
        exact_results, file.path(exact_bundle, "results.tsv")
    )
    fertility_atomic_write_table(
        exact_summary, file.path(exact_bundle, "summary.tsv")
    )
    stopifnot(length(fertility_validate_exact_table_bundle(
        exact_bundle, c(results = "results.tsv", summary = "summary.tsv"),
        list(results = exact_results, summary = exact_summary),
        paste(boundary, "report bundle")
    )) == 2L)
    changed_results <- exact_results
    changed_results$classification <- "metadata-mismatch"
    fertility_atomic_write_table(
        changed_results, file.path(exact_bundle, "results.tsv")
    )
    expect_error(fertility_validate_exact_table_bundle(
        exact_bundle, c(results = "results.tsv", summary = "summary.tsv"),
        list(results = exact_results, summary = exact_summary),
        paste(boundary, "report bundle")
    ), "exact contents changed")

    assessment_bundle <- file.path(root, paste0("exact-assessment-", boundary))
    dir.create(assessment_bundle)
    expected_assessment <- data.frame(
        assessment_id = paste(rep("a", 64L), collapse = ""),
        manifest_gate = TRUE, stringsAsFactors = FALSE, check.names = FALSE
    )
    fertility_atomic_write_table(
        expected_assessment, file.path(assessment_bundle, "assessment.tsv")
    )
    changed_assessment <- expected_assessment
    changed_assessment$manifest_gate <- FALSE
    fertility_atomic_write_table(
        changed_assessment, file.path(assessment_bundle, "assessment.tsv")
    )
    expect_error(fertility_validate_exact_table_bundle(
        assessment_bundle, c(assessment = "assessment.tsv"),
        list(assessment = expected_assessment),
        paste(boundary, "assessment bundle")
    ), "exact contents changed")
}
for (bundle_kind in c("run", "merge", "assessment")) {
    for (boundary in c("staged", "renamed")) {
        for (mutation in c("extra-file", "hidden-file", "nested-directory")) {
            shape_bundle <- file.path(
                root, paste("exact-shape", bundle_kind, boundary, mutation, sep = "-")
            )
            dir.create(shape_bundle)
            expected_name <- if (identical(bundle_kind, "assessment")) {
                "assessment.tsv"
            } else "results.tsv"
            expected_table <- data.frame(
                value = "canonical", stringsAsFactors = FALSE,
                check.names = FALSE
            )
            fertility_atomic_write_table(
                expected_table, file.path(shape_bundle, expected_name)
            )
            if (identical(mutation, "extra-file")) {
                writeLines("extra", file.path(shape_bundle, "extra.tsv"))
            } else if (identical(mutation, "hidden-file")) {
                writeLines("hidden", file.path(shape_bundle, ".hidden"))
            } else {
                dir.create(file.path(shape_bundle, "nested"))
                writeLines("nested", file.path(shape_bundle, "nested", "value"))
            }
            expect_error(fertility_validate_exact_table_bundle(
                shape_bundle, setNames(expected_name, "table"),
                list(table = expected_table),
                paste(boundary, bundle_kind, "publication bundle")
            ), "exact file set changed")
        }
    }
}
build_id_fixture <- paste(rep("c", 64L), collapse = "")
builds_fixture <- file.path(confinement_raw, "builds")
generation_fixture <- file.path(builds_fixture, build_id_fixture)
library_fixture <- file.path(generation_fixture, "library")
package_fixture <- file.path(library_fixture, "dtaparser")
dir.create(package_fixture, recursive = TRUE)
writeLines("synthetic", file.path(generation_fixture, "build-provenance.tsv"))
writeLines(build_id_fixture, file.path(builds_fixture, "CURRENT"))
stopifnot(identical(
    fertility_resolve_build_bundle(
        confinement_raw, build_id_fixture, require_current = TRUE
    )$package,
    package_fixture
))
build_external <- file.path(root, "build-descendant-external")
dir.create(file.path(build_external, "library", "dtaparser"), recursive = TRUE)
writeLines("external", file.path(build_external, "CURRENT"))
writeLines("external", file.path(build_external, "build-provenance.tsv"))
build_external_before <- as.list(file.info(c(
    build_external, file.path(build_external, "CURRENT"),
    file.path(build_external, "build-provenance.tsv")
))[, c("size", "mode")])
for (case in list(
    list(path = file.path(builds_fixture, "CURRENT"),
         target = file.path(build_external, "CURRENT")),
    list(path = generation_fixture, target = build_external),
    list(path = library_fixture, target = file.path(build_external, "library")),
    list(path = file.path(generation_fixture, "build-provenance.tsv"),
         target = file.path(build_external, "build-provenance.tsv")),
    list(path = package_fixture,
         target = file.path(build_external, "library", "dtaparser"))
)) {
    saved <- paste0(case$path, ".saved")
    stopifnot(file.rename(case$path, saved), file.symlink(case$target, case$path))
    expect_error(fertility_resolve_build_bundle(
        confinement_raw, build_id_fixture, require_current = TRUE
    ), "symlink")
    unlink(case$path)
    stopifnot(file.rename(saved, case$path))
}
stopifnot(identical(as.list(file.info(c(
    build_external, file.path(build_external, "CURRENT"),
    file.path(build_external, "build-provenance.tsv")
))[, c("size", "mode")]), build_external_before))
package_nested <- file.path(package_fixture, "R")
dir.create(package_nested)
package_file <- file.path(package_nested, "dtaparser")
writeLines("equal-content", package_file)
package_attestation <- fertility_attest_regular_tree(
    package_fixture, "synthetic installed package"
)
external_package_file <- file.path(root, "external-package-file")
writeLines("equal-content", external_package_file)
stopifnot(file.rename(package_file, paste0(package_file, ".saved")))
stopifnot(file.symlink(external_package_file, package_file))
expect_error(fertility_attest_regular_tree(
    package_fixture, "synthetic installed package"
), "symlinks")
unlink(package_file)
stopifnot(file.rename(paste0(package_file, ".saved"), package_file))
external_package_directory <- file.path(root, "external-package-directory")
dir.create(external_package_directory)
writeLines("equal-content", file.path(external_package_directory, "dtaparser"))
stopifnot(file.rename(package_nested, paste0(package_nested, ".saved")))
stopifnot(file.symlink(external_package_directory, package_nested))
expect_error(fertility_attest_regular_tree(
    package_fixture, "synthetic installed package"
), "symlinks")
unlink(package_nested)
stopifnot(file.rename(paste0(package_nested, ".saved"), package_nested))
stopifnot(isTRUE(fertility_revalidate_regular_tree(
    package_attestation, "synthetic installed package"
)))
unlink(builds_fixture, recursive = TRUE)
checkpoint_framework_id <- paste(rep("e", 64L), collapse = "")
checkpoint_config_id <- paste(rep("f", 64L), collapse = "")
checkpoint_case_id <- "F0001"
checkpoint_case <- file.path(
    confinement_raw, "checkpoints", checkpoint_framework_id,
    checkpoint_config_id, checkpoint_case_id
)
dir.create(file.path(checkpoint_case, "tiles"), recursive = TRUE)
saveRDS("result", file.path(checkpoint_case, "result.rds"))
saveRDS("tile", file.path(checkpoint_case, "tiles", "metadata.rds"))
checkpoint_paths <- fertility_resolve_checkpoint_case(
    confinement_raw, checkpoint_framework_id, checkpoint_config_id,
    checkpoint_case_id
)
stopifnot(length(fertility_checkpoint_tile_files(checkpoint_paths)) == 1L)
checkpoint_external <- file.path(root, "checkpoint-descendant-external")
dir.create(file.path(checkpoint_external, "tiles"), recursive = TRUE)
saveRDS("external-result", file.path(checkpoint_external, "result.rds"))
saveRDS("external-tile", file.path(checkpoint_external, "tiles", "metadata.rds"))
checkpoint_external_before <- unname(tools::sha256sum(c(
    file.path(checkpoint_external, "result.rds"),
    file.path(checkpoint_external, "tiles", "metadata.rds")
)))
checkpoint_framework <- file.path(
    confinement_raw, "checkpoints", checkpoint_framework_id
)
checkpoint_configuration <- file.path(
    checkpoint_framework, checkpoint_config_id
)
for (case in list(
    list(path = checkpoint_framework, target = checkpoint_external),
    list(path = checkpoint_configuration, target = checkpoint_external),
    list(path = checkpoint_case, target = checkpoint_external),
    list(path = file.path(checkpoint_case, "result.rds"),
         target = file.path(checkpoint_external, "result.rds")),
    list(path = file.path(checkpoint_case, "tiles"),
         target = file.path(checkpoint_external, "tiles"))
)) {
    saved <- paste0(case$path, ".saved")
    stopifnot(file.rename(case$path, saved), file.symlink(case$target, case$path))
    expect_error(fertility_resolve_checkpoint_case(
        confinement_raw, checkpoint_framework_id, checkpoint_config_id,
        checkpoint_case_id
    ), "symlink")
    unlink(case$path)
    stopifnot(file.rename(saved, case$path))
}
tile_path <- file.path(checkpoint_case, "tiles", "metadata.rds")
tile_saved <- file.path(root, "checkpoint-metadata.saved")
stopifnot(file.rename(tile_path, tile_saved), file.symlink(
    file.path(checkpoint_external, "tiles", "metadata.rds"), tile_path
))
expect_error(fertility_checkpoint_tile_files(
    fertility_resolve_checkpoint_case(
        confinement_raw, checkpoint_framework_id, checkpoint_config_id,
        checkpoint_case_id
    )
), "symlink")
unlink(tile_path)
stopifnot(file.rename(tile_saved, tile_path))
stopifnot(identical(unname(tools::sha256sum(c(
    file.path(checkpoint_external, "result.rds"),
    file.path(checkpoint_external, "tiles", "metadata.rds")
))), checkpoint_external_before))
unlink(file.path(confinement_raw, "checkpoints"), recursive = TRUE)
owner_fixture <- file.path(root, "owner-confinement")
dir.create(owner_fixture)
owner_external <- file.path(root, "owner-external.tsv")
writeLines("external-owner", owner_external)
stopifnot(file.symlink(owner_external, file.path(owner_fixture, "owner.tsv")))
expect_error(fertility_read_owner(owner_fixture), "symlink")
unlink(file.path(owner_fixture, "owner.tsv"))
heartbeat_external <- file.path(root, "heartbeat-external")
writeLines("generation", heartbeat_external)
heartbeat_link <- file.path(owner_fixture, "heartbeat")
stopifnot(file.symlink(heartbeat_external, heartbeat_link))
expect_error(fertility_owner_alive(list(
    token = "token", pid = 1L, host = "foreign-host", start = "generation",
    heartbeat = heartbeat_link, created = as.numeric(Sys.time())
)), "symlink")
stopifnot(identical(readLines(owner_external), "external-owner"),
          identical(readLines(heartbeat_external), "generation"))
benchmark_lines <- readLines(file.path(script_dir, "benchmark.sh"), warn = FALSE)
atomic_function_start <- grep(
    "^atomic_move_noreplace\\(\\) \\{$", benchmark_lines
)[[1L]]
atomic_function_end <- which(
    seq_along(benchmark_lines) > atomic_function_start & benchmark_lines == "}"
)[[1L]]
shell_atomic_root <- file.path(root, "shell-atomic-publication")
dir.create(shell_atomic_root)
shell_atomic_source <- file.path(shell_atomic_root, "source")
shell_atomic_competitor <- file.path(shell_atomic_root, "competitor")
shell_atomic_destination <- file.path(shell_atomic_root, "destination")
dir.create(shell_atomic_source)
dir.create(shell_atomic_competitor)
writeLines("source", file.path(shell_atomic_source, "value"))
writeLines("competitor", file.path(shell_atomic_competitor, "value"))
shell_atomic_script <- file.path(root, "shell-atomic-test.sh")
writeLines(c(
    "#!/bin/sh", "set -eu",
    benchmark_lines[atomic_function_start:atomic_function_end],
    paste(
        "atomic_move_noreplace", shQuote(shell_atomic_source),
        shQuote(shell_atomic_destination), shQuote("synthetic shell publication")
    ),
    paste(
        "atomic_move_noreplace", shQuote(shell_atomic_competitor),
        shQuote(shell_atomic_destination), shQuote("synthetic shell race")
    )
), shell_atomic_script)
shell_atomic_result <- suppressWarnings(system2(
    "sh", shell_atomic_script, stdout = TRUE, stderr = TRUE
))
stopifnot(
    identical(attr(shell_atomic_result, "status"), 2L),
    any(grepl("destination already exists", shell_atomic_result, fixed = TRUE)),
    !dir.exists(shell_atomic_source),
    identical(readLines(file.path(shell_atomic_destination, "value")), "source"),
    identical(readLines(file.path(shell_atomic_competitor, "value")), "competitor")
)
shell_checkout <- file.path(root, "shell-confinement-checkout")
shell_script_dir <- file.path(shell_checkout, "benchmarks", "fertility-surveys")
shell_raw <- file.path(shell_checkout, "target", "fertility-surveys", "raw")
dir.create(shell_script_dir, recursive = TRUE)
dir.create(shell_raw, recursive = TRUE)
stopifnot(file.copy(
    file.path(script_dir, "benchmark.sh"), file.path(shell_script_dir, "benchmark.sh")
), file.symlink(confinement_outside, file.path(shell_raw, "tmp")))
run_shell_confinement <- function(arguments = "--inventory-only") {
    suppressWarnings(system2(
    "/usr/bin/env",
    c(
        "-u", "CI", "-u", "GITHUB_ACTIONS", "-u", "GITHUB_RUN_ID",
        "-u", "GITHUB_WORKFLOW",
        paste0("DTAPARSER_FERTILITY_CORPUS=", fertility_opt_in_value),
        "sh", file.path(shell_script_dir, "benchmark.sh"), arguments
    ),
    stdout = TRUE, stderr = TRUE
    ))
}
assert_shell_confinement <- function(result) stopifnot(
    !is.null(attr(result, "status")),
    any(grepl("symlink", result)),
    identical(file.info(confinement_outside)$mode[[1L]], outside_mode),
    !length(list.files(confinement_outside, all.files = TRUE, no.. = TRUE))
)
assert_shell_confinement(run_shell_confinement())
unlink(file.path(shell_raw, "tmp"))
unlink(shell_raw, recursive = TRUE)
stopifnot(file.symlink(confinement_outside, shell_raw))
assert_shell_confinement(run_shell_confinement())
unlink(shell_raw)
dir.create(file.path(shell_raw, "tmp"), recursive = TRUE)
stopifnot(
    file.copy(file.path(script_dir, "runtime.R"),
              file.path(shell_script_dir, "runtime.R")),
    file.symlink(confinement_outside, file.path(shell_raw, "builds"))
)
assert_shell_confinement(run_shell_confinement(character()))
unlink(file.path(shell_raw, "builds"))
shell_build_id <- paste(rep("d", 64L), collapse = "")
shell_builds <- file.path(shell_raw, "builds")
shell_generation <- file.path(shell_builds, shell_build_id)
shell_library <- file.path(shell_generation, "library")
shell_package <- file.path(shell_library, "dtaparser")
dir.create(shell_package, recursive = TRUE)
writeLines(shell_build_id, file.path(shell_builds, "CURRENT"))
writeLines("synthetic", file.path(shell_generation, "build-provenance.tsv"))
shell_external <- file.path(root, "shell-build-external")
dir.create(file.path(shell_external, "library", "dtaparser"), recursive = TRUE)
writeLines(shell_build_id, file.path(shell_external, "CURRENT"))
writeLines("external", file.path(shell_external, "build-provenance.tsv"))
shell_external_mode <- file.info(shell_external)$mode[[1L]]
for (case in list(
    list(path = file.path(shell_builds, "CURRENT"),
         target = file.path(shell_external, "CURRENT")),
    list(path = shell_generation, target = shell_external),
    list(path = shell_library, target = file.path(shell_external, "library")),
    list(path = file.path(shell_generation, "build-provenance.tsv"),
         target = file.path(shell_external, "build-provenance.tsv")),
    list(path = shell_package,
         target = file.path(shell_external, "library", "dtaparser"))
)) {
    saved <- paste0(case$path, ".saved")
    stopifnot(file.rename(case$path, saved), file.symlink(case$target, case$path))
    result <- run_shell_confinement(character())
    stopifnot(
        !is.null(attr(result, "status")), any(grepl("symlink", result)),
        identical(file.info(shell_external)$mode[[1L]], shell_external_mode),
        identical(readLines(file.path(shell_external, "build-provenance.tsv")),
                  "external")
    )
    unlink(case$path)
    stopifnot(file.rename(saved, case$path))
}
reports_root <- file.path(confinement_raw, "reports")
selection_parent <- file.path(reports_root, "selection")
bundle_dir <- file.path(selection_parent, "bundle")
dir.create(bundle_dir, recursive = TRUE)
for (name in c(
    "run-provenance.tsv", "results.tsv", "summary.tsv",
    "family-manifest.tsv", "input-attestation.tsv"
)) {
    writeLines("synthetic", file.path(bundle_dir, name))
}
writeLines("bundle", file.path(selection_parent, "CURRENT"))
current_files <- c(
    provenance = "run-provenance.tsv", results = "results.tsv",
    summary = "summary.tsv", family_manifest = "family-manifest.tsv",
    input_attestation = "input-attestation.tsv"
)
stopifnot(identical(
    fertility_current_bundle_paths(
        selection_parent, current_files, "synthetic report"
    )$bundle,
    bundle_dir
))
current_path <- file.path(selection_parent, "CURRENT")
current_saved <- paste0(current_path, ".saved")
stopifnot(file.rename(current_path, current_saved),
          file.symlink(current_saved, current_path))
expect_error(fertility_current_bundle_paths(
    selection_parent, current_files, "synthetic report"
), "CURRENT pointer must not be a symlink")
unlink(current_path)
stopifnot(file.rename(current_saved, current_path))
bundle_saved <- paste0(bundle_dir, ".saved")
stopifnot(file.rename(bundle_dir, bundle_saved),
          file.symlink(bundle_saved, bundle_dir))
expect_error(fertility_current_bundle_paths(
    selection_parent, current_files, "synthetic report"
), "bundle must not be a symlink")
unlink(bundle_dir)
stopifnot(file.rename(bundle_saved, bundle_dir))
for (field in names(current_files)) {
    consumed_path <- file.path(bundle_dir, current_files[[field]])
    consumed_saved <- paste0(consumed_path, ".saved")
    stopifnot(file.rename(consumed_path, consumed_saved),
              file.symlink(consumed_saved, consumed_path))
    expect_error(fertility_current_bundle_paths(
        selection_parent, current_files, "synthetic report"
    ), paste0(field, " must not be a symlink"))
    unlink(consumed_path)
    stopifnot(file.rename(consumed_saved, consumed_path))
}
second_bundle <- file.path(selection_parent, "bundle-two")
dir.create(second_bundle)
stopifnot(all(file.copy(
    file.path(bundle_dir, unname(current_files)), second_bundle
)))
writeLines("bundle-two", current_path)
expect_error(fertility_revalidate_current_bundle(
    selection_parent, "bundle", current_files, "source report shard"
), "CURRENT changed")
writeLines("bundle", current_path)
stopifnot(identical(fertility_revalidate_current_bundle(
    selection_parent, "bundle", current_files, "source report shard"
)$run_name, "bundle"))

cache <- file.path(root, "cache")
dir.create(cache)
write_release <- function(path, release) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    bytes <- if (release >= 117L) {
        charToRaw(sprintf("<stata_dta><header><release>%03d</release></header>", release))
    } else c(as.raw(release), as.raw(rep(0L, 40L)))
    writeBin(bytes, path)
}
rows <- data.frame(
    program = c("dhs", "dhs", "mics", "wfs", "enadid"),
    survey = c("AA_2000", "BB_2001", "CC_2002", "WFTEST", "EE_2003"),
    level = c("women", "births", "women", "women", "births"),
    datasig = "", sha512 = "", stringsAsFactors = FALSE
)
paths <- c(
    file.path(cache, "DHS/Original_Data/AA,2000/wm.dta"),
    file.path(cache, "DHS/Original_Data_Provenance_Unknown/BB,2001/bh.dta"),
    file.path(cache, "MICS/Data/Original Data/CC,2002/wm.dta"),
    file.path(cache, "WFS/Data/WFTEST.dta"),
    file.path(cache, "ENADID/Data/Original Data/EE,2003/bh.dta")
)
releases <- c(111L, 113L, 114L, 117L, 118L)
for (i in seq_along(paths)) write_release(paths[[i]], releases[[i]])
datasigs <- file.path(root, "datasigs.csv")
write.csv(rows, datasigs, row.names = FALSE, quote = FALSE)
inventory <- fertility_build_inventory(
    list(cache = cache, datasigs = datasigs), assert_counts = FALSE,
    enforce_required_paths = FALSE
)
stopifnot(
    identical(inventory$id, sprintf("F%04d", 1:5)),
    identical(inventory$release, releases),
    identical(inventory$path, normalizePath(paths, winslash = "/")),
    identical(names(fertility_public_inventory(inventory)),
              c("id", "program", "level", "release")),
    !any(c("path", "survey", "expected_sha512") %in%
         names(fertility_public_inventory(inventory)))
)
primary_second <- file.path(cache, "DHS/Original_Data/BB,2001/bh.dta")
write_release(primary_second, 113L)
precedence_inventory <- fertility_build_inventory(
    list(cache = cache, datasigs = datasigs), assert_counts = FALSE,
    enforce_required_paths = FALSE
)
stopifnot(precedence_inventory$path[[2L]] ==
          normalizePath(primary_second, winslash = "/"))

options <- fertility_parse_arguments(c(
    "--program=dhs,mics", "--release=113,114", "--shard-index=1",
    "--shard-count=2", "--max-files=1", "--timeout-seconds=9", "--retry"
))
selected <- fertility_filter_inventory(inventory, options)
stopifnot(nrow(selected) == 1L, selected$id[[1L]] == "F0003",
          options$timeout_seconds == 9L, options$retry)
expect_error(fertility_parse_arguments("--shard-count=2"), "supplied together")
expect_error(fertility_parse_arguments("--timeout-seconds=0"), "positive integer")
expect_error(fertility_parse_arguments("--beyond-end-windows=9"), "must not exceed 8")
encoding_options <- fertility_parse_arguments(c(
    "--encoding-override=F0003:latin1,F0001:UTF8",
    "--encoding-override=F0002:CP1252"
))
stopifnot(
    identical(encoding_options$encoding_overrides, c(
        F0001 = "UTF-8", F0002 = "Windows-1252", F0003 = "ISO-8859-1"
    )),
    identical(
        fertility_encoding_overrides_text(encoding_options$encoding_overrides),
        "F0001:UTF-8,F0002:Windows-1252,F0003:ISO-8859-1"
    )
)
expect_error(fertility_parse_arguments(
    c("--encoding-override=F0001:UTF-8", "--encoding-override=F0001:latin1")
), "duplicate")
expect_error(fertility_parse_arguments("--encoding-override=F0001:KOI8-R"),
             "unsupported encoding")
expect_error(fertility_parse_arguments("--encoding-override=bad:UTF-8"),
             "invalid.*ID")
expect_error(fertility_parse_arguments("--encoding-override=F0001"),
             "form F0001")
expect_error(fertility_filter_inventory(
    inventory, fertility_parse_arguments("--id=F9999")
), "unknown --id")
shard_options <- fertility_parse_arguments(c("--shard-index=1", "--shard-count=2"))
shard_one <- fertility_filter_inventory(inventory, shard_options)
shard_options$shard_index <- 2L
shard_two <- fertility_filter_inventory(inventory, shard_options)
stopifnot(!length(intersect(shard_one$id, shard_two$id)),
          identical(sort(c(shard_one$id, shard_two$id)), sort(inventory$id)),
          nrow(fertility_family_selection(inventory, shard_options)) == nrow(inventory))
expect_error(fertility_validate_encoding_overrides(
    c(F0003 = "UTF-8"),
    fertility_family_selection(
        inventory, fertility_parse_arguments("--id=F0001,F0002")
    )
), "outside the complete selected family")
family_a <- fertility_parse_arguments(c("--program=dhs,mics", "--shard-index=1",
                                        "--shard-count=2"))
family_b <- fertility_parse_arguments(c("--program=mics,dhs", "--shard-index=2",
                                        "--shard-count=2"))
stopifnot(identical(
    fertility_selection_family_id(inventory, family_a, "framework", "config", "build"),
    fertility_selection_family_id(inventory, family_b, "framework", "config", "build")
))

test_framework_id <- paste(rep("a", 64L), collapse = "")
test_build_id <- paste(rep("b", 64L), collapse = "")
test_config_id <- paste(rep("c", 64L), collapse = "")
make_public_results <- function(expected, classifications = "pass") {
    count <- nrow(expected)
    if (length(classifications) == 1L) classifications <- rep(classifications, count)
    data.frame(
        framework_id = rep(test_framework_id, count), id = expected$id,
        program = expected$program, level = expected$level,
        release = as.character(expected$release), classification = classifications,
        secondary_categories = rep("", count), mismatch_count = rep("0", count),
        mismatch_categories = rep("", count), mismatch_signatures = rep("", count),
        rows = rep("", count), columns = rep("", count),
        tiles_expected = rep("0", count), tiles_completed = rep("0", count),
        complete = rep("TRUE", count), elapsed_seconds = rep("", count),
        build_provenance_id = rep(test_build_id, count),
        stringsAsFactors = FALSE, check.names = FALSE
    )
}
make_bundle_family <- function(
    canonical, family_options, classifications = NULL,
    inventory_id = paste(rep("d", 64L), collapse = ""), acceptance = NULL
) {
    manifest <- fertility_family_manifest(canonical, family_options)
    manifest_id <- fertility_manifest_id(manifest)
    family_config_id <- fertility_tile_configuration(
        family_options, acceptance
    )$config_id
    family_id <- fertility_family_id_from_manifest(
        manifest, test_framework_id, family_config_id, test_build_id, inventory_id,
        family_options$shard_count, family_options$max_files
    )
    spec <- fertility_filter_spec(family_options)
    bundles <- lapply(seq_len(family_options$shard_count), function(index) {
        expected <- manifest[manifest$shard_index == index,
                             c("id", "program", "level", "release"), drop = FALSE]
        classes <- if (is.null(classifications)) "pass" else
            classifications[match(expected$id, manifest$id)]
        results <- make_public_results(expected, classes)
        selection_id <- fertility_stable_id(list(
            family_id = family_id, shard_index = index,
            selected_ids = paste(expected$id, collapse = ",")
        ))
        input_attestation_id <- fertility_stable_id(list(
            synthetic_shard = index, ids = paste(expected$id, collapse = ",")
        ))
        acceptance_authority <- if (is.null(acceptance)) "" else
            acceptance$authority
        acceptance_commitment_id <- if (is.null(acceptance)) "" else
            acceptance$commitment_id
        evidence_selection_id <- fertility_evidence_selection_id(
            selection_id, input_attestation_id, "fresh-execution",
            fertility_schema_version, fertility_report_schema_id(),
            acceptance_authority, acceptance_commitment_id
        )
        provenance <- data.frame(
            schema_version = as.character(fertility_schema_version),
            report_schema_version = as.character(fertility_report_schema_version),
            evidence_origin = "fresh-execution",
            source_corpus_schema_version = as.character(fertility_schema_version),
            replayed_at_utc = "", acceptance_authority = acceptance_authority,
            acceptance_commitment_id = acceptance_commitment_id,
            acceptance_artifact_sha256 = if (is.null(acceptance)) "" else
                acceptance$artifact_sha256,
            selection_id = selection_id,
            evidence_selection_id = evidence_selection_id,
            input_attestation_id = input_attestation_id, family_id = family_id,
            family_manifest_id = manifest_id, framework_id = test_framework_id,
            config_id = family_config_id, build_provenance_id = test_build_id,
            inventory_id = inventory_id, report_schema_id = fertility_report_schema_id(),
            selected_files = as.character(nrow(expected)),
            expected_family_files = as.character(nrow(manifest)),
            full_default_family = if (fertility_full_default_family(family_options))
                "TRUE" else "FALSE",
            program_filter = spec$program_filter, release_filter = spec$release_filter,
            id_filter = spec$id_filter,
            encoding_overrides = fertility_encoding_overrides_text(
                family_options$encoding_overrides
            ),
            max_files = spec$max_files,
            shard_index = as.character(index),
            shard_count = as.character(family_options$shard_count),
            timeout_seconds = "600", chunk_rows = "10000", column_batch = "16",
            memory_mib = "256", cell_budget = "1000000",
            max_tiles_per_batch = "100000", beyond_end_windows = "1",
            retry = "FALSE", created_at_utc = "2026-01-01T00:00:00Z",
            stringsAsFactors = FALSE, check.names = FALSE
        )
        list(provenance = provenance, results = results,
             family_manifest = manifest)
    })
    list(id = family_id, bundles = bundles, manifest = manifest)
}
canonical_inventory <- fertility_inventory_manifest(inventory)
merge_options <- fertility_parse_arguments(c(
    "--id=F0001,F0002", "--shard-index=1", "--shard-count=2"
))
merge_fixture <- make_bundle_family(canonical_inventory, merge_options)
merge_bundles <- merge_fixture$bundles
validated_merge <- fertility_validate_shard_bundles(
    merge_bundles, merge_fixture$id, canonical_inventory
)
stopifnot(identical(validated_merge$results$id, c("F0001", "F0002")),
          validated_merge$shard_count == 2L)
current_family_files <- c(
    provenance = "run-provenance.tsv", results = "results.tsv",
    family_manifest = "family-manifest.tsv"
)
write_current_report <- function(name, bundle, run_name = "bundle") {
    parent <- file.path(root, name)
    run <- file.path(parent, run_name)
    dir.create(run, recursive = TRUE)
    fertility_atomic_write_table(
        bundle$provenance, file.path(run, current_family_files[["provenance"]])
    )
    fertility_atomic_write_table(
        bundle$results, file.path(run, current_family_files[["results"]])
    )
    fertility_atomic_write_table(
        bundle$family_manifest,
        file.path(run, current_family_files[["family_manifest"]])
    )
    writeLines(run_name, file.path(parent, "CURRENT"))
    parent
}
load_current_report <- function(parent, family_id) {
    current <- fertility_current_bundle_for_family(
        parent, family_id, current_family_files, "synthetic report shard"
    )
    if (is.null(current)) return(NULL)
    lapply(current$paths, function(path) read.delim(
        path, colClasses = "character", check.names = FALSE
    ))
}
valid_report_parents <- lapply(seq_along(merge_bundles), function(index) {
    write_current_report(paste0("merge-valid-", index), merge_bundles[[index]])
})
loaded_valid_reports <- lapply(
    valid_report_parents, load_current_report, family_id = merge_fixture$id
)
valid_current_merge <- fertility_validate_shard_bundles(
    loaded_valid_reports, merge_fixture$id, canonical_inventory
)
stopifnot(
    identical(valid_current_merge$results$id, c("F0001", "F0002")),
    valid_current_merge$shard_count == 2L
)
stale_report_parent <- file.path(root, "merge-stale-bundle")
dir.create(stale_report_parent)
writeLines("removed-bundle", file.path(stale_report_parent, "CURRENT"))
stopifnot(is.null(load_current_report(stale_report_parent, merge_fixture$id)))
unrelated_bundle <- merge_bundles[[1L]]
unrelated_bundle$provenance$family_id <- paste(rep("0", 64L), collapse = "")
unrelated_missing_parent <- write_current_report(
    "merge-unrelated-missing-file", unrelated_bundle
)
unlink(file.path(unrelated_missing_parent, "bundle", "results.tsv"))
stopifnot(is.null(load_current_report(
    unrelated_missing_parent, merge_fixture$id
)))
matching_missing_parent <- write_current_report(
    "merge-matching-missing-file", merge_bundles[[1L]]
)
unlink(file.path(matching_missing_parent, "bundle", "results.tsv"))
expect_error(load_current_report(
    matching_missing_parent, merge_fixture$id
), "No such file|results must be an existing regular file")
matching_tampered_parent <- write_current_report(
    "merge-matching-tampered-file", merge_bundles[[1L]]
)
tampered_results_path <- file.path(
    matching_tampered_parent, "bundle", "results.tsv"
)
tampered_results <- read.delim(
    tampered_results_path, colClasses = "character", check.names = FALSE
)
tampered_results$id[[1L]] <- "F9999"
fertility_atomic_write_table(tampered_results, tampered_results_path)
expect_error(fertility_validate_shard_bundles(
    list(
        load_current_report(matching_tampered_parent, merge_fixture$id),
        loaded_valid_reports[[2L]]
    ),
    merge_fixture$id, canonical_inventory
), "shard results do not match canonical family membership")
escape_report_parent <- write_current_report(
    "merge-current-escape", unrelated_bundle
)
writeLines("../bundle", file.path(escape_report_parent, "CURRENT"))
expect_error(load_current_report(
    escape_report_parent, merge_fixture$id
), "CURRENT pointer is invalid")
symlink_report_parent <- file.path(root, "merge-bundle-symlink")
dir.create(symlink_report_parent)
writeLines("bundle", file.path(symlink_report_parent, "CURRENT"))
stopifnot(file.symlink(
    file.path(valid_report_parents[[1L]], "bundle"),
    file.path(symlink_report_parent, "bundle")
))
expect_error(load_current_report(
    symlink_report_parent, merge_fixture$id
), "bundle must not be a symlink")
provenance_symlink_parent <- write_current_report(
    "merge-provenance-symlink", unrelated_bundle
)
provenance_path <- file.path(
    provenance_symlink_parent, "bundle", "run-provenance.tsv"
)
unlink(provenance_path)
stopifnot(file.symlink(
    file.path(valid_report_parents[[1L]], "bundle", "run-provenance.tsv"),
    provenance_path
))
expect_error(load_current_report(
    provenance_symlink_parent, merge_fixture$id
), "provenance must not be a symlink")
legacy_provenance_bundles <- merge_bundles
for (index in seq_along(legacy_provenance_bundles)) {
    legacy_provenance_bundles[[index]]$provenance[c(
        "acceptance_authority", "acceptance_commitment_id",
        "acceptance_artifact_sha256"
    )] <- NULL
}
stopifnot(is.list(fertility_validate_shard_bundles(
    legacy_provenance_bundles, merge_fixture$id, canonical_inventory
)))
override_merge_options <- fertility_parse_arguments(c(
    "--id=F0001,F0002", "--shard-index=1", "--shard-count=2",
    "--encoding-override=F0001:ISO-8859-1"
))
override_merge_fixture <- make_bundle_family(
    canonical_inventory, override_merge_options
)
stopifnot(is.list(fertility_validate_shard_bundles(
    override_merge_fixture$bundles, override_merge_fixture$id, canonical_inventory
)))
foreign_override <- override_merge_fixture$bundles
foreign_override[[2L]]$provenance$encoding_overrides <- ""
expect_error(fertility_validate_shard_bundles(
    foreign_override, override_merge_fixture$id, canonical_inventory
), "identical framework/config/build/inventory")
false_origin <- merge_bundles
false_origin[[1L]]$provenance$evidence_origin <- "historical-schema-10-replay"
expect_error(fertility_validate_shard_bundles(
    false_origin, merge_fixture$id, canonical_inventory
), "false claim|identical framework/config/build/inventory")
historical_non_eight <- merge_bundles
historical_config <- fertility_tile_configuration(fertility_parse_arguments(c(
    "--shard-index=1", "--shard-count=8", "--timeout-seconds=600",
    "--chunk-rows=50000", "--column-batch=32", "--memory-mib=1024",
    "--cell-budget=10000000", "--max-tiles-per-batch=100000",
    "--beyond-end-windows=1"
)))
historical_family_id <- fertility_family_id_from_manifest(
    merge_fixture$manifest, test_framework_id, historical_config$config_id,
    test_build_id, historical_non_eight[[1L]]$provenance$inventory_id[[1L]],
    2L, Inf, fertility_report_schema_id(), "historical-schema-10-replay",
    fertility_legacy_corpus_schema_version
)
for (index in seq_along(historical_non_eight)) {
    provenance <- historical_non_eight[[index]]$provenance
    selected_ids <- historical_non_eight[[index]]$results$id
    selection_id <- fertility_stable_id(list(
        family_id = historical_family_id, shard_index = index,
        selected_ids = paste(selected_ids, collapse = ",")
    ))
    provenance$evidence_origin <- "historical-schema-10-replay"
    provenance$source_corpus_schema_version <-
        as.character(fertility_legacy_corpus_schema_version)
    provenance$replayed_at_utc <- "2026-01-01T00:00:00Z"
    provenance$family_id <- historical_family_id
    provenance$config_id <- historical_config$config_id
    provenance$selection_id <- selection_id
    provenance$evidence_selection_id <- fertility_evidence_selection_id(
        selection_id, provenance$input_attestation_id[[1L]],
        provenance$evidence_origin[[1L]],
        fertility_legacy_corpus_schema_version, fertility_report_schema_id()
    )
    provenance$timeout_seconds <- "600"
    provenance$chunk_rows <- "50000"
    provenance$column_batch <- "32"
    provenance$memory_mib <- "1024"
    provenance$cell_budget <- "10000000"
    provenance$max_tiles_per_batch <- "100000"
    provenance$beyond_end_windows <- "1"
    historical_non_eight[[index]]$provenance <- provenance
}
expect_error(fertility_validate_shard_bundles(
    historical_non_eight, historical_family_id, canonical_inventory
), "exact eight-shard run")
false_attestation <- merge_bundles
false_attestation[[1L]]$provenance$input_attestation_id <- paste(rep("f", 64L), collapse = "")
expect_error(fertility_validate_shard_bundles(
    false_attestation, merge_fixture$id, canonical_inventory
), "evidence selection identity")
expect_error(fertility_validate_shard_bundles(
    merge_bundles[1L], merge_fixture$id, canonical_inventory
), "every shard index")
substitution <- merge_bundles
substitution[[1L]]$results$id <- "F0003"
expect_error(fertility_validate_shard_bundles(
    substitution, merge_fixture$id, canonical_inventory
), "canonical family membership")
foreign_config <- merge_bundles
foreign_config[[2L]]$provenance$config_id <- paste(rep("d", 64L), collapse = "")
expect_error(fertility_validate_shard_bundles(
    foreign_config, merge_fixture$id, canonical_inventory
), "identical framework/config/build/inventory")
wrong_filter <- merge_bundles
wrong_filter[[2L]]$provenance$id_filter <- "F0001"
expect_error(fertility_validate_shard_bundles(
    wrong_filter, merge_fixture$id, canonical_inventory
), "identical framework/config/build/inventory")
wrong_release <- merge_bundles
wrong_release[[2L]]$results$release <- "118"
expect_error(fertility_validate_shard_bundles(
    wrong_release, merge_fixture$id, canonical_inventory
), "canonical family membership")
wrong_classification <- merge_bundles
wrong_classification[[1L]]$results$classification <- "private-reader-message"
expect_error(fertility_validate_shard_bundles(
    wrong_classification, merge_fixture$id, canonical_inventory
), "invalid scalar")
privacy_path <- merge_bundles
privacy_path[[1L]]$results$path <- "/private/source"
expect_error(fertility_validate_shard_bundles(
    privacy_path, merge_fixture$id, canonical_inventory
), "exact public schema|manifest schema")
privacy_reader <- merge_bundles
privacy_reader[[1L]]$results$reader_error <- "private error"
expect_error(fertility_validate_shard_bundles(
    privacy_reader, merge_fixture$id, canonical_inventory
), "exact public schema|manifest schema")
privacy_allowed_field <- merge_bundles
privacy_allowed_field[[1L]]$results$secondary_categories <-
    "reader failed at /private/source"
expect_error(fertility_validate_shard_bundles(
    privacy_allowed_field, merge_fixture$id, canonical_inventory
), "non-public mismatch detail")
private_program <- merge_bundles
private_program[[1L]]$results$program <- "private_identifier"
expect_error(fertility_validate_shard_bundles(
    private_program, merge_fixture$id, canonical_inventory
), "invalid scalar")
inconsistent_mismatch <- merge_bundles
inconsistent_mismatch[[1L]]$results$mismatch_categories <- "value-mismatch=1"
expect_error(fertility_validate_shard_bundles(
    inconsistent_mismatch, merge_fixture$id, canonical_inventory
), "inconsistent counts")
duplicate_mismatch <- merge_bundles
duplicate_mismatch[[1L]]$results$mismatch_count <- "2"
duplicate_mismatch[[1L]]$results$mismatch_categories <-
    "value-mismatch=1,value-mismatch=1"
duplicate_mismatch[[1L]]$results$mismatch_signatures <- paste0(
    paste(rep("a", 64L), collapse = ""), "=2"
)
expect_error(fertility_validate_shard_bundles(
    duplicate_mismatch, merge_fixture$id, canonical_inventory
), "inconsistent counts")
noncanonical_mismatch <- merge_bundles
noncanonical_mismatch[[1L]]$results$mismatch_count <- "3"
noncanonical_mismatch[[1L]]$results$mismatch_categories <-
    "value-mismatch=1,metadata-mismatch=2"
noncanonical_mismatch[[1L]]$results$mismatch_signatures <- paste0(
    paste(rep("a", 64L), collapse = ""), "=1,",
    paste(rep("b", 64L), collapse = ""), "=2"
)
expect_error(fertility_validate_shard_bundles(
    noncanonical_mismatch, merge_fixture$id, canonical_inventory
), "inconsistent counts")
privacy_provenance <- merge_bundles
privacy_provenance[[1L]]$provenance$path <- "/private/source"
expect_error(fertility_validate_shard_bundles(
    privacy_provenance, merge_fixture$id, canonical_inventory
), "provenance schema")
prior_report_schema_id <- fertility_report_schema_id(
    fertility_legacy_report_schema_version
)
stopifnot(
    !identical(prior_report_schema_id, fertility_report_schema_id()),
    fertility_report_schema_version != fertility_schema_version
)
wrong_report_schema <- merge_bundles
wrong_report_schema[[1L]]$provenance$report_schema_id <- prior_report_schema_id
expect_error(fertility_validate_shard_bundles(
    wrong_report_schema, merge_fixture$id, canonical_inventory
), "identical framework/config/build/inventory|schema identity")
wrong_report_version <- merge_bundles
wrong_report_version[[1L]]$provenance$report_schema_version <-
    as.character(fertility_legacy_report_schema_version)
expect_error(fertility_validate_shard_bundles(
    wrong_report_version, merge_fixture$id, canonical_inventory
), "invalid scalar|identical framework/config/build/inventory")
missing_report_version <- merge_bundles
missing_report_version[[1L]]$provenance$report_schema_version <- NULL
expect_error(fertility_validate_shard_bundles(
    missing_report_version, merge_fixture$id, canonical_inventory
), "provenance schema")
substituted_manifest <- merge_bundles
substituted_manifest[[1L]]$family_manifest$id[[1L]] <- "F0003"
expect_error(fertility_validate_shard_bundles(
    substituted_manifest, merge_fixture$id, canonical_inventory
), "family manifest")
reordered_manifest <- merge_bundles
reordered_manifest[[1L]]$family_manifest <-
    reordered_manifest[[1L]]$family_manifest[2:1, , drop = FALSE]
expect_error(fertility_validate_shard_bundles(
    reordered_manifest, merge_fixture$id, canonical_inventory
), "family manifest")
wrong_manifest_owner <- merge_bundles
wrong_manifest_owner[[1L]]$family_manifest$shard_index[[1L]] <- 2L
expect_error(fertility_validate_shard_bundles(
    wrong_manifest_owner, merge_fixture$id, canonical_inventory
), "family manifest")
wrong_manifest_program <- merge_bundles
wrong_manifest_program[[1L]]$family_manifest$program[[1L]] <- "mics"
expect_error(fertility_validate_shard_bundles(
    wrong_manifest_program, merge_fixture$id, canonical_inventory
), "family manifest")
wrong_manifest_level <- merge_bundles
wrong_manifest_level[[1L]]$family_manifest$level[[1L]] <- "births"
expect_error(fertility_validate_shard_bundles(
    wrong_manifest_level, merge_fixture$id, canonical_inventory
), "family manifest")
wrong_manifest_release <- merge_bundles
wrong_manifest_release[[1L]]$family_manifest$release[[1L]] <- 118L
expect_error(fertility_validate_shard_bundles(
    wrong_manifest_release, merge_fixture$id, canonical_inventory
), "family manifest")
empty_options <- fertility_parse_arguments(c(
    "--id=F0001", "--shard-index=1", "--shard-count=2"
))
empty_fixture <- make_bundle_family(canonical_inventory, empty_options)
stopifnot(nrow(fertility_validate_shard_bundles(
    empty_fixture$bundles, empty_fixture$id, canonical_inventory
)$results) == 1L)

full_releases <- rep(as.integer(names(fertility_expected_releases)),
                     as.integer(fertility_expected_releases))
full_canonical <- data.frame(
    id = sprintf("F%04d", seq_len(fertility_expected_rows)),
    program = "dhs", level = "women", release = full_releases,
    stringsAsFactors = FALSE
)
full_options <- fertility_parse_arguments(character())
full_classes <- rep("pass", fertility_expected_rows)
full_classes[full_releases == 111L] <- "expected-unsupported-111"
supported_positions <- which(full_releases != 111L)
full_classes[match(fertility_accepted_ids(), full_canonical$id)] <-
    "inventory-hash-error"
full_fixture <- make_bundle_family(
    full_canonical, full_options, full_classes,
    inventory_id = paste(rep("e", 64L), collapse = "")
)
for (index in seq_along(full_fixture$bundles)) {
    hash_rows <- full_fixture$bundles[[index]]$results$classification ==
        "inventory-hash-error"
    full_fixture$bundles[[index]]$results$secondary_categories[hash_rows] <-
        "signature-mismatch"
}
full_validated <- fertility_validate_shard_bundles(
    full_fixture$bundles, full_fixture$id, full_canonical
)
stopifnot(nrow(full_validated$results) == 1004L,
          sum(full_validated$results$classification == "inventory-hash-error") == 5L)
full_missing <- full_fixture$bundles
full_missing[[1L]]$results <- full_missing[[1L]]$results[-1004L, , drop = FALSE]
expect_error(fertility_validate_shard_bundles(
    full_missing, full_fixture$id, full_canonical
), "count|accounting")
full_bad_release <- full_fixture$bundles
full_bad_release[[1L]]$results$release[[131L]] <- "114"
expect_error(fertility_validate_shard_bundles(
    full_bad_release, full_fixture$id, full_canonical
), "canonical family membership")
full_bad_unsupported <- full_fixture$bundles
full_bad_unsupported[[1L]]$results$classification[[1L]] <- "pass"
expect_error(fertility_validate_shard_bundles(
    full_bad_unsupported, full_fixture$id, full_canonical
), "release 111 classifications")
full_bad_hash_count <- full_fixture$bundles
additional_supported <- supported_positions[
    !full_canonical$id[supported_positions] %in% fertility_accepted_ids()
][[1L]]
full_bad_hash_count[[1L]]$results$classification[[additional_supported]] <-
    "inventory-hash-error"
expect_error(fertility_validate_shard_bundles(
    full_bad_hash_count, full_fixture$id, full_canonical
), "executable accounting")
full_too_few_hashes <- full_fixture$bundles
full_too_few_hashes[[1L]]$results$classification[[
    match(fertility_accepted_ids()[[1L]], full_canonical$id)
]] <- "pass"
expect_error(fertility_validate_shard_bundles(
    full_too_few_hashes, full_fixture$id, full_canonical
), "executable accounting")
full_bad_supported_class <- full_fixture$bundles
full_bad_supported_class[[1L]]$results$classification[[additional_supported]] <-
    "expected-unsupported-111"
expect_error(fertility_validate_shard_bundles(
    full_bad_supported_class, full_fixture$id, full_canonical
), "executable accounting")

output_releases <- rep(
    as.integer(names(fertility_output_expected_releases)),
    as.integer(fertility_output_expected_releases)
)
output_levels <- rep(
    names(fertility_output_expected_levels),
    as.integer(fertility_output_expected_levels)
)
output_canonical <- data.frame(
    id = sprintf("F%04d", seq_len(fertility_output_expected_files)),
    program = "output", level = output_levels, release = output_releases,
    stringsAsFactors = FALSE
)
output_options <- fertility_parse_arguments(c(
    "--program=output", "--shard-index=1", "--shard-count=8"
))
stopifnot(fertility_full_output_family(output_options),
          fertility_full_default_family(output_options),
          !fertility_full_default_family(fertility_parse_arguments(c(
              "--program=output", "--release=118"
          ))))
output_classes <- rep("pass", fertility_output_expected_files)
output_classes[output_releases == 111L] <- "expected-unsupported-111"
output_fixture <- make_bundle_family(
    output_canonical, output_options, output_classes,
    inventory_id = paste(rep("a", 64L), collapse = "")
)
output_fixture$bundles <- lapply(output_fixture$bundles, function(bundle) {
    supported_rows <- bundle$results$release != "111"
    bundle$results$tiles_expected[supported_rows] <- "1"
    bundle$results$tiles_completed[supported_rows] <- "1"
    bundle
})
output_validated <- fertility_validate_shard_bundles(
    output_fixture$bundles, output_fixture$id, output_canonical
)
stopifnot(output_validated$full_default,
          nrow(output_validated$results) == fertility_output_expected_files)
supported_bundle <- which(vapply(output_fixture$bundles, function(bundle) {
    "F0131" %in% bundle$results$id
}, logical(1)))[[1L]]
supported_row <- match("F0131", output_fixture$bundles[[supported_bundle]]$results$id)
expected_output_terminal_classifications <- c(
    "pass", "direct-vs-rust-mismatch", "dtaparser-only-error",
    "haven-only-error", "shared-reader-error", "metadata-mismatch",
    "value-mismatch", "tag-mismatch", "date-mismatch",
    "encoding-mismatch", "row-termination-mismatch",
    "known-intentional-divergence"
)
stopifnot(identical(
    fertility_output_terminal_classifications(),
    expected_output_terminal_classifications
))
for (classification in expected_output_terminal_classifications) {
    output_allowed <- output_fixture$bundles
    output_allowed[[supported_bundle]]$results$classification[[supported_row]] <-
        classification
    stopifnot(nrow(fertility_validate_shard_bundles(
        output_allowed, output_fixture$id, output_canonical
    )$results) == fertility_output_expected_files)
}
output_bad_unsupported <- output_fixture$bundles
output_bad_unsupported[[1L]]$results$classification[[1L]] <- "pass"
expect_error(fertility_validate_shard_bundles(
    output_bad_unsupported, output_fixture$id, output_canonical
), "unsupported-release classifications")
output_bad_terminal <- output_fixture$bundles
output_bad_terminal[[supported_bundle]]$results$classification[[supported_row]] <-
    "timeout"
expect_error(fertility_validate_shard_bundles(
    output_bad_terminal, output_fixture$id, output_canonical
), "executable accounting")
output_terminal_reader_error <- output_fixture$bundles
output_terminal_reader_error[[supported_bundle]]$results$classification[[supported_row]] <-
    "haven-only-error"
output_terminal_reader_error[[supported_bundle]]$results$complete[[supported_row]] <-
    "FALSE"
stopifnot(nrow(fertility_validate_shard_bundles(
    output_terminal_reader_error, output_fixture$id, output_canonical
)$results) == fertility_output_expected_files)
output_bad_tile_accounting <- output_terminal_reader_error
output_bad_tile_accounting[[supported_bundle]]$results$tiles_completed[[supported_row]] <-
    "0"
expect_error(fertility_validate_shard_bundles(
    output_bad_tile_accounting, output_fixture$id, output_canonical
), "executable accounting")
output_bad_complete <- output_fixture$bundles
output_bad_complete[[supported_bundle]]$results$complete[[supported_row]] <- "FALSE"
expect_error(fertility_validate_shard_bundles(
    output_bad_complete, output_fixture$id, output_canonical
), "executable accounting")
output_bad_release_canonical <- output_canonical
output_bad_release_canonical$release[[131L]] <- 118L
output_bad_release_fixture <- make_bundle_family(
    output_bad_release_canonical, output_options, output_classes,
    inventory_id = paste(rep("b", 64L), collapse = "")
)
expect_error(fertility_validate_shard_bundles(
    output_bad_release_fixture$bundles, output_bad_release_fixture$id,
    output_bad_release_canonical
), "release counts")
output_bad_level_canonical <- output_canonical
output_bad_level_canonical$level[[9L]] <- "aggregate"
output_bad_level_fixture <- make_bundle_family(
    output_bad_level_canonical, output_options, output_classes,
    inventory_id = paste(rep("c", 64L), collapse = "")
)
expect_error(fertility_validate_shard_bundles(
    output_bad_level_fixture$bundles, output_bad_level_fixture$id,
    output_bad_level_canonical
), "level counts")

publication_na <- make_public_results(output_canonical[1L, , drop = FALSE],
                                      "expected-unsupported-111")
publication_na$rows <- NA_character_
publication_na$columns <- NA_character_
publication_na$elapsed_seconds <- NA_character_
publication_na <- fertility_publication_frame(publication_na)
stopifnot(!anyNA(publication_na), publication_na$rows[[1L]] == "",
          publication_na$columns[[1L]] == "",
          publication_na$elapsed_seconds[[1L]] == "")
publication_na_root <- file.path(root, "publication-na")
dir.create(publication_na_root)
fertility_atomic_write_table(
    publication_na, file.path(publication_na_root, "results.tsv")
)
stopifnot(identical(
    fertility_validate_exact_table_bundle(
        publication_na_root, c(results = "results.tsv"),
        list(results = publication_na), "NA publication regression"
    )$results,
    fertility_character_frame(publication_na)
))

stopifnot(nrow(fertility_validate_canonical_inventory(
    full_canonical, exact = TRUE
)) == fertility_expected_rows)
expect_error(fertility_validate_canonical_inventory(
    full_canonical[-1L, , drop = FALSE], exact = TRUE
), "exactly F0001 through F1004")
full_extra <- rbind(full_canonical, transform(
    full_canonical[1004L, , drop = FALSE], id = "F1005"
))
expect_error(fertility_validate_canonical_inventory(
    full_extra, exact = TRUE
), "exactly F0001 through F1004")
full_reordered <- full_canonical[c(2L, 1L, 3:nrow(full_canonical)), , drop = FALSE]
expect_error(fertility_validate_canonical_inventory(
    full_reordered, exact = TRUE
), "exactly F0001 through F1004")
full_duplicate <- full_canonical
full_duplicate$id[[2L]] <- full_duplicate$id[[1L]]
expect_error(fertility_validate_canonical_inventory(
    full_duplicate, exact = TRUE
), "manifest is invalid")
full_canonical_bad_release <- full_canonical
full_canonical_bad_release$release[[131L]] <- 114L
expect_error(fertility_validate_canonical_inventory(
    full_canonical_bad_release, exact = TRUE
), "release counts")
legacy_snapshot <- file.path(root, "legacy-framework-snapshot")
dir.create(legacy_snapshot)
fertility_atomic_write_table(
    full_canonical, file.path(legacy_snapshot, "inventory-manifest.tsv")
)
legacy_inventory_provenance <- data.frame(
    schema_version = fertility_schema_version, framework_id = test_framework_id,
    inventory_id = paste(rep("e", 64L), collapse = ""),
    inventory_manifest_id = fertility_manifest_id(full_canonical),
    report_schema_id = fertility_report_schema_id(
        fertility_legacy_report_schema_version
    ), files = nrow(full_canonical), stringsAsFactors = FALSE, check.names = FALSE
)
fertility_atomic_write_table(
    legacy_inventory_provenance,
    file.path(legacy_snapshot, "inventory-manifest-provenance.tsv")
)
stopifnot(nrow(fertility_framework_inventory(
    legacy_snapshot, framework_id = test_framework_id,
    report_schema_version = fertility_legacy_report_schema_version
)$manifest) == fertility_expected_rows)
expect_error(fertility_framework_inventory(
    legacy_snapshot, framework_id = test_framework_id
), "provenance is invalid")
stale_legacy_provenance <- legacy_inventory_provenance
stale_legacy_provenance$report_schema_id <- fertility_report_schema_id()
fertility_atomic_write_table(
    stale_legacy_provenance,
    file.path(legacy_snapshot, "inventory-manifest-provenance.tsv")
)
expect_error(fertility_framework_inventory(
    legacy_snapshot, framework_id = test_framework_id,
    report_schema_version = fertility_legacy_report_schema_version
), "provenance is invalid")
fertility_atomic_write_table(
    legacy_inventory_provenance,
    file.path(legacy_snapshot, "inventory-manifest-provenance.tsv")
)
current_snapshot <- file.path(root, "current-framework-snapshot")
dir.create(current_snapshot)
fertility_atomic_write_table(
    full_canonical, file.path(current_snapshot, "inventory-manifest.tsv")
)
current_inventory_provenance <- data.frame(
    schema_version = fertility_schema_version,
    report_schema_version = fertility_report_schema_version,
    framework_id = test_framework_id,
    inventory_id = paste(rep("e", 64L), collapse = ""),
    inventory_manifest_id = fertility_manifest_id(full_canonical),
    report_schema_id = fertility_report_schema_id(), files = nrow(full_canonical),
    stringsAsFactors = FALSE, check.names = FALSE
)
fertility_atomic_write_table(
    current_inventory_provenance,
    file.path(current_snapshot, "inventory-manifest-provenance.tsv")
)
stopifnot(nrow(fertility_framework_inventory(
    current_snapshot, framework_id = test_framework_id
)$manifest) == fertility_expected_rows)
framework_acceptance_path <- file.path(
    current_snapshot, "acceptance-provenance.tsv"
)
fertility_atomic_write_table(data.frame(
    authority = fertility_acceptance_authority(),
    commitment_id = paste(rep("a", 64L), collapse = ""),
    artifact_sha256 = paste(rep("b", 64L), collapse = ""),
    stringsAsFactors = FALSE, check.names = FALSE
), framework_acceptance_path)
stopifnot(!is.null(fertility_framework_inventory(
    current_snapshot, framework_id = test_framework_id
)$acceptance_provenance))
for (name in c(
    "inventory-manifest.tsv", "inventory-manifest-provenance.tsv",
    "acceptance-provenance.tsv"
)) {
    path <- file.path(current_snapshot, name)
    saved <- paste0(path, ".saved")
    stopifnot(file.rename(path, saved), file.symlink(saved, path))
    expect_error(fertility_framework_inventory(
        current_snapshot, framework_id = test_framework_id
    ), "symlink")
    unlink(path)
    stopifnot(file.rename(saved, path))
}
current_snapshot_saved <- paste0(current_snapshot, ".saved")
stopifnot(file.rename(current_snapshot, current_snapshot_saved),
          file.symlink(current_snapshot_saved, current_snapshot))
expect_error(fertility_framework_inventory(
    current_snapshot, framework_id = test_framework_id
), "symlink")
unlink(current_snapshot)
stopifnot(file.rename(current_snapshot_saved, current_snapshot))
framework_confinement_root <- file.path(confinement_raw, "framework")
framework_confinement_snapshot <- file.path(
    framework_confinement_root, test_framework_id
)
dir.create(framework_confinement_snapshot, recursive = TRUE)
for (name in c("common.R", "accepted.R", "worker.R", "compare.R", "runtime.R")) {
    stopifnot(file.copy(
        file.path(script_dir, name), file.path(framework_confinement_snapshot, name)
    ))
}
fertility_atomic_write_table(
    full_canonical,
    file.path(framework_confinement_snapshot, "inventory-manifest.tsv")
)
fertility_atomic_write_table(
    current_inventory_provenance,
    file.path(framework_confinement_snapshot,
              "inventory-manifest-provenance.tsv")
)
stopifnot(identical(fertility_verify_framework_snapshot(
    script_dir, confinement_raw, test_framework_id
), framework_confinement_snapshot))
for (name in c("common.R", "accepted.R", "worker.R", "compare.R", "runtime.R")) {
    path <- file.path(framework_confinement_snapshot, name)
    saved <- file.path(root, paste0("framework-", name, ".saved"))
    stopifnot(file.rename(path, saved), file.symlink(saved, path))
    expect_error(fertility_verify_framework_snapshot(
        script_dir, confinement_raw, test_framework_id
    ), "symlink")
    unlink(path)
    stopifnot(file.rename(saved, path))
}
fresh_snapshot_provenance <- data.frame(
    evidence_origin = "fresh-execution",
    source_corpus_schema_version = as.character(fertility_schema_version),
    stringsAsFactors = FALSE
)
historical_snapshot_provenance <- data.frame(
    evidence_origin = "historical-schema-10-replay",
    source_corpus_schema_version =
        as.character(fertility_legacy_corpus_schema_version),
    stringsAsFactors = FALSE
)
stopifnot(
    identical(
        fertility_snapshot_report_schema_version(fresh_snapshot_provenance),
        fertility_report_schema_version
    ),
    identical(
        fertility_snapshot_report_schema_version(historical_snapshot_provenance),
        fertility_legacy_report_schema_version
    ),
    nrow(fertility_framework_inventory(
        legacy_snapshot, framework_id = test_framework_id,
        report_schema_version = fertility_snapshot_report_schema_version(
            historical_snapshot_provenance
        )
    )$manifest) == fertility_expected_rows,
    nrow(fertility_framework_inventory(
        current_snapshot, framework_id = test_framework_id,
        report_schema_version = fertility_snapshot_report_schema_version(
            fresh_snapshot_provenance
        )
    )$manifest) == fertility_expected_rows
)
mixed_snapshot_provenance <- rbind(
    fresh_snapshot_provenance, historical_snapshot_provenance
)
expect_error(fertility_snapshot_report_schema_version(
    mixed_snapshot_provenance
), "mixed evidence origins")
expect_error(fertility_snapshot_report_schema_version(data.frame(
    source_corpus_schema_version = as.character(fertility_schema_version)
)), "unavailable")
preflight_item <- list(expected_sha512 = paste(rep("a", 128L), collapse = ""))
preflight_match <- list(hash_status = "ok", actual_sha512 = preflight_item$expected_sha512)
preflight_mismatch <- list(hash_status = "ok",
                           actual_sha512 = paste(rep("b", 128L), collapse = ""))
preflight_read_error <- list(hash_status = "error", actual_sha512 = NA_character_)
stopifnot(is.null(fertility_inventory_preflight(preflight_item, preflight_match)),
          identical(fertility_inventory_preflight(
              preflight_item, preflight_mismatch
          )$reason, "signature-mismatch"),
          identical(fertility_inventory_preflight(
              preflight_item, preflight_read_error
          )$reason, "hash-read-error"))
preflight_item$expected_sha512 <- ""
stopifnot(is.null(fertility_inventory_preflight(
    preflight_item, preflight_mismatch
)))

# Explicit accepted-current-hash evidence is a private immutable commitment for
# exactly F0633-F0637. It remains distinct from the unchanged manifest signatures.
acceptance_checkout <- file.path(root, "acceptance-checkout")
dir.create(acceptance_checkout)
acceptance_checkout <- normalizePath(acceptance_checkout, winslash = "/")
acceptance_checkout_raw <- file.path(
    acceptance_checkout, "target", "fertility-surveys", "raw"
)
stopifnot(identical(
    fertility_assert_acceptance_raw_root(
        acceptance_checkout_raw, acceptance_checkout
    ),
    acceptance_checkout_raw
))
symlink_checkout <- file.path(root, "acceptance-symlink-checkout")
dir.create(symlink_checkout)
symlink_checkout <- normalizePath(symlink_checkout, winslash = "/")
symlink_destination <- file.path(root, "acceptance-symlink-destination")
dir.create(symlink_destination)
symlink_destination <- normalizePath(symlink_destination, winslash = "/")
stopifnot(file.symlink(
    symlink_destination, file.path(symlink_checkout, "target")
))
expect_error(fertility_assert_acceptance_raw_root(
    file.path(symlink_checkout, "target", "fertility-surveys", "raw"),
    symlink_checkout
), "must not be symlinks")
acceptance_raw <- file.path(root, "acceptance-raw")
dir.create(acceptance_raw, mode = "0700")
acceptance_paths <- file.path(root, paste0("accepted-", seq_len(5L), ".dta"))
for (index in seq_along(acceptance_paths)) {
    writeBin(as.raw(c(118L, index, 0:15)), acceptance_paths[[index]])
}
acceptance_actual <- vapply(acceptance_paths, fertility_file_sha512, character(1))
acceptance_expected <- vapply(seq_along(acceptance_actual), function(index) {
    candidate <- paste(rep(sprintf("%x", index - 1L), 128L), collapse = "")
    if (identical(candidate, acceptance_actual[[index]])) {
        paste(rep(sprintf("%x", index), 128L), collapse = "")
    } else candidate
}, character(1))
acceptance_inventory <- data.frame(
    id = fertility_accepted_ids(), program = "dhs", level = "women",
    release = 118L, path = normalizePath(acceptance_paths, winslash = "/"),
    expected_sha512 = acceptance_expected,
    stringsAsFactors = FALSE, check.names = FALSE
)
acceptance_id <- fertility_capture_acceptance(
    acceptance_inventory, acceptance_raw
)
acceptance <- fertility_load_acceptance(
    acceptance_raw, acceptance_id, acceptance_inventory
)
sequential_reuse_refuses_changed_early_input <- function() {
    original_capture_input <- fertility_capture_input
    capture_count <- 0L
    on.exit(assign(
        "fertility_capture_input", original_capture_input, envir = .GlobalEnv
    ), add = TRUE)
    on.exit(writeBin(
        as.raw(c(118L, 1L, 0:15)), acceptance_paths[[1L]]
    ), add = TRUE)
    assign("fertility_capture_input", function(...) {
        capture_count <<- capture_count + 1L
        if (capture_count == 2L) {
            writeBin(as.raw(c(118L, 93L, 0:15)), acceptance_paths[[1L]])
        }
        original_capture_input(...)
    }, envir = .GlobalEnv)
    expect_error(fertility_capture_acceptance(
        acceptance_inventory, acceptance_raw
    ), "input changed during capture")
}
sequential_reuse_refuses_changed_early_input()
old_hook <- getOption("dtaparser.fertility.publication_test_hook")
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(boundary, "acceptance-before-existing-reuse-revalidation")) {
        writeBin(as.raw(c(118L, 92L, 0:15)), acceptance_paths[[1L]])
    }
})
expect_error(fertility_capture_acceptance(
    acceptance_inventory, acceptance_raw
), "input changed during capture")
options(dtaparser.fertility.publication_test_hook = old_hook)
writeBin(as.raw(c(118L, 1L, 0:15)), acceptance_paths[[1L]])
for (with_content in c(FALSE, TRUE)) {
    refusal_raw <- file.path(
        root, paste0("acceptance-existing-", as.integer(with_content))
    )
    dir.create(file.path(refusal_raw, "accepted-current-hashes", acceptance_id),
               recursive = TRUE)
    sentinel <- file.path(
        refusal_raw, "accepted-current-hashes", acceptance_id, "sentinel"
    )
    if (with_content) writeLines("untouched", sentinel)
    before <- list.files(
        file.path(refusal_raw, "accepted-current-hashes", acceptance_id),
        all.files = TRUE, no.. = TRUE
    )
    expect_error(fertility_capture_acceptance(
        acceptance_inventory, refusal_raw
    ), "accepted-current-hash")
    stopifnot(identical(list.files(
        file.path(refusal_raw, "accepted-current-hashes", acceptance_id),
        all.files = TRUE, no.. = TRUE
    ), before))
    if (with_content) stopifnot(identical(readLines(sentinel), "untouched"))
}
race_raw <- file.path(root, "acceptance-race")
dir.create(race_raw)
race_destination <- file.path(
    race_raw, "accepted-current-hashes", acceptance_id
)
old_hook <- getOption("dtaparser.fertility.publication_test_hook")
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(boundary, "acceptance-before-destination-publication")) {
        dir.create(context$destination)
        writeLines("race-winner", file.path(context$destination, "sentinel"))
    }
})
expect_error(fertility_capture_acceptance(
    acceptance_inventory, race_raw
), "accepted-current-hash")
options(dtaparser.fertility.publication_test_hook = old_hook)
stopifnot(
    identical(readLines(file.path(race_destination, "sentinel")), "race-winner"),
    !file.exists(file.path(race_destination, "commitment.rds"))
)
complete_race_raw <- file.path(root, "acceptance-complete-race")
dir.create(complete_race_raw)
complete_race_destination <- file.path(
    complete_race_raw, "accepted-current-hashes", acceptance_id
)
source_commitment <- file.path(
    acceptance_raw, "accepted-current-hashes", acceptance_id, "commitment.rds"
)
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(boundary, "acceptance-before-destination-publication")) {
        dir.create(context$destination)
        stopifnot(file.copy(
            source_commitment, file.path(context$destination, "commitment.rds")
        ))
    }
})
stopifnot(identical(
    fertility_capture_acceptance(acceptance_inventory, complete_race_raw),
    acceptance_id
))
options(dtaparser.fertility.publication_test_hook = old_hook)
stopifnot(identical(
    list.files(complete_race_destination, all.files = TRUE, no.. = TRUE),
    "commitment.rds"
))
publication_winner_raw <- file.path(root, "acceptance-publication-winner")
dir.create(publication_winner_raw)
publication_winner_destination <- file.path(
    publication_winner_raw, "accepted-current-hashes", acceptance_id
)
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(boundary, "atomic-noreplace-before-operation") &&
        identical(context$label, "accepted-current-hash commitment")) {
        dir.create(context$to)
        stopifnot(file.copy(
            source_commitment, file.path(context$to, "commitment.rds")
        ))
    }
})
stopifnot(identical(
    fertility_capture_acceptance(acceptance_inventory, publication_winner_raw),
    acceptance_id
))
options(dtaparser.fertility.publication_test_hook = old_hook)
stopifnot(identical(
    list.files(publication_winner_destination, all.files = TRUE, no.. = TRUE),
    "commitment.rds"
))
extra_claim_raw <- file.path(root, "acceptance-extra-claim")
dir.create(extra_claim_raw)
extra_claim_destination <- file.path(
    extra_claim_raw, "accepted-current-hashes", acceptance_id
)
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(boundary, "acceptance-before-destination-publication")) {
        writeLines("unexpected", file.path(context$stage, ".extra"))
    }
})
expect_error(fertility_capture_acceptance(
    acceptance_inventory, extra_claim_raw
), "exactly commitment.rds")
options(dtaparser.fertility.publication_test_hook = old_hook)
stopifnot(!file.exists(extra_claim_destination))
atomic_mutation_raw <- file.path(root, "acceptance-atomic-source-mutation")
dir.create(atomic_mutation_raw)
atomic_mutation_destination <- file.path(
    atomic_mutation_raw, "accepted-current-hashes", acceptance_id
)
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(boundary, "atomic-noreplace-before-operation") &&
        identical(context$label, "accepted-current-hash commitment")) {
        writeLines("invalid", file.path(context$from, ".invalid"))
    }
})
expect_error(fertility_capture_acceptance(
    acceptance_inventory, atomic_mutation_raw
), "exactly commitment.rds")
options(dtaparser.fertility.publication_test_hook = old_hook)
stopifnot(
    !file.exists(atomic_mutation_destination),
    identical(
        fertility_capture_acceptance(acceptance_inventory, atomic_mutation_raw),
        acceptance_id
    )
)
rollback_raw <- file.path(root, "acceptance-post-publication-rollback")
dir.create(rollback_raw)
rollback_destination <- file.path(
    rollback_raw, "accepted-current-hashes", acceptance_id
)
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(
        boundary, "acceptance-before-new-publication-revalidation"
    )) writeLines("invalid", file.path(context$destination, ".invalid"))
})
expect_error(fertility_capture_acceptance(
    acceptance_inventory, rollback_raw
), "exactly commitment.rds")
options(dtaparser.fertility.publication_test_hook = old_hook)
stopifnot(
    !file.exists(rollback_destination),
    identical(
        fertility_capture_acceptance(acceptance_inventory, rollback_raw),
        acceptance_id
    )
)
concurrent_reuse_raw <- file.path(root, "acceptance-concurrent-final-check")
dir.create(concurrent_reuse_raw)
concurrent_reuse_destination <- file.path(
    concurrent_reuse_raw, "accepted-current-hashes", acceptance_id
)
concurrent_inventory_path <- file.path(root, "concurrent-inventory.rds")
saveRDS(acceptance_inventory, concurrent_inventory_path)
concurrent_reuse_script <- file.path(root, "concurrent-acceptance-reuse.R")
writeLines(c(
    paste0("source(", encodeString(file.path(script_dir, "common.R"), quote = "\""), ")"),
    paste0("source(", encodeString(file.path(script_dir, "runner.R"), quote = "\""), ")"),
    paste0("source(", encodeString(file.path(script_dir, "accepted.R"), quote = "\""), ")"),
    paste0("inventory <- readRDS(", encodeString(concurrent_inventory_path, quote = "\""), ")"),
    paste0(
        "fertility_capture_acceptance(inventory, ",
        encodeString(concurrent_reuse_raw, quote = "\""), ")"
    )
), concurrent_reuse_script)
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(
        boundary, "acceptance-before-new-publication-revalidation"
    )) {
        child_status <- suppressWarnings(system2(
            file.path(R.home("bin"), "Rscript"),
            c("--vanilla", shQuote(concurrent_reuse_script)),
            stdout = FALSE, stderr = FALSE
        ))
        stopifnot(identical(child_status, 0L))
        writeBin(as.raw(c(118L, 94L, 0:15)), acceptance_paths[[2L]])
    }
})
expect_error(fertility_capture_acceptance(
    acceptance_inventory, concurrent_reuse_raw
), "input changed during capture")
options(dtaparser.fertility.publication_test_hook = old_hook)
writeBin(as.raw(c(118L, 2L, 0:15)), acceptance_paths[[2L]])
stopifnot(
    identical(
        list.files(
            concurrent_reuse_destination, all.files = TRUE, no.. = TRUE
        ),
        "commitment.rds"
    ),
    identical(
        fertility_capture_acceptance(
            acceptance_inventory, concurrent_reuse_raw
        ),
        acceptance_id
    )
)
terminated_raw <- file.path(root, "acceptance-terminated-publication")
dir.create(terminated_raw)
terminated_destination <- file.path(
    terminated_raw, "accepted-current-hashes", acceptance_id
)
terminated_inventory_path <- file.path(root, "terminated-inventory.rds")
saveRDS(acceptance_inventory, terminated_inventory_path)
terminated_script <- file.path(root, "terminate-acceptance.R")
writeLines(c(
    paste0("source(", encodeString(file.path(script_dir, "common.R"), quote = "\""), ")"),
    paste0("source(", encodeString(file.path(script_dir, "runner.R"), quote = "\""), ")"),
    paste0("source(", encodeString(file.path(script_dir, "accepted.R"), quote = "\""), ")"),
    paste0("inventory <- readRDS(", encodeString(terminated_inventory_path, quote = "\""), ")"),
    "options(dtaparser.fertility.publication_test_hook = function(boundary, context) {",
    "    if (identical(boundary, 'acceptance-before-destination-publication')) {",
    "        tools::pskill(Sys.getpid(), 9L)",
    "    }",
    "})",
    paste0(
        "fertility_capture_acceptance(inventory, ", encodeString(terminated_raw, quote = "\""), ")"
    )
), terminated_script)
terminated_result <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(terminated_script)),
    stdout = FALSE, stderr = FALSE
))
stopifnot(
    !identical(terminated_result, 0L),
    !file.exists(terminated_destination),
    length(list.files(
        file.path(terminated_raw, "accepted-current-hashes"),
        pattern = "^\\.acceptance\\.", all.files = TRUE
    )) == 1L,
    identical(
        fertility_capture_acceptance(acceptance_inventory, terminated_raw),
        acceptance_id
    )
)
unlink(list.files(
    file.path(terminated_raw, "accepted-current-hashes"),
    pattern = "^\\.acceptance\\.", all.files = TRUE, full.names = TRUE
), recursive = TRUE)
input_race_raw <- file.path(root, "acceptance-input-race")
dir.create(input_race_raw)
options(dtaparser.fertility.publication_test_hook = function(boundary, context) {
    if (identical(boundary, "acceptance-before-destination-publication")) {
        writeBin(as.raw(c(118L, 91L, 0:15)), acceptance_paths[[4L]])
    }
})
expect_error(fertility_capture_acceptance(
    acceptance_inventory, input_race_raw
), "input changed during capture")
options(dtaparser.fertility.publication_test_hook = old_hook)
writeBin(as.raw(c(118L, 4L, 0:15)), acceptance_paths[[4L]])
stopifnot(!file.exists(file.path(
    input_race_raw, "accepted-current-hashes", acceptance_id
)))
stopifnot(
    grepl("^[0-9a-f]{64}$", acceptance_id),
    identical(acceptance$authority, fertility_acceptance_authority()),
    identical(acceptance$entries$id, fertility_accepted_ids()),
    identical(acceptance$entries$expected_sha512, acceptance_expected),
    identical(acceptance$entries$accepted_sha512, unname(acceptance_actual)),
    !"path" %in% names(acceptance$entries),
    isTRUE(fertility_validate_acceptance_current(
        acceptance, acceptance_inventory
    ))
)
expect_rejected_acceptance_shape <- function(label, populate, pattern) {
    shape_raw <- file.path(root, paste0("acceptance-shape-", label))
    shape_destination <- file.path(
        shape_raw, "accepted-current-hashes", acceptance_id
    )
    dir.create(shape_destination, recursive = TRUE)
    populate(shape_destination)
    expect_error(fertility_load_acceptance(
        shape_raw, acceptance_id, acceptance_inventory
    ), pattern)
}
expect_rejected_acceptance_shape("missing", function(destination) NULL,
                                 "exactly commitment.rds")
expect_rejected_acceptance_shape("additional", function(destination) {
    stopifnot(file.copy(
        source_commitment, file.path(destination, "commitment.rds")
    ))
    writeLines("unexpected", file.path(destination, "extra"))
}, "exactly commitment.rds")
expect_rejected_acceptance_shape("symlink", function(destination) {
    stopifnot(file.symlink(
        source_commitment, file.path(destination, "commitment.rds")
    ))
}, "regular nonsymlink")
expect_rejected_acceptance_shape("nonregular", function(destination) {
    dir.create(file.path(destination, "commitment.rds"))
}, "regular nonsymlink")
expect_error(fertility_validate_acceptance_entries(transform(
    acceptance$entries, accepted_sha512 = toupper(accepted_sha512)
)), "invalid")
expect_error(fertility_validate_acceptance_entries(
    acceptance$entries[c(2:5, 1), , drop = FALSE]
), "invalid")
expect_error(fertility_parse_arguments("--accepted-current-hashes=BAD"),
             "exact commitment ID")
accepted_options <- fertility_parse_arguments(c(
    paste0("--accepted-current-hashes=", acceptance_id),
    paste0("--id=", paste(fertility_accepted_ids(), collapse = ","))
))
fertility_validate_accepted_selection(accepted_options, acceptance_inventory)
expect_error(fertility_validate_accepted_selection(
    fertility_parse_arguments(c(
        paste0("--accepted-current-hashes=", acceptance_id),
        "--id=F0633,F0634,F0635,F0636"
    )), acceptance_inventory[1:4, , drop = FALSE]
), "exactly F0633 through F0637")
expect_error(fertility_validate_accepted_selection(
    fertility_parse_arguments(c(
        paste0("--accepted-current-hashes=", acceptance_id),
        paste0("--id=", paste(fertility_accepted_ids(), collapse = ",")),
        "--shard-index=1", "--shard-count=2"
    )), acceptance_inventory
), "exactly F0633 through F0637")
legacy_config_identity <- fertility_tile_configuration(
    fertility_parse_arguments(character())
)$config_id
accepted_config <- fertility_tile_configuration(accepted_options, acceptance)
stopifnot(
    !identical(legacy_config_identity, accepted_config$config_id),
    !identical(
        fertility_framework_id(test_build_id, datasigs),
        fertility_framework_id(test_build_id, datasigs, acceptance)
    )
)
accepted_item <- as.list(acceptance_inventory[1L, , drop = FALSE])
accepted_input <- fertility_capture_input(accepted_item, acceptance)
stopifnot(
    identical(accepted_input$manifest_hash_status, "signature-mismatch"),
    identical(accepted_input$local_evidence_status,
              "accepted-current-sha512-match"),
    is.null(fertility_inventory_preflight(accepted_item, accepted_input))
)
accepted_result <- fertility_base_result(
    accepted_item, test_framework_id, accepted_config$timeout_seconds,
    accepted_input, "pass"
)
accepted_result$config_id <- accepted_config$config_id
accepted_result$component <- NULL
stopifnot(
    isTRUE(fertility_validate_recorded_input_attestation(accepted_result)),
    fertility_recorded_result_valid(
        accepted_result, accepted_item, test_framework_id, accepted_config
    ),
    !identical(
        fertility_input_attestation_id(list(accepted_result)),
        fertility_input_attestation_id(list(transform(
            accepted_result, input_id = paste(rep("9", 64L), collapse = "")
        )))
    )
)
accepted_public <- fertility_result_frame(list(accepted_result))
accepted_public$build_provenance_id <- test_build_id
stopifnot(
    isTRUE(fertility_validate_public_results(accepted_public)),
    !any(grepl("accept|sha512|manifest", names(accepted_public))),
    fertility_file_result_valid(
        accepted_result, accepted_item, test_framework_id, accepted_config,
        accepted_input
    )
)
accepted_tile <- fertility_value_tile(1L, 0, 1L, "x")
accepted_tile_path <- file.path(root, "accepted-tile.rds")
accepted_tile_execute <- function(item, tile, input) list(
    schema_version = fertility_schema_version, framework_id = test_framework_id,
    id = item$id, tile_id = tile$tile_id, tile_type = tile$type,
    batch = tile$batch, skip = tile$skip, n_max = tile$n_max,
    classification = "pass", secondary = character(),
    mismatches = fertility_bind_mismatches(list()), rows = 1L,
    reader_rows = c(direct = 1L, rust = 1L, haven = 1L),
    columns = 1L, column_names = character(), storage = character(),
    structural_rows = NA_real_, column_bytes = numeric(), strl = logical(),
    projection_expected_count = 1L,
    projection_expected_hash = fertility_projection_hash("x", test_framework_id),
    projection_counts = c(direct = 1L, rust = 1L, haven = 1L),
    projection_hashes = setNames(rep(
        fertility_projection_hash("x", test_framework_id), 3L
    ), c("direct", "rust", "haven")),
    projection_ok = c(direct = TRUE, rust = TRUE, haven = TRUE),
    elapsed_seconds = 0
)
accepted_tile_result <- fertility_process_tile(
    accepted_item, accepted_tile, accepted_tile_path, test_framework_id,
    accepted_config, accepted_input, FALSE, accepted_tile_execute
)$result
stopifnot(
    identical(accepted_tile_result$acceptance_authority,
              acceptance$authority),
    identical(accepted_tile_result$acceptance_commitment_id,
              acceptance$commitment_id),
    isTRUE(fertility_validate_recorded_tile(accepted_tile_result))
)
changed_acceptance <- acceptance
changed_acceptance$artifact_sha256 <- paste(rep("8", 64L), collapse = "")
stopifnot(
    !identical(
        fertility_tile_configuration(accepted_options, changed_acceptance)$config_id,
        accepted_config$config_id
    ),
    !identical(
        fertility_capture_input(accepted_item, changed_acceptance)$input_id,
        accepted_input$input_id
    ),
    !fertility_file_result_valid(
        accepted_result, accepted_item, test_framework_id,
        fertility_tile_configuration(accepted_options, changed_acceptance),
        fertility_capture_input(accepted_item, changed_acceptance)
    )
)
changed_acceptance_inventory <- acceptance_inventory
writeBin(as.raw(c(118L, 99L, 0:15)), changed_acceptance_inventory$path[[1L]])
expect_error(fertility_validate_acceptance_current(
    acceptance, changed_acceptance_inventory
), "input validation failed")
writeBin(as.raw(c(118L, 1L, 0:15)), changed_acceptance_inventory$path[[1L]])
stopifnot(isTRUE(fertility_validate_acceptance_current(
    acceptance, changed_acceptance_inventory
)))
artifact_path <- file.path(
    acceptance_raw, "accepted-current-hashes", acceptance_id, "commitment.rds"
)
artifact <- readRDS(artifact_path)
artifact$entries$accepted_sha512[[1L]] <- paste(rep("f", 128L), collapse = "")
fertility_atomic_save_rds(artifact, artifact_path)
expect_error(fertility_load_acceptance(
    acceptance_raw, acceptance_id, acceptance_inventory
), "commitment identity")
artifact$entries$accepted_sha512[[1L]] <- acceptance_actual[[1L]]
artifact$created_at_utc <- "2026-01-01T00:00:00Z"
fertility_atomic_save_rds(artifact, artifact_path)
acceptance_reloaded <- fertility_load_acceptance(
    acceptance_raw, acceptance_id, acceptance_inventory
)
stopifnot(!identical(acceptance_reloaded$artifact_sha256,
                    acceptance$artifact_sha256))
recorded_acceptance <- data.frame(
    acceptance_authority = acceptance_reloaded$authority,
    acceptance_commitment_id = acceptance_reloaded$commitment_id,
    acceptance_artifact_sha256 = acceptance_reloaded$artifact_sha256,
    inventory_id = fertility_inventory_id(acceptance_inventory),
    stringsAsFactors = FALSE, check.names = FALSE
)
stopifnot(identical(
    fertility_revalidate_recorded_acceptance(
        acceptance_raw, recorded_acceptance, acceptance_inventory
    )$artifact_sha256,
    acceptance_reloaded$artifact_sha256
))
writeBin(as.raw(c(118L, 77L, 0:15)), acceptance_inventory$path[[2L]])
expect_error(fertility_revalidate_recorded_acceptance(
    acceptance_raw, recorded_acceptance, acceptance_inventory
), "input validation failed")
writeBin(as.raw(c(118L, 2L, 0:15)), acceptance_inventory$path[[2L]])
artifact_saved <- readRDS(artifact_path)
artifact_saved$created_at_utc <- "2026-01-02T00:00:00Z"
fertility_atomic_save_rds(artifact_saved, artifact_path)
expect_error(fertility_revalidate_recorded_acceptance(
    acceptance_raw, recorded_acceptance, acceptance_inventory
), "artifact identity changed")
artifact_saved$created_at_utc <- "2026-01-01T00:00:00Z"
fertility_atomic_save_rds(artifact_saved, artifact_path)
deleted_artifact <- paste0(artifact_path, ".deleted")
stopifnot(file.rename(artifact_path, deleted_artifact))
expect_error(fertility_revalidate_recorded_acceptance(
    acceptance_raw, recorded_acceptance, acceptance_inventory
), "accepted-current-hash")
stopifnot(file.rename(deleted_artifact, artifact_path))
stopifnot(identical(
    fertility_revalidate_recorded_acceptance(
        acceptance_raw, recorded_acceptance, acceptance_inventory
    )$artifact_sha256,
    acceptance_reloaded$artifact_sha256
))
publication_inventory <- full_canonical
publication_inventory$path <- rep(acceptance_inventory$path[[1L]], nrow(publication_inventory))
publication_inventory$expected_sha512 <- rep("", nrow(publication_inventory))
accepted_positions <- match(fertility_accepted_ids(), publication_inventory$id)
publication_inventory$path[accepted_positions] <- acceptance_inventory$path
publication_inventory$expected_sha512[accepted_positions] <- acceptance_expected
publication_framework_id <- fertility_framework_id(
    test_build_id, datasigs, acceptance_reloaded
)
publication_snapshot <- file.path(
    acceptance_raw, "framework", publication_framework_id
)
dir.create(publication_snapshot, recursive = TRUE)
fertility_atomic_write_table(
    full_canonical, file.path(publication_snapshot, "inventory-manifest.tsv")
)
publication_inventory_id <- fertility_inventory_id(publication_inventory)
publication_inventory_provenance <- data.frame(
    schema_version = fertility_schema_version,
    report_schema_version = fertility_report_schema_version,
    framework_id = publication_framework_id,
    inventory_id = publication_inventory_id,
    inventory_manifest_id = fertility_manifest_id(full_canonical),
    report_schema_id = fertility_report_schema_id(),
    files = nrow(full_canonical), stringsAsFactors = FALSE, check.names = FALSE
)
fertility_atomic_write_table(
    publication_inventory_provenance,
    file.path(publication_snapshot, "inventory-manifest-provenance.tsv")
)
fertility_atomic_write_table(data.frame(
    authority = acceptance_reloaded$authority,
    commitment_id = acceptance_reloaded$commitment_id,
    artifact_sha256 = acceptance_reloaded$artifact_sha256,
    stringsAsFactors = FALSE, check.names = FALSE
), file.path(publication_snapshot, "acceptance-provenance.tsv"))
publication_provenance <- data.frame(
    schema_version = fertility_schema_version,
    report_schema_version = fertility_report_schema_version,
    evidence_origin = "fresh-execution",
    source_corpus_schema_version = fertility_schema_version,
    framework_id = publication_framework_id,
    build_provenance_id = test_build_id,
    inventory_id = publication_inventory_id,
    report_schema_id = fertility_report_schema_id(),
    acceptance_authority = acceptance_reloaded$authority,
    acceptance_commitment_id = acceptance_reloaded$commitment_id,
    acceptance_artifact_sha256 = acceptance_reloaded$artifact_sha256,
    stringsAsFactors = FALSE, check.names = FALSE
)
stopifnot(identical(
    fertility_revalidate_accepted_publication(
        acceptance_raw, publication_provenance, publication_inventory, datasigs
    )$acceptance$artifact_sha256,
    acceptance_reloaded$artifact_sha256
))
publication_provenance_path <- file.path(
    root, "accepted-publication-provenance.tsv"
)
fertility_atomic_write_table(publication_provenance, publication_provenance_path)
publication_provenance_tsv <- read.delim(
    publication_provenance_path, colClasses = "character", check.names = FALSE
)
stopifnot(
    all(vapply(publication_provenance_tsv[c(
        "schema_version", "report_schema_version",
        "source_corpus_schema_version"
    )], is.character, logical(1))),
    identical(
        fertility_revalidate_accepted_publication(
            acceptance_raw, publication_provenance_tsv, publication_inventory,
            datasigs
        )$acceptance$artifact_sha256,
        acceptance_reloaded$artifact_sha256
    )
)
publication_schema_fields <- c(
    schema_version = fertility_schema_version,
    report_schema_version = fertility_report_schema_version,
    source_corpus_schema_version = fertility_schema_version
)
for (field in names(publication_schema_fields)) {
    wrong_publication_schema <- publication_provenance
    wrong_publication_schema[[field]] <-
        as.character(publication_schema_fields[[field]] + 1L)
    expect_error(fertility_revalidate_accepted_publication(
        acceptance_raw, wrong_publication_schema, publication_inventory, datasigs
    ), "framework provenance is invalid")
}
malformed_publication_schema <- publication_provenance
malformed_publication_schema$source_corpus_schema_version <-
    paste0(fertility_schema_version, ".0")
expect_error(fertility_revalidate_accepted_publication(
    acceptance_raw, malformed_publication_schema, publication_inventory, datasigs
), "framework provenance is invalid")
missing_publication_schema <- publication_provenance
missing_publication_schema$report_schema_version <- NULL
expect_error(fertility_revalidate_accepted_publication(
    acceptance_raw, missing_publication_schema, publication_inventory, datasigs
), "framework provenance is invalid")
nonatomic_publication_schema <- publication_provenance
nonatomic_publication_schema$schema_version <- I(list(fertility_schema_version))
expect_error(fertility_revalidate_accepted_publication(
    acceptance_raw, nonatomic_publication_schema, publication_inventory, datasigs
), "framework provenance is invalid")
mixed_publication_schema <- rbind(publication_provenance, publication_provenance)
mixed_publication_schema$source_corpus_schema_version[[2L]] <-
    fertility_schema_version + 1L
expect_error(fertility_revalidate_accepted_publication(
    acceptance_raw, mixed_publication_schema, publication_inventory, datasigs
), "framework provenance is invalid")
empty_publication_provenance <- publication_provenance[FALSE, , drop = FALSE]
expect_error(fertility_revalidate_accepted_publication(
    acceptance_raw, empty_publication_provenance, publication_inventory, datasigs
), "framework provenance is invalid")
foreign_publication_framework <- publication_provenance
foreign_publication_framework$framework_id <- test_framework_id
expect_error(fertility_revalidate_accepted_publication(
    acceptance_raw, foreign_publication_framework, publication_inventory, datasigs
), "framework provenance changed")
changed_publication_path <- publication_inventory$path[[accepted_positions[[3L]]]]
writeBin(as.raw(c(118L, 88L, 0:15)), changed_publication_path)
expect_error(fertility_revalidate_accepted_publication(
    acceptance_raw, publication_provenance, publication_inventory, datasigs
), "input validation failed")
writeBin(as.raw(c(118L, 3L, 0:15)), changed_publication_path)

accepted_family_fixture <- make_bundle_family(
    full_canonical, accepted_options, classifications = rep("pass", nrow(full_canonical)),
    inventory_id = paste(rep("e", 64L), collapse = ""),
    acceptance = acceptance_reloaded
)
accepted_family_validated <- fertility_validate_shard_bundles(
    accepted_family_fixture$bundles, accepted_family_fixture$id, full_canonical
)
stopifnot(
    identical(accepted_family_validated$results$id, fertility_accepted_ids()),
    identical(
        accepted_family_validated$provenance$acceptance_commitment_id[[1L]],
        acceptance_id
    )
)
accepted_wrong_member <- accepted_family_fixture$bundles
accepted_wrong_member[[1L]]$results$id[[1L]] <- "F0632"
expect_error(fertility_validate_shard_bundles(
    accepted_wrong_member, accepted_family_fixture$id, full_canonical
), "canonical family membership|exact executable five-ID")
accepted_foreign_artifact <- accepted_family_fixture$bundles
accepted_foreign_artifact[[1L]]$provenance$acceptance_artifact_sha256 <-
    paste(rep("7", 64L), collapse = "")
expect_error(fertility_validate_shard_bundles(
    accepted_foreign_artifact, accepted_family_fixture$id, full_canonical
), "configuration provenance identity")
merge_live_inventory <- full_canonical
merge_live_inventory$expected_sha512 <- rep(
    paste(rep("a", 128L), collapse = ""), nrow(merge_live_inventory)
)
make_merged_bundle <- function(
    validated, family_id, canonical_inventory = merge_live_inventory
) {
    provenance <- validated$provenance
    family_input_attestation_id <- fertility_family_input_attestation_id(provenance)
    evidence_family_id <- fertility_evidence_family_id(
        family_id, family_input_attestation_id,
        provenance$evidence_origin[[1L]],
        as.integer(provenance$source_corpus_schema_version[[1L]]),
        provenance$report_schema_id[[1L]],
        provenance$acceptance_authority[[1L]],
        provenance$acceptance_commitment_id[[1L]]
    )
    merge_provenance <- data.frame(
        schema_version = as.character(fertility_schema_version),
        report_schema_version = as.character(fertility_report_schema_version),
        evidence_origin = provenance$evidence_origin[[1L]],
        source_corpus_schema_version = provenance$source_corpus_schema_version[[1L]],
        replayed_at_utc = provenance$replayed_at_utc[[1L]],
        acceptance_authority = provenance$acceptance_authority[[1L]],
        acceptance_commitment_id = provenance$acceptance_commitment_id[[1L]],
        acceptance_artifact_sha256 = provenance$acceptance_artifact_sha256[[1L]],
        family_id = family_id, evidence_family_id = evidence_family_id,
        family_input_attestation_id = family_input_attestation_id,
        framework_id = provenance$framework_id[[1L]],
        config_id = provenance$config_id[[1L]],
        build_provenance_id = provenance$build_provenance_id[[1L]],
        inventory_id = fertility_inventory_id(canonical_inventory),
        family_manifest_id = provenance$family_manifest_id[[1L]],
        report_schema_id = provenance$report_schema_id[[1L]],
        results_id = fertility_merged_results_id(validated$results),
        merge_id = "", shard_count = as.character(validated$shard_count),
        files = as.character(nrow(validated$results)),
        full_default_family = if (validated$full_default) "TRUE" else "FALSE",
        created_at_utc = "2026-01-01T00:00:00Z",
        stringsAsFactors = FALSE, check.names = FALSE
    )
    merge_provenance$merge_id <- fertility_merge_identity(merge_provenance)
    merge_provenance <- merge_provenance[fertility_merge_provenance_fields()]
    list(
        provenance = merge_provenance, results = validated$results,
        summary = fertility_classification_summary(validated$results),
        family_manifest = validated$family_manifest,
        input_attestation = fertility_family_input_attestation(provenance)
    )
}
full_merged_bundle <- make_merged_bundle(full_validated, full_fixture$id)
accepted_merged_bundle <- make_merged_bundle(
    accepted_family_validated, accepted_family_fixture$id
)
full_assessment <- fertility_validate_merged_bundle(
    full_merged_bundle, full_fixture$id, merge_live_inventory
)
accepted_assessment <- fertility_validate_merged_bundle(
    accepted_merged_bundle, accepted_family_fixture$id, merge_live_inventory
)
output_merge_live_inventory <- output_canonical
output_merge_live_inventory$expected_sha512 <- rep(
    paste(rep("b", 128L), collapse = ""), nrow(output_merge_live_inventory)
)
output_merged_bundle <- make_merged_bundle(
    output_validated, output_fixture$id, output_merge_live_inventory
)
output_assessment <- fertility_validate_merged_bundle(
    output_merged_bundle, output_fixture$id, output_merge_live_inventory
)
stopifnot(
    grepl("^[0-9a-f]{64}$", full_assessment$merge_id),
    grepl("^[0-9a-f]{64}$", accepted_assessment$merge_id),
    grepl("^[0-9a-f]{64}$", output_assessment$merge_id),
    nrow(output_assessment$results) == fertility_output_expected_files
)
production_framework_inventory <- fertility_framework_inventory(
    publication_snapshot, inventory = publication_inventory,
    framework_id = publication_framework_id
)
stopifnot(
    !"expected_sha512" %in% names(production_framework_inventory$manifest),
    identical(
        production_framework_inventory$provenance$inventory_id[[1L]],
        fertility_inventory_id(publication_inventory)
    )
)
production_merged_bundle <- make_merged_bundle(
    accepted_family_validated, accepted_family_fixture$id, publication_inventory
)
stopifnot(grepl("^[0-9a-f]{64}$", fertility_validate_merged_bundle(
    production_merged_bundle, accepted_family_fixture$id, publication_inventory
)$merge_id))
wrong_live_signature <- publication_inventory
wrong_live_signature$expected_sha512[[1L]] <- paste(rep("b", 128L), collapse = "")
expect_error(fertility_framework_inventory(
    publication_snapshot, inventory = wrong_live_signature,
    framework_id = publication_framework_id
), "does not match the live inventory")
expect_error(fertility_validate_merged_bundle(
    production_merged_bundle, accepted_family_fixture$id, wrong_live_signature
), "does not match canonical inventory authority")
wrong_live_inventory_id <- production_merged_bundle
wrong_live_inventory_id$provenance$inventory_id <- paste(rep("b", 64L), collapse = "")
expect_error(fertility_validate_merged_bundle(
    wrong_live_inventory_id, accepted_family_fixture$id, publication_inventory
), "does not match canonical inventory authority")
merge_source <- paste(
    readLines(file.path(script_dir, "merge.R"), warn = FALSE), collapse = "\n"
)
stopifnot(
    grepl("inventory = live_inventory", merge_source, fixed = TRUE),
    grepl("inventory = current_live_inventory", merge_source, fixed = TRUE),
    grepl(
        "fertility_validate_merged_bundle(loaded, family_id, canonical_inventory)",
        merge_source, fixed = TRUE
    ),
    !grepl(
        "fertility_validate_merged_bundle(\n        loaded, family_id, framework_inventory$manifest",
        merge_source, fixed = TRUE
    )
)
assessment_source <- paste(
    readLines(file.path(script_dir, "assessment.R"), warn = FALSE), collapse = "\n"
)
stopifnot(
    grepl('load_family(full_family_id, inventory, "original")',
          assessment_source, fixed = TRUE),
    grepl('load_family(accepted_family_id, inventory, "accepted")',
          assessment_source, fixed = TRUE),
    grepl("original_source_id = full$source_id", assessment_source, fixed = TRUE),
    grepl("assessment_source_snapshot(current$full)",
          assessment_source, fixed = TRUE),
    grepl("assessment_source_snapshot(current$accepted)",
          assessment_source, fixed = TRUE),
    grepl("assessment-before-bundle-revalidation", assessment_source, fixed = TRUE),
    grepl("assessment-before-current-revalidation", assessment_source, fixed = TRUE)
)
tampered_merged_results <- accepted_merged_bundle
tampered_merged_results$results$classification[[1L]] <- "timeout"
expect_error(fertility_validate_merged_bundle(
    tampered_merged_results, accepted_family_fixture$id, merge_live_inventory
), "results are not bound")
tampered_merged_attestation <- accepted_merged_bundle
tampered_merged_attestation$provenance$family_input_attestation_id <-
    paste(rep("9", 64L), collapse = "")
expect_error(fertility_validate_merged_bundle(
    tampered_merged_attestation, accepted_family_fixture$id, merge_live_inventory
), "input attestation identity")
tampered_input_attestation <- accepted_merged_bundle
tampered_input_attestation$input_attestation$input_attestation_id[[1L]] <-
    paste(rep("8", 64L), collapse = "")
expect_error(fertility_validate_merged_bundle(
    tampered_input_attestation, accepted_family_fixture$id, merge_live_inventory
), "input attestation identity")
tampered_merged_evidence <- accepted_merged_bundle
tampered_merged_evidence$provenance$evidence_family_id <-
    paste(rep("9", 64L), collapse = "")
expect_error(fertility_validate_merged_bundle(
    tampered_merged_evidence, accepted_family_fixture$id, merge_live_inventory
), "evidence family identity")
tampered_merged_manifest <- accepted_merged_bundle
tampered_merged_manifest$family_manifest$id[[1L]] <- "F0632"
expect_error(fertility_validate_merged_bundle(
    tampered_merged_manifest, accepted_family_fixture$id, merge_live_inventory
), "manifest")

make_legacy_assessment_original <- function() {
    manifest <- fertility_family_manifest(
        merge_live_inventory,
        fertility_parse_arguments(c("--shard-index=1", "--shard-count=8"))
    )
    family_id <- fertility_family_id_from_manifest(
        manifest, test_framework_id, test_config_id, test_build_id,
        fertility_inventory_id(merge_live_inventory), 8L, Inf
    )
    results <- make_public_results(manifest, full_classes)
    hash_rows <- results$classification == "inventory-hash-error"
    results$secondary_categories[hash_rows] <- "signature-mismatch"
    family_input_attestation_id <- fertility_stable_id(list(
        synthetic_legacy_family = family_id, shards = 8L
    ))
    evidence_family_id <- fertility_evidence_family_id(
        family_id, family_input_attestation_id, "fresh-execution",
        fertility_schema_version, fertility_report_schema_id()
    )
    provenance <- data.frame(
        schema_version = as.character(fertility_schema_version),
        report_schema_version = as.character(fertility_report_schema_version),
        evidence_origin = "fresh-execution",
        source_corpus_schema_version = as.character(fertility_schema_version),
        replayed_at_utc = "", family_id = family_id,
        evidence_family_id = evidence_family_id,
        family_input_attestation_id = family_input_attestation_id,
        framework_id = test_framework_id, config_id = test_config_id,
        build_provenance_id = test_build_id,
        inventory_id = fertility_inventory_id(merge_live_inventory),
        family_manifest_id = fertility_manifest_id(manifest),
        report_schema_id = fertility_report_schema_id(), shard_count = "8",
        files = as.character(fertility_expected_rows), full_default_family = "TRUE",
        created_at_utc = "2026-01-01T00:00:00Z",
        stringsAsFactors = FALSE, check.names = FALSE
    )
    provenance <- provenance[fertility_assessment_legacy_provenance_fields()]
    list(
        family_id = family_id,
        bundle = list(
            provenance = provenance, results = results,
            summary = fertility_classification_summary(results),
            family_manifest = manifest
        )
    )
}
legacy_original_fixture <- make_legacy_assessment_original()
legacy_original <- fertility_validate_assessment_legacy_original_bundle(
    legacy_original_fixture$bundle, legacy_original_fixture$family_id,
    merge_live_inventory
)
stopifnot(
    identical(legacy_original$source_format,
              "legacy-original-merged-report-v2"),
    grepl("^[0-9a-f]{64}$", legacy_original$source_id),
    identical(legacy_original$merge_id, ""),
    identical(legacy_original$source_content_ids$results_id,
              fertility_merged_results_id(legacy_original$results)),
    identical(
        fertility_assessment_bundle_format(
            unname(fertility_assessment_bundle_files("legacy-original")),
            "original"
        ),
        "legacy-original-merged-report-v2"
    ),
    identical(
        fertility_assessment_bundle_format(
            unname(fertility_assessment_bundle_files("current")), "accepted"
        ),
        "current-merged-report-v2"
    )
)
legacy_assessment_gates <- fertility_validate_assessment_families(
    legacy_original, accepted_assessment
)
stopifnot(
    identical(legacy_assessment_gates$manifest_gate,
              "blocked-signature-mismatch"),
    identical(legacy_assessment_gates$explicit_local_evidence_gate, "validated")
)
expect_error(fertility_assessment_bundle_format(
    unname(fertility_assessment_bundle_files("legacy-original")), "accepted"
), "unsupported exact file set")
expect_error(fertility_validate_assessment_families(
    accepted_assessment, legacy_original
), "assessment family evidence")
for (entries in list(
    c(unname(fertility_assessment_bundle_files("legacy-original")), "extra.tsv"),
    setdiff(unname(fertility_assessment_bundle_files("legacy-original")),
            "summary.tsv")
)) expect_error(fertility_assessment_bundle_format(
    entries, "original"
), "unsupported exact file set")
legacy_shape_parent <- file.path(root, "legacy-assessment-shape")
legacy_shape_run <- file.path(legacy_shape_parent, "bundle")
dir.create(legacy_shape_run, recursive = TRUE)
writeLines("bundle", file.path(legacy_shape_parent, "CURRENT"))
for (name in unname(fertility_assessment_bundle_files("legacy-original"))) {
    writeLines("synthetic", file.path(legacy_shape_run, name))
}
legacy_shape_external <- file.path(root, "legacy-assessment-external.tsv")
writeLines("external", legacy_shape_external)
unlink(file.path(legacy_shape_run, "results.tsv"))
stopifnot(file.symlink(legacy_shape_external, file.path(legacy_shape_run, "results.tsv")))
expect_error(fertility_current_bundle_paths(
    legacy_shape_parent, fertility_assessment_bundle_files("legacy-original"),
    "legacy assessment shape"
), "symlink")

legacy_mutation <- function(field, value) {
    changed <- legacy_original_fixture$bundle
    changed$provenance[[field]] <- value
    changed
}
legacy_reject <- function(bundle, family_id = legacy_original_fixture$family_id,
                          pattern) expect_error(
    fertility_validate_assessment_legacy_original_bundle(
        bundle, family_id, merge_live_inventory
    ), pattern
)
legacy_reject(legacy_original_fixture$bundle,
              paste(rep("f", 64L), collapse = ""), "provenance")
for (case in list(
    list("schema_version", "9", "provenance"),
    list("report_schema_version", "1", "provenance"),
    list("evidence_origin", "historical-schema-10-replay", "provenance"),
    list("shard_count", "7", "provenance"),
    list("files", "1003", "provenance"),
    list("full_default_family", "FALSE", "provenance"),
    list("inventory_id", paste(rep("1", 64L), collapse = ""), "inventory authority"),
    list("framework_id", paste(rep("2", 64L), collapse = ""), "family identity"),
    list("report_schema_id", fertility_report_schema_id(
        fertility_legacy_report_schema_version
    ), "provenance"),
    list("evidence_family_id", paste(rep("3", 64L), collapse = ""),
         "evidence family identity"),
    list("family_input_attestation_id", "not-a-hash", "provenance")
)) legacy_reject(legacy_mutation(case[[1L]], case[[2L]]), pattern = case[[3L]])
legacy_wrong_manifest <- legacy_original_fixture$bundle
legacy_wrong_manifest$family_manifest$shard_index[[1L]] <- "2"
legacy_reject(legacy_wrong_manifest, pattern = "family manifest")
legacy_wrong_results <- legacy_original_fixture$bundle
legacy_wrong_results$results$classification[[1L]] <- "pass"
legacy_reject(legacy_wrong_results, pattern = "preserved manifest-gated family")
legacy_wrong_result_count <- legacy_original_fixture$bundle
legacy_wrong_result_count$results <- legacy_wrong_result_count$results[-1L, , drop = FALSE]
legacy_reject(legacy_wrong_result_count, pattern = "results are not bound")
legacy_wrong_result_schema <- legacy_original_fixture$bundle
legacy_wrong_result_schema$results$elapsed_seconds <- NULL
legacy_reject(legacy_wrong_result_schema, pattern = "manifest schema")
legacy_wrong_summary <- legacy_original_fixture$bundle
legacy_wrong_summary$summary$files[[1L]] <- "999"
legacy_reject(legacy_wrong_summary, pattern = "classification summary")
legacy_extra_table <- legacy_original_fixture$bundle
legacy_extra_table$input_attestation <- data.frame(value = "forbidden")
legacy_reject(legacy_extra_table, pattern = "bundle schema")
legacy_missing_table <- legacy_original_fixture$bundle
legacy_missing_table$summary <- NULL
legacy_reject(legacy_missing_table, pattern = "bundle schema")
legacy_extra_provenance <- legacy_original_fixture$bundle
legacy_extra_provenance$provenance$merge_id <- paste(rep("4", 64L), collapse = "")
legacy_reject(legacy_extra_provenance, pattern = "manifest schema")
legacy_wrong_reason <- legacy_original_fixture$bundle
legacy_wrong_reason$results$secondary_categories[
    legacy_wrong_reason$results$id == fertility_accepted_ids()[[1L]]
] <- "hash-read-error"
legacy_reject(legacy_wrong_reason, pattern = "preserved manifest-gated family")
legacy_source_changed <- legacy_original_fixture$bundle
legacy_source_changed$provenance$created_at_utc <- "2026-01-02T00:00:00Z"
legacy_source_changed <- fertility_validate_assessment_legacy_original_bundle(
    legacy_source_changed, legacy_original_fixture$family_id, merge_live_inventory
)
stopifnot(!identical(legacy_source_changed$source_id, legacy_original$source_id))

assessment_gates <- fertility_validate_assessment_families(
    full_assessment, accepted_assessment
)
stopifnot(
    identical(assessment_gates$manifest_gate, "blocked-signature-mismatch"),
    identical(assessment_gates$explicit_local_evidence_gate, "validated")
)
assessment_replaced_full <- full_assessment
assessment_replaced_full$results$classification[
    assessment_replaced_full$results$id == "F0633"
] <- "pass"
expect_error(fertility_validate_assessment_families(
    assessment_replaced_full, accepted_assessment
), "preserved manifest-gated family")
for (reason in c("hash-read-error", "input-changed")) {
    assessment_wrong_reason <- full_assessment
    assessment_wrong_reason$results$secondary_categories[
        assessment_wrong_reason$results$id == "F0633"
    ] <- reason
    expect_error(fertility_validate_assessment_families(
        assessment_wrong_reason, accepted_assessment
    ), "preserved manifest-gated family")
}
assessment_mixed_reasons <- full_assessment
assessment_mixed_reasons$results$secondary_categories[
    assessment_mixed_reasons$results$id == "F0634"
] <- "hash-read-error"
expect_error(fertility_validate_assessment_families(
    assessment_mixed_reasons, accepted_assessment
), "preserved manifest-gated family")
assessment_multiple_reasons <- full_assessment
assessment_multiple_reasons$results$secondary_categories[
    assessment_multiple_reasons$results$id == "F0635"
] <- "signature-mismatch,input-changed"
expect_error(fertility_validate_assessment_families(
    assessment_multiple_reasons, accepted_assessment
), "preserved manifest-gated family")
assessment_bad_accepted <- accepted_assessment
assessment_bad_accepted$results$classification[[1L]] <- "inventory-hash-error"
expect_error(fertility_validate_assessment_families(
    full_assessment, assessment_bad_accepted
), "explicit local evidence")

actual <- tibble::tibble(
    number = c(1, 2 + 5e-8, haven::tagged_na("a")),
    text = c("a", NA, "c"),
    day = as.Date(c("2020-01-01", NA, "2020-01-03"))
)
attr(actual, "label") <- "synthetic"
attr(actual$number, "label") <- "number"
expected <- actual
stopifnot(fertility_compare_internal(actual, actual)$ok)
stopifnot(fertility_compare_haven(actual, expected)$ok)
expected$number[[2L]] <- expected$number[[2L]] + 4e-8
stopifnot(fertility_compare_haven(actual, expected)$ok)
large_actual <- tibble::tibble(value = c(1e15, 2))
large_expected <- tibble::tibble(value = c(1e15 + 1, 2))
stopifnot(fertility_compare_haven(large_actual, large_expected)$classification ==
          "value-mismatch")
outlier_actual <- tibble::tibble(value = rep(0, 10000L))
outlier_expected <- outlier_actual
outlier_expected$value[[9876L]] <- 2e-7
stopifnot(fertility_compare_haven(outlier_actual, outlier_expected)$classification ==
          "value-mismatch")
expected$number[[2L]] <- 3
stopifnot(fertility_compare_haven(actual, expected)$classification == "value-mismatch")
expected <- actual
expected$number[[3L]] <- haven::tagged_na("b")
stopifnot(fertility_compare_haven(actual, expected)$classification ==
          "tagged-missing-mismatch")
expected <- actual
expected$number[[2L]] <- NaN
actual_missing <- actual
actual_missing$number[[2L]] <- NA_real_
stopifnot(fertility_compare_haven(actual_missing, expected)$classification ==
          "missing-kind-mismatch")
expected <- actual
attr(expected$text, "label") <- "different"
stopifnot(fertility_compare_haven(actual, expected)$classification ==
          "attribute-label-mismatch")
changed <- actual
changed$text[[1L]] <- "different"
stopifnot(fertility_compare_internal(actual, changed)$classification ==
          "internal-collector-mismatch")
internal_float <- actual
internal_float$number[[2L]] <- internal_float$number[[2L]] + 1e-12
stopifnot(!fertility_compare_internal(actual, internal_float)$ok)
date_float <- actual
date_float$day[[1L]] <- structure(
    unclass(date_float$day[[1L]]) + 1e-8, class = "Date"
)
stopifnot("date-mismatch" %in%
          fertility_compare_haven(actual, date_float)$mismatches$category)
posix_actual <- tibble::tibble(
    time = as.POSIXct("1970-01-01 00:00:00", tz = "UTC")
)
posix_expected <- posix_actual
posix_expected$time <- structure(
    unclass(posix_expected$time) + 1e-8,
    class = c("POSIXct", "POSIXt"), tzone = "UTC"
)
stopifnot("date-mismatch" %in%
          fertility_compare_haven(posix_actual, posix_expected)$mismatches$category)

# Exhaustive comparison records independent mismatches in early and late columns.
multi_expected <- actual
multi_expected$number[[1L]] <- 9
multi_expected$text[[3L]] <- "different"
multi <- fertility_compare_haven(actual, multi_expected)$mismatches
stopifnot(all(c(1L, 2L) %in% multi$component),
          all(c("value-mismatch", "encoding-mismatch") %in% multi$category))
paired <- multi[1L, , drop = FALSE]
paired$pair <- "direct-haven"
unpaired <- fertility_mismatch_record("metadata-mismatch", "source-name-mismatch")
stopifnot(nrow(fertility_bind_mismatches(list(paired, unpaired))) == 2L)
short_actual <- tibble::tibble(value = c(1, 2, 3))
short_expected <- tibble::tibble(value = c(9, 2))
short_mismatches <- fertility_compare_haven(short_actual, short_expected)$mismatches
stopifnot(all(c("row-count-mismatch", "value-mismatch") %in%
              short_mismatches$detail))
pair_frames <- list(
    direct = tibble::tibble(value = c(1, 2)),
    rust = tibble::tibble(value = c(1, 3)),
    haven = tibble::tibble(value = c(4, 2))
)
pair_result <- fertility_compare_available_pairs(
    pair_frames, c(direct = FALSE, rust = FALSE, haven = FALSE)
)
stopifnot(identical(sort(unique(pair_result$mismatches$pair)),
                    c("direct-haven", "direct-rust", "rust-haven")))
equal_count_summary <- fertility_mismatch_summary(list(list(
    mismatches = pair_result$mismatches
)))
equal_count_public <- make_public_results(canonical_inventory[1L, , drop = FALSE])
equal_count_public$mismatch_count <- as.character(equal_count_summary$count)
equal_count_public$mismatch_categories <- equal_count_summary$categories
equal_count_public$mismatch_signatures <- equal_count_summary$signatures
equal_count_public$secondary_categories <- "value-mismatch"
stopifnot(isTRUE(fertility_validate_public_results(equal_count_public)))
tied_categories <- fertility_mismatch_summary(list(list(mismatches = data.frame(
    category = c("value-mismatch", "metadata-mismatch"),
    detail = c("private-b", "private-a"), component = c(2L, 1L),
    pair = c("direct-haven", "direct-rust"), stringsAsFactors = FALSE
))))
stopifnot(identical(
    tied_categories$categories,
    "metadata-mismatch=1,value-mismatch=1"
))
private_attribute <- pair_frames$haven
attr(private_attribute$value, "private_source_attribute") <- "different"
private_pair_result <- fertility_compare_available_pairs(
    list(direct = pair_frames$direct, rust = pair_frames$direct,
         haven = private_attribute),
    c(direct = FALSE, rust = FALSE, haven = FALSE)
)
stopifnot(any(grepl("private_source_attribute",
                   private_pair_result$mismatches$detail)),
          !any(grepl("private_source_attribute", private_pair_result$secondary)))
private_summary <- fertility_mismatch_summary(list(list(
    mismatches = private_pair_result$mismatches
)))
renamed_private <- private_pair_result$mismatches
renamed_private$detail <- sub(
    "private_source_attribute", "another_private_attribute", renamed_private$detail,
    fixed = TRUE
)
renamed_private$component <- renamed_private$component + 100L
renamed_summary <- fertility_mismatch_summary(list(list(mismatches = renamed_private)))
stopifnot(identical(private_summary$signatures, renamed_summary$signatures))
date_expected <- actual
date_expected$day[[1L]] <- date_expected$day[[1L]] + 1
stopifnot("date-mismatch" %in%
          fertility_compare_haven(actual, date_expected)$mismatches$category)
tag_expected <- actual
tag_expected$number[[3L]] <- haven::tagged_na("b")
stopifnot("tag-mismatch" %in%
          fertility_compare_haven(actual, tag_expected)$mismatches$category)
metadata_expected <- actual
attr(metadata_expected, "notes") <- "different"
stopifnot("metadata-mismatch" %in%
          fertility_compare_haven(actual, metadata_expected)$mismatches$category)

# Sizing and batching are deterministic, preserve fixed-string widths, isolate
# strL columns, and cannot create an unbounded traversal plan.
tile_options <- fertility_parse_arguments(c(
    "--chunk-rows=100", "--column-batch=8", "--memory-mib=128",
    "--cell-budget=300", "--max-tiles-per-batch=3"
))
tile_configuration <- fertility_tile_configuration(tile_options)
legacy_configuration_fields <- tile_configuration[setdiff(
    names(tile_configuration), c("encoding_overrides", "config_id")
)]
override_configuration <- fertility_tile_configuration(fertility_parse_arguments(c(
    "--chunk-rows=100", "--column-batch=8", "--memory-mib=128",
    "--cell-budget=300", "--max-tiles-per-batch=3",
    "--encoding-override=F0001:latin1"
)))
canonical_override_configuration <- fertility_tile_configuration(
    fertility_parse_arguments(c(
        "--chunk-rows=100", "--column-batch=8", "--memory-mib=128",
        "--cell-budget=300", "--max-tiles-per-batch=3",
        "--encoding-override=F0001:ISO-8859-1"
    ))
)
stopifnot(
    identical(tile_configuration$encoding_overrides, ""),
    identical(tile_configuration$config_id,
              fertility_stable_id(legacy_configuration_fields)),
    !identical(tile_configuration$config_id, override_configuration$config_id),
    identical(override_configuration$config_id,
              canonical_override_configuration$config_id)
)
stopifnot(identical(fertility_adaptive_rows(8, tile_configuration), 100L),
          identical(fertility_adaptive_rows(rep(8, 8), tile_configuration), 12L),
          identical(fertility_adaptive_rows(2045, tile_configuration), 100L),
          identical(fertility_adaptive_rows(Inf, tile_configuration), 1L),
          identical(fertility_strl_sample_offsets(0, 16L), 0),
          identical(fertility_strl_sample_offsets(5, 3L), c(0, 2, 4)),
          identical(fertility_strl_rows(12, 1L, tile_configuration), 100L),
          identical(
              fertility_column_batches(c("a", "wide", "long", "b"), 8L,
                                        c(8, 2045, Inf, 8)),
              list(c("a", "wide"), "long", "b")
          ))
finite_plan <- fertility_plan_offsets(5, 2L, 3L)
stopifnot(!finite_plan$ceiling, identical(finite_plan$offsets, c(0, 2, 4)))
stopifnot(fertility_plan_offsets(7, 2L, 3L)$ceiling,
          fertility_plan_offsets(Inf, 2L, 3L)$ceiling)
large_strl_configuration <- tile_configuration
large_strl_configuration$chunk_rows <- 10000L
large_strl_configuration$cell_budget <- 1000000L
small_payload_rows <- fertility_strl_rows(24, 1L, large_strl_configuration)
small_payload_plan <- fertility_plan_offsets(10000000, small_payload_rows, 2000L)
stopifnot(small_payload_rows == 10000L, !small_payload_plan$ceiling,
          length(small_payload_plan$offsets) == 1000L)

# A rare large payload missed by sampling is still memory-safe: a memory-limited
# range is split deterministically until the exceptional row is isolated, with no
# gaps, overlaps, or skipped rows.
adaptive_execute <- function(tile) {
    contains_rare <- tile$skip <= 13 && tile$skip + tile$n_max > 13
    memory <- contains_rare && tile$n_max > 1L
    list(
        tile_type = "value", batch = tile$batch, skip = tile$skip,
        n_max = tile$n_max, rows = if (memory) NA_integer_ else tile$n_max,
        classification = if (memory) "memory-limit" else "pass"
    )
}
run_adaptive_fixture <- function() {
    budget <- new.env(parent = emptyenv())
    budget$remaining <- 20L
    fertility_process_adaptive_range(
        1L, 0, 20L, "long", adaptive_execute, budget
    )
}
adaptive_leaves <- run_adaptive_fixture()
adaptive_again <- run_adaptive_fixture()
leaf_skip <- vapply(adaptive_leaves, `[[`, numeric(1), "skip")
leaf_n <- vapply(adaptive_leaves, `[[`, integer(1), "n_max")
stopifnot(
    identical(leaf_skip, vapply(adaptive_again, `[[`, numeric(1), "skip")),
    identical(leaf_n, vapply(adaptive_again, `[[`, integer(1), "n_max")),
    all(vapply(adaptive_leaves, `[[`, character(1), "classification") == "pass"),
    identical(leaf_skip, cumsum(c(0, head(leaf_n, -1L)))),
    sum(leaf_n) == 20L, any(leaf_skip == 13 & leaf_n == 1L)
)
limited_budget <- new.env(parent = emptyenv())
limited_budget$remaining <- 0L
limited_leaf <- fertility_process_adaptive_range(
    1L, 0, 20L, "long", adaptive_execute, limited_budget
)
stopifnot(length(limited_leaf) == 1L,
          limited_leaf[[1L]]$classification == "memory-limit")
execution_counter <- new.env(parent = emptyenv())
execution_counter$n <- 0L
counted_execute <- function(tile) {
    execution_counter$n <- execution_counter$n + 1L
    adaptive_execute(tile)
}
execution_ceiling <- 7L
execution_budget <- new.env(parent = emptyenv())
execution_budget$remaining <- execution_ceiling - 1L
invisible(fertility_process_adaptive_range(
    1L, 0, 20L, "long", counted_execute, execution_budget
))
stopifnot(execution_counter$n <= execution_ceiling)
stopifnot(fertility_memory_error(simpleError("vector memory exhausted")),
          !fertility_memory_error(simpleError("reader failed")))

# Structural parsing independently binds traversal to the source header and
# retains both wide fixed-string widths and strL identity.
wide_path <- file.path(root, "wide.dta")
haven::write_dta(data.frame(
    number = 1:3, fixed = rep(strrep("x", 2000), 3),
    long_string = rep(strrep("y", 3000), 3)
), wide_path, version = 14)
wide_structure <- fertility_structural_metadata(wide_path)
stopifnot(wide_structure$rows == 3, wide_structure$columns == 3L,
          identical(wide_structure$column_bytes, c(8, 2000, Inf)),
          identical(wide_structure$strl, c(FALSE, FALSE, TRUE)))
legacy_path <- file.path(root, "legacy.dta")
haven::write_dta(data.frame(number = 1:3, fixed = c("a", "bb", "ccc")),
                 legacy_path, version = 10)
legacy_structure <- fertility_structural_metadata(legacy_path)
stopifnot(legacy_structure$rows == 3, legacy_structure$columns == 2L,
          identical(legacy_structure$column_bytes, c(8, 3)))
tag_path <- file.path(root, "tag-values.dta")
haven::write_dta(data.frame(text = c("<N>", "</N>", "<variable_types>")),
                 tag_path, version = 14)
tag_structure <- fertility_structural_metadata(tag_path)
stopifnot(tag_structure$rows == 3, tag_structure$columns == 1L)
# A reader that keeps returning rows beyond the independent count is classified
# immediately; the configured window count, rather than reader behavior, bounds
# the number of probes.
nonterminating <- replicate(tile_configuration$beyond_end_windows,
                            c(direct = 1L, rust = 1L, haven = 1L), simplify = FALSE)
stopifnot(length(nonterminating) == 1L,
          all(vapply(nonterminating, fertility_row_termination_mismatch,
                     logical(1))))
stopifnot(fertility_structural_shape_mismatch(
              c(direct = 3L, rust = 3L), 4, 2L, 2L
          ),
          !fertility_structural_shape_mismatch(
              c(direct = 3L, rust = 3L), 3, 2L, 2L
          ))
if (requireNamespace("callr", quietly = TRUE)) {
    memory_failure <- tryCatch(callr::r(
        function() raw(512L * 1024L * 1024L), timeout = 30,
        env = c(R_MAX_VSIZE = "128M"), spinner = FALSE, show = FALSE,
        user_profile = FALSE, system_profile = FALSE
    ), error = identity)
    stopifnot(inherits(memory_failure, "error"),
              fertility_memory_error(memory_failure))
}

# Metadata plus every deterministic value tile is required for completeness. A
# mismatch in the first tile does not prevent later tiles from being assessed.
empty_mismatches <- fertility_bind_mismatches(list())
metadata_result <- list(
    tile_type = "metadata", classification = "pass", secondary = character(),
    mismatches = empty_mismatches, rows = 3L, elapsed_seconds = 0
)
synthetic_batches <- list("a", "b")
make_tile_result <- function(batch, skip, rows, classification = "pass",
                             mismatches = empty_mismatches) {
    expected_names <- synthetic_batches[[batch]]
    expected_hash <- fertility_projection_hash(expected_names, "test-framework")
    list(
        framework_id = "test-framework", tile_type = "value", batch = batch,
        skip = as.double(skip), n_max = 2L, rows = rows,
        classification = classification, secondary = character(),
        mismatches = mismatches,
        projection_expected_count = length(expected_names),
        projection_expected_hash = expected_hash,
        projection_counts = setNames(rep(length(expected_names), 3L),
                                     c("direct", "rust", "haven")),
        projection_hashes = setNames(rep(expected_hash, 3L),
                                     c("direct", "rust", "haven")),
        projection_ok = setNames(rep(TRUE, 3L),
                                 c("direct", "rust", "haven")),
        elapsed_seconds = 0
    )
}
make_terminal_result <- function(skip = 3, n_max = 1L, batch = 1L) {
    expected_names <- synthetic_batches[[1L]]
    expected_hash <- fertility_projection_hash(expected_names, "test-framework")
    list(
        framework_id = "test-framework", tile_type = "terminal", batch = batch,
        skip = as.double(skip), n_max = as.integer(n_max), rows = 0L,
        reader_rows = setNames(rep(0L, 3L), c("direct", "rust", "haven")),
        classification = "pass", secondary = character(),
        mismatches = empty_mismatches,
        projection_expected_count = length(expected_names),
        projection_expected_hash = expected_hash,
        projection_counts = setNames(rep(length(expected_names), 3L),
                                     c("direct", "rust", "haven")),
        projection_hashes = setNames(rep(expected_hash, 3L),
                                     c("direct", "rust", "haven")),
        projection_ok = setNames(rep(TRUE, 3L), c("direct", "rust", "haven")),
        elapsed_seconds = 0
    )
}
early_issue <- fertility_mismatch_record("value-mismatch", "value-mismatch", 1L)
traversed_tiles <- list(
    metadata_result,
    make_tile_result(1L, 0, 2L, "value-mismatch", early_issue),
    make_tile_result(1L, 2, 1L),
    make_tile_result(2L, 0, 2L),
    make_tile_result(2L, 2, 1L),
    make_terminal_result()
)
stopifnot(
    fertility_validate_tile_execution(
        traversed_tiles, synthetic_batches, 3, tile_configuration,
        length(traversed_tiles)
    ),
    fertility_validate_tile_completeness(
        traversed_tiles, synthetic_batches, 3, tile_configuration
    ),
    fertility_aggregate_classification(traversed_tiles, TRUE) == "value-mismatch"
)
reader_error_tiles <- traversed_tiles
reader_error_tiles[[2L]]$classification <- "haven-only-error"
reader_error_tiles[[2L]]$projection_ok[["haven"]] <- FALSE
reader_error_tiles[[2L]]$projection_counts[["haven"]] <- NA_integer_
reader_error_tiles[[2L]]$projection_hashes[["haven"]] <- NA_character_
stopifnot(
    fertility_validate_tile_execution(
        reader_error_tiles, synthetic_batches, 3, tile_configuration,
        length(reader_error_tiles)
    ),
    !fertility_validate_tile_completeness(
        reader_error_tiles, synthetic_batches, 3, tile_configuration
    ),
    fertility_aggregate_classification(
        reader_error_tiles, complete = FALSE, execution_complete = TRUE
    ) == "haven-only-error"
)
reader_planning_failure <- c(reader_error_tiles, list(list(
    tile_type = "planning", classification = "unresolved",
    secondary = "tile-ceiling-reached", mismatches = empty_mismatches
)))
reader_missing_value <- reader_error_tiles[-3L]
reader_missing_terminal <- reader_error_tiles[-length(reader_error_tiles)]
for (incomplete_tiles in list(
    reader_planning_failure, reader_missing_value, reader_missing_terminal
)) {
    stopifnot(
        !fertility_validate_tile_execution(
            incomplete_tiles, synthetic_batches, 3, tile_configuration,
            length(incomplete_tiles)
        ),
        fertility_aggregate_classification(
            incomplete_tiles, complete = FALSE, execution_complete = FALSE
        ) == "unresolved"
    )
}
execution_item <- list(
    id = "F0001", program = "dhs", level = "women", release = 118L,
    expected_sha512 = ""
)
execution_input <- list(
    input_id = paste(rep("e", 64L), collapse = ""),
    actual_sha512 = paste(rep("f", 128L), collapse = "")
)
complete_reader_error_result <- fertility_tiled_result(
    execution_item, test_framework_id, tile_configuration, execution_input,
    reader_error_tiles, synthetic_batches, 3,
    tiles_expected = length(reader_error_tiles)
)
incomplete_reader_error_result <- fertility_tiled_result(
    execution_item, test_framework_id, tile_configuration, execution_input,
    reader_missing_terminal, synthetic_batches, 3,
    tiles_expected = length(reader_error_tiles)
)
stopifnot(
    complete_reader_error_result$classification == "haven-only-error",
    !complete_reader_error_result$complete,
    complete_reader_error_result$tiles_expected ==
        complete_reader_error_result$tiles_completed,
    incomplete_reader_error_result$classification == "unresolved",
    incomplete_reader_error_result$tiles_expected ==
        incomplete_reader_error_result$tiles_completed + 1L
)
reader_flags <- setNames(rep(FALSE, 3L), c("direct", "rust", "haven"))
stopifnot(!length(fertility_reader_error_categories(reader_flags)))
reader_flags[["rust"]] <- TRUE
stopifnot(identical(fertility_reader_error_categories(reader_flags),
                    "rust-reader-error"))
legacy_tiles <- traversed_tiles
legacy_tiles <- lapply(legacy_tiles, function(tile) {
    tile$secondary <- c(tile$secondary, "-reader-error")
    tile
})
similar_artifact_tiles <- legacy_tiles
similar_artifact_tiles[[1L]]$secondary <- "-reader-errors"
expect_error(fertility_tile_secondary(
    similar_artifact_tiles, allow_legacy_empty_reader_artifact = TRUE
), "non-canonical reader-error")
expect_error(fertility_tiled_result(
    list(id = "F0001", program = "dhs", level = "women", release = 118L,
         expected_sha512 = ""),
    test_framework_id, tile_configuration,
    list(input_id = paste(rep("e", 64L), collapse = ""),
         actual_sha512 = paste(rep("f", 128L), collapse = "")),
    legacy_tiles, synthetic_batches, 3
), "legacy empty-reader artifact")
legacy_result <- fertility_tiled_result(
    list(id = "F0001", program = "dhs", level = "women", release = 118L,
         expected_sha512 = ""),
    test_framework_id, tile_configuration,
    list(input_id = paste(rep("e", 64L), collapse = ""),
         actual_sha512 = paste(rep("f", 128L), collapse = "")),
    legacy_tiles, synthetic_batches, 3,
    allow_legacy_empty_reader_artifact = TRUE
)
stopifnot(!grepl("-reader-error", legacy_result$secondary_categories, fixed = TRUE))
legacy_public <- fertility_result_frame(list(legacy_result))
legacy_public$build_provenance_id <- test_build_id
stopifnot(isTRUE(fertility_validate_public_results(legacy_public)))
recorded_item <- list(
    id = "F0001", program = "dhs", level = "women", release = 118L
)
stopifnot(fertility_recorded_result_valid(
    legacy_result, recorded_item, test_framework_id, tile_configuration
))
foreign_schema_result <- legacy_result
foreign_schema_result$schema_version <- fertility_schema_version + 1L
stopifnot(
    !fertility_recorded_result_valid(
        foreign_schema_result, recorded_item, test_framework_id, tile_configuration
    ),
    fertility_recorded_result_valid(
        foreign_schema_result, recorded_item, test_framework_id, tile_configuration,
        corpus_schema_version = fertility_schema_version + 1L
    )
)
stale_recorded_result <- legacy_result
stale_recorded_result$schema_version <- fertility_schema_version - 1L
stopifnot(!fertility_recorded_result_valid(
    stale_recorded_result, recorded_item, test_framework_id, tile_configuration
))
private_recorded_result <- legacy_result
private_recorded_result$private_path <- "/private/source"
stopifnot(!fertility_recorded_result_valid(
    private_recorded_result, recorded_item, test_framework_id, tile_configuration
))
attested_result <- legacy_result
attested_result$expected_sha512 <- paste(rep("a", 128L), collapse = "")
attested_result$actual_sha512 <- attested_result$expected_sha512
attested_result$classification <- "pass"
attested_result$secondary_categories <- ""
stopifnot(isTRUE(fertility_validate_recorded_input_attestation(attested_result)))
signature_failure <- attested_result
signature_failure$actual_sha512 <- paste(rep("b", 128L), collapse = "")
signature_failure$classification <- "inventory-hash-error"
signature_failure$secondary_categories <- "signature-mismatch"
stopifnot(isTRUE(fertility_validate_recorded_input_attestation(signature_failure)))
hash_read_failure <- attested_result
hash_read_failure$actual_sha512 <- NA_character_
hash_read_failure$classification <- "inventory-hash-error"
hash_read_failure$secondary_categories <- "hash-read-error"
stopifnot(isTRUE(fertility_validate_recorded_input_attestation(hash_read_failure)))
input_changed_failure <- attested_result
input_changed_failure$classification <- "inventory-hash-error"
input_changed_failure$secondary_categories <- "input-changed"
stopifnot(
    isTRUE(fertility_validate_recorded_input_attestation(
        input_changed_failure
    )),
    identical(fertility_changed_input_reason(list(
        input_id = input_changed_failure$input_id,
        hash_status = "ok",
        actual_sha512 = input_changed_failure$actual_sha512
    )), "input-changed"),
    identical(fertility_changed_input_reason(list(
        input_id = input_changed_failure$input_id,
        hash_status = "error", actual_sha512 = NA_character_
    )), "hash-read-error")
)
expect_error(fertility_changed_input_reason(list(
    input_id = input_changed_failure$input_id,
    hash_status = "error", actual_sha512 = input_changed_failure$actual_sha512
)), "inconsistent")
for (attestation in list(
    attested_result, signature_failure, hash_read_failure, input_changed_failure
)) {
    fresh_attestation <- attestation
    fresh_attestation$schema_version <- fertility_schema_version
    replay_attestation <- attestation
    replay_attestation$schema_version <- fertility_legacy_corpus_schema_version
    stopifnot(
        fertility_recorded_result_valid(
            fresh_attestation, recorded_item, test_framework_id, tile_configuration
        ),
        isTRUE(fertility_validate_recorded_input_attestation(fresh_attestation)),
        fertility_recorded_result_valid(
            replay_attestation, recorded_item, test_framework_id, tile_configuration,
            corpus_schema_version = fertility_legacy_corpus_schema_version
        ),
        isTRUE(fertility_validate_recorded_input_attestation(replay_attestation))
    )
}
input_changed_recorded <- input_changed_failure
input_changed_recorded$complete <- FALSE
input_changed_recorded$mismatch_count <- 0L
input_changed_recorded$mismatch_categories <- ""
input_changed_recorded$mismatch_signatures <- ""
for (corpus_schema_version in c(
    fertility_schema_version, fertility_legacy_corpus_schema_version
)) {
    input_changed_recorded$schema_version <- as.integer(corpus_schema_version)
    stopifnot(isTRUE(fertility_validate_recorded_input_result(
        input_changed_recorded, 3L
    )))
}
expect_error(fertility_validate_recorded_input_result(
    signature_failure, 1L
), "input-validation result is inconsistent")
expect_error(fertility_validate_recorded_input_result(
    hash_read_failure, 1L
), "input-validation result is inconsistent")
expect_error(fertility_validate_recorded_input_result(
    input_changed_failure, 1L
), "input-validation result is inconsistent")
unsupported_attested <- attested_result
unsupported_attested$classification <- "expected-unsupported-111"
stopifnot(isTRUE(fertility_validate_recorded_input_attestation(unsupported_attested)))
invalid_attestations <- list(
    { value <- signature_failure; value$expected_sha512 <- ""; value },
    { value <- signature_failure; value$actual_sha512 <- value$expected_sha512; value },
    { value <- attested_result; value$actual_sha512 <- paste(rep("b", 128L), collapse = ""); value },
    { value <- attested_result; value$actual_sha512 <- NA_character_; value },
    { value <- attested_result; value$classification <- "inventory-hash-error"; value },
    { value <- unsupported_attested; value$actual_sha512 <- paste(rep("b", 128L), collapse = ""); value },
    { value <- attested_result; value$secondary_categories <- "signature-mismatch"; value },
    { value <- hash_read_failure; value$actual_sha512 <- attested_result$actual_sha512; value },
    { value <- attested_result; value$input_id <- "invalid"; value },
    { value <- signature_failure; value$input_id <- "invalid"; value },
    { value <- hash_read_failure; value$input_id <- "invalid"; value },
    { value <- input_changed_failure; value$actual_sha512 <- NA_character_; value },
    { value <- input_changed_failure; value$input_id <- "invalid"; value },
    { value <- input_changed_failure; value$secondary_categories <-
        "input-changed,signature-mismatch"; value }
)
for (corpus_schema_version in c(
    fertility_schema_version, fertility_legacy_corpus_schema_version
)) {
    for (invalid_attestation in invalid_attestations) {
        invalid_attestation$schema_version <- as.integer(corpus_schema_version)
        expect_error(
            fertility_validate_recorded_input_attestation(invalid_attestation),
            "preflight attestation is inconsistent"
        )
    }
}
for (malformed_actual in list(NULL, NA, NA_real_)) {
    malformed_hash_read <- hash_read_failure
    malformed_hash_read$actual_sha512 <- malformed_actual
    stopifnot(!fertility_recorded_result_valid(
        malformed_hash_read, recorded_item, test_framework_id, tile_configuration
    ))
    expect_error(fertility_validate_recorded_input_attestation(
        malformed_hash_read
    ), "preflight attestation is inconsistent")
}
empty_expected_attestation <- attested_result
empty_expected_attestation$id <- "F0002"
empty_expected_attestation$expected_sha512 <- ""
input_attestation_id <- fertility_input_attestation_id(list(
    attested_result, empty_expected_attestation
))
changed_empty_attestation <- empty_expected_attestation
changed_empty_attestation$actual_sha512 <- paste(rep("c", 128L), collapse = "")
stopifnot(
    grepl("^[0-9a-f]{64}$", input_attestation_id),
    !identical(input_attestation_id, fertility_input_attestation_id(list(
        attested_result, changed_empty_attestation
    )))
)
expect_error(fertility_input_attestation_id(list(
    empty_expected_attestation, attested_result
)), "canonical case order")
stage_state <- new.env(parent = emptyenv())
stage_state$paths <- setNames(logical(), character())
stage_error <- tryCatch(fertility_prepare_report_stages(
    list(1L, 2L),
    create_stage = function(item) {
        path <- paste0("stage", item)
        stage_state$paths[[path]] <- TRUE
        list(stage = path)
    },
    write_stage = function(stage, item) item != 2L,
    remove_path = function(path) {
        stage_state$paths[[path]] <- FALSE
        TRUE
    },
    path_exists = function(path) isTRUE(stage_state$paths[[path]])
), error = identity)
stopifnot(inherits(stage_error, "error"),
          !any(unlist(as.list(stage_state$paths), use.names = FALSE)))
transaction_stages <- list(
    list(parent = "p1", stage = "s1", published = "p1/n1", old_current = "old1"),
    list(parent = "p2", stage = "s2", published = "p2/n2", old_current = NA_character_)
)
run_transaction_fixture <- function(fail_rename = 0L, fail_pointer = 0L,
                                    fail_rollback = FALSE,
                                    fail_before_rename = 0L,
                                    fail_before_pointer = 0L) {
    state <- new.env(parent = emptyenv())
    state$paths <- c(s1 = TRUE, s2 = TRUE, `p1/n1` = FALSE, `p2/n2` = FALSE)
    state$pointers <- c(p1 = "old1", p2 = NA_character_)
    state$rename_calls <- state$pointer_calls <- 0L
    rename_path <- function(from, to) {
        state$rename_calls <- state$rename_calls + 1L
        if (state$rename_calls == fail_rename) return(FALSE)
        state$paths[[from]] <- FALSE
        state$paths[[to]] <- TRUE
        TRUE
    }
    write_pointer <- function(parent, value) {
        state$pointer_calls <- state$pointer_calls + 1L
        if (state$pointer_calls == fail_pointer ||
            (fail_rollback && state$pointer_calls > fail_pointer)) return(FALSE)
        state$pointers[[parent]] <- value
        TRUE
    }
    remove_path <- function(path) {
        if (fail_rollback && startsWith(path, "p")) return(FALSE)
        if (endsWith(path, "CURRENT")) {
            state$pointers[[dirname(path)]] <- NA_character_
        } else state$paths[[path]] <- FALSE
        TRUE
    }
    expression <- function() fertility_publish_pointer_transaction(
        transaction_stages, rename_path, write_pointer, remove_path,
        pointer_state = function(parent) state$pointers[[parent]],
        path_exists = function(path) isTRUE(state$paths[[path]]),
        before_rename = function(index, stage) index != fail_before_rename,
        before_pointer = function(index, stage) index != fail_before_pointer
    )
    list(state = state, expression = expression)
}
transaction_success <- run_transaction_fixture()
stopifnot(isTRUE(transaction_success$expression()))
rename_failure <- run_transaction_fixture(fail_rename = 2L)
expect_error(rename_failure$expression(), "atomically publish every report bundle")
stopifnot(!isTRUE(rename_failure$state$paths[["p1/n1"]]))
pointer_failure <- run_transaction_fixture(fail_pointer = 2L)
expect_error(pointer_failure$expression(), "republished shard pointer")
stopifnot(identical(pointer_failure$state$pointers[["p1"]], "old1"),
          is.na(pointer_failure$state$pointers[["p2"]]),
          !isTRUE(pointer_failure$state$paths[["p1/n1"]]),
          !isTRUE(pointer_failure$state$paths[["p2/n2"]]))
rename_revalidation_failure <- run_transaction_fixture(fail_before_rename = 2L)
expect_error(rename_revalidation_failure$expression(),
             "atomically publish every report bundle")
stopifnot(
    identical(rename_revalidation_failure$state$pointers[["p1"]], "old1"),
    is.na(rename_revalidation_failure$state$pointers[["p2"]]),
    !isTRUE(rename_revalidation_failure$state$paths[["p1/n1"]]),
    !isTRUE(rename_revalidation_failure$state$paths[["p2/n2"]])
)
pointer_revalidation_failure <- run_transaction_fixture(
    fail_before_pointer = 2L
)
expect_error(pointer_revalidation_failure$expression(),
             "republished shard pointer")
stopifnot(
    identical(pointer_revalidation_failure$state$pointers[["p1"]], "old1"),
    is.na(pointer_revalidation_failure$state$pointers[["p2"]]),
    !isTRUE(pointer_revalidation_failure$state$paths[["p1/n1"]]),
    !isTRUE(pointer_revalidation_failure$state$paths[["p2/n2"]])
)
rollback_failure <- run_transaction_fixture(fail_pointer = 2L, fail_rollback = TRUE)
expect_error(rollback_failure$expression(), "rollback did not restore")
recorded_tile_spec <- fertility_value_tile(1L, 0, 2L, "a")
recorded_tile_fixture <- c(make_tile_result(1L, 0, 2L), list(
    schema_version = fertility_schema_version, config_id = tile_configuration$config_id,
    input_id = paste(rep("d", 64L), collapse = ""), id = "F0001",
    tile_id = recorded_tile_spec$tile_id, tile_type = recorded_tile_spec$type,
    column_hash = recorded_tile_spec$column_hash,
    timeout_seconds = tile_configuration$timeout_seconds,
    reader_rows = setNames(rep(2L, 3L), c("direct", "rust", "haven")),
    columns = 1L, column_names = character(), storage = character(),
    structural_rows = NA_real_, column_bytes = numeric(), strl = logical()
))
recorded_tile_fixture <- recorded_tile_fixture[!duplicated(names(recorded_tile_fixture),
                                                           fromLast = TRUE)]
stopifnot(isTRUE(fertility_validate_recorded_tile(recorded_tile_fixture)))
current_artifact_tile <- recorded_tile_fixture
current_artifact_tile$secondary <- "-reader-error"
expect_error(fertility_validate_recorded_tile(current_artifact_tile),
             "malformed or non-canonical")
expect_error(fertility_validate_recorded_tile(
    current_artifact_tile, allow_legacy_empty_reader_artifact = TRUE
), "malformed or non-canonical")
legacy_artifact_tile <- current_artifact_tile
legacy_artifact_tile$schema_version <- fertility_legacy_corpus_schema_version
expect_error(fertility_validate_recorded_tile(
    legacy_artifact_tile,
    corpus_schema_version = fertility_legacy_corpus_schema_version
), "malformed or non-canonical")
stopifnot(isTRUE(fertility_validate_recorded_tile(
    legacy_artifact_tile,
    corpus_schema_version = fertility_legacy_corpus_schema_version,
    allow_legacy_empty_reader_artifact = TRUE
)))
similar_legacy_artifact_tile <- legacy_artifact_tile
similar_legacy_artifact_tile$secondary <- "-reader-errors"
expect_error(fertility_validate_recorded_tile(
    similar_legacy_artifact_tile,
    corpus_schema_version = fertility_legacy_corpus_schema_version,
    allow_legacy_empty_reader_artifact = TRUE
), "malformed or non-canonical")
foreign_schema_tile <- recorded_tile_fixture
foreign_schema_tile$schema_version <- fertility_schema_version + 1L
expect_error(fertility_validate_recorded_tile(foreign_schema_tile),
             "schema is invalid")
stopifnot(isTRUE(fertility_validate_recorded_tile(
    foreign_schema_tile, corpus_schema_version = fertility_schema_version + 1L
)))
private_tile <- recorded_tile_fixture
private_tile$secondary <- "/private/source"
expect_error(fertility_validate_recorded_tile(private_tile),
             "malformed or non-canonical")
malformed_tile <- recorded_tile_fixture
malformed_tile$unexpected <- "stale"
expect_error(fertility_validate_recorded_tile(malformed_tile), "schema is invalid")
missing_terminal <- traversed_tiles[-length(traversed_tiles)]
duplicate_terminal <- c(traversed_tiles, list(make_terminal_result()))
wrong_terminal_skip <- traversed_tiles
wrong_terminal_skip[[length(wrong_terminal_skip)]]$skip <- 4
wrong_terminal_n_max <- traversed_tiles
wrong_terminal_n_max[[length(wrong_terminal_n_max)]]$n_max <- 2L
wrong_terminal_batch <- traversed_tiles
wrong_terminal_batch[[length(wrong_terminal_batch)]]$batch <- 2L
for (invalid in list(missing_terminal, duplicate_terminal, wrong_terminal_skip,
                     wrong_terminal_n_max, wrong_terminal_batch)) {
    stopifnot(!fertility_validate_tile_completeness(
        invalid, synthetic_batches, 3, tile_configuration
    ))
}
two_probe_configuration <- tile_configuration
two_probe_configuration$beyond_end_windows <- 2L
two_probe_tiles <- c(traversed_tiles, list(make_terminal_result(skip = 4)))
stopifnot(fertility_validate_tile_completeness(
    two_probe_tiles, synthetic_batches, 3, two_probe_configuration
))
zero_batches <- fertility_structural_batches(character(), 8L, numeric(), 0L)
stopifnot(length(zero_batches) == 1L, identical(zero_batches[[1L]], character()))
retarget_projection <- function(tile, names) {
    hash <- fertility_projection_hash(names, "test-framework")
    tile$projection_expected_count <- length(names)
    tile$projection_expected_hash <- hash
    tile$projection_counts[] <- length(names)
    tile$projection_hashes[] <- hash
    tile
}
zero_column_tiles <- list(
    metadata_result,
    retarget_projection(make_tile_result(1L, 0, 2L), character()),
    retarget_projection(make_tile_result(1L, 2, 1L), character()),
    retarget_projection(make_terminal_result(), character())
)
stopifnot(
    fertility_validate_tile_execution(
        zero_column_tiles, zero_batches, 3, tile_configuration,
        length(zero_column_tiles)
    ),
    fertility_validate_tile_completeness(
        zero_column_tiles, zero_batches, 3, tile_configuration
    )
)
zero_row_tiles <- list(
    metadata_result,
    make_tile_result(1L, 0, 0L),
    make_tile_result(2L, 0, 0L),
    make_terminal_result(skip = 0)
)
stopifnot(
    fertility_validate_tile_execution(
        zero_row_tiles, synthetic_batches, 0, tile_configuration,
        length(zero_row_tiles)
    ),
    fertility_validate_tile_completeness(
        zero_row_tiles, synthetic_batches, 0, tile_configuration
    ),
    !fertility_validate_tile_execution(
        c(zero_row_tiles, list(list())), synthetic_batches, 0,
        tile_configuration, length(zero_row_tiles) + 1L
    )
)
reader_error_without_observed_rows <- reader_error_tiles
reader_error_without_observed_rows[[2L]]$rows <- NA_integer_
stopifnot(fertility_validate_tile_execution(
    reader_error_without_observed_rows, synthetic_batches, 3,
    tile_configuration, length(reader_error_without_observed_rows)
))
shared_empty <- fertility_projection_attestation(
    list(direct = data.frame(), rust = data.frame(), haven = data.frame()),
    c(direct = FALSE, rust = FALSE, haven = FALSE), "a", "test-framework"
)
stopifnot(!any(shared_empty$ok), all(shared_empty$counts == 0L),
          nchar(shared_empty$expected_hash) == 64L)
wrong_projection_tiles <- traversed_tiles
for (i in 2:length(wrong_projection_tiles)) {
    wrong_projection_tiles[[i]]$projection_counts[] <- 0L
    wrong_projection_tiles[[i]]$projection_hashes[] <-
        fertility_projection_hash(character(), "test-framework")
    wrong_projection_tiles[[i]]$projection_ok[] <- FALSE
    wrong_projection_tiles[[i]]$classification <- "metadata-mismatch"
}
stopifnot(!fertility_validate_tile_completeness(
              wrong_projection_tiles, synthetic_batches, 3, tile_configuration
          ),
          fertility_aggregate_classification(wrong_projection_tiles, FALSE) != "pass")
public_projection_result <- fertility_result_frame(list(list(
    framework_id = "framework", id = "F0001", program = "dhs", level = "women",
    release = 118L, classification = "metadata-mismatch",
    projection_expected_hash = shared_empty$expected_hash,
    projection_hashes = shared_empty$hashes
)))
stopifnot(!any(grepl("projection", names(public_projection_result))))
unresolved_tiles <- traversed_tiles
unresolved_tiles[[2L]]$classification <- "unresolved"
unresolved_tiles[[2L]]$mismatches <- empty_mismatches
stopifnot(fertility_aggregate_classification(unresolved_tiles, TRUE) == "unresolved")
changed_tiles <- traversed_tiles
changed_tiles[[2L]]$classification <- "input-changed"
stopifnot(fertility_aggregate_classification(changed_tiles, FALSE) ==
          "inventory-hash-error")

item <- as.list(inventory[1L, , drop = FALSE])
item_input <- fertility_capture_input(item)
checkpoint <- list(
    schema_version = fertility_schema_version, framework_id = "framework",
    input_id = item_input$input_id,
    id = inventory$id[[1L]], expected_sha512 = inventory$expected_sha512[[1L]],
    release = inventory$release[[1L]], timeout_seconds = 1L,
    classification = "match"
)
stopifnot(fertility_checkpoint_valid(
              checkpoint, item, "framework", item_input, 1L
          ),
          !fertility_checkpoint_valid(
              checkpoint, item, "framework", item_input, 2L
          ),
          !fertility_should_retry(checkpoint))
checkpoint$classification <- "timeout"
stopifnot(fertility_should_retry(checkpoint))
checkpoint$expected_sha512 <- "changed"
stopifnot(!fertility_checkpoint_valid(checkpoint, item, "framework"))
checkpoint_path <- file.path(root, "checkpoint.rds")
fertility_atomic_save_rds(checkpoint, checkpoint_path)
stopifnot(identical(readRDS(checkpoint_path), checkpoint))

# Tile checkpoints resume independently. Resource failures rerun only with
# --retry, while completed semantic mismatches remain reusable.
tile_item <- item
tile_input <- item_input
tile <- fertility_value_tile(1L, 0, 2L, "x")
tile_checkpoint <- file.path(root, "tile-checkpoint.rds")
tile_counter <- new.env(parent = emptyenv())
tile_counter$n <- 0L
tile_execute <- function(item, tile, input) {
    tile_counter$n <- tile_counter$n + 1L
    list(
        schema_version = fertility_schema_version, framework_id = "framework",
        id = item$id, tile_id = tile$tile_id, tile_type = tile$type,
        batch = tile$batch, skip = tile$skip, n_max = tile$n_max,
        classification = "timeout", secondary = character(),
        mismatches = fertility_bind_mismatches(list()), rows = NA_integer_,
        columns = NA_integer_, column_names = character(), storage = character(),
        elapsed_seconds = 0
    )
}
tile_config <- fertility_tile_configuration(fertility_parse_arguments(
    "--timeout-seconds=1"
))
first_tile <- fertility_process_tile(
    tile_item, tile, tile_checkpoint, "framework", tile_config, tile_input,
    FALSE, tile_execute
)
resumed_tile <- fertility_process_tile(
    tile_item, tile, tile_checkpoint, "framework", tile_config, tile_input,
    FALSE, tile_execute
)
retried_tile <- fertility_process_tile(
    tile_item, tile, tile_checkpoint, "framework", tile_config, tile_input,
    TRUE, tile_execute
)
stopifnot(!first_tile$resumed, resumed_tile$resumed, !retried_tile$resumed,
          tile_counter$n == 2L)
metadata_retry_checkpoint <- file.path(root, "metadata-retry-checkpoint.rds")
metadata_retry_counter <- new.env(parent = emptyenv())
metadata_retry_counter$n <- 0L
metadata_retry_execute <- function(item, tile, input) {
    metadata_retry_counter$n <- metadata_retry_counter$n + 1L
    list(
        schema_version = fertility_schema_version, framework_id = "framework",
        id = item$id, tile_id = tile$tile_id, tile_type = tile$type,
        batch = tile$batch, skip = tile$skip, n_max = tile$n_max,
        classification = "unresolved",
        secondary = "structural-metadata-unavailable",
        mismatches = fertility_bind_mismatches(list()), rows = 3L,
        reader_rows = c(direct = 3L, rust = 3L, haven = NA_integer_),
        columns = 1L, column_names = "x", storage = "double",
        structural_rows = NA_real_, column_bytes = numeric(), strl = logical(),
        projection_expected_count = NA_integer_,
        projection_expected_hash = NA_character_,
        projection_counts = c(direct = NA_integer_, rust = NA_integer_,
                              haven = NA_integer_),
        projection_hashes = c(direct = NA_character_, rust = NA_character_,
                              haven = NA_character_),
        projection_ok = c(direct = NA, rust = NA, haven = NA),
        elapsed_seconds = 0
    )
}
metadata_retry_tile <- fertility_metadata_tile()
metadata_retry_first <- fertility_process_tile(
    tile_item, metadata_retry_tile, metadata_retry_checkpoint, "framework",
    tile_config, tile_input, FALSE, metadata_retry_execute
)
metadata_retry_resumed <- fertility_process_tile(
    tile_item, metadata_retry_tile, metadata_retry_checkpoint, "framework",
    tile_config, tile_input, FALSE, metadata_retry_execute
)
metadata_retry_rerun <- fertility_process_tile(
    tile_item, metadata_retry_tile, metadata_retry_checkpoint, "framework",
    tile_config, tile_input, TRUE, metadata_retry_execute
)
stopifnot(
    !metadata_retry_first$resumed, metadata_retry_resumed$resumed,
    !metadata_retry_rerun$resumed, metadata_retry_counter$n == 2L,
    metadata_retry_rerun$result$classification == "unresolved",
    identical(
        metadata_retry_rerun$result$secondary,
        "structural-metadata-unavailable"
    )
)
foreign_tile_checkpoint <- first_tile$result
foreign_tile_checkpoint$schema_version <- fertility_schema_version + 1L
stopifnot(
    !fertility_tile_checkpoint_valid(
        foreign_tile_checkpoint, tile_item, tile, "framework", tile_config$config_id,
        tile_input$input_id, tile_config$timeout_seconds
    ),
    fertility_tile_checkpoint_valid(
        foreign_tile_checkpoint, tile_item, tile, "framework", tile_config$config_id,
        tile_input$input_id, tile_config$timeout_seconds,
        corpus_schema_version = fertility_schema_version + 1L
    ),
    !fertility_tile_checkpoint_valid(
        first_tile$result, tile_item, tile, "framework",
        override_configuration$config_id, tile_input$input_id,
        tile_config$timeout_seconds
    )
)
sizing_tile <- fertility_sizing_tile(1L, "long", 10000000,
                                     tile_config$strl_sample_count)
sizing_checkpoint <- file.path(root, "sizing-checkpoint.rds")
sizing_counter <- new.env(parent = emptyenv())
sizing_counter$n <- 0L
sizing_execute <- function(item, tile, input) {
    sizing_counter$n <- sizing_counter$n + 1L
    list(
        schema_version = fertility_schema_version, framework_id = "framework",
        id = item$id, tile_id = tile$tile_id, tile_type = tile$type,
        batch = tile$batch, skip = tile$skip, n_max = tile$n_max,
        classification = "pass", secondary = character(),
        mismatches = fertility_bind_mismatches(list()), rows = 16L,
        payload_bytes_per_row = 24, chosen_rows = 10000L,
        elapsed_seconds = 0
    )
}
first_sizing <- fertility_process_tile(
    tile_item, sizing_tile, sizing_checkpoint, "framework", tile_config,
    tile_input, FALSE, sizing_execute
)
resumed_sizing <- fertility_process_tile(
    tile_item, sizing_tile, sizing_checkpoint, "framework", tile_config,
    tile_input, FALSE, sizing_execute
)
stopifnot(!first_sizing$resumed, resumed_sizing$resumed,
          sizing_counter$n == 1L,
          resumed_sizing$result$chosen_rows == 10000L,
          identical(resumed_sizing$result$column_hash, sizing_tile$column_hash))
adaptive_checkpoint_root <- file.path(root, "adaptive-checkpoints")
dir.create(adaptive_checkpoint_root)
adaptive_counter <- new.env(parent = emptyenv())
adaptive_counter$n <- 0L
adaptive_checkpoint_execute <- function(item, tile, input) {
    adaptive_counter$n <- adaptive_counter$n + 1L
    contains_rare <- tile$skip <= 13 && tile$skip + tile$n_max > 13
    memory <- contains_rare && tile$n_max > 1L
    list(
        schema_version = fertility_schema_version, framework_id = "framework",
        id = item$id, tile_id = tile$tile_id, tile_type = tile$type,
        batch = tile$batch, skip = tile$skip, n_max = tile$n_max,
        classification = if (memory) "memory-limit" else "pass",
        secondary = character(), mismatches = fertility_bind_mismatches(list()),
        rows = if (memory) NA_integer_ else tile$n_max, elapsed_seconds = 0
    )
}
run_checkpointed_adaptation <- function() {
    budget <- new.env(parent = emptyenv())
    budget$remaining <- 20L
    process <- function(tile) fertility_process_tile(
        tile_item, tile,
        file.path(adaptive_checkpoint_root, paste0(tile$tile_id, ".rds")),
        "framework", tile_config, tile_input, FALSE,
        adaptive_checkpoint_execute
    )$result
    fertility_process_adaptive_range(1L, 0, 20L, "long", process, budget)
}
checkpointed_first <- run_checkpointed_adaptation()
first_execution_count <- adaptive_counter$n
checkpointed_resumed <- run_checkpointed_adaptation()
stopifnot(first_execution_count > 1L,
          adaptive_counter$n == first_execution_count,
          identical(vapply(checkpointed_first, `[[`, numeric(1), "skip"),
                    vapply(checkpointed_resumed, `[[`, numeric(1), "skip")),
          identical(vapply(checkpointed_first, `[[`, integer(1), "n_max"),
                    vapply(checkpointed_resumed, `[[`, integer(1), "n_max")))

supported_item <- as.list(inventory[2L, , drop = FALSE])
supported_item$path <- normalizePath(primary_second, winslash = "/")
supported_input <- fertility_capture_input(supported_item)
supported_checkpoint <- list(
    schema_version = fertility_schema_version, framework_id = "framework",
    input_id = supported_input$input_id,
    id = supported_item$id, expected_sha512 = "", release = supported_item$release,
    timeout_seconds = 1L, actual_sha512 = supported_input$actual_sha512,
    classification = "match"
)
stopifnot(fertility_checkpoint_input_current(supported_checkpoint, supported_item))
writeBin(as.raw(1L), supported_item$path, useBytes = TRUE)
stopifnot(!fertility_checkpoint_input_current(supported_checkpoint, supported_item))

unsupported_item <- as.list(inventory[1L, , drop = FALSE])
unsupported <- fertility_worker(
    unsupported_item, file.path(script_dir, "compare.R"),
    root, root, "framework", 1L, fertility_file_sha512(unsupported_item$path)
)
stopifnot(unsupported$classification == "expected-unsupported-111")
hash_item <- as.list(inventory[2L, , drop = FALSE])
hash_item$expected_sha512 <- paste(rep("0", 128L), collapse = "")
hash_failure <- fertility_worker(
    hash_item, file.path(script_dir, "compare.R"), root, root, "framework", 1L,
    fertility_file_sha512(hash_item$path)
)
stopifnot(hash_failure$classification == "input-signature-mismatch")

# Real metadata discovery uses zero-row frames plus zero-column shape reads; value
# workers materialize only their explicit row/column window.
bounded_path <- file.path(root, "bounded.dta")
bounded_data <- tibble::tibble(
    number = 1:5,
    text = c("encoding_probe_ascii", "b", "c", "d", "e"),
    day = as.Date("2020-01-01") + 0:4,
    encoding_name_ascii = 6:10
)
haven::write_dta(bounded_data, bounded_path, version = 14)
encoding_probe_path <- file.path(root, "encoding-probe.dta")
encoding_probe_bytes <- readBin(
    bounded_path, "raw", n = file.info(bounded_path)$size
)
encoding_needle <- charToRaw("encoding_probe_ascii")
encoding_starts <- seq_len(length(encoding_probe_bytes) - length(encoding_needle) + 1L)
encoding_matches <- encoding_starts[vapply(encoding_starts, function(start) {
    identical(
        encoding_probe_bytes[start:(start + length(encoding_needle) - 1L)],
        encoding_needle
    )
}, logical(1))]
stopifnot(length(encoding_matches) == 1L)
encoding_probe_bytes[[encoding_matches[[1L]]]] <- as.raw(0x80)
encoding_name_needle <- charToRaw("encoding_name_ascii")
encoding_name_starts <- seq_len(
    length(encoding_probe_bytes) - length(encoding_name_needle) + 1L
)
encoding_name_matches <- encoding_name_starts[vapply(
    encoding_name_starts, function(start) identical(
        encoding_probe_bytes[start:(start + length(encoding_name_needle) - 1L)],
        encoding_name_needle
    ), logical(1)
)]
stopifnot(length(encoding_name_matches) == 1L)
encoding_probe_bytes[[encoding_name_matches[[1L]]]] <- as.raw(0x80)
writeBin(encoding_probe_bytes, encoding_probe_path)
stopifnot(fertility_release(encoding_probe_path) == 118L)
rare_strl_path <- file.path(root, "rare-strl.dta")
haven::write_dta(data.frame(
    long_string = c(rep("x", 999L), strrep("z", 100000L))
), rare_strl_path, version = 14)
rare_structure <- fertility_structural_metadata(rare_strl_path)
stopifnot(rare_structure$rows == 1000, identical(rare_structure$strl, TRUE))
bounded_item <- list(
    id = "F9900", program = "dhs", level = "women", release = 118L,
    path = normalizePath(bounded_path, winslash = "/"), expected_sha512 = ""
)
haven_zero_column <- tryCatch(
    haven::read_dta(bounded_path, col_select = character()), error = identity
)
stopifnot(inherits(haven_zero_column, "error"))
checkout_raw <- file.path(script_dir, "..", "..", "target",
                          "fertility-surveys", "raw")
checkout_library <- file.path(checkout_raw, "library")
build_pointer <- file.path(checkout_raw, "builds", "CURRENT")
if (file.exists(build_pointer)) {
    build_id <- readLines(build_pointer, warn = FALSE, n = 1L)
    if (length(build_id) == 1L && grepl("^[0-9a-f]{64}$", build_id)) {
        checkout_library <- file.path(checkout_raw, "builds", build_id, "library")
    }
}
if (dir.exists(file.path(checkout_library, "dtaparser"))) {
    old_paths <- .libPaths()
    .libPaths(c(checkout_library, old_paths))
    on.exit(.libPaths(old_paths), add = TRUE)
    installed_dtaparser <- normalizePath(find.package("dtaparser"), winslash = "/")
    metadata_worker <- fertility_worker_tile(
        bounded_item, fertility_metadata_tile(), file.path(script_dir, "compare.R"),
        dirname(installed_dtaparser), installed_dtaparser, "framework", 10L
    )
    stopifnot(metadata_worker$rows == 5L,
              metadata_worker$columns == ncol(bounded_data),
              identical(metadata_worker$column_names, names(bounded_data)))
    structural_failure_message <- "private synthetic structural parser failure"
    structural_failure_worker <- (function() {
        worker_environment <- environment(fertility_worker_tile)
        had_binding <- exists(
            "fertility_structural_metadata", envir = worker_environment,
            inherits = FALSE
        )
        original <- get(
            "fertility_structural_metadata", envir = worker_environment,
            inherits = TRUE
        )
        assign(
            "fertility_structural_metadata",
            function(path) stop(structural_failure_message),
            envir = worker_environment
        )
        on.exit({
            if (had_binding) {
                assign(
                    "fertility_structural_metadata", original,
                    envir = worker_environment
                )
            } else {
                rm("fertility_structural_metadata", envir = worker_environment)
            }
        }, add = TRUE)
        fertility_worker_tile(
            bounded_item, fertility_metadata_tile(),
            file.path(script_dir, "compare.R"), dirname(installed_dtaparser),
            installed_dtaparser, "framework", 10L
        )
    })()
    structural_planning_failure <- list(
        classification = "unresolved",
        secondary = "structural-metadata-unavailable",
        mismatches = fertility_mismatch_record(
            "unresolved", "structural-metadata-unavailable"
        )
    )
    structural_failure_tiles <- list(
        structural_failure_worker, structural_planning_failure
    )
    stopifnot(
        structural_failure_worker$classification == "unresolved",
        all(structural_failure_worker$reader_rows[c("direct", "rust")] ==
            nrow(bounded_data)),
        is.na(structural_failure_worker$reader_rows[["haven"]]),
        identical(
            structural_failure_worker$secondary,
            "structural-metadata-unavailable"
        ),
        !any(grepl("reader-error", structural_failure_worker$secondary, fixed = TRUE)),
        is.na(structural_failure_worker$structural_rows),
        !length(structural_failure_worker$column_bytes),
        !length(structural_failure_worker$strl),
        fertility_aggregate_classification(
            structural_failure_tiles, complete = FALSE
        ) == "unresolved",
        identical(
            unique(fertility_tile_secondary(structural_failure_tiles)),
            "structural-metadata-unavailable"
        ),
        !any(grepl(
            structural_failure_message,
            as.character(unlist(structural_failure_tiles, use.names = FALSE)),
            fixed = TRUE
        ))
    )
    bounded_tile <- fertility_value_tile(1L, 1L, 2L, c("number", "day"))
    bounded_worker <- fertility_worker_tile(
        bounded_item, bounded_tile, file.path(script_dir, "compare.R"),
        dirname(installed_dtaparser), installed_dtaparser, "framework", 10L
    )
    stopifnot(bounded_worker$rows == 2L, bounded_worker$columns == 2L,
              all(bounded_worker$projection_ok),
              all(bounded_worker$projection_counts == 2L),
              all(bounded_worker$projection_hashes ==
                  bounded_worker$projection_expected_hash),
              !any(c("number", "day") %in% unlist(
                  bounded_worker[c("projection_hashes", "projection_expected_hash")],
                  use.names = FALSE
              )))
    default_tile <- fertility_value_tile(1L, 0L, 1L, "text")
    stopifnot(
        identical(
            fertility_tile_read("direct", bounded_path, default_tile),
            dtaparser::read_dta(
                bounded_path, col_select = tidyselect::all_of("text"),
                skip = 0L, n_max = 1L, .name_repair = "minimal"
            )
        ),
        identical(
            fertility_tile_read("rust", bounded_path, default_tile),
            dtaparser:::.read_dta_rust_vectors(
                bounded_path, col_select = tidyselect::all_of("text"),
                skip = 0L, n_max = 1L, .name_repair = "minimal"
            )
        ),
        identical(
            fertility_tile_read("haven", bounded_path, default_tile),
            haven::read_dta(
                bounded_path, col_select = tidyselect::all_of("text"),
                skip = 0L, n_max = 1L, .name_repair = "minimal"
            )
        )
    )
    encoding_item <- bounded_item
    encoding_item$id <- "F9903"
    encoding_item$path <- normalizePath(encoding_probe_path, winslash = "/")
    encoding_item$encoding_override <- "ISO-8859-1"
    encoding_values <- lapply(c("direct", "rust", "haven"), function(reader) {
        fertility_tile_read(
            reader, encoding_item$path, default_tile,
            encoding = encoding_item$encoding_override
        )
    })
    stopifnot(
        identical(encoding_values[[1L]], encoding_values[[2L]]),
        identical(encoding_values[[1L]], encoding_values[[3L]]),
        startsWith(encoding_values[[1L]]$text[[1L]], intToUtf8(128L))
    )
    encoding_worker <- fertility_worker_tile(
        encoding_item, default_tile, file.path(script_dir, "compare.R"),
        dirname(installed_dtaparser), installed_dtaparser, "framework", 10L
    )
    encoding_metadata <- fertility_worker_tile(
        encoding_item, fertility_metadata_tile(), file.path(script_dir, "compare.R"),
        dirname(installed_dtaparser), installed_dtaparser, "framework", 10L
    )
    encoding_terminal_probe <- (function() {
        worker_environment <- environment(fertility_worker_tile)
        original <- get(
            "fertility_tile_read", envir = worker_environment, inherits = TRUE
        )
        calls <- list()
        assign("fertility_tile_read", function(reader, path, tile, encoding = NULL) {
            if (identical(tile$type, "terminal")) {
                calls[[length(calls) + 1L]] <<- list(
                    reader = reader, encoding = encoding
                )
            }
            original(reader, path, tile, encoding = encoding)
        }, envir = worker_environment)
        on.exit(assign(
            "fertility_tile_read", original, envir = worker_environment
        ), add = TRUE)
        result <- fertility_worker_tile(
            encoding_item, fertility_value_tile(
                1L, nrow(bounded_data), 1L,
                encoding_metadata$column_names[[4L]], type = "terminal", probe = 1L
            ), file.path(script_dir, "compare.R"), dirname(installed_dtaparser),
            installed_dtaparser, "framework", 10L
        )
        list(result = result, calls = calls)
    })()
    encoding_terminal <- encoding_terminal_probe$result
    encoding_sizing <- fertility_worker_tile(
        encoding_item, fertility_sizing_tile(1L, "text", 1, 1L),
        file.path(script_dir, "compare.R"), dirname(installed_dtaparser),
        installed_dtaparser, "framework", 10L
    )
    stopifnot(
        encoding_worker$classification == "pass",
        all(encoding_worker$projection_ok),
        encoding_metadata$classification == "pass",
        startsWith(encoding_metadata$column_names[[4L]], intToUtf8(128L)),
        identical(
            encoding_metadata$column_names,
            as.character(dtaparser:::.dta_metadata(
                encoding_item$path, encoding = "ISO-8859-1"
            ))
        ),
        encoding_terminal$classification == "pass",
        all(encoding_terminal$reader_rows == 0L),
        identical(
            vapply(encoding_terminal_probe$calls, `[[`, character(1), "reader"),
            c("direct", "rust", "haven")
        ),
        length(encoding_terminal_probe$calls) == 3L,
        all(vapply(encoding_terminal_probe$calls, function(call) {
            identical(call$encoding, encoding_item$encoding_override)
        }, logical(1))),
        encoding_sizing$classification == "pass",
        encoding_sizing$samples_completed == 1L
    )
    wide_item <- bounded_item
    wide_item$id <- "F9901"
    wide_item$path <- normalizePath(wide_path, winslash = "/")
    sizing_worker <- fertility_worker_tile(
        wide_item, fertility_sizing_tile(1L, "long_string", 3, 16L),
        file.path(script_dir, "compare.R"), dirname(installed_dtaparser),
        installed_dtaparser, "framework", 10L
    )
    stopifnot(sizing_worker$classification == "pass",
              sizing_worker$samples_requested == 3L,
              sizing_worker$samples_completed == 3L,
              sizing_worker$payload_bytes_per_row >= 9000,
              !any(c("long_string", strrep("y", 10)) %in%
                   unlist(sizing_worker, use.names = FALSE)))
    rare_item <- wide_item
    rare_item$id <- "F9902"
    rare_item$path <- normalizePath(rare_strl_path, winslash = "/")
    rare_sizing <- fertility_worker_tile(
        rare_item, fertility_sizing_tile(1L, "long_string", 1000, 16L),
        file.path(script_dir, "compare.R"), dirname(installed_dtaparser),
        installed_dtaparser, "framework", 10L
    )
    stopifnot(rare_sizing$classification == "pass",
              rare_sizing$samples_completed == 16L,
              rare_sizing$payload_bytes_per_row >= 300000,
              !any(c("long_string", strrep("z", 10)) %in%
                   unlist(rare_sizing, use.names = FALSE)))
    # The isolated callr worker must install comparator functions in the worker's
    # lexical environment, not only in the transient fertility_worker_tile frame.
    isolated_worker <- callr::r(
        function(common_script, runtime_script, worker_script, compare_script,
                 item, tile, package_library, expected_package_path, raw_root) {
            source(common_script, local = environment())
            source(runtime_script, local = environment())
            invisible(fertility_assert_tempdir(raw_root))
            source(worker_script, local = environment())
            result <- fertility_worker_tile(
                item, tile, compare_script, package_library,
                expected_package_path, "framework", 10L
            )
            helpers <- c("fertility_bind_mismatches",
                         "fertility_compare_available_pairs")
            stopifnot(!any(vapply(helpers, exists, logical(1),
                                  envir = globalenv(), inherits = FALSE)))
            result
        },
        args = list(
            file.path(script_dir, "common.R"), file.path(script_dir, "runtime.R"),
            file.path(script_dir, "worker.R"), file.path(script_dir, "compare.R"),
            bounded_item, fertility_metadata_tile(), dirname(installed_dtaparser),
            installed_dtaparser,
            normalizePath(Sys.getenv("TMPDIR"), winslash = "/", mustWork = TRUE)
        ),
        libpath = .libPaths(), timeout = 30, spinner = FALSE, show = FALSE,
        user_profile = FALSE, system_profile = FALSE,
        env = c(R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null",
                R_MAX_VSIZE = "256M")
    )
    stopifnot(isolated_worker$classification != "crash",
              isolated_worker$rows == 5L,
              isolated_worker$columns == ncol(bounded_data))
} else {
    stop(paste(
        "checkout-local dtaparser installation is required; run a manual",
        "benchmark.sh smoke first so the isolated worker regression cannot skip"
    ))
}
worker_source <- paste(readLines(file.path(script_dir, "worker.R")), collapse = "\n")
stopifnot(!grepl("read_dta\\(item\\$path\\)", worker_source))
republish_source <- paste(readLines(file.path(script_dir, "republish.R")), collapse = "\n")
stopifnot(
    !grepl("fertility_capture_input", republish_source, fixed = TRUE),
    !grepl("read_dta", republish_source, fixed = TRUE),
    !grepl("item$path", republish_source, fixed = TRUE),
    grepl("options$shard_count != 8L", republish_source, fixed = TRUE)
)

# Timeout checkpoints retain the parent hash, publish, resume without retry, and
# execute again only when retry is requested.
timeout_path <- file.path(root, "timeout-input.dta")
write_release(timeout_path, 118L)
timeout_item <- list(
    id = "F9001", program = "dhs", level = "women", release = 118L,
    path = normalizePath(timeout_path, winslash = "/"), expected_sha512 = ""
)
timeout_checkpoint <- file.path(root, "timeout-checkpoint.rds")
timeout_counter <- new.env(parent = emptyenv())
timeout_counter$n <- 0L
timeout_counter$seconds <- 1L
timeout_execute <- function(item, input) {
    timeout_counter$n <- timeout_counter$n + 1L
    error <- tryCatch(
        callr::r(function() Sys.sleep(2), timeout = 0.1, spinner = FALSE),
        error = identity
    )
    stopifnot(inherits(error, "callr_timeout_error"))
    fertility_base_result(
        item, test_framework_id, timeout_counter$seconds, input, "timeout"
    )
}
first_timeout <- fertility_process_item(
    timeout_item, timeout_checkpoint, test_framework_id, 1L, FALSE, timeout_execute
)
stopifnot(!first_timeout$resumed, first_timeout$result$classification == "timeout",
          nzchar(first_timeout$result$input_id), timeout_counter$n == 1L)
timeout_report <- file.path(root, "timeout-results.tsv")
invisible(fertility_publish_results(
    list(first_timeout$result), test_build_id, timeout_report
))
stopifnot(file.exists(timeout_report),
          read.delim(timeout_report)$classification[[1L]] == "timeout")
resumed_timeout <- fertility_process_item(
    timeout_item, timeout_checkpoint, test_framework_id, 1L, FALSE, timeout_execute
)
stopifnot(resumed_timeout$resumed, timeout_counter$n == 1L)
timeout_counter$seconds <- 2L
changed_timeout <- fertility_process_item(
    timeout_item, timeout_checkpoint, test_framework_id, 2L, FALSE, timeout_execute
)
stopifnot(!changed_timeout$resumed, timeout_counter$n == 2L,
          changed_timeout$result$timeout_seconds == 2L)
retried_timeout <- fertility_process_item(
    timeout_item, timeout_checkpoint, test_framework_id, 2L, TRUE, timeout_execute
)
stopifnot(!retried_timeout$resumed, timeout_counter$n == 3L)

hash_error_item <- timeout_item
hash_error_item$id <- "F9002"
hash_error_item$path <- file.path(root, "missing-input.dta")
hash_error_checkpoint <- file.path(root, "hash-error-checkpoint.rds")
never_execute <- function(item, input) stop("hash errors must not launch a child")
hash_error <- fertility_process_item(
    hash_error_item, hash_error_checkpoint, test_framework_id, 1L, FALSE, never_execute
)
stopifnot(hash_error$result$classification == "inventory-hash-error",
          hash_error$result$secondary_categories == "hash-read-error",
          isTRUE(fertility_validate_recorded_input_attestation(hash_error$result)),
          nzchar(hash_error$result$input_id),
          fertility_process_item(hash_error_item, hash_error_checkpoint,
                                 test_framework_id, 1L, FALSE, never_execute)$resumed)
signature_error_item <- timeout_item
signature_error_item$id <- "F9003"
signature_error_item$expected_sha512 <- paste(rep("a", 128L), collapse = "")
signature_error <- fertility_process_item(
    signature_error_item, file.path(root, "signature-error-checkpoint.rds"),
    test_framework_id, 1L, FALSE, never_execute
)
stopifnot(
    signature_error$result$classification == "inventory-hash-error",
    signature_error$result$secondary_categories == "signature-mismatch",
    isTRUE(fertility_validate_recorded_input_attestation(signature_error$result))
)
changed_input_path <- file.path(root, "changed-input.dta")
write_release(changed_input_path, 118L)
changed_input_item <- timeout_item
changed_input_item$id <- "F9004"
changed_input_item$path <- normalizePath(changed_input_path, winslash = "/")
change_during_execute <- function(item, input) {
    write("changed", file = item$path, append = TRUE)
    fertility_base_result(item, test_framework_id, 1L, input, "pass")
}
changed_input <- fertility_process_item(
    changed_input_item, file.path(root, "changed-input-checkpoint.rds"),
    test_framework_id, 1L, FALSE, change_during_execute
)
stopifnot(
    changed_input$result$classification == "inventory-hash-error",
    changed_input$result$secondary_categories == "input-changed",
    isTRUE(fertility_validate_recorded_input_attestation(changed_input$result))
)
removed_input_path <- file.path(root, "removed-input.dta")
write_release(removed_input_path, 118L)
removed_input_item <- timeout_item
removed_input_item$id <- "F9005"
removed_input_item$path <- normalizePath(removed_input_path, winslash = "/")
remove_during_execute <- function(item, input) {
    unlink(item$path)
    fertility_base_result(item, test_framework_id, 1L, input, "pass")
}
removed_input <- fertility_process_item(
    removed_input_item, file.path(root, "removed-input-checkpoint.rds"),
    test_framework_id, 1L, FALSE, remove_during_execute
)
stopifnot(
    removed_input$result$classification == "inventory-hash-error",
    removed_input$result$secondary_categories == "hash-read-error",
    is.character(removed_input$result$actual_sha512),
    is.na(removed_input$result$actual_sha512),
    isTRUE(fertility_validate_recorded_input_attestation(removed_input$result))
)
invisible(fertility_publish_results(
    list(hash_error$result), test_build_id,
    file.path(root, "hash-error-results.tsv")
))
empty_results_path <- file.path(root, "empty-shard-results.tsv")
empty_results <- fertility_publish_results(list(), test_build_id, empty_results_path)
empty_roundtrip <- read.delim(empty_results_path, colClasses = "character",
                              check.names = FALSE)
stopifnot(nrow(empty_results) == 0L, nrow(empty_roundtrip) == 0L,
          "build_provenance_id" %in% names(empty_roundtrip),
          identical(names(fertility_classification_summary(empty_results)),
                    c("classification", "files")),
          nrow(fertility_classification_summary(empty_results)) == 0L)

# Ownership follows a long-lived orchestrator rather than the short-lived R
# helper that writes metadata. Live owners block reclamation; dead owners do not.
stopifnot(!fertility_pid_alive(.Machine$integer.max))

# A matching OS process generation remains authoritative even if its supplemental
# heartbeat is old.
stale_heartbeat_state <- file.path(root, "stale-heartbeat-owner")
dir.create(stale_heartbeat_state, mode = "0700")
stale_heartbeat <- file.path(stale_heartbeat_state, "heartbeat")
stale_heartbeat_owner <- fertility_owner(stale_heartbeat)
fertility_touch_heartbeat(stale_heartbeat, stale_heartbeat_owner$start)
Sys.setFileTime(stale_heartbeat, Sys.time() - 60)
stopifnot(isTRUE(fertility_owner_alive(stale_heartbeat_owner)))
stale_heartbeat_lock <- file.path(root, "stale-heartbeat.lock")
dir.create(stale_heartbeat_lock, mode = "0700")
fertility_write_owner(stale_heartbeat_lock, stale_heartbeat_owner)
expect_error(fertility_acquire_lock(
    stale_heartbeat_lock, initialization_grace = 0
), "another fertility corpus")
stale_heartbeat_temp_root <- file.path(root, "stale-heartbeat-temp")
stale_heartbeat_temp <- file.path(stale_heartbeat_temp_root, "run.live")
dir.create(stale_heartbeat_temp, recursive = TRUE, mode = "0700")
fertility_write_temp_owner(stale_heartbeat_temp, stale_heartbeat_owner)
fertility_clean_stale_tempdirs(stale_heartbeat_temp_root, current = "")
stopifnot(dir.exists(stale_heartbeat_temp))
unlink(c(stale_heartbeat_lock, stale_heartbeat_temp_root), recursive = TRUE)

# Permission-denied/unavailable probes are indeterminate, never dead. With no
# recent heartbeat they follow the conservative stale-age policy rather than
# permitting immediate lock or temp reclamation.
remote_owner <- stale_heartbeat_owner
remote_owner$host <- "synthetic-remote-host"
fertility_touch_heartbeat(remote_owner$heartbeat, remote_owner$start)
stopifnot(isTRUE(fertility_owner_alive(remote_owner)))
remote_lock <- file.path(root, "remote-live.lock")
dir.create(remote_lock, mode = "0700")
fertility_write_owner(remote_lock, remote_owner)
Sys.setFileTime(remote_lock, Sys.time() - 8 * 24 * 3600)
expect_error(fertility_acquire_lock(
    remote_lock, initialization_grace = 0, remote_stale_after = 0
), "another fertility corpus")
unlink(remote_lock, recursive = TRUE)
Sys.setFileTime(remote_owner$heartbeat, Sys.time() - 60)

denied_probe <- function(pid) list(alive = NA, start = NA_character_)
denied_status <- function(owner) fertility_owner_alive(
    owner, process_probe = denied_probe
)
stopifnot(is.na(denied_status(stale_heartbeat_owner)))
denied_lock <- file.path(root, "denied-probes.lock")
dir.create(denied_lock, mode = "0700")
fertility_write_owner(denied_lock, stale_heartbeat_owner)
expect_error(fertility_acquire_lock(
    denied_lock, initialization_grace = 0, owner_status = denied_status
), "another fertility corpus")
denied_temp_root <- file.path(root, "denied-probes-temp")
denied_temp <- file.path(denied_temp_root, "run.indeterminate")
dir.create(denied_temp, recursive = TRUE, mode = "0700")
fertility_write_owner(denied_temp, stale_heartbeat_owner)
fertility_clean_stale_tempdirs(
    denied_temp_root, current = "", owner_status = denied_status
)
stopifnot(dir.exists(denied_temp))
unlink(c(denied_lock, denied_temp_root), recursive = TRUE)

# A confirmed live PID with a different start generation is definitive PID reuse
# and can be reclaimed immediately.
mismatch_status <- function(owner) fertility_owner_alive(
    owner,
    process_probe = function(pid) list(alive = TRUE, start = "different-generation")
)
stopifnot(isFALSE(mismatch_status(stale_heartbeat_owner)))
mismatch_lock <- file.path(root, "pid-reuse.lock")
dir.create(mismatch_lock, mode = "0700")
fertility_write_owner(mismatch_lock, stale_heartbeat_owner)
mismatch_token <- fertility_acquire_lock(
    mismatch_lock, initialization_grace = 0, owner_status = mismatch_status
)
stopifnot(fertility_release_lock(mismatch_lock, mismatch_token))

owner_state <- file.path(root, "live-owner-state")
owner_process <- processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    c("--vanilla", file.path(script_dir, "runtime.R"), "hold-owner",
      owner_state, as.character(Sys.getpid())),
    cleanup_tree = TRUE, stdout = "|", stderr = "|"
)
on.exit(if (owner_process$is_alive()) owner_process$kill_tree(), add = TRUE)
for (attempt in seq_len(100L)) {
    if (file.exists(file.path(owner_state, "owner.tsv"))) break
    if (!owner_process$is_alive()) stop("owner helper exited during initialization")
    Sys.sleep(0.02)
}
live_owner <- fertility_read_owner(owner_state)
stopifnot(!is.null(live_owner), identical(live_owner$pid, Sys.getpid()),
          identical(live_owner$start, fertility_process_start(Sys.getpid())),
          isTRUE(fertility_owner_alive(live_owner)))

# Two independent shard processes can hold disjoint deterministic case selections
# concurrently, while a third overlapping selection is rejected.
concurrent_root <- file.path(root, "concurrent-shards")
dir.create(concurrent_root, recursive = TRUE, mode = "0700")
launch_shard <- function(name, case_id) {
    ready <- file.path(concurrent_root, paste0(name, ".ready"))
    release <- file.path(concurrent_root, paste0(name, ".release"))
    process <- callr::r_bg(
        function(runtime_script, owner_state, lock_root, name, case_id,
                 ready, release) {
            source(runtime_script, local = environment())
            owner <- fertility_read_owner(owner_state)
            paths <- c(file.path(lock_root, "selections", name),
                       file.path(lock_root, "cases", case_id))
            tokens <- fertility_acquire_lock_set(paths, owner)
            on.exit(fertility_release_lock_set(tokens), add = TRUE)
            file.create(ready)
            deadline <- Sys.time() + 10
            while (!file.exists(release) && Sys.time() < deadline) Sys.sleep(0.02)
            if (!file.exists(release)) stop("concurrent shard release timed out")
            TRUE
        },
        args = list(file.path(script_dir, "runtime.R"), owner_state,
                    concurrent_root, name, case_id, ready, release),
        user_profile = FALSE, system_profile = FALSE, stdout = "|", stderr = "|"
    )
    list(process = process, ready = ready, release = release)
}
concurrent_one <- launch_shard("selection-one", "F0001")
concurrent_two <- launch_shard("selection-two", "F0002")
on.exit({
    if (concurrent_one$process$is_alive()) concurrent_one$process$kill_tree()
    if (concurrent_two$process$is_alive()) concurrent_two$process$kill_tree()
}, add = TRUE)
for (attempt in seq_len(500L)) {
    if (file.exists(concurrent_one$ready) && file.exists(concurrent_two$ready)) break
    if (!concurrent_one$process$is_alive() || !concurrent_two$process$is_alive()) {
        stop("concurrent shard process exited before acquiring disjoint locks")
    }
    Sys.sleep(0.02)
}
stopifnot(file.exists(concurrent_one$ready), file.exists(concurrent_two$ready))
overlap_error <- tryCatch(callr::r(
    function(runtime_script, owner_state, path) {
        source(runtime_script, local = environment())
        fertility_acquire_lock_set(path, fertility_read_owner(owner_state))
    },
    args = list(file.path(script_dir, "runtime.R"), owner_state,
                file.path(concurrent_root, "cases", "F0001")),
    user_profile = FALSE, system_profile = FALSE, spinner = FALSE
), error = identity)
stopifnot(inherits(overlap_error, "error"),
          grepl("another fertility corpus", conditionMessage(overlap_error)))
file.create(concurrent_one$release, concurrent_two$release)
concurrent_one$process$wait(timeout = 5000)
concurrent_two$process$wait(timeout = 5000)
stopifnot(isTRUE(concurrent_one$process$get_result()),
          isTRUE(concurrent_two$process$get_result()),
          !file.exists(file.path(concurrent_root, "cases", "F0001")),
          !file.exists(file.path(concurrent_root, "cases", "F0002")))

live_lock <- file.path(root, "live-owner.lock")
dir.create(live_lock, mode = "0700")
fertility_write_owner(live_lock, live_owner)
expect_error(fertility_acquire_lock(
    live_lock, initialization_grace = 0
), "another fertility corpus")
live_temp_root <- file.path(root, "live-owner-temp")
live_temp <- file.path(live_temp_root, "run.live")
dir.create(live_temp, recursive = TRUE, mode = "0700")
fertility_write_temp_owner(live_temp, live_owner)
fertility_clean_stale_tempdirs(live_temp_root, current = "")
stopifnot(dir.exists(live_temp))
invisible(owner_process$kill_tree())
owner_process$wait(timeout = 5000)
stopifnot(isTRUE(fertility_owner_alive(live_owner)))
expect_error(fertility_acquire_lock(
    live_lock, initialization_grace = 0
), "another fertility corpus")
fertility_clean_stale_tempdirs(live_temp_root, current = "")
stopifnot(dir.exists(live_temp))
unlink(c(live_lock, live_temp_root), recursive = TRUE)

# The owner helper monitors the orchestrator's exact process generation. Killing
# only that parent makes the helper exit and releases both kinds of stale state.
monitored_parent <- processx::process$new(
    "/bin/sleep", "30", cleanup_tree = TRUE, stdout = "|", stderr = "|"
)
on.exit(if (monitored_parent$is_alive()) monitored_parent$kill_tree(), add = TRUE)
monitored_state <- file.path(root, "monitored-owner-state")
monitored_helper <- processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    c("--vanilla", file.path(script_dir, "runtime.R"), "hold-owner",
      monitored_state, as.character(monitored_parent$get_pid())),
    cleanup_tree = TRUE, stdout = "|", stderr = "|"
)
on.exit(if (monitored_helper$is_alive()) monitored_helper$kill_tree(), add = TRUE)
for (attempt in seq_len(100L)) {
    if (file.exists(file.path(monitored_state, "owner.tsv"))) break
    if (!monitored_helper$is_alive()) stop("monitored owner helper exited early")
    Sys.sleep(0.02)
}
monitored_owner <- fertility_read_owner(monitored_state)
stopifnot(!is.null(monitored_owner),
          identical(monitored_owner$pid, monitored_parent$get_pid()),
          identical(monitored_owner$start,
                    fertility_process_start(monitored_parent$get_pid())),
          isTRUE(fertility_owner_alive(monitored_owner)))
monitored_lock <- file.path(root, "monitored-owner.lock")
dir.create(monitored_lock, mode = "0700")
fertility_write_owner(monitored_lock, monitored_owner)
monitored_temp_root <- file.path(root, "monitored-owner-temp")
monitored_temp <- file.path(monitored_temp_root, "run.live")
dir.create(monitored_temp, recursive = TRUE, mode = "0700")
fertility_write_temp_owner(monitored_temp, monitored_owner)
# Helper death alone cannot release ownership while its published parent
# generation is still alive.
invisible(monitored_helper$kill_tree())
monitored_helper$wait(timeout = 5000)
stopifnot(isTRUE(fertility_owner_alive(monitored_owner)))
expect_error(fertility_acquire_lock(
    monitored_lock, initialization_grace = 0
), "another fertility corpus")
fertility_clean_stale_tempdirs(monitored_temp_root, current = "")
stopifnot(dir.exists(monitored_temp))
# Once that exact parent dies, recovery succeeds even though the heartbeat helper
# was already gone.
invisible(monitored_parent$kill())
monitored_parent$wait(timeout = 5000)
stopifnot(!isTRUE(fertility_owner_alive(monitored_owner)))
monitored_token <- fertility_acquire_lock(monitored_lock, initialization_grace = 0)
stopifnot(fertility_release_lock(monitored_lock, monitored_token))
fertility_clean_stale_tempdirs(monitored_temp_root, current = "")
stopifnot(!file.exists(monitored_temp))

# Stale and ownerless locks are reclaimed, while release remains token-owned.
lock_path <- file.path(root, "run.lock")
dir.create(lock_path, mode = "0700")
fertility_write_owner(lock_path, list(
    token = "dead", pid = .Machine$integer.max, host = fertility_host(),
    start = "not-a-process", heartbeat = file.path(root, "missing-heartbeat"),
    created = 0
))
lock_token <- fertility_acquire_lock(lock_path)
stopifnot(nzchar(lock_token), fertility_release_lock(lock_path, lock_token),
          !file.exists(lock_path))
dir.create(lock_path, mode = "0700")
Sys.setFileTime(lock_path, Sys.time() - 10)
lock_token <- fertility_acquire_lock(lock_path, initialization_grace = 0)
stopifnot(fertility_release_lock(lock_path, lock_token))
temp_root <- file.path(root, "stale-temp")
current_temp <- file.path(temp_root, "run.current")
stale_temp <- file.path(temp_root, "run.stale")
dir.create(current_temp, recursive = TRUE, mode = "0700")
dir.create(stale_temp, mode = "0700")
fertility_write_owner(stale_temp, list(
    token = "dead-temp", pid = .Machine$integer.max, host = fertility_host(),
    start = "not-a-process", heartbeat = file.path(root, "missing-heartbeat"),
    created = 0
))
fertility_clean_stale_tempdirs(temp_root, current_temp)
stopifnot(dir.exists(current_temp), !file.exists(stale_temp))

# Runtime dependencies are bound to canonical paths and installed trees.
dependency <- fertility_dependency_provenance("rlang")
moved <- dependency
moved$rlang_path <- paste0(moved$rlang_path, "-moved")
stopifnot("rlang_path" %in% fertility_provenance_mismatches(dependency, moved))
source_package <- dependency$rlang_path[[1L]]
copy_parent <- file.path(root, "dependency-copy")
dir.create(copy_parent)
stopifnot(file.copy(source_package, copy_parent, recursive = TRUE))
copy_package <- file.path(copy_parent, basename(source_package))
original_digest <- fertility_directory_digest(copy_package)
cat("\nsynthetic modification\n", file = file.path(copy_package, "DESCRIPTION"),
    append = TRUE)
modified_digest <- fertility_directory_digest(copy_package)
modified <- dependency
modified$rlang_installed_sha256 <- modified_digest
stopifnot(!identical(original_digest, modified_digest),
          "rlang_installed_sha256" %in%
              fertility_provenance_mismatches(dependency, modified))

# Start a real parent R process with TMPDIR configured before startup. That
# parent launches callr, and both its tempdir and callr's live serialization and
# control artifacts must remain beneath the private raw root.
private_raw <- file.path(root, "target", "fertility-surveys", "raw")
private_tmp <- file.path(private_raw, "tmp", "run.synthetic")
dir.create(private_tmp, recursive = TRUE, mode = "0700")
temp_lifecycle <- callr::r(
    function(runtime_script, raw_root, configured_tmp) {
        source(runtime_script, local = environment())
        parent_temp <- fertility_assert_tempdir(raw_root)
        before <- list.files(parent_temp, recursive = TRUE, all.files = TRUE,
                             full.names = TRUE, no.. = TRUE)
        child <- callr::r_bg(
            function(runtime_script, raw_root) {
                source(runtime_script, local = environment())
                value <- fertility_assert_tempdir(raw_root)
                Sys.sleep(0.5)
                value
            },
            args = list(runtime_script, raw_root),
            env = c(TMPDIR = configured_tmp, R_ENVIRON_USER = "/dev/null",
                    R_PROFILE_USER = "/dev/null"),
            user_profile = FALSE, system_profile = FALSE,
            stdout = "|", stderr = "|"
        )
        Sys.sleep(0.1)
        during <- list.files(parent_temp, recursive = TRUE, all.files = TRUE,
                             full.names = TRUE, no.. = TRUE)
        control <- setdiff(during, before)
        child$wait(timeout = 5000)
        child_temp <- child$get_result()
        list(parent = parent_temp, child = child_temp, control = control)
    },
    args = list(file.path(script_dir, "runtime.R"), private_raw, private_tmp),
    env = c(TMPDIR = private_tmp, R_ENVIRON_USER = "/dev/null",
            R_PROFILE_USER = "/dev/null"),
    user_profile = FALSE, system_profile = FALSE, spinner = FALSE
)
private_prefix <- paste0(normalizePath(private_raw, winslash = "/"), "/")
all_temp_paths <- c(temp_lifecycle$parent, temp_lifecycle$child,
                    temp_lifecycle$control)
stopifnot(length(temp_lifecycle$control) > 0L,
          all(startsWith(normalizePath(
              all_temp_paths, winslash = "/", mustWork = FALSE
          ), private_prefix)))

environment_names <- c("DTAPARSER_FERTILITY_CORPUS", "CI", "GITHUB_ACTIONS",
                       "GITHUB_RUN_ID", "GITHUB_WORKFLOW")
old_environment <- Sys.getenv(environment_names, unset = NA_character_)
on.exit({
    for (i in seq_along(environment_names)) {
        if (is.na(old_environment[[i]])) Sys.unsetenv(environment_names[[i]])
        else do.call(Sys.setenv, setNames(list(old_environment[[i]]), environment_names[[i]]))
    }
}, add = TRUE)
Sys.setenv(DTAPARSER_FERTILITY_CORPUS = fertility_opt_in_value, CI = "true")
expect_error(fertility_assert_manual_run(), "refused in CI")
Sys.unsetenv(c("CI", "GITHUB_ACTIONS", "GITHUB_RUN_ID", "GITHUB_WORKFLOW"))
Sys.setenv(DTAPARSER_FERTILITY_CORPUS = "")
expect_error(fertility_assert_manual_run(), "manual opt-in")
Sys.setenv(DTAPARSER_FERTILITY_CORPUS = fertility_opt_in_value)
stopifnot(is.null(fertility_assert_manual_run()))

message("fertility framework synthetic tests passed")
