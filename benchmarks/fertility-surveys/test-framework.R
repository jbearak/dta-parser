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
expect_error(fertility_filter_inventory(
    inventory, fertility_parse_arguments("--id=F9999")
), "unknown --id")

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
          "attribute-mismatch")
changed <- actual
changed$text[[1L]] <- "different"
stopifnot(fertility_compare_internal(actual, changed)$classification ==
          "internal-collector-mismatch")

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
stopifnot(unsupported$classification == "unsupported-release")
hash_item <- as.list(inventory[2L, , drop = FALSE])
hash_item$expected_sha512 <- paste(rep("0", 128L), collapse = "")
hash_failure <- fertility_worker(
    hash_item, file.path(script_dir, "compare.R"), root, root, "framework", 1L,
    fertility_file_sha512(hash_item$path)
)
stopifnot(hash_failure$classification == "input-signature-mismatch")

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
        item, "framework", timeout_counter$seconds, input, "timeout"
    )
}
first_timeout <- fertility_process_item(
    timeout_item, timeout_checkpoint, "framework", 1L, FALSE, timeout_execute
)
stopifnot(!first_timeout$resumed, first_timeout$result$classification == "timeout",
          nzchar(first_timeout$result$input_id), timeout_counter$n == 1L)
timeout_report <- file.path(root, "timeout-results.tsv")
invisible(fertility_publish_results(list(first_timeout$result), "build", timeout_report))
stopifnot(file.exists(timeout_report),
          read.delim(timeout_report)$classification[[1L]] == "timeout")
resumed_timeout <- fertility_process_item(
    timeout_item, timeout_checkpoint, "framework", 1L, FALSE, timeout_execute
)
stopifnot(resumed_timeout$resumed, timeout_counter$n == 1L)
timeout_counter$seconds <- 2L
changed_timeout <- fertility_process_item(
    timeout_item, timeout_checkpoint, "framework", 2L, FALSE, timeout_execute
)
stopifnot(!changed_timeout$resumed, timeout_counter$n == 2L,
          changed_timeout$result$timeout_seconds == 2L)
retried_timeout <- fertility_process_item(
    timeout_item, timeout_checkpoint, "framework", 2L, TRUE, timeout_execute
)
stopifnot(!retried_timeout$resumed, timeout_counter$n == 3L)

hash_error_item <- timeout_item
hash_error_item$id <- "F9002"
hash_error_item$path <- file.path(root, "missing-input.dta")
hash_error_checkpoint <- file.path(root, "hash-error-checkpoint.rds")
never_execute <- function(item, input) stop("hash errors must not launch a child")
hash_error <- fertility_process_item(
    hash_error_item, hash_error_checkpoint, "framework", 1L, FALSE, never_execute
)
stopifnot(hash_error$result$classification == "input-hash-error",
          nzchar(hash_error$result$input_id),
          fertility_process_item(hash_error_item, hash_error_checkpoint,
                                 "framework", 1L, FALSE, never_execute)$resumed)
invisible(fertility_publish_results(
    list(hash_error$result), "build", file.path(root, "hash-error-results.tsv")
))

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
modified$rlang_installed_md5 <- modified_digest
stopifnot(!identical(original_digest, modified_digest),
          "rlang_installed_md5" %in%
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
