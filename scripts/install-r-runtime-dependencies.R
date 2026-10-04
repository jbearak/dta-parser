# Usage: Rscript scripts/install-r-runtime-dependencies.R key|install|check PACKAGE LIBRARY
# Run without --vanilla when installing, to retain setup-r's binary repository.
# The cache contains runtime dependencies, never dtatools or its Suggests.
.runtime_parse <- function(description) {
    requirements <- unlist(lapply(c("Depends", "Imports"), function(field) {
        text <- description[[field]]
        if (is.null(text) || is.na(text) || !nzchar(trimws(text))) return(character())
        trimws(strsplit(text, ",", fixed = TRUE)[[1L]])
    }))
    parsed <- lapply(requirements, function(item) {
        match <- regexec("^([A-Za-z][A-Za-z0-9.]*)\\s*(?:\\(\\s*(>=|<=|==|>|<)\\s*([0-9][A-Za-z0-9.-]*)\\s*\\))?$", item, perl = TRUE)
        parts <- regmatches(item, match)[[1L]]
        if (length(parts) != 4L) stop("Unsupported runtime dependency: ", item)
        if (tolower(parts[[2L]]) == "dtatools") stop("Cannot cache dtatools itself")
        list(name = parts[[2L]], operator = parts[[3L]], version = parts[[4L]])
    })
    parsed[order(vapply(parsed, function(x) paste(x$name, x$operator, x$version), character(1)))]
}

.runtime_satisfies <- function(actual, requirement) {
    if (!nzchar(requirement$operator)) return(TRUE)
    comparison <- utils::compareVersion(actual, requirement$version)
    switch(requirement$operator, ">=" = comparison >= 0L, "<=" = comparison <= 0L,
           "==" = comparison == 0L, ">" = comparison > 0L, "<" = comparison < 0L, FALSE)
}

.runtime_key <- function(requirements, identity) {
    normalized <- vapply(requirements, function(x) paste(x$name, x$operator, x$version), character(1))
    text <- c("r-runtime-v1", unlist(identity), sort(unique(normalized)))
    path <- tempfile("r-runtime-key-")
    on.exit(unlink(path), add = TRUE)
    writeLines(enc2utf8(text), path, useBytes = TRUE)
    paste0("r-runtime-v1-", unname(tools::md5sum(path)))
}

.runtime_identity <- function() {
    config <- function(field) {
        value <- system2(file.path(R.home("bin"), "R"), c("CMD", "config", field), stdout = TRUE)
        if (!is.null(attr(value, "status"))) stop("Cannot resolve R compiler identity")
        paste(value, collapse = " ")
    }
    list(image = Sys.getenv("ImageOS", Sys.info()[["sysname"]]),
         image_version = Sys.getenv("ImageVersion"),
         runner_arch = Sys.getenv("RUNNER_ARCH", Sys.info()[["machine"]]),
         r_version = as.character(getRversion()), r_platform = R.version$platform,
         r_arch = R.version$arch, rust = Sys.getenv("RUSTUP_TOOLCHAIN"),
         deployment_target = Sys.getenv("MACOSX_DEPLOYMENT_TARGET"),
         cc = config("CC"), cxx = config("CXX17"))
}

.runtime_missing <- function(requirements, installed) {
    unique(vapply(Filter(function(requirement) {
        name <- requirement$name
        if (name == "R") return(FALSE)
        !name %in% rownames(installed) ||
            !.runtime_satisfies(installed[name, "Version"], requirement)
    }, requirements), `[[`, character(1), "name"))
}

.runtime_main <- function(args = commandArgs(TRUE)) {
    if (length(args) != 3L || !args[[1L]] %in% c("key", "install", "check")) {
        stop("Arguments: key|install|check PACKAGE_SOURCE RUNTIME_LIBRARY")
    }
    description <- read.dcf(file.path(args[[2L]], "DESCRIPTION"))
    stopifnot(nrow(description) == 1L)
    requirements <- .runtime_parse(as.list(description[1L, ]))
    for (requirement in requirements) if (requirement$name == "R" &&
        !.runtime_satisfies(as.character(getRversion()), requirement)) stop("Unsupported R version")
    library <- args[[3L]]
    if (!dir.exists(library)) dir.create(library, recursive = TRUE)
    library <- normalizePath(library, winslash = "/", mustWork = TRUE)
    if (any(tolower(list.files(library)) == "dtatools")) stop("Runtime library must not contain dtatools")
    if (args[[1L]] == "key") {
        if (length(list.files(library, all.files = TRUE, no.. = TRUE))) stop("Key step requires a fresh empty library")
        key <- .runtime_key(requirements, .runtime_identity())
        output <- c(paste0("cache_key=", key), paste0("library=", library))
        github_output <- Sys.getenv("GITHUB_OUTPUT")
        if (nzchar(github_output)) cat(paste0(output, "\n"), file = github_output, append = TRUE, sep = "")
        cat(paste(output, collapse = "\n"), "\n", sep = "")
        return(invisible(NULL))
    }
    .libPaths(c(library, .libPaths()))
    installed <- utils::installed.packages()
    missing <- .runtime_missing(requirements, installed)
    if (length(missing) && args[[1L]] == "check") stop("Missing/outdated runtime dependencies: ", paste(missing, collapse = ", "))
    if (length(missing)) {
        repos <- getOption("repos")
        if (!length(repos) || any(repos == "@CRAN@")) stop("Configure the setup-r package repository before installing")
        options(install.packages.check.source = "no", install.packages.compile.from.source = "never")
        utils::install.packages(missing, lib = library, repos = repos, dependencies = NA, Ncpus = 2L)
    }
    for (requirement in requirements) {
        name <- requirement$name
        if (name == "R") next
        if (!requireNamespace(name, quietly = TRUE) ||
            !.runtime_satisfies(as.character(utils::packageVersion(name)), requirement)) {
            stop("Runtime dependency failed namespace/version validation: ", name)
        }
    }
    populated <- nrow(utils::installed.packages(lib.loc = library)) > 0L
    output <- paste0("cache_populated=", if (populated) "true" else "false")
    github_output <- Sys.getenv("GITHUB_OUTPUT")
    if (nzchar(github_output)) cat(output, "\n", file = github_output, append = TRUE, sep = "")
    cat(output, "\n", sep = "")
    cat("R runtime dependencies: PASS", if (length(missing)) "(installed missing/outdated packages)" else "(reused installed packages)", "\n")
}

if (sys.nframe() == 0L) .runtime_main()
