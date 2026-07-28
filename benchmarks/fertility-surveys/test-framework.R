script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument), winslash = "/"))
source(file.path(script_dir, "common.R"))
source(file.path(script_dir, "compare.R"))
source(file.path(script_dir, "runner.R"))
source(file.path(script_dir, "worker.R"))
source(file.path(script_dir, "runtime.R"))
source(file.path(script_dir, "provenance.R"))

expect_error <- function(expression, pattern) {
    error <- tryCatch({ force(expression); NULL }, error = identity)
    stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}

root <- tempfile("fertility-framework-")
dir.create(root)
on.exit(unlink(root, recursive = TRUE), add = TRUE)
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
    inventory_id = paste(rep("d", 64L), collapse = "")
) {
    manifest <- fertility_family_manifest(canonical, family_options)
    manifest_id <- fertility_manifest_id(manifest)
    family_id <- fertility_family_id_from_manifest(
        manifest, test_framework_id, test_config_id, test_build_id, inventory_id,
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
        evidence_selection_id <- fertility_evidence_selection_id(
            selection_id, input_attestation_id, "fresh-execution",
            fertility_schema_version, fertility_report_schema_id()
        )
        provenance <- data.frame(
            schema_version = as.character(fertility_schema_version),
            report_schema_version = as.character(fertility_report_schema_version),
            evidence_origin = "fresh-execution",
            source_corpus_schema_version = as.character(fertility_schema_version),
            replayed_at_utc = "", selection_id = selection_id,
            evidence_selection_id = evidence_selection_id,
            input_attestation_id = input_attestation_id, family_id = family_id,
            family_manifest_id = manifest_id, framework_id = test_framework_id,
            config_id = test_config_id, build_provenance_id = test_build_id,
            inventory_id = inventory_id, report_schema_id = fertility_report_schema_id(),
            selected_files = as.character(nrow(expected)),
            expected_family_files = as.character(nrow(manifest)),
            full_default_family = if (fertility_full_default_family(family_options))
                "TRUE" else "FALSE",
            program_filter = spec$program_filter, release_filter = spec$release_filter,
            id_filter = spec$id_filter, max_files = spec$max_files,
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
full_classes[supported_positions[seq_len(5L)]] <- "inventory-hash-error"
full_fixture <- make_bundle_family(
    full_canonical, full_options, full_classes,
    inventory_id = paste(rep("e", 64L), collapse = "")
)
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
full_bad_hash_count[[1L]]$results$classification[[supported_positions[[6L]]]] <-
    "inventory-hash-error"
expect_error(fertility_validate_shard_bundles(
    full_bad_hash_count, full_fixture$id, full_canonical
), "executable accounting")
full_too_few_hashes <- full_fixture$bundles
full_too_few_hashes[[1L]]$results$classification[[supported_positions[[5L]]]] <- "pass"
expect_error(fertility_validate_shard_bundles(
    full_too_few_hashes, full_fixture$id, full_canonical
), "executable accounting")
full_bad_supported_class <- full_fixture$bundles
full_bad_supported_class[[1L]]$results$classification[[supported_positions[[6L]]]] <-
    "expected-unsupported-111"
expect_error(fertility_validate_shard_bundles(
    full_bad_supported_class, full_fixture$id, full_canonical
), "executable accounting")
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
stopifnot(fertility_validate_tile_completeness(
              traversed_tiles, synthetic_batches, 3, tile_configuration
          ),
          fertility_aggregate_classification(traversed_tiles, TRUE) ==
              "value-mismatch")
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
                                    fail_rollback = FALSE) {
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
        path_exists = function(path) isTRUE(state$paths[[path]])
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
stopifnot(fertility_validate_tile_completeness(
    zero_column_tiles, zero_batches, 3, tile_configuration
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
    text = c("a", "b", "c", "d", "e"),
    day = as.Date("2020-01-01") + 0:4
)
haven::write_dta(bounded_data, bounded_path)
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
    stopifnot(metadata_worker$rows == 5L, metadata_worker$columns == 3L,
              identical(metadata_worker$column_names, names(bounded_data)))
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
              isolated_worker$rows == 5L, isolated_worker$columns == 3L)
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
