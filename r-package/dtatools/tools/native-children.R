# Verify installed native tests and explicitly declared process boundaries.
.native_child_context <- function() {
    context <- getOption("dtatools.native.context")
    .native_require(is.list(context) && is.environment(context$state), "No native child context")
    context
}
.native_child_request <- function(id, kind) {
    context <- .native_child_context()
    policies <- Filter(function(x) identical(x$id, id), context$family$children)
    .native_require(length(policies) == 1L && identical(policies[[1L]]$kind, kind),
                    "Child id/kind is not in the family manifest")
    context$state$next_child <- context$state$next_child + 1L
    directory <- file.path(context$output, "children", sprintf("%04d-%s", context$state$next_child, id))
    .native_require(dir.create(directory, recursive = TRUE), "Child record directory already exists")
    cfg_path <- file.path(directory, "configuration.R")
    child_cfg <- context$cfg
    child_cfg$forks <- policies[[1L]]$forks
    .native_write(cfg_path, child_cfg)
    request <- list(id = id, kind = kind, policy = policies[[1L]], directory = directory,
                    cfg_path = cfg_path, guard = context$cfg$guard,
                    requested_r = context$cfg$runtime$child_r$path,
                    requested_rscript = context$cfg$runtime$rscript$path,
                    parent_pid = Sys.getpid(), cfg = context$cfg)
    .native_write(file.path(directory, "request.R"), request[setdiff(names(request), "cfg")])
    inputs <- c(cfg_path, context$cfg$guard, context$cfg$children)
    request$inputs <- unname(tools::md5sum(inputs))
    names(request$inputs) <- inputs
    .native_write(file.path(directory, "inputs-before.R"), request$inputs)
    request
}
.native_self_contained <- function(fun) {
    .native_require(is.function(fun) && !is.primitive(fun), "A self-contained R function is required")
    # Matches callr's documented function transport boundary. Do not transport
    # the test environment and accidentally load optional namespaces before guard.
    eval(call("function", formals(fun), body(fun)), envir = .GlobalEnv)
}
.native_plain_arguments <- function(args) {
    .native_require(is.list(args), "Child arguments must be an explicit list")
    active <- character()
    clean <- function(x) {
        if (is.function(x)) return(.native_self_contained(x))
        if (is.environment(x) || typeof(x) %in% c("externalptr", "weakref"))
            stop("Pass explicit child data/paths rather than process-local state", call. = FALSE)
        if (typeof(x) == "list") {
            .native_require(!is.object(x), "Use plain child arguments or an explicitly bound RDS fixture path")
            address <- rlang::obj_address(x)
            .native_require(!address %in% active, "Cyclic argument lists require an explicit fixture path")
            active <<- c(active, address)
            on.exit(active <<- utils::head(active, -1L), add = TRUE)
            return(lapply(x, clean))
        }
        x
    }
    clean(args)
}
.native_child_body <- function(guard, config_path, directory, fun, args) {
    sys.source(guard, envir = .GlobalEnv)
    cfg <- dget(config_path)
    sys.source(cfg$children, envir = .GlobalEnv)
    original <- NULL
    on.exit(.native_terminal(cfg, directory, original), add = TRUE)
    tryCatch({
        .native_prepare(cfg, directory)
        options(dtatools.native.child = list(cfg = cfg, directory = directory))
        do.call(fun, args, envir = .GlobalEnv)
    }, error = function(e) { original <<- e; stop(e) },
       interrupt = function(e) { original <<- e; stop(e) })
}
.native_child_finished <- function(request, parent_error, exit_status = NULL, service_terminated = FALSE) {
    after <- unname(tools::md5sum(names(request$inputs)))
    names(after) <- names(request$inputs)
    .native_write(file.path(request$directory, "parent-result.R"),
        list(error = .native_condition(parent_error), exit_status = exit_status,
             service_terminated = service_terminated, inputs_after = after,
             inputs_unchanged = identical(after, request$inputs)))
    .native_require(identical(after, request$inputs), "Child selected inputs changed")
    .native_checkpoint(request$cfg, "after-child", file.path(request$directory, "parent-after.R"))
}
.native_parent_cleanup <- function(request, original, exit_status = NULL, service_terminated = FALSE) {
    secondary <- tryCatch({
        .native_child_finished(request, original, exit_status, service_terminated)
        NULL
    }, error = identity, interrupt = identity)
    if (!is.null(secondary)) {
        tryCatch(.native_write(file.path(request$directory, "parent-cleanup-error.R"),
            list(original = .native_condition(original), secondary = .native_condition(secondary))),
            error = function(e) NULL)
        if (is.null(original)) stop(secondary)
    }
    invisible(NULL)
}
native_r <- function(id, func, args = list(), timeout = 120) {
    .native_require(length(timeout) == 1L && is.finite(timeout) && timeout > 0, "Finite child timeout required")
    request <- .native_child_request(id, "r")
    original <- NULL
    on.exit(.native_parent_cleanup(request, original), add = TRUE)
    tryCatch(callr::r(.native_self_contained(.native_child_body),
        args = list(request$guard, request$cfg_path, request$directory,
                    .native_self_contained(func), .native_plain_arguments(args)),
        libpath = .native_chr(request$cfg$libraries), system_profile = FALSE, user_profile = FALSE,
        env = .native_environment(request$cfg), arch = request$cfg$runtime$child_r$path,
        stdout = file.path(request$directory, "stdout.log"),
        stderr = file.path(request$directory, "stderr.log"), timeout = timeout, package = FALSE),
        error = function(e) { original <<- e; stop(e) },
        interrupt = function(e) { original <<- e; stop(e) })
}
native_r_bg <- function(id, func, args = list(), stdout = "|", stderr = "|") {
    request <- .native_child_request(id, "r_bg")
    original <- NULL
    process <- tryCatch(callr::r_bg(.native_self_contained(.native_child_body),
        args = list(request$guard, request$cfg_path, request$directory,
                    .native_self_contained(func), .native_plain_arguments(args)),
        libpath = .native_chr(request$cfg$libraries), system_profile = FALSE, user_profile = FALSE,
        env = .native_environment(request$cfg), arch = request$cfg$runtime$child_r$path,
        stdout = stdout, stderr = stderr, supervise = TRUE, package = FALSE),
        error = function(e) { original <<- e; NULL })
    if (!is.null(original)) {
        .native_parent_cleanup(request, original)
        stop(original)
    }
    handle <- structure(list(process = process, request = request), class = "native_child_handle")
    state <- .native_child_context()$state
    state$background[[request$directory]] <- handle
    handle
}
native_bg_finish <- function(handle, timeout = 120, terminate_service = FALSE) {
    .native_require(inherits(handle, "native_child_handle"), "Expected guarded background handle")
    .native_require(length(timeout) == 1L && is.finite(timeout) && timeout > 0, "Finite child timeout required")
    request <- handle$request
    process <- handle$process
    original <- NULL
    terminated <- FALSE
    on.exit({
        if (process$is_alive()) process$kill()
        .native_parent_cleanup(request, original, process$get_exit_status(), terminated)
    }, add = TRUE)
    tryCatch({
        if (terminate_service) {
            .native_require(identical(request$policy$completion, "service"), "Only declared services may be terminated")
            .native_require(file.exists(file.path(request$directory, "loaded.R")), "Service lacks checked startup")
            .native_require(process$is_alive(), "Service exited before requested shutdown")
            process$kill()
            process$wait(timeout = timeout * 1000)
            terminated <- TRUE
            return(invisible(NULL))
        }
        .native_require(identical(request$policy$completion, "complete"), "Declared service requires explicit shutdown")
        process$wait(timeout = timeout * 1000)
        .native_require(!process$is_alive(), "Background child timeout")
        process$get_result()
    }, error = function(e) { original <<- e; stop(e) },
       interrupt = function(e) { original <<- e; stop(e) })
}
native_rscript <- function(id, script, timeout = 120) {
    .native_require(length(timeout) == 1L && is.finite(timeout) && timeout > 0, "Finite child timeout required")
    request <- .native_child_request(id, "rscript")
    script <- .native_path(script)
    copied <- file.path(request$directory, "body.R")
    .native_require(file.copy(script, copied, overwrite = FALSE), "Cannot retain script body")
    before <- unname(tools::md5sum(script))
    .native_require(identical(before, unname(tools::md5sum(copied))), "Script copy differs")
    combined <- file.path(request$directory, "script.R")
    quote <- function(x) paste(deparse(x, width.cutoff = 500L), collapse = "\n")
    header <- c(
        paste0("sys.source(", quote(request$guard), ", envir = .GlobalEnv)"),
        paste0(".native_cfg <- dget(", quote(request$cfg_path), ")"),
        "sys.source(.native_cfg$children, envir = .GlobalEnv)",
        paste0(".native_directory <- ", quote(request$directory)),
        ".native_finalized <- FALSE",
        ".native_script_finish <- function(cnd = NULL) {",
        "  if (.native_finalized) return(invisible(NULL))",
        "  .native_finalized <<- TRUE",
        "  .native_terminal(.native_cfg, .native_directory, cnd)",
        "}",
        "globalCallingHandlers(error = function(cnd) .native_script_finish(cnd),",
        "                      interrupt = function(cnd) .native_script_finish(cnd))",
        ".native_prepare(.native_cfg, .native_directory)",
        "options(dtatools.native.child = list(cfg = .native_cfg, directory = .native_directory))")
    writeLines(c(header, readLines(copied, warn = FALSE), ".native_script_finish()"), combined, useBytes = TRUE)
    .native_write(file.path(request$directory, "script-inputs.R"),
        list(original = script, original_md5 = before, copied_md5 = unname(tools::md5sum(copied)),
             combined_md5 = unname(tools::md5sum(combined)), scope = "Top-level body preserved between guard statements"))
    original <- NULL
    on.exit({
        source_error <- tryCatch({
            after <- unname(tools::md5sum(script))
            .native_write(file.path(request$directory, "script-after.R"),
                list(original = script, md5 = after, unchanged = identical(before, after)))
            .native_require(identical(before, after), "Original Rscript body changed")
            NULL
        }, error = identity, interrupt = identity)
        cleanup_error <- tryCatch({ .native_parent_cleanup(request, original); NULL },
            error = identity, interrupt = identity)
        if (!is.null(source_error)) {
            tryCatch(.native_write(file.path(request$directory, "parent-script-source-error.R"),
                list(original = .native_condition(original), secondary = .native_condition(source_error),
                     cleanup = .native_condition(cleanup_error))), error = function(e) NULL)
        }
        if (is.null(original)) {
            if (!is.null(source_error)) stop(source_error)
            if (!is.null(cleanup_error)) stop(cleanup_error)
        }
    }, add = TRUE)
    tryCatch({
        result <- callr::rscript(combined, libpath = .native_chr(request$cfg$libraries),
            system_profile = FALSE, user_profile = FALSE, env = .native_environment(request$cfg),
            show = FALSE, fail_on_status = FALSE, timeout = timeout)
        for (stream in c("stdout", "stderr")) {
            value <- result[[stream]]
            if (is.character(value) && length(value) == 1L)
                writeBin(charToRaw(value), file.path(request$directory, paste0(stream, ".log")))
        }
        .native_write(file.path(request$directory, "rscript-result.R"), result)
        .native_require(identical(result$status, 0L) || identical(result$status, 0), "Child Rscript failed")
        result
    },
        error = function(e) { original <<- e; stop(e) },
        interrupt = function(e) { original <<- e; stop(e) })
}
.native_check_children <- function(context) {
    abandoned <- character()
    for (handle in context$state$background) {
        if (handle$process$is_alive()) {
            abandoned <- c(abandoned, handle$request$directory)
            handle$process$kill()
        }
    }
    .native_write(file.path(context$output, "abandoned-children.R"), abandoned)
    .native_require(!length(abandoned), "Unfinished background children were terminated")
    root <- file.path(context$output, "children")
    directories <- if (dir.exists(root)) list.dirs(root, recursive = FALSE) else character()
    facts <- lapply(directories, function(directory) {
        request <- dget(file.path(directory, "request.R"))
        parent <- dget(file.path(directory, "parent-result.R"))
        .native_require(isTRUE(parent$inputs_unchanged), "Child input verification missing or failed")
        .native_require(!file.exists(file.path(directory, "parent-cleanup-error.R")), "Parent child-cleanup error was recorded")
        if (identical(request$kind, "rscript")) {
            .native_require(!file.exists(file.path(directory, "parent-script-source-error.R")),
                "Rscript source cleanup error was recorded")
            script_after <- dget(file.path(directory, "script-after.R"))
            .native_require(isTRUE(script_after$unchanged), "Rscript source verification missing or failed")
        }
        parent_after <- dget(file.path(directory, "parent-after.R"))
        .native_require(!length(parent_after$violations), "After-child parent library guard failed")
        .native_check_forks(request$policy$forks, directory)
        phases <- c("startup", "restricted", "loaded")
        if (identical(request$policy$completion, "complete")) phases <- c(phases, "terminal")
        for (phase in phases) {
            record <- dget(file.path(directory, paste0(phase, ".R")))
            .native_require(!length(record$violations), "Child library guard failed")
        }
        if (identical(request$policy$completion, "service")) {
            .native_require(isTRUE(parent$service_terminated) && is.null(parent$error), "Service shutdown unverified")
        } else {
            status <- dget(file.path(directory, "status.R"))
            .native_require(is.null(status$observation_error), "Child terminal observation incomplete")
            if (!isTRUE(request$policy$allow_error)) {
                .native_require(isTRUE(status$complete) && is.null(parent$error), "Child did not complete cleanly")
            } else if (!is.null(parent$error) || !isTRUE(status$complete)) {
                .native_require(!is.null(status$original_error) && !is.null(parent$error),
                    "Allowed error lacks actual remote-body error evidence")
                .native_require(!any(grepl("timeout|timedout", parent$error$class, ignore.case = TRUE)),
                    "Transport timeout is not an allowed remote-body error")
                if (identical(request$kind, "rscript")) {
                    script_result <- dget(file.path(directory, "rscript-result.R"))
                    .native_require(identical(script_result$status, 1L) || identical(script_result$status, 1),
                        "Allowed script error lacks an ordinary recorded R error exit")
                } else {
                    .native_require("callr_error" %in% parent$error$class,
                        "Allowed error is not a recorded callr remote-body failure")
                }
            }
        }
        list(id = request$id, kind = request$kind, directory = directory,
             completion = request$policy$completion, parent_error = parent$error)
    })
    ids <- vapply(facts, `[[`, "", "id")
    for (policy in context$family$children) {
        count <- sum(ids == policy$id)
        .native_require(count >= policy$minimum && count <= policy$maximum,
                        paste("Child count differs:", policy$id, count))
    }
    .native_write(file.path(context$output, "children-summary.R"), facts)
    .native_check_forks(context$family$forks, context$output)
    invisible(facts)
}

# These helpers observe the two existing signal-sender forks. They do not
# create processes, change the signal delay, or inventory a fork's file system.
.native_fork_context <- function() {
    child <- getOption("dtatools.native.child")
    if (!is.null(child)) return(list(cfg = child$cfg, directory = child$directory,
                                    policies = child$cfg$forks))
    parent <- .native_child_context()
    list(cfg = parent$cfg, directory = parent$output, policies = parent$family$forks)
}
.native_fork_snapshot <- function() {
    namespaces <- lapply(sort(loadedNamespaces()), function(name) {
        ns <- asNamespace(name)
        if (identical(ns, .BaseNamespaceEnv)) {
            path <- file.path(.Library, "base")
            version <- unname(as.character(getRversion()))
        } else {
            path <- unname(getNamespaceInfo(ns, "path"))
            version <- unname(as.character(getNamespaceVersion(ns)))
        }
        list(name = name, path = path, version = version)
    })
    list(pid = Sys.getpid(), state = list(libraries = unname(.libPaths()), namespaces = namespaces))
}
native_fork_request <- function(id) {
    context <- .native_fork_context()
    policies <- Filter(function(x) identical(x$id, id), context$policies)
    .native_require(length(policies) == 1L, "Fork id is not declared")
    .native_require("parallel" %in% loadedNamespaces(), "Load parallel before recording inherited fork state")
    directory <- file.path(context$directory, "forks", id)
    .native_require(dir.create(directory, recursive = TRUE), "Fork id already used")
    observed <- .native_checkpoint(context$cfg, "before-fork", file.path(directory, "parent-before.R"))
    expected <- .native_fork_snapshot()
    # Resolve aliases only in the parent. Fork snapshots stay in memory before
    # the existing signal delay and retain their raw paths for equality checks.
    canonical <- expected$state
    canonical$libraries <- .native_path(canonical$libraries)
    canonical$namespaces <- lapply(canonical$namespaces, function(namespace) {
        namespace$path <- .native_path(namespace$path)
        namespace
    })
    .native_require(identical(canonical$libraries, observed$libraries) &&
                    identical(canonical$namespaces, observed$namespaces),
                    "Caller state changed while preparing fork")
    request <- list(id = id, directory = directory, policy = policies[[1L]],
                    parent_pid = Sys.getpid(), expected = expected)
    .native_write(file.path(directory, "request.R"), request)
    request
}
native_fork_signal <- function(request, delay, signal) {
    .native_require(identical(delay, request$policy$delay), "Fork signal delay changed")
    .native_require(identical(signal, tools::SIGINT), "Only the existing interrupt signal is supported")
    .native_require(Sys.getpid() != request$parent_pid, "Signal helper must run in the fork")
    before <- .native_fork_snapshot()
    original <- NULL
    sent <- tryCatch({
        Sys.sleep(delay)
        tools::pskill(request$parent_pid, signal)
    }, error = function(e) { original <<- e; NULL },
       interrupt = function(e) { original <<- e; NULL })
    after <- tryCatch(.native_fork_snapshot(), error = function(e) {
        if (is.null(original)) original <<- e
        NULL
    })
    result <- list(id = request$id, target_pid = request$parent_pid, delay = delay,
                   signal = signal, signal_result = sent, before = before, after = after,
                   error = .native_condition(original),
                   scope = "Inherited state only; no independent startup or full image inventory")
    # The first durable fork write is after the real signal and second snapshot.
    .native_write(file.path(request$directory, "fork-result.R"), result)
    result
}
.native_fork_validate <- function(request, pid, collected, actual) {
    .native_require(is.list(collected) && length(collected) == 1L &&
                    identical(names(collected), as.character(pid)), "Fork collection is incomplete")
    .native_require(identical(collected[[1L]], actual), "Collected fork value differs from retained observation")
    .native_require(is.null(actual$error) && isTRUE(actual$signal_result), "Fork signal did not complete")
    .native_require(identical(actual$id, request$id) && identical(actual$target_pid, request$parent_pid) &&
                    identical(actual$delay, request$policy$delay), "Fork request identity differs")
    .native_require(identical(actual$before$pid, pid) && identical(actual$after$pid, pid) &&
                    pid != request$parent_pid, "Fork PID does not match actual process handle")
    .native_require(identical(actual$before$state, request$expected$state) &&
                    identical(actual$after$state, request$expected$state), "Fork inherited state changed")
}
native_fork_finish <- function(request, collected, pid) {
    context <- .native_fork_context()
    .native_write(file.path(request$directory, "collection.R"), list(pid = pid, value = collected))
    original <- NULL
    terminal_error <- NULL
    tryCatch(.native_fork_validate(request, pid, collected,
        dget(file.path(request$directory, "fork-result.R"))), error = function(e) { original <<- e })
    tryCatch(.native_checkpoint(context$cfg, "after-fork", file.path(request$directory, "parent-after.R")),
        error = function(e) { terminal_error <<- e })
    .native_write(file.path(request$directory, "status.R"), list(original_error = .native_condition(original),
        terminal_error = .native_condition(terminal_error), complete = is.null(original) && is.null(terminal_error)))
    if (!is.null(original)) stop(original)
    if (!is.null(terminal_error)) stop(terminal_error)
    invisible(TRUE)
}
.native_check_forks <- function(policies, directory) {
    root <- file.path(directory, "forks")
    directories <- if (dir.exists(root)) list.dirs(root, recursive = FALSE) else character()
    ids <- character()
    for (path in directories) {
        request <- dget(file.path(path, "request.R"))
        policy <- Filter(function(x) identical(x$id, request$id), policies)
        .native_require(length(policy) == 1L && identical(policy[[1L]], request$policy), "Undeclared fork request")
        status <- dget(file.path(path, "status.R"))
        .native_require(isTRUE(status$complete), "Fork completion missing or failed")
        for (phase in c("parent-before", "parent-after")) {
            guard <- dget(file.path(path, paste0(phase, ".R")))
            .native_require(!length(guard$violations), "Fork caller library guard failed")
        }
        collection <- dget(file.path(path, "collection.R"))
        .native_fork_validate(request, collection$pid, collection$value, dget(file.path(path, "fork-result.R")))
        ids <- c(ids, request$id)
    }
    for (policy in policies) {
        count <- sum(ids == policy$id)
        .native_require(count >= policy$minimum && count <= policy$maximum, "Fork count differs")
    }
    .native_write(file.path(directory, "forks-summary.R"),
        list(ids = ids, scope = "Explicit inherited-state signal helpers, separate from callr child counts"))
    invisible(ids)
}
