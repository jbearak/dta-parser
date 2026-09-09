# Verify installed native tests and explicitly declared process boundaries.
.native_chr <- function(x) unname(as.character(unlist(x, use.names = FALSE)))
.native_path <- function(x) unname(normalizePath(x, winslash = "/", mustWork = TRUE))
.native_require <- function(ok, message) {
    if (!isTRUE(ok)) stop(message, call. = FALSE)
}
.native_write <- function(path, value) {
    .native_require(!file.exists(path), paste("Record already exists:", path))
    con <- file(path, open = "wt", encoding = "UTF-8")
    on.exit(close(con), add = TRUE)
    # Keep names as quoted attributes so Windows path backslashes round-trip.
    dput(value, con, control = c("keepNA", "keepInteger", "showAttributes"))
    invisible(value)
}
.native_condition <- function(cnd) {
    field <- function(fun) tryCatch(list(available = TRUE, value = fun()),
        error = function(e) list(available = FALSE, error = unname(conditionMessage(e))))
    if (is.null(cnd)) return(NULL)
    list(class = class(cnd), message = field(function() conditionMessage(cnd)),
         call = field(function() {
             call <- conditionCall(cnd)
             if (is.null(call)) NULL else deparse(call, width.cutoff = 500L)
         }))
}
.native_environment <- function(cfg) {
    paths <- .native_chr(cfg$libraries)
    c(R_LIBS = paste(paths[-length(paths)], collapse = .Platform$path.sep),
      R_LIBS_USER = paths[[length(paths) - 1L]],
      R_LIBS_SITE = paths[[length(paths) - 1L]],
      R_ENVIRON = cfg$empty_startup, R_ENVIRON_USER = cfg$empty_startup,
      R_DEFAULT_PACKAGES = "utils,stats,methods", R_TESTS = "")
}
.native_observe <- function(cfg, stage) {
    issues <- character()
    issue <- function(message) issues <<- c(issues, message)
    paths <- tryCatch(.native_path(.libPaths()), error = function(e) {
        issue(paste("library path observation:", conditionMessage(e))); character()
    })
    expected_paths <- .native_path(.native_chr(cfg$libraries))
    if (!identical(paths, expected_paths)) issue("visible library order or membership differs")
    if (anyDuplicated(paths)) issue("duplicate resolved library path")
    if (!identical(unname(as.character(getRversion())), cfg$runtime$version)) issue("R version differs")
    if (!identical(unname(R.version$platform), cfg$runtime$platform)) issue("R platform differs")
    if (!identical(.native_path(R.home()), .native_path(cfg$runtime$home))) issue("R home differs")
    if (!identical(.native_path(.Library), .native_path(cfg$runtime$base_library))) issue("base library differs")
    rscript <- .native_path(file.path(R.home("bin"),
        if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"))
    if (!identical(rscript, .native_path(cfg$runtime$rscript$path))) issue("selected Rscript sibling differs")
    members <- list()
    for (library in paths) {
        candidates <- list.dirs(library, recursive = FALSE, full.names = TRUE)
        for (candidate in candidates) {
            desc <- file.path(candidate, "DESCRIPTION")
            if (!file.exists(desc)) next
            record <- tryCatch({
                d <- read.dcf(desc)
                .native_require(nrow(d) == 1L, "Expected one DESCRIPTION record")
                .native_require(all(c("Package", "Version") %in% colnames(d)), "Missing DESCRIPTION identity")
                list(name = unname(d[1L, "Package"]), version = unname(d[1L, "Version"]),
                     path = .native_path(candidate), description_md5 = unname(tools::md5sum(desc)),
                     priority = if ("Priority" %in% colnames(d)) unname(d[1L, "Priority"]) else NULL)
            }, error = function(e) {
                issue(paste("invalid installed metadata:", candidate))
                list(path = candidate, error = .native_condition(e))
            })
            members[[length(members) + 1L]] <- record
        }
    }
    named <- Filter(function(x) !is.null(x$name), members)
    names_found <- vapply(named, `[[`, "", "name")
    if (anyDuplicated(names_found)) issue("duplicate installed package identity")
    forbidden <- .native_chr(cfg$forbidden)
    if (any(names_found %in% forbidden)) issue("forbidden package physically visible")
    for (name in names(cfg$expected_packages)) {
        selected <- cfg$expected_packages[[name]]
        found <- named[names_found == name]
        if (length(found) != 1L) {
            issue(paste("missing or duplicate expected package:", name))
        } else if (!identical(found[[1L]]$path, .native_path(selected$path)) ||
                   !identical(found[[1L]]$version, selected$version)) {
            issue(paste("expected package path/version differs:", name))
        }
    }
    extra <- named[!names_found %in% names(cfg$expected_packages)]
    for (record in extra) {
        base_location <- identical(dirname(record$path), .native_path(cfg$runtime$base_library))
        base_member <- record$name == "translations" ||
            (!is.null(record$priority) && record$priority %in% c("base", "recommended"))
        if (!base_location || !base_member) issue(paste("unexpected visible package:", record$name))
    }
    namespaces <- lapply(sort(loadedNamespaces()), function(name) {
        tryCatch({
            ns <- asNamespace(name)
            if (identical(ns, .BaseNamespaceEnv)) {
                path <- .native_path(file.path(.Library, "base"))
                version <- unname(as.character(getRversion()))
            } else {
                path <- .native_path(getNamespaceInfo(ns, "path"))
                version <- unname(as.character(getNamespaceVersion(ns)))
            }
            if (name %in% forbidden) issue(paste("forbidden loaded namespace:", name))
            if (!dirname(path) %in% expected_paths) issue(paste("namespace outside allowed libraries:", name))
            selected <- cfg$expected_packages[[name]]
            if (!is.null(selected) && (!identical(path, .native_path(selected$path)) ||
                                      !identical(version, selected$version))) {
                issue(paste("loaded namespace path/version differs:", name))
            }
            if (is.null(selected) && !identical(dirname(path), .native_path(cfg$runtime$base_library)))
                issue(paste("unexpected loaded namespace:", name))
            list(name = name, path = path, version = version)
        }, error = function(e) {
            issue(paste("namespace observation failed:", name))
            list(name = name, error = .native_condition(e))
        })
    })
    dlls <- lapply(getLoadedDLLs(), function(x) list(name = x[["name"]], path = x[["path"]],
                                                  dynamic_lookup = x[["dynamicLookup"]]))
    if ("dtatools" %in% loadedNamespaces()) {
        ns <- asNamespace("dtatools")
        if (!identical(sort(getNamespaceExports(ns)), sort(.native_chr(cfg$exports)))) issue("export set differs")
        dll <- getLoadedDLLs()[["dtatools"]]
        if (is.null(dll) || !identical(.native_path(dll[["path"]]), .native_path(cfg$package$dll_path)))
            issue("selected dtatools DLL differs")
    }
    list(stage = stage, time = as.character(Sys.time()), pid = Sys.getpid(), R = R.version,
         home = R.home(), bin = R.home("bin"), selected_rscript = rscript,
         libraries = paths, site = .Library.site, base = .Library,
         members = members, namespaces = namespaces, dlls = dlls, violations = unique(issues))
}
.native_checkpoint <- function(cfg, stage, path) {
    observed <- .native_observe(cfg, stage)
    .native_write(path, observed)
    .native_require(!length(observed$violations), paste("Native library guard failed:",
        paste(observed$violations, collapse = "; ")))
    invisible(observed)
}
.native_prepare <- function(cfg, directory) {
    # Observe startup before any corrective path assignment or package load.
    .native_checkpoint(cfg, "startup", file.path(directory, "startup.R"))
    .libPaths(.native_chr(cfg$libraries), include.site = FALSE)
    .native_checkpoint(cfg, "restricted", file.path(directory, "restricted.R"))
    library("dtatools", lib.loc = dirname(cfg$package$path), character.only = TRUE)
    .native_checkpoint(cfg, "loaded", file.path(directory, "loaded.R"))
}
.native_terminal <- function(cfg, directory, error = NULL) {
    observation_error <- NULL
    observed <- tryCatch(.native_checkpoint(cfg, "terminal", file.path(directory, "terminal.R")),
        error = function(e) { observation_error <<- .native_condition(e); NULL })
    .native_write(file.path(directory, "status.R"), list(original_error = .native_condition(error),
        observation_error = observation_error, complete = is.null(error) && is.null(observation_error)))
    if (is.null(error) && !is.null(observation_error)) stop("Native terminal guard failed", call. = FALSE)
    invisible(observed)
}
