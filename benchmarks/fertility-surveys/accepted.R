fertility_accepted_ids <- function() sprintf("F%04d", 633:637)

fertility_acceptance_authority <- function() "explicit-local-current-sha512-v1"

fertility_acceptance_commitment_id <- function(authority, entries) {
    if (!is.data.frame(entries) || !identical(
        names(entries), c("id", "expected_sha512", "accepted_sha512")
    )) stop("accepted-current-hash artifact schema is invalid")
    fertility_stable_id(list(
        authority = authority,
        ids = paste(entries$id, collapse = ","),
        manifest_commitments = paste(entries$expected_sha512, collapse = ","),
        accepted_commitments = paste(entries$accepted_sha512, collapse = ",")
    ))
}

fertility_validate_acceptance_entries <- function(entries) {
    if (!is.data.frame(entries) || !identical(
        names(entries), c("id", "expected_sha512", "accepted_sha512")
    ) || !identical(as.character(entries$id), fertility_accepted_ids()) ||
        any(!grepl("^[0-9a-f]{128}$", entries$expected_sha512)) ||
        any(!grepl("^[0-9a-f]{128}$", entries$accepted_sha512)) ||
        any(entries$expected_sha512 == entries$accepted_sha512)) {
        stop("accepted-current-hash artifact is invalid")
    }
    entries$id <- as.character(entries$id)
    entries$expected_sha512 <- as.character(entries$expected_sha512)
    entries$accepted_sha512 <- as.character(entries$accepted_sha512)
    rownames(entries) <- NULL
    entries
}

fertility_acceptance_artifact_root <- function(raw_root) {
    file.path(raw_root, "accepted-current-hashes")
}

fertility_assert_acceptance_raw_root <- function(raw_root, checkout_root) {
    expected <- fertility_assert_checkout_raw_root(
        raw_root, checkout_root, create = TRUE
    )
    Sys.chmod(expected, mode = "0700")
    expected
}

fertility_validate_acceptance_directory <- function(directory, parent) {
    directory <- fertility_assert_existing_directory(
        directory, parent, "accepted-current-hash commitment"
    )
    contents <- list.files(
        directory, all.files = TRUE, no.. = TRUE,
        recursive = FALSE, include.dirs = TRUE
    )
    if (!identical(contents, "commitment.rds")) {
        stop("accepted-current-hash commitment must contain exactly commitment.rds")
    }
    path <- file.path(directory, "commitment.rds")
    if (fertility_path_is_symlink(path) || !file_test("-f", path)) {
        stop("accepted-current-hash artifact must be a regular nonsymlink file")
    }
    fertility_assert_existing_file(
        path, directory, "accepted-current-hash artifact"
    )
}

fertility_revalidate_recorded_acceptance <- function(raw_root, provenance,
                                                      inventory) {
    required <- c(
        "acceptance_authority", "acceptance_commitment_id",
        "acceptance_artifact_sha256", "inventory_id"
    )
    if (!is.data.frame(provenance) || nrow(provenance) < 1L ||
        !all(required %in% names(provenance)) ||
        any(provenance$acceptance_authority != fertility_acceptance_authority()) ||
        length(unique(provenance$acceptance_commitment_id)) != 1L ||
        length(unique(provenance$acceptance_artifact_sha256)) != 1L ||
        length(unique(provenance$inventory_id)) != 1L ||
        !grepl("^[0-9a-f]{64}$", provenance$acceptance_commitment_id[[1L]]) ||
        !grepl("^[0-9a-f]{64}$", provenance$acceptance_artifact_sha256[[1L]]) ||
        !identical(provenance$inventory_id[[1L]], fertility_inventory_id(inventory))) {
        stop("recorded accepted-current-hash provenance is invalid")
    }
    acceptance <- fertility_load_acceptance(
        raw_root, provenance$acceptance_commitment_id[[1L]], inventory
    )
    if (!identical(acceptance$authority,
                   provenance$acceptance_authority[[1L]]) ||
        !identical(acceptance$artifact_sha256,
                   provenance$acceptance_artifact_sha256[[1L]])) {
        stop("recorded accepted-current-hash artifact identity changed")
    }
    fertility_validate_acceptance_current(acceptance, inventory)
    acceptance
}

fertility_revalidate_accepted_publication <- function(
    raw_root, provenance, inventory = NULL, datasigs_path = NULL
) {
    schema_fields <- c(
        "schema_version", "report_schema_version",
        "source_corpus_schema_version"
    )
    required <- c(
        schema_fields, "evidence_origin", "framework_id", "build_provenance_id",
        "inventory_id", "report_schema_id"
    )
    if (!is.data.frame(provenance) || !all(required %in% names(provenance)) ||
        any(vapply(schema_fields, function(field) {
            !is.atomic(provenance[[field]]) || !is.null(dim(provenance[[field]]))
        }, logical(1)))) {
        stop("accepted publication framework provenance is invalid")
    }
    provenance[schema_fields] <- lapply(
        provenance[schema_fields], as.character
    )
    if (any(vapply(required, function(field) {
            length(unique(provenance[[field]])) != 1L
        }, logical(1))) ||
        !identical(provenance$schema_version[[1L]],
                   as.character(fertility_schema_version)) ||
        !identical(provenance$report_schema_version[[1L]],
                   as.character(fertility_report_schema_version)) ||
        !identical(provenance$evidence_origin[[1L]], "fresh-execution") ||
        !identical(provenance$source_corpus_schema_version[[1L]],
                   as.character(fertility_schema_version)) ||
        !identical(provenance$report_schema_id[[1L]], fertility_report_schema_id()) ||
        any(!grepl("^[0-9a-f]{64}$", unlist(provenance[1L, c(
            "framework_id", "build_provenance_id", "inventory_id"
        ), drop = FALSE], use.names = FALSE)))) {
        stop("accepted publication framework provenance is invalid")
    }
    if (is.null(inventory)) inventory <- fertility_build_inventory()
    fertility_validate_canonical_inventory(
        fertility_inventory_manifest(inventory), exact = TRUE
    )
    acceptance <- fertility_revalidate_recorded_acceptance(
        raw_root, provenance, inventory
    )
    if (is.null(datasigs_path)) datasigs_path <- fertility_required_paths()$datasigs
    if (!identical(
        fertility_framework_id(
            provenance$build_provenance_id[[1L]], datasigs_path, acceptance
        ),
        provenance$framework_id[[1L]]
    )) stop("accepted publication framework provenance changed")
    framework_inventory <- fertility_framework_inventory(
        file.path(raw_root, "framework", provenance$framework_id[[1L]]),
        inventory = inventory, framework_id = provenance$framework_id[[1L]],
        report_schema_version = fertility_report_schema_version
    )
    if (!identical(provenance$inventory_id[[1L]],
                   framework_inventory$provenance$inventory_id[[1L]])) {
        stop("accepted publication inventory provenance changed")
    }
    recorded_acceptance <- framework_inventory$acceptance_provenance
    if (is.null(recorded_acceptance) || !identical(
        recorded_acceptance,
        data.frame(
            authority = provenance$acceptance_authority[[1L]],
            commitment_id = provenance$acceptance_commitment_id[[1L]],
            artifact_sha256 = provenance$acceptance_artifact_sha256[[1L]],
            stringsAsFactors = FALSE, check.names = FALSE
        )
    )) stop("accepted publication framework acceptance provenance changed")
    invisible(list(
        acceptance = acceptance, inventory = inventory,
        framework_inventory = framework_inventory
    ))
}

fertility_capture_acceptance <- function(inventory, raw_root) {
    ids <- fertility_accepted_ids()
    selected <- inventory[match(ids, inventory$id), , drop = FALSE]
    if (nrow(selected) != length(ids) || anyNA(selected$id) ||
        !identical(as.character(selected$id), ids) ||
        any(!grepl("^[0-9a-f]{128}$", selected$expected_sha512))) {
        stop("accepted-current-hash inventory selection is invalid")
    }
    captures <- lapply(seq_len(nrow(selected)), function(index) {
        fertility_capture_input(as.list(selected[index, , drop = FALSE]))
    })
    if (any(vapply(captures, function(value) {
        !identical(value$hash_status, "ok") ||
            !grepl("^[0-9a-f]{128}$", value$actual_sha512)
    }, logical(1)))) stop("accepted-current-hash capture failed")
    entries <- data.frame(
        id = ids,
        expected_sha512 = tolower(selected$expected_sha512),
        accepted_sha512 = vapply(captures, `[[`, character(1), "actual_sha512"),
        stringsAsFactors = FALSE, check.names = FALSE
    )
    entries <- fertility_validate_acceptance_entries(entries)
    authority <- fertility_acceptance_authority()
    commitment_id <- fertility_acceptance_commitment_id(authority, entries)
    artifact <- list(
        schema_version = fertility_schema_version,
        authority = authority,
        commitment_id = commitment_id,
        entries = entries,
        created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    )
    revalidate_capture_inputs <- function() {
        current <- vapply(seq_len(nrow(selected)), function(index) {
            captured <- fertility_capture_input(
                as.list(selected[index, , drop = FALSE])
            )
            if (!identical(captured$hash_status, "ok")) {
                stop("accepted-current-hash input changed during capture")
            }
            captured$actual_sha512
        }, character(1))
        if (!identical(current, entries$accepted_sha512)) {
            stop("accepted-current-hash input changed during capture")
        }
        invisible(TRUE)
    }
    parent <- fertility_acceptance_artifact_root(raw_root)
    invisible(fertility_assert_direct_child(
        parent, raw_root, "accepted-current-hashes output directory",
        must_work = FALSE
    ))
    if (!dir.exists(parent) &&
        !dir.create(parent, showWarnings = FALSE, mode = "0700")) {
        stop("could not create accepted-current-hash artifact root")
    }
    invisible(fertility_assert_direct_child(
        parent, raw_root, "accepted-current-hashes output directory"
    ))
    destination <- file.path(parent, commitment_id)
    artifact_path <- file.path(destination, "commitment.rds")
    invisible(fertility_assert_direct_child(
        destination, parent, "accepted-current-hash commitment", must_work = FALSE
    ))
    Sys.chmod(parent, mode = "0700")
    finish_commitment <- function(boundary = NULL) {
        loaded <- fertility_load_acceptance(raw_root, commitment_id, inventory)
        if (!identical(loaded$entries, entries)) {
            stop("immutable accepted-current-hash artifact conflicts with capture")
        }
        if (!is.null(boundary)) fertility_publication_test_hook(
            boundary,
            list(parent = parent, destination = destination,
                 artifact = artifact_path)
        )
        fertility_validate_acceptance_directory(destination, parent)
        revalidate_capture_inputs()
        commitment_id
    }
    if (file.exists(destination) || dir.exists(destination) ||
        fertility_path_is_symlink(destination)) {
        return(finish_commitment(
            "acceptance-before-existing-reuse-revalidation"
        ))
    }
    stage <- tempfile(".acceptance.", tmpdir = parent)
    if (!dir.create(stage, showWarnings = FALSE, mode = "0700")) {
        stop("could not create accepted-current-hash staging directory")
    }
    on.exit(unlink(stage, recursive = TRUE), add = TRUE)
    stage_artifact <- file.path(stage, "commitment.rds")
    fertility_atomic_save_rds(artifact, stage_artifact)
    Sys.chmod(stage_artifact, mode = "0600")
    invisible(fertility_assert_direct_child(
        parent, raw_root, "accepted-current-hashes output directory"
    ))
    stage <- fertility_assert_existing_directory(
        stage, parent, "accepted-current-hash staging directory"
    )
    fertility_validate_acceptance_directory(stage, parent)
    fertility_publication_test_hook(
        "acceptance-before-destination-publication",
        list(parent = parent, destination = destination, stage = stage)
    )
    revalidate_capture_inputs()
    fertility_validate_acceptance_directory(stage, parent)
    moved_identity <- NULL
    validate_stage_for_publication <- function(from, to, label) {
        revalidate_capture_inputs()
        fertility_validate_acceptance_directory(from, parent)
        moved_identity <<- fertility_filesystem_identity(
            from, "accepted-current-hash staging directory"
        )
        invisible(TRUE)
    }
    publication_error <- tryCatch({
        fertility_atomic_rename_noreplace(
            stage, destination, "accepted-current-hash commitment",
            validate_source = validate_stage_for_publication
        )
        NULL
    }, error = identity)
    if (!is.null(publication_error)) {
        if (file.exists(destination) || dir.exists(destination) ||
            fertility_path_is_symlink(destination)) {
            return(finish_commitment(
                "acceptance-before-concurrent-winner-revalidation"
            ))
        }
        stop(publication_error)
    }
    Sys.chmod(destination, mode = "0700")
    result <- tryCatch(finish_commitment(
        "acceptance-before-new-publication-revalidation"
    ), error = identity)
    if (inherits(result, "error")) {
        publication_content_valid <- isTRUE(tryCatch({
            loaded <- fertility_load_acceptance(
                raw_root, commitment_id, inventory
            )
            fertility_validate_acceptance_directory(destination, parent)
            identical(loaded$entries, entries)
        }, error = function(error) FALSE))
        if (!publication_content_valid) {
            destination_identity <- tryCatch(
                fertility_filesystem_identity(
                    destination, "published accepted-current-hash commitment"
                ),
                error = function(error) NULL
            )
            if (!is.null(moved_identity) &&
                identical(destination_identity, moved_identity)) {
                removed <- tryCatch(fertility_remove_confirmed_new_path(
                    destination, parent,
                    "invalid newly published accepted-current-hash commitment"
                ), error = function(error) FALSE)
                if (!isTRUE(removed)) {
                    stop("could not roll back invalid accepted-current-hash publication")
                }
            }
        }
        stop(result)
    }
    result
}

fertility_load_acceptance <- function(raw_root, commitment_id, inventory = NULL) {
    if (!is.character(commitment_id) || length(commitment_id) != 1L ||
        !grepl("^[0-9a-f]{64}$", commitment_id)) {
        stop("accepted-current-hash commitment ID is invalid")
    }
    artifact_root <- fertility_acceptance_artifact_root(raw_root)
    if (fertility_path_is_symlink(raw_root) || fertility_path_is_symlink(artifact_root)) {
        stop("accepted-current-hash artifact root must not be a symlink")
    }
    resolved_raw_root <- normalizePath(raw_root, winslash = "/", mustWork = TRUE)
    root <- normalizePath(artifact_root, winslash = "/", mustWork = TRUE)
    if (!identical(dirname(root), resolved_raw_root)) {
        stop("accepted-current-hash artifact root escaped its private root")
    }
    directory <- fertility_assert_existing_directory(
        file.path(root, commitment_id), root,
        "accepted-current-hash commitment"
    )
    path <- fertility_validate_acceptance_directory(directory, root)
    resolved_directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
    resolved_path <- normalizePath(path, winslash = "/", mustWork = TRUE)
    if (!identical(dirname(resolved_directory), root) ||
        !identical(dirname(resolved_path), resolved_directory)) {
        stop("accepted-current-hash artifact escaped its private root")
    }
    artifact <- tryCatch(readRDS(resolved_path), error = function(error) NULL)
    required <- c(
        "schema_version", "authority", "commitment_id", "entries", "created_at_utc"
    )
    if (!is.list(artifact) || !identical(names(artifact), required) ||
        !identical(artifact$schema_version, fertility_schema_version) ||
        !identical(artifact$authority, fertility_acceptance_authority()) ||
        !identical(artifact$commitment_id, commitment_id) ||
        !is.character(artifact$created_at_utc) || length(artifact$created_at_utc) != 1L ||
        !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
               artifact$created_at_utc)) {
        stop("accepted-current-hash artifact is invalid")
    }
    entries <- fertility_validate_acceptance_entries(artifact$entries)
    if (!identical(
        fertility_acceptance_commitment_id(artifact$authority, entries), commitment_id
    )) stop("accepted-current-hash commitment identity is invalid")
    if (!is.null(inventory)) {
        selected <- inventory[match(entries$id, inventory$id), , drop = FALSE]
        if (nrow(selected) != nrow(entries) || anyNA(selected$id) ||
            !identical(as.character(selected$id), entries$id) ||
            !identical(tolower(as.character(selected$expected_sha512)),
                       entries$expected_sha512)) {
            stop("accepted-current-hash artifact does not match the manifest inventory")
        }
    }
    list(
        authority = artifact$authority,
        commitment_id = artifact$commitment_id,
        entries = entries,
        artifact_sha256 = unname(tools::sha256sum(resolved_path))
    )
}

fertility_validate_acceptance_current <- function(acceptance, inventory) {
    if (is.null(acceptance)) return(invisible(TRUE))
    selected <- inventory[match(acceptance$entries$id, inventory$id), , drop = FALSE]
    if (!identical(as.character(selected$id), acceptance$entries$id) ||
        !identical(tolower(as.character(selected$expected_sha512)),
                   acceptance$entries$expected_sha512)) {
        stop("accepted-current-hash inventory changed")
    }
    actual <- vapply(seq_len(nrow(selected)), function(index) {
        value <- tryCatch(
            fertility_file_sha512(selected$path[[index]]), error = function(error) NA_character_
        )
        if (is.na(value)) stop("accepted-current-hash input validation failed")
        value
    }, character(1))
    if (!identical(actual, acceptance$entries$accepted_sha512)) {
        stop("accepted-current-hash input validation failed")
    }
    invisible(TRUE)
}

fertility_validate_accepted_selection <- function(options, family) {
    if (!nzchar(options$accepted_current_hashes)) return(invisible(TRUE))
    exact_ids <- fertility_accepted_ids()
    if (!identical(sort(options$ids), exact_ids) || length(options$programs) ||
        length(options$releases) || is.finite(options$max_files) ||
        options$shard_index != 1L || options$shard_count != 1L ||
        !identical(as.character(family$id), exact_ids)) {
        stop("accepted-current-hash execution requires exactly F0633 through F0637")
    }
    invisible(TRUE)
}

if (sys.nframe() == 0L) {
    script_path <- normalizePath(sub("^--file=", "", grep(
        "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
    )[[1L]]), winslash = "/")
    script_dir <- dirname(script_path)
    source(file.path(script_dir, "common.R"))
    source(file.path(script_dir, "runner.R"))
    fertility_assert_manual_run()
    arguments <- commandArgs(trailingOnly = TRUE)
    if (!identical(arguments, "--capture-accepted-current-hashes")) {
        stop("usage: accepted.R --capture-accepted-current-hashes")
    }
    checkout_root <- fertility_checkout_root(script_path)
    raw_root <- fertility_assert_acceptance_raw_root(
        file.path(checkout_root, "target", "fertility-surveys", "raw"),
        checkout_root
    )
    inventory <- fertility_build_inventory()
    cat(fertility_capture_acceptance(inventory, raw_root))
}
