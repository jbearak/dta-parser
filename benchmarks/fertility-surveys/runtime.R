fertility_host <- function() {
    value <- unname(Sys.info()[["nodename"]])
    if (is.null(value) || is.na(value) || !nzchar(value)) "unknown-host" else value
}

fertility_process_observation <- function(
    pid,
    signal_probe = function(pid) tools::pskill(pid, signal = 0L),
    handle_probe = ps::ps_handle,
    running_probe = ps::ps_is_running,
    start_probe = ps::ps_create_time
) {
    pid <- as.integer(pid)
    signal_alive <- tryCatch({
        value <- signal_probe(pid)
        if (isTRUE(value)) TRUE else NA
    }, no_such_process = function(error) FALSE,
       error = function(error) NA)
    handle <- tryCatch(handle_probe(pid),
                       no_such_process = function(error) structure(
                           list(), class = "fertility_missing_process"
                       ),
                       error = function(error) NULL)
    if (inherits(handle, "fertility_missing_process")) {
        return(list(alive = FALSE, start = NA_character_))
    }
    if (!is.null(handle)) {
        running <- tryCatch(running_probe(handle),
                            no_such_process = function(error) FALSE,
                            error = function(error) NA)
        if (isFALSE(running)) return(list(alive = FALSE, start = NA_character_))
        if (isTRUE(running)) {
            start <- tryCatch(
                sprintf("%.6f", as.numeric(start_probe(handle))),
                no_such_process = function(error) NA_character_,
                error = function(error) NA_character_
            )
            return(list(alive = TRUE, start = start))
        }
    }
    list(alive = signal_alive, start = NA_character_)
}

fertility_pid_alive <- function(pid) {
    fertility_process_observation(pid)$alive
}

fertility_process_start <- function(pid) {
    fertility_process_observation(pid)$start
}

fertility_random_identity <- function(pid = Sys.getpid()) {
    paste(pid, as.integer(Sys.time()), sample.int(.Machine$integer.max, 1L),
          sep = "-")
}

fertility_touch_heartbeat <- function(path, identity) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
    temporary <- tempfile("heartbeat.", tmpdir = dirname(path))
    on.exit(unlink(temporary), add = TRUE)
    writeLines(identity, temporary, useBytes = TRUE)
    Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) stop("could not update owner heartbeat")
    invisible(path)
}

fertility_owner <- function(heartbeat, pid = Sys.getpid(), start = NULL,
                            token = NULL) {
    pid <- as.integer(pid)
    if (length(pid) != 1L || is.na(pid) || pid < 1L ||
        !isTRUE(fertility_pid_alive(pid))) {
        stop("owner process is not alive")
    }
    if (is.null(start)) start <- fertility_process_start(pid)
    if (length(start) != 1L || is.na(start) || !nzchar(start)) {
        stop("could not identify owner process generation")
    }
    if (is.null(token)) token <- fertility_random_identity(pid)
    list(token = token, pid = pid, host = fertility_host(), start = start,
         heartbeat = normalizePath(heartbeat, winslash = "/", mustWork = FALSE),
         created = as.numeric(Sys.time()))
}

fertility_write_owner <- function(directory, owner) {
    path <- file.path(directory, "owner.tsv")
    temporary <- tempfile("owner.", tmpdir = directory)
    on.exit(unlink(temporary), add = TRUE)
    fields <- c("token", "pid", "host", "start", "heartbeat", "created")
    values <- vapply(fields, function(name) as.character(owner[[name]]), character(1))
    writeLines(paste(names(values), values, sep = "\t"), temporary, useBytes = TRUE)
    Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) stop("could not publish ownership record")
    invisible(path)
}

fertility_read_owner <- function(directory) {
    path <- file.path(directory, "owner.tsv")
    if (!file.exists(path)) return(NULL)
    lines <- tryCatch(readLines(path, warn = FALSE), error = function(error) character())
    pieces <- strsplit(lines, "\t", fixed = TRUE)
    fields <- c("token", "pid", "host", "start", "heartbeat", "created")
    if (length(pieces) != length(fields) || any(lengths(pieces) != 2L)) return(NULL)
    values <- setNames(vapply(pieces, `[[`, character(1), 2L),
                       vapply(pieces, `[[`, character(1), 1L))
    if (!identical(names(values), fields) ||
        !grepl("^[1-9][0-9]*$", values[["pid"]]) ||
        is.na(suppressWarnings(as.numeric(values[["created"]])))) return(NULL)
    list(token = values[["token"]], pid = as.integer(values[["pid"]]),
         host = values[["host"]], start = values[["start"]],
         heartbeat = values[["heartbeat"]],
         created = as.numeric(values[["created"]]))
}

fertility_owner_alive <- function(owner, heartbeat_grace = 3,
                                    process_probe = fertility_process_observation) {
    if (is.null(owner) || !identical(owner$host, fertility_host())) return(NA)
    observation <- process_probe(owner$pid)
    if (isFALSE(observation$alive)) return(FALSE)
    if (isTRUE(observation$alive) && !is.na(observation$start)) {
        return(identical(observation$start, owner$start))
    }

    # If OS process-generation metadata is temporarily unavailable, a recent
    # matching heartbeat can preserve ownership but can never prove staleness.
    if (!file.exists(owner$heartbeat)) return(NA)
    identity <- tryCatch(readLines(owner$heartbeat, warn = FALSE, n = 1L),
                         error = function(error) character())
    if (length(identity) != 1L || !identical(identity[[1L]], owner$start)) return(NA)
    info <- file.info(owner$heartbeat)
    if (!nrow(info) || is.na(info$mtime[[1L]])) return(NA)
    age <- as.numeric(difftime(Sys.time(), info$mtime[[1L]], units = "secs"))
    if (is.finite(age) && age <= heartbeat_grace) TRUE else NA
}

fertility_directory_age <- function(path) {
    info <- file.info(path)
    if (!nrow(info) || is.na(info$mtime[[1L]])) return(Inf)
    as.numeric(difftime(Sys.time(), info$mtime[[1L]], units = "secs"))
}

fertility_local_owner <- function(directory) {
    heartbeat <- file.path(directory, "heartbeat")
    owner <- fertility_owner(heartbeat)
    fertility_touch_heartbeat(heartbeat, owner$start)
    owner
}

fertility_acquire_lock <- function(path, owner = NULL, initialization_grace = 5,
                                   remote_stale_after = 7 * 24 * 3600,
                                   owner_status = fertility_owner_alive) {
    parent <- dirname(path)
    dir.create(parent, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    for (attempt in seq_len(3L)) {
        if (dir.create(path, showWarnings = FALSE, mode = "0700")) {
            if (is.null(owner)) owner <- fertility_local_owner(path)
            if (!isTRUE(fertility_owner_alive(owner))) {
                unlink(path, recursive = TRUE)
                stop("orchestrator owner is not alive")
            }
            complete <- FALSE
            on.exit(if (!complete) unlink(path, recursive = TRUE), add = TRUE)
            fertility_write_owner(path, owner)
            complete <- TRUE
            return(owner$token)
        }
        recorded <- fertility_read_owner(path)
        age <- fertility_directory_age(path)
        alive <- owner_status(recorded)
        stale <- if (is.null(recorded)) {
            age >= initialization_grace
        } else if (isTRUE(alive)) {
            FALSE
        } else if (isFALSE(alive)) {
            TRUE
        } else {
            age >= remote_stale_after
        }
        if (!stale) stop("another fertility corpus build or run is active")
        stale_path <- paste0(path, ".stale.", Sys.getpid(), ".", attempt)
        if (!file.rename(path, stale_path)) next
        moved_owner <- fertility_read_owner(stale_path)
        same_generation <- if (is.null(recorded)) is.null(moved_owner) else
            !is.null(moved_owner) && identical(moved_owner$token, recorded$token)
        if (!same_generation) {
            if (!file.exists(path)) file.rename(stale_path, path)
            stop("lock ownership changed during stale-lock reclamation")
        }
        unlink(stale_path, recursive = TRUE)
    }
    stop("could not acquire fertility corpus run lock")
}

fertility_release_lock <- function(path, token) {
    owner <- fertility_read_owner(path)
    if (is.null(owner) || !identical(owner$token, token)) return(FALSE)
    released <- paste0(path, ".released.", Sys.getpid())
    if (!file.rename(path, released)) return(FALSE)
    moved <- fertility_read_owner(released)
    if (is.null(moved) || !identical(moved$token, token)) {
        if (!file.exists(path)) file.rename(released, path)
        return(FALSE)
    }
    unlink(released, recursive = TRUE)
    TRUE
}

fertility_write_temp_owner <- function(path, owner = NULL) {
    if (is.null(owner)) owner <- fertility_local_owner(path)
    if (!isTRUE(fertility_owner_alive(owner))) stop("orchestrator owner is not alive")
    fertility_write_owner(path, owner)
}

fertility_clean_stale_tempdirs <- function(temp_root, current,
                                           ownerless_grace = 3600,
                                           remote_stale_after = 7 * 24 * 3600,
                                           owner_status = fertility_owner_alive) {
    paths <- list.dirs(temp_root, recursive = FALSE, full.names = TRUE)
    paths <- paths[grepl("^run[.]", basename(paths)) & paths != current]
    removed <- character()
    for (path in paths) {
        owner <- fertility_read_owner(path)
        alive <- owner_status(owner)
        stale <- if (is.null(owner)) {
            fertility_directory_age(path) >= ownerless_grace
        } else if (isFALSE(alive)) {
            TRUE
        } else if (is.na(alive)) {
            fertility_directory_age(path) >= remote_stale_after
        } else FALSE
        if (stale) {
            claimed <- paste0(path, ".stale.", Sys.getpid())
            if (file.rename(path, claimed)) {
                unlink(claimed, recursive = TRUE)
                removed <- c(removed, path)
            }
        }
    }
    invisible(removed)
}

fertility_hold_owner <- function(state, parent_pid) {
    parent_handle <- tryCatch(ps::ps_handle(as.integer(parent_pid)),
                              error = function(error) NULL)
    if (is.null(parent_handle) || !isTRUE(ps::ps_is_running(parent_handle))) {
        stop("could not identify orchestrator process generation")
    }
    parent_start <- tryCatch(
        sprintf("%.6f", as.numeric(ps::ps_create_time(parent_handle))),
        error = function(error) NA_character_
    )
    if (is.na(parent_start)) stop("could not identify orchestrator process generation")
    dir.create(state, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    heartbeat <- file.path(state, "heartbeat")
    owner <- fertility_owner(heartbeat, pid = parent_pid, start = parent_start)
    fertility_touch_heartbeat(heartbeat, owner$start)
    fertility_write_owner(state, owner)
    while (isTRUE(tryCatch(ps::ps_is_running(parent_handle),
                           error = function(error) FALSE))) {
        fertility_touch_heartbeat(heartbeat, owner$start)
        Sys.sleep(0.5)
    }
    invisible(NULL)
}

fertility_assert_tempdir <- function(raw_root) {
    root <- normalizePath(raw_root, winslash = "/", mustWork = TRUE)
    temporary <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
    if (!startsWith(temporary, paste0(root, "/"))) {
        stop("R temporary directory must remain beneath target/fertility-surveys/raw")
    }
    temporary
}

if (sys.nframe() == 0L) {
    arguments <- commandArgs(trailingOnly = TRUE)
    if (length(arguments) < 2L) stop("runtime.R requires an action and path")
    action <- arguments[[1L]]
    path <- arguments[[2L]]
    if (identical(action, "hold-owner")) {
        if (length(arguments) != 3L) stop("hold-owner requires parent PID")
        fertility_hold_owner(path, as.integer(arguments[[3L]]))
    } else if (identical(action, "acquire-lock")) {
        if (length(arguments) != 3L) stop("acquire-lock requires owner state")
        owner <- fertility_read_owner(arguments[[3L]])
        cat(fertility_acquire_lock(path, owner))
    } else if (identical(action, "release-lock")) {
        if (length(arguments) != 3L || !fertility_release_lock(path, arguments[[3L]]))
            quit(status = 1L)
    } else if (identical(action, "write-temp-owner")) {
        if (length(arguments) != 3L) stop("write-temp-owner requires owner state")
        fertility_write_temp_owner(path, fertility_read_owner(arguments[[3L]]))
    } else if (identical(action, "clean-temp")) {
        if (length(arguments) != 3L) stop("clean-temp requires current temp path")
        fertility_clean_stale_tempdirs(path, arguments[[3L]])
    } else stop("unknown runtime.R action")
}
