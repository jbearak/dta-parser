# Explicit test adapters: ordinary callr for present runs, checked children for
# the installed native runner. Every native child id is manifest-accounted.
.dtatools_child_native <- function(libpath) {
    context <- getOption("dtatools.native.context")
    if (is.null(context)) return(FALSE)
    stopifnot(identical(unname(normalizePath(libpath, winslash = "/", mustWork = TRUE)),
        .native_path(.native_chr(context$cfg$libraries))))
    TRUE
}
.dtatools_child_r <- function(id, func, args = list(), libpath = .libPaths(), timeout = 120) {
    if (.dtatools_child_native(libpath)) return(native_r(id, func, args, timeout))
    callr::r(func, args = args, libpath = libpath, timeout = timeout)
}
.dtatools_child_r_bg <- function(id, func, args = list(), libpath = .libPaths(),
                               stdout = "|", stderr = "|", supervise = TRUE) {
    if (.dtatools_child_native(libpath)) {
        stopifnot(isTRUE(supervise))
        return(list(process = native_r_bg(id, func, args, stdout, stderr), native = TRUE))
    }
    list(process = callr::r_bg(func, args = args, libpath = libpath,
        stdout = stdout, stderr = stderr, supervise = supervise), native = FALSE)
}
.dtatools_child_process <- function(handle) {
    if (handle$native) handle$process$process else handle$process
}
.dtatools_child_finish <- function(handle, timeout = 120, terminate_service = FALSE) {
    if (handle$native) return(native_bg_finish(handle$process, timeout, terminate_service))
    process <- handle$process
    if (terminate_service) { process$kill(); return(invisible(NULL)) }
    process$wait(timeout = timeout * 1000)
    if (process$is_alive()) stop("Background child timed out")
    process$get_result()
}
.dtatools_child_rscript <- function(id, script, libpath = .libPaths(), show = FALSE,
                                   fail_on_status = TRUE, timeout = 120) {
    if (.dtatools_child_native(libpath)) {
        stopifnot(identical(show, FALSE), isTRUE(fail_on_status))
        return(native_rscript(id, script, timeout))
    }
    callr::rscript(script, libpath = libpath, show = show,
        fail_on_status = fail_on_status, timeout = timeout)
}

.dtatools_child_observe <- function(handle, observations) {
    if (handle$native) .native_write(
        file.path(handle$process$request$directory, "caller-observations.R"), observations)
    invisible(NULL)
}
