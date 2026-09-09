# Build dplyr-free dependency libraries for the installed native test runner.
# Rscript --vanilla scripts/provision-r-native-libraries.R PACKAGE OUTPUT MODE LANE ARROW
# MODE: current or floors. ARROW: with-arrow or without-arrow.
# Upload OUTPUT/evidence only. OUTPUT/payload contains dependency code and logs.
.native_dependency_fields <- c("Depends", "Imports", "LinkingTo")
.native_forbidden_packages <- c("dplyr", "labelled", "dtplyr", "tidyr", "haven")
.native_floor_sources <- list(
    pillar = list(Version = "1.9.0", Depends = "", LinkingTo = "",
        Imports = "cli (>= 2.3.0), fansi, glue, lifecycle, rlang (>= 1.0.2), utf8 (>= 1.1.0), utils, vctrs (>= 0.5.0)",
        sha256 = "f23eb486c087f864c2b4072d5cba01d5bebf2f554118bcba6886d8dbceb87acc"),
    rlang = list(Version = "1.2.0", Depends = "R (>= 4.0.0)", Imports = "utils", LinkingTo = "",
        sha256 = "8f808ad4f6c1ba37d81b6a4a2cdb4a7d4d30d5bee4ba3e9924352d85a3874357"),
    tibble = list(Version = "3.3.1", Depends = "R (>= 3.4.0)", LinkingTo = "",
        Imports = "cli, lifecycle (>= 1.0.0), magrittr, methods, pillar (>= 1.8.1), pkgconfig, rlang (>= 1.0.2), utils, vctrs (>= 0.5.0)",
        sha256 = "fb309f8a1939021b237c7e85ff7ad6e8ff5acd57a6230d220a452094b492b28f"),
    tidyselect = list(Version = "1.2.0", Depends = "R (>= 3.4)", LinkingTo = "",
        Imports = "cli (>= 3.3.0), glue (>= 1.3.0), lifecycle (>= 1.0.3), rlang (>= 1.0.4), vctrs (>= 0.4.1), withr",
        sha256 = "538d26b727e37d618e2efd3b00836048f103112a03e6994bf07a02392e269e3b"),
    vctrs = list(Version = "0.7.3", Depends = "R (>= 4.0.0)", LinkingTo = "",
        Imports = "cli (>= 3.4.0), glue, lifecycle (>= 1.0.3), rlang (>= 1.1.7)",
        sha256 = "b45078413e06ac624dddb7221a3a43908b405c8abec09822cb86638d30b0435b")
)
.native_dep_require <- function(ok, message) {
    if (!isTRUE(ok)) stop(message, call. = FALSE)
}
.native_dep_parse <- function(text) {
    if (is.null(text) || is.na(text) || !nzchar(trimws(text))) return(list())
    lapply(strsplit(text, ",", fixed = TRUE)[[1L]], function(item) {
        match <- regexec("^\\s*([A-Za-z][A-Za-z0-9.]*)\\s*(?:\\(\\s*(>=|<=|==|>|<)\\s*([0-9][A-Za-z0-9.-]*)\\s*\\))?\\s*$", item, perl = TRUE)
        parts <- regmatches(item, match)[[1L]]
        .native_dep_require(length(parts) == 4L, paste("Unsupported dependency declaration:", item))
        list(name = parts[[2L]], operator = parts[[3L]], version = parts[[4L]])
    })
}
.native_dep_edges <- function(record) {
    unlist(lapply(.native_dependency_fields, function(field) .native_dep_parse(record[[field]])), recursive = FALSE)
}
.native_dep_satisfies <- function(actual, operator, required) {
    if (!nzchar(operator)) return(TRUE)
    comparison <- utils::compareVersion(actual, required)
    switch(operator, ">=" = comparison >= 0L, "<=" = comparison <= 0L,
           "==" = comparison == 0L, ">" = comparison > 0L, "<" = comparison < 0L, FALSE)
}
.native_dep_plan <- function(package, records, base_versions, seeds, mode) {
    selected <- records
    if (mode == "floors") for (name in names(.native_floor_sources)) {
        selected[[name]] <- c(list(Package = name), .native_floor_sources[[name]])
    }
    visited <- character(); active <- character(); ordered <- character(); constraints <- list()
    visit <- function(edge, owner) {
        name <- edge$name
        .native_dep_require(!name %in% .native_forbidden_packages,
            paste("Forbidden mandatory dependency before package downloads:", owner, "->", name))
        version <- if (name %in% names(base_versions)) base_versions[[name]] else selected[[name]]$Version
        .native_dep_require(!is.null(version) && !is.na(version), paste("Unavailable dependency:", name))
        .native_dep_require(.native_dep_satisfies(version, edge$operator, edge$version),
            paste("Unsatisfied dependency before package downloads:", owner, "requires", name,
                  edge$operator, edge$version, "but selected", version))
        constraints[[length(constraints) + 1L]] <<- c(list(owner = owner, selected_version = version), edge)
        if (name %in% names(base_versions) || name %in% visited) return(invisible(NULL))
        .native_dep_require(!name %in% active, paste("Mandatory dependency cycle:", name))
        active <<- c(active, name)
        for (dependency in .native_dep_edges(selected[[name]])) visit(dependency, name)
        active <<- head(active, -1L)
        visited <<- c(visited, name); ordered <<- c(ordered, name)
    }
    for (dependency in .native_dep_edges(package)) visit(dependency, "dtatools")
    core <- ordered
    suggested <- .native_dep_parse(package$Suggests)
    for (name in seeds) {
        declared <- Filter(function(edge) identical(edge$name, name), suggested)
        edge <- if (length(declared)) declared[[1L]] else
            list(name = name, operator = "", version = "")
        visit(edge, "native tests")
    }
    list(core = core, tests = setdiff(ordered, core), order = ordered,
         records = selected[ordered], constraints = constraints)
}
.native_dep_dcf <- function(path) {
    value <- read.dcf(path)
    .native_dep_require(nrow(value) == 1L, paste("Expected one DESCRIPTION:", path))
    as.list(setNames(unname(value[1L, ]), colnames(value)))
}
.native_dep_main <- function(args = commandArgs(TRUE)) {
    .native_dep_require(length(args) == 5L,
        "Arguments: PACKAGE_SOURCE NEW_OUTPUT current|floors LANE with-arrow|without-arrow")
    package <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
    output <- args[[2L]]; mode <- args[[3L]]; lane <- args[[4L]]; arrow <- args[[5L]]
    .native_dep_require(mode %in% c("current", "floors"), "Unknown dependency mode")
    .native_dep_require(arrow %in% c("with-arrow", "without-arrow"), "Declare Arrow capability")
    .native_dep_require(grepl("^[a-z][a-z0-9_-]*$", lane), "Invalid lane name")
    .native_dep_require(getRversion() >= "4.6.0", "R 4.6.0 or later is required")
    .native_dep_require(!file.exists(output), "Output must be a fresh directory")
    .native_dep_require(dir.create(output, recursive = TRUE), "Cannot create output directory")
    output <- normalizePath(output, winslash = "/", mustWork = TRUE)
    evidence <- file.path(output, "evidence"); payload <- file.path(output, "payload")
    for (path in c(evidence, payload, file.path(payload, c("downloads", "logs", "metadata", "staging", "core", "tests", "empty")))) {
        .native_dep_require(dir.create(path), paste("Cannot create directory:", path))
    }
    record <- function(name, value) {
        path <- file.path(evidence, paste0(name, ".R"))
        .native_dep_require(!file.exists(path), paste("Record already exists:", path))
        dput(value, path)
    }
    original <- NULL
    completion <- NULL
    terminal_reader <- function() list(bound_inputs_available = FALSE)
    on.exit({
        terminal_error <- NULL
        terminal <- tryCatch(terminal_reader(), error = function(e) {
            terminal_error <<- list(class = class(e), message = conditionMessage(e)); NULL
        })
        result_error <- tryCatch({
            record("terminal", list(time = as.character(Sys.time()), observation = terminal,
                original_error = if (is.null(original)) NULL else
                    list(class = class(original), message = conditionMessage(original)),
                observation_error = terminal_error))
            NULL
        }, error = identity)
        # Keep the original install/download error if a later observation fails.
        if (is.null(original)) {
            if (!is.null(result_error)) stop(result_error)
            .native_dep_require(is.null(terminal_error) && isTRUE(terminal$inputs_unchanged),
                "Terminal provisioning input verification failed")
            .native_dep_require(is.list(completion), "Provisioning completion is missing")
            record("completed", completion)
        }
    }, add = TRUE)
    tryCatch({
        python <- Sys.getenv("DTA_NATIVE_PYTHON", unset = "")
        if (!nzchar(python)) {
            candidates <- Sys.which(c("python3", "python"))
            python <- unname(candidates[nzchar(candidates)][1L])
        }
        .native_dep_require(length(python) == 1L && !is.na(python) && nzchar(python), "Python 3 is required for SHA256 and safe DESCRIPTION reads")
        python <- normalizePath(python, winslash = "/", mustWork = TRUE)
        python_call <- function(code, paths) {
            value <- system2(python, c("-c", shQuote(code), shQuote(paths)), stdout = TRUE, stderr = TRUE)
            status <- attr(value, "status")
            .native_dep_require(is.null(status) || status == 0L, "Python identity/metadata helper failed")
            value
        }
        sha <- function(paths) {
            if (!length(paths)) return(character())
            value <- python_call("import hashlib,sys; print(chr(10).join(hashlib.sha256(open(p,'rb').read()).hexdigest() for p in sys.argv[1:]))", paths)
            .native_dep_require(length(value) == length(paths) && all(grepl("^[a-f0-9]{64}$", value)), "Invalid SHA256 output")
            unname(value)
        }
        observe_sha <- function(path) tryCatch(sha(path),
            error = function(e) list(error = conditionMessage(e)))
        inventory <- function(path) {
            code <- paste(
                "import hashlib,os,pathlib,stat,sys",
                "root=pathlib.Path(sys.argv[1]); rows=[]",
                "if not root.is_dir() or root.is_symlink(): raise RuntimeError('Invalid package root')",
                "for directory,dirs,files in os.walk(root,followlinks=False):",
                " for name in dirs+files:",
                "  p=pathlib.Path(directory)/name; s=p.lstat()",
                "  if p.is_symlink() or not (stat.S_ISDIR(s.st_mode) or stat.S_ISREG(s.st_mode)): raise RuntimeError('Nonregular package member')",
                "  if stat.S_ISREG(s.st_mode):",
                "   rel=p.relative_to(root).as_posix()",
                "   if chr(9) in rel or chr(10) in rel: raise RuntimeError('Unrepresentable member path')",
                "   rows.append((rel,str(s.st_size),oct(stat.S_IMODE(s.st_mode)),hashlib.sha256(p.read_bytes()).hexdigest()))",
                "print(chr(9).join(('path','bytes','mode','sha256')))",
                "for row in sorted(rows): print(chr(9).join(row))", sep = "\n")
            lines <- python_call(code, path)
            read.delim(text = paste(lines, collapse = "\n"), quote = "", comment.char = "",
                stringsAsFactors = FALSE, colClasses = c("character", "numeric", "character", "character"))
        }
        description_path <- file.path(package, "DESCRIPTION")
        description_sha <- sha(description_path)
        description <- .native_dep_dcf(description_path)
        .native_dep_require(identical(sha(description_path), description_sha), "Package DESCRIPTION changed while reading")
        .native_dep_require(identical(description$Package, "dtatools"), "Expected dtatools source")
        source_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
        .native_dep_require(length(source_arg) == 1L, "Run the provisioner as a standalone Rscript")
        script <- normalizePath(sub("^--file=", "", source_arg), winslash = "/", mustWork = TRUE)
        r <- normalizePath(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R"), winslash = "/", mustWork = TRUE)
        input_paths <- c(script, description_path, r, python)
        input_hashes <- setNames(sha(input_paths), input_paths)
        .native_dep_require(identical(unname(input_hashes[[description_path]]), description_sha),
            "Parsed package DESCRIPTION differs from invocation input")
        terminal_reader <- function() {
            after <- lapply(input_paths, function(path) tryCatch(sha(path),
                error = function(e) list(error = conditionMessage(e))))
            names(after) <- input_paths
            list(expected = as.list(input_hashes), observed = after,
                 inputs_unchanged = identical(as.list(input_hashes), after))
        }
        startup <- list(R = R.version, home = R.home(), libraries = .libPaths(), argv = commandArgs(FALSE),
            mode = mode, lane = lane, arrow = arrow, input_sha256 = input_hashes,
            scope = "Selected source/archive/package file identities; dependency payloads and raw install logs remain under payload")
        record("invocation", startup)
        base <- utils::installed.packages(lib.loc = .Library, fields = c("Priority"))
        .native_dep_require(!any(base[, "Package"] %in% .native_forbidden_packages), "Forbidden package in base library")
        .native_dep_require(all(base[, "Package"] == "translations" | base[, "Priority"] %in% c("base", "recommended")), "Unexpected non-base package in base library")
        base_versions <- c(R = as.character(getRversion()), setNames(unname(base[, "Version"]), unname(base[, "Package"])))
        repository <- Sys.getenv("DTA_NATIVE_REPOSITORY", unset = "https://cloud.r-project.org")
        .native_dep_require(grepl("^https://", repository), "An HTTPS CRAN source repository is required")
        # Repository index metadata is needed to reject the complete closure
        # before fetching any package archive or installing package code.
        available <- utils::available.packages(repos = repository, type = "source",
            fields = c("MD5sum"), filters = c("R_version", "OS_type", "subarch", "duplicates"))
        .native_dep_require(nrow(available) > 0L, "Empty repository metadata")
        records <- lapply(seq_len(nrow(available)), function(i)
            as.list(setNames(unname(available[i, ]), colnames(available))))
        names(records) <- unname(available[, "Package"])
        seeds <- c("testthat", "withr", "data.table", "callr", "bit64", "jsonlite", "purrr",
                   if (arrow == "with-arrow") "arrow")
        plan <- .native_dep_plan(description, records, base_versions, seeds, mode)
        record("dependency-plan", list(repository = repository, base = base, seeds = seeds, plan = plan))
        staging <- file.path(payload, "staging"); empty <- file.path(payload, "empty")
        empty_startup <- file.path(payload, "empty-startup")
        file.create(empty_startup)
        environment <- c(R_LIBS = staging, R_LIBS_SITE = empty, R_LIBS_USER = empty,
            R_ENVIRON = empty_startup, R_ENVIRON_USER = empty_startup,
            R_PROFILE = empty_startup, R_PROFILE_USER = empty_startup,
            R_MAKEVARS_USER = empty_startup, R_MAKEVARS_SITE = empty_startup,
            R_DEFAULT_PACKAGES = "utils,stats,methods", R_TESTS = "")
        do.call(Sys.setenv, as.list(environment))
        .libPaths(c(staging, empty, .Library), include.site = FALSE)
        record("build-environment", as.list(environment))
        installed_records <- list()
        for (name in plan$order) {
            selected <- plan$records[[name]]
            version <- selected$Version
            filename <- paste0(name, "_", version, ".tar.gz")
            urls <- if (mode == "floors" && name %in% names(.native_floor_sources)) {
                c(paste0("https://cran.r-project.org/src/contrib/Archive/", name, "/", filename),
                  paste0("https://cran.r-project.org/src/contrib/", filename))
            } else paste0(sub("/$", "", selected$Repository), "/", filename)
            archive <- NULL; archive_sha <- NULL
            for (attempt in seq_along(urls)) {
                destination <- file.path(payload, "downloads", paste0(attempt, "-", filename))
                status <- NULL; download_error <- NULL
                status <- tryCatch(utils::download.file(urls[[attempt]], destination, mode = "wb", quiet = TRUE),
                    error = function(e) { download_error <<- conditionMessage(e); NULL })
                ok <- identical(status, 0L) || identical(status, 0)
                digest <- if (ok) observe_sha(destination) else NULL
                record(paste0("download-", name, "-", attempt), list(url = urls[[attempt]],
                    download_status = status, error = download_error,
                    bytes = if (file.exists(destination)) unname(file.info(destination)$size) else NULL,
                    sha256 = digest, path = destination))
                if (!ok) next
                .native_dep_require(is.character(digest) && length(digest) == 1L &&
                    grepl("^[a-f0-9]{64}$", digest), "Downloaded archive digest could not be observed")
                if (!is.null(selected$sha256)) .native_dep_require(identical(digest, selected$sha256), "Pinned floor archive SHA256 differs")
                if (!is.null(selected$MD5sum) && !is.na(selected$MD5sum) && nzchar(selected$MD5sum)) {
                    .native_dep_require(identical(unname(tools::md5sum(destination)), selected$MD5sum), "Repository archive MD5 differs")
                }
                archive <- destination
                archive_sha <- digest
                break
            }
            .native_dep_require(!is.null(archive), paste("Source download failed:", name, version))
            desc_path <- file.path(payload, "metadata", paste0(name, "-DESCRIPTION"))
            python_call(paste(
                "import pathlib,sys,tarfile",
                "with tarfile.open(sys.argv[1]) as archive:",
                " member=archive.getmember(sys.argv[2]+'/DESCRIPTION')",
                " if not member.isfile(): raise RuntimeError('DESCRIPTION is not a regular member')",
                " pathlib.Path(sys.argv[3]).write_bytes(archive.extractfile(member).read())", sep = "\n"),
                c(archive, name, desc_path))
            actual <- .native_dep_dcf(desc_path)
            .native_dep_require(identical(actual$Package, name) && identical(actual$Version, version), "Source DESCRIPTION identity differs")
            normalize_edges <- function(value) lapply(.native_dep_edges(value), function(x) unname(unlist(x)))
            .native_dep_require(identical(normalize_edges(actual), normalize_edges(selected)), "Source dependencies differ from pre-download plan")
            .native_dep_require(!any(vapply(.native_dep_edges(actual), `[[`, "", "name") %in% .native_forbidden_packages), "Forbidden source dependency")
            log <- file.path(payload, "logs", paste0(name, ".log"))
            arguments <- c("CMD", "INSTALL", "--no-multiarch", paste0("--library=", shQuote(staging)), shQuote(archive))
            .native_dep_require(identical(sha(archive), archive_sha), "Source archive changed before install")
            record(paste0("install-", name, "-invocation"), list(r = r, args = arguments,
                source_sha256 = archive_sha, description_sha256 = sha(desc_path), environment = environment))
            status <- NULL; install_error <- NULL
            status <- tryCatch(system2(r, arguments, stdout = log, stderr = log, timeout = 1800),
                error = function(e) { install_error <<- conditionMessage(e); NULL })
            record(paste0("install-", name, "-result"), list(status = status, error = install_error,
                log = log, log_sha256 = if (file.exists(log)) observe_sha(log) else NULL,
                source_sha256_after = observe_sha(archive)))
            .native_dep_require(identical(status, 0L) || identical(status, 0), paste("Dependency installation failed:", name))
            .native_dep_require(identical(sha(archive), archive_sha), "Source archive changed during install")
            installed <- .native_dep_dcf(file.path(staging, name, "DESCRIPTION"))
            .native_dep_require(identical(installed$Package, name) && identical(installed$Version, version), "Installed version differs")
            .native_dep_require(identical(normalize_edges(installed), normalize_edges(selected)), "Installed dependencies differ from source plan")
            installed_records[[name]] <- inventory(file.path(staging, name))
            record(paste0("installed-", name), installed_records[[name]])
        }
        visible <- utils::installed.packages(lib.loc = staging)
        .native_dep_require(setequal(unname(visible[, "Package"]), plan$order) && !anyDuplicated(visible[, "Package"]), "Unexpected staging package membership")
        expected <- list()
        for (name in plan$order) {
            role <- if (name %in% plan$core) "core" else "tests"
            destination <- file.path(payload, role, name); source <- file.path(staging, name)
            before <- inventory(source)
            .native_dep_require(identical(before, installed_records[[name]]), "Installed dependency changed before copy")
            .native_dep_require(file.copy(source, dirname(destination), recursive = TRUE, copy.mode = TRUE, copy.date = TRUE), "Package copy failed")
            copied <- inventory(destination); after <- inventory(source)
            record(paste0("copy-", name), list(source = source, destination = destination,
                before = before, copied = copied, after = after))
            .native_dep_require(identical(before, copied) && identical(before, after), "Copied package bytes or modes differ")
            expected[[name]] <- list(version = plan$records[[name]]$Version, path = destination)
        }
        terminal_hashes <- setNames(sha(input_paths), input_paths)
        .native_dep_require(identical(input_hashes, terminal_hashes), "Provisioner inputs changed")
        # jsonlite is an explicit native seed and has now been installed and
        # inventoried. It only serializes metadata; it never computes the closure.
        loadNamespace("jsonlite", lib.loc = staging)
        lane_value <- list(r = r, R = as.character(getRversion()), core = file.path(payload, "core"),
            tests = file.path(payload, "tests"), empty = empty, expected_packages = expected)
        result <- list(schema_version = 1L, lanes = setNames(list(lane_value), lane), mode = mode,
            native_capabilities = seeds, repository = repository)
        jsonlite::write_json(result, file.path(evidence, "lane-plan.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
        completion <- list(input_sha256_before = input_hashes, input_sha256_after = terminal_hashes,
            lane_plan_sha256 = sha(file.path(evidence, "lane-plan.json")), packages = plan$order,
            source_packages = length(plan$order), core_packages = length(plan$core), test_packages = length(plan$tests),
            scope = "Prepared source-built dependency libraries; fresh installed dtatools and parent/child absence guards remain required")
        cat("Prepared", length(plan$core), "core and", length(plan$tests), "test dependencies for", lane, "\n")
    }, error = function(e) { original <<- e; stop(e) }, interrupt = function(e) { original <<- e; stop(e) })
}
if (sys.nframe() == 0L) .native_dep_main()
