fertility_runtime_path_is_symlink <- function(path) {
    link <- Sys.readlink(path)
    !is.na(link) & nzchar(link)
}

fertility_runtime_assert_file <- function(path, parent = dirname(path),
                                          label = "runtime file") {
    path <- path.expand(path)
    parent <- path.expand(parent)
    if (!identical(dirname(path), parent) || !dir.exists(parent) ||
        fertility_runtime_path_is_symlink(parent) ||
        fertility_runtime_path_is_symlink(path) || !file.exists(path) ||
        dir.exists(path)) stop(label, " must be a direct non-symlink file")
    if (!identical(normalizePath(parent, winslash = "/", mustWork = TRUE), parent) ||
        !identical(normalizePath(path, winslash = "/", mustWork = TRUE), path)) {
        stop(label, " must be canonical")
    }
    path
}

fertility_secure_directory <- function(path, label = "runtime directory") {
    lexical <- path.expand(path)
    if (!startsWith(lexical, "/")) stop(label, " must be absolute")
    pieces <- strsplit(sub("^/", "", lexical), "/", fixed = TRUE)[[1L]]
    current <- "/"
    for (piece in pieces[nzchar(pieces)]) {
        child <- file.path(current, piece)
        if (fertility_runtime_path_is_symlink(child)) stop(label, " must not traverse symlinks")
        if (!dir.exists(child) &&
            !dir.create(child, showWarnings = FALSE, mode = "0700")) {
            stop("could not create ", label)
        }
        if (fertility_runtime_path_is_symlink(current) || fertility_runtime_path_is_symlink(child) ||
            !identical(
                dirname(normalizePath(child, winslash = "/", mustWork = TRUE)),
                normalizePath(current, winslash = "/", mustWork = TRUE)
            )) stop(label, " escaped its lexical parent")
        current <- child
    }
    lexical
}

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
    parent <- fertility_secure_directory(dirname(path), "heartbeat parent")
    if (fertility_runtime_path_is_symlink(path) || dir.exists(path)) {
        stop("owner heartbeat must not be a symlink or directory")
    }
    if (file.exists(path)) fertility_runtime_assert_file(
        path, parent, "owner heartbeat"
    )
    temporary <- tempfile("heartbeat.", tmpdir = parent)
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
    directory <- fertility_secure_directory(directory, "owner directory")
    path <- file.path(directory, "owner.tsv")
    if (fertility_runtime_path_is_symlink(path) || dir.exists(path)) {
        stop("ownership record must not be a symlink or directory")
    }
    if (file.exists(path)) fertility_runtime_assert_file(
        path, directory, "ownership record"
    )
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
    directory <- path.expand(directory)
    if (fertility_runtime_path_is_symlink(directory)) {
        stop("owner directory must not be a symlink")
    }
    path <- file.path(directory, "owner.tsv")
    if (fertility_runtime_path_is_symlink(path)) {
        stop("ownership record must not be a symlink")
    }
    if (!file.exists(path)) return(NULL)
    path <- fertility_runtime_assert_file(path, directory, "ownership record")
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
    if (is.null(owner)) return(NA)
    if (identical(owner$host, fertility_host())) {
        observation <- process_probe(owner$pid)
        if (isFALSE(observation$alive)) return(FALSE)
        if (isTRUE(observation$alive) && !is.na(observation$start)) {
            return(identical(observation$start, owner$start))
        }
    }

    # If the owner is remote or OS process-generation metadata is temporarily
    # unavailable, a recent matching heartbeat can preserve ownership but can
    # never prove staleness.
    if (fertility_runtime_path_is_symlink(owner$heartbeat)) {
        stop("owner heartbeat must not be a symlink")
    }
    if (!file.exists(owner$heartbeat)) return(NA)
    heartbeat <- fertility_runtime_assert_file(
        owner$heartbeat, dirname(owner$heartbeat), "owner heartbeat"
    )
    identity <- tryCatch(readLines(heartbeat, warn = FALSE, n = 1L),
                         error = function(error) character())
    if (length(identity) != 1L || !identical(identity[[1L]], owner$start)) return(NA)
    info <- file.info(heartbeat)
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
    parent <- fertility_secure_directory(dirname(path), "lock parent")
    if (fertility_runtime_path_is_symlink(path)) stop("lock path must not be a symlink")
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

fertility_acquire_lock_wait <- function(path, owner, timeout = 1800,
                                        poll_seconds = 0.1) {
    deadline <- Sys.time() + timeout
    repeat {
        result <- tryCatch(fertility_acquire_lock(path, owner), error = identity)
        if (!inherits(result, "error")) return(result)
        if (!grepl("another fertility corpus", conditionMessage(result)) ||
            Sys.time() >= deadline) stop(result)
        Sys.sleep(poll_seconds)
    }
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

fertility_lock_component <- function(value, label = "lock component") {
    value <- as.character(value)
    if (length(value) != 1L || is.na(value) ||
        !grepl("^[A-Za-z0-9._-]+$", value)) {
        stop(label, " is not safe for a lock path")
    }
    value
}

fertility_acquire_lock_set <- function(paths, owner) {
    paths <- sort(unique(normalizePath(paths, winslash = "/", mustWork = FALSE)))
    acquired <- character()
    tokens <- character()
    on.exit({
        if (length(acquired)) {
            for (index in rev(seq_along(acquired))) {
                fertility_release_lock(acquired[[index]], tokens[[index]])
            }
        }
    }, add = TRUE)
    for (path in paths) {
        token <- fertility_acquire_lock(path, owner)
        acquired <- c(acquired, path)
        tokens <- c(tokens, token)
    }
    result <- setNames(tokens, acquired)
    acquired <- character()
    result
}

fertility_release_lock_set <- function(tokens) {
    if (!length(tokens)) return(TRUE)
    results <- vapply(rev(seq_along(tokens)), function(index) {
        fertility_release_lock(names(tokens)[[index]], tokens[[index]])
    }, logical(1))
    all(results)
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
    state <- fertility_secure_directory(state, "owner state directory")
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
    } else if (identical(action, "acquire-lock-wait")) {
        if (length(arguments) != 3L) stop("acquire-lock-wait requires owner state")
        owner <- fertility_read_owner(arguments[[3L]])
        cat(fertility_acquire_lock_wait(path, owner))
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
