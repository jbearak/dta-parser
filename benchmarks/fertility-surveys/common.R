fertility_schema_version <- 13L
fertility_expected_rows <- 1004L
fertility_expected_releases <- c(`111` = 130L, `113` = 475L, `114` = 23L,
                                  `117` = 150L, `118` = 226L)
fertility_supported_releases <- c(113L, 114L, 115L, 117L, 118L)
fertility_programs <- c("dhs", "mics", "wfs", "nsfg", "enadid", "output")
fertility_cache_levels <- c("women", "births")
fertility_output_levels <- c("survey", "aggregate")
fertility_levels <- c(fertility_cache_levels, fertility_output_levels)
fertility_opt_in_value <- "I_UNDERSTAND_THIS_READS_PROPRIETARY_DATA"
fertility_output_expected_files <- 1226L
fertility_output_expected_bytes <- 70748321626
fertility_output_expected_largest <- 10332252930
fertility_output_inventory_schema_version <- 2L

fertility_script_path <- function() {
    argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
    if (!length(argument)) stop("could not determine script path", call. = FALSE)
    normalizePath(sub("^--file=", "", argument[[1L]]), winslash = "/")
}

fertility_checkout_root <- function(script_path = fertility_script_path()) {
    normalizePath(file.path(dirname(script_path), "..", ".."), winslash = "/")
}

fertility_path_is_symlink <- function(path) {
    link <- Sys.readlink(path)
    !is.na(link) & nzchar(link)
}

fertility_assert_canonical_components <- function(path, label,
                                                   must_exist = TRUE) {
    lexical <- path.expand(path)
    if (length(lexical) != 1L || is.na(lexical) || !startsWith(lexical, "/")) {
        stop(label, " must be an absolute canonical path")
    }
    pieces <- strsplit(sub("^/", "", lexical), "/", fixed = TRUE)[[1L]]
    current <- "/"
    for (piece in pieces[nzchar(pieces)]) {
        if (piece %in% c(".", "..")) stop(label, " must be canonical")
        current <- file.path(current, piece)
        exists <- file.exists(current) || dir.exists(current) ||
            fertility_path_is_symlink(current)
        if (exists && fertility_path_is_symlink(current)) {
            stop(label, " must not traverse symlinks")
        }
        if (!exists) break
    }
    if (must_exist) {
        if (!file.exists(lexical) && !dir.exists(lexical)) {
            stop(label, " must exist")
        }
        resolved <- normalizePath(lexical, winslash = "/", mustWork = TRUE)
        if (!identical(resolved, lexical)) stop(label, " must be canonical")
    }
    lexical
}

fertility_assert_existing_directory <- function(path, parent, label) {
    path <- fertility_assert_direct_child(path, parent, label)
    if (!dir.exists(path)) stop(label, " must be an existing directory")
    fertility_assert_canonical_components(path, label)
}

fertility_assert_existing_file <- function(path, parent, label) {
    path <- fertility_assert_direct_child(path, parent, label)
    if (!file.exists(path) || dir.exists(path)) {
        stop(label, " must be an existing regular file")
    }
    fertility_assert_canonical_components(path, label)
}

fertility_assert_checkpoint_file <- function(path, label,
                                             must_exist = FALSE) {
    parent <- fertility_assert_canonical_components(
        dirname(path), paste(label, "parent")
    )
    if (!dir.exists(parent)) stop(label, " parent must exist")
    if (fertility_path_is_symlink(path) || dir.exists(path)) {
        stop(label, " must not be a symlink or directory")
    }
    if (must_exist || file.exists(path)) {
        return(fertility_assert_existing_file(path, parent, label))
    }
    fertility_assert_direct_child(path, parent, label, must_work = FALSE)
}

fertility_assert_new_destination <- function(path, parent, label) {
    path <- fertility_assert_direct_child(
        path, parent, label, must_work = FALSE
    )
    if (file.exists(path) || dir.exists(path) || fertility_path_is_symlink(path)) {
        stop(label, " already exists")
    }
    path
}

fertility_remove_confirmed_new_path <- function(path, parent, label) {
    path <- fertility_assert_direct_child(path, parent, label)
    if (fertility_path_is_symlink(path)) {
        stop("refusing to remove symlinked ", label)
    }
    unlink(path, recursive = TRUE)
    !file.exists(path) && !dir.exists(path) && !fertility_path_is_symlink(path)
}

fertility_character_frame <- function(value) {
    if (!is.data.frame(value)) stop("expected table must be a data frame")
    result <- as.data.frame(
        lapply(value, as.character), stringsAsFactors = FALSE,
        check.names = FALSE
    )
    rownames(result) <- NULL
    result
}

fertility_validate_exact_table_bundle <- function(
    bundle, files, expected, label
) {
    bundle <- fertility_assert_existing_directory(
        bundle, dirname(bundle), paste(label, "directory")
    )
    expected_files <- unname(files)
    if (!identical(names(files), names(expected)) ||
        anyDuplicated(expected_files) || !length(files) ||
        any(!nzchar(expected_files)) ||
        !identical(basename(expected_files), expected_files)) {
        stop(label, " specification is invalid")
    }
    entries <- sort(list.files(
        bundle, all.files = TRUE, no.. = TRUE, full.names = TRUE,
        recursive = FALSE, include.dirs = TRUE
    ))
    if (!identical(sort(basename(entries)), sort(expected_files))) {
        stop(label, " exact file set changed")
    }
    loaded <- lapply(seq_along(files), function(index) {
        path <- fertility_assert_existing_file(
            file.path(bundle, files[[index]]), bundle,
            paste(label, names(files)[[index]])
        )
        if (!file_test("-f", path) || fertility_path_is_symlink(path)) {
            stop(label, " must contain only regular nonsymlink files")
        }
        read.delim(path, colClasses = "character", check.names = FALSE)
    })
    names(loaded) <- names(files)
    expected <- lapply(expected, fertility_character_frame)
    if (!identical(loaded, expected)) stop(label, " exact contents changed")
    loaded
}

fertility_attest_existing_files <- function(paths, label) {
    paths <- vapply(paths, function(path) fertility_assert_existing_file(
        path, dirname(path), label
    ), character(1))
    list(paths = paths, sha256 = unname(tools::sha256sum(paths)))
}

fertility_revalidate_existing_files <- function(attestation, label) {
    if (!is.list(attestation) || !identical(
        names(attestation), c("paths", "sha256")
    )) stop(label, " attestation is invalid")
    current <- fertility_attest_existing_files(attestation$paths, label)
    if (!identical(current, attestation)) stop(label, " identity changed")
    invisible(TRUE)
}

fertility_attest_regular_tree <- function(directory, label) {
    directory <- fertility_assert_existing_directory(
        directory, dirname(directory), paste(label, "root")
    )
    files <- character()
    walk <- function(parent) {
        entries <- sort(list.files(
            parent, all.files = TRUE, no.. = TRUE, full.names = TRUE,
            recursive = FALSE, include.dirs = TRUE
        ))
        for (entry in entries) {
            if (!identical(dirname(entry), parent) || fertility_path_is_symlink(entry)) {
                stop(label, " must not contain symlinks or escaped entries")
            }
            info <- file.info(entry)
            if (nrow(info) != 1L || is.na(info$isdir[[1L]])) {
                stop(label, " contains an unavailable entry")
            }
            resolved <- normalizePath(entry, winslash = "/", mustWork = TRUE)
            if (!identical(dirname(resolved), parent) ||
                !identical(resolved, file.path(parent, basename(entry)))) {
                stop(label, " entry escaped its canonical direct parent")
            }
            if (isTRUE(info$isdir[[1L]])) {
                walk(resolved)
            } else if (isTRUE(file_test("-f", resolved))) {
                files <<- c(files, resolved)
            } else {
                stop(label, " contains a non-regular file")
            }
        }
    }
    walk(directory)
    files <- sort(files)
    if (!length(files)) stop(label, " is empty")
    relative <- substring(files, nchar(directory) + 2L)
    list(
        directory = directory, paths = relative,
        sha256 = unname(tools::sha256sum(files))
    )
}

fertility_revalidate_regular_tree <- function(attestation, label) {
    if (!is.list(attestation) || !identical(
        names(attestation), c("directory", "paths", "sha256")
    )) stop(label, " attestation is invalid")
    current <- fertility_attest_regular_tree(attestation$directory, label)
    if (!identical(current, attestation)) stop(label, " identity changed")
    invisible(TRUE)
}

fertility_filesystem_identity <- function(path, label) {
    path <- fertility_assert_canonical_components(path, label)
    if (fertility_path_is_symlink(path)) stop(label, " must not be a symlink")
    python <- Sys.which("python3")
    if (!nzchar(python)) stop("python3 is required for filesystem identity")
    code <- paste(
        "import os, sys",
        "value=os.lstat(sys.argv[1])",
        "print(f'{value.st_dev}:{value.st_ino}:{value.st_mode}')",
        sep = "\n"
    )
    output <- suppressWarnings(system2(
        python, c("-c", shQuote(code), shQuote(path)),
        stdout = TRUE, stderr = FALSE
    ))
    status <- attr(output, "status", exact = TRUE)
    if ((!is.null(status) && status != 0L) || length(output) != 1L ||
        !grepl("^[0-9]+:[0-9]+:[0-9]+$", output[[1L]])) {
        stop("could not attest filesystem identity for ", label)
    }
    output[[1L]]
}

fertility_atomic_rename_noreplace <- function(
    from, to, label, validate_source = NULL
) {
    from <- path.expand(from)
    to <- path.expand(to)
    if (!file.exists(from) && !dir.exists(from)) stop(label, " source is absent")
    if (fertility_path_is_symlink(from) || fertility_path_is_symlink(to)) {
        stop(label, " must not use symlinks")
    }
    fertility_assert_canonical_components(dirname(from), paste(label, "source parent"))
    fertility_assert_canonical_components(dirname(to), paste(label, "destination parent"))
    fertility_publication_test_hook(
        "atomic-noreplace-before-operation",
        list(from = from, to = to, label = label)
    )
    if (!is.null(validate_source)) {
        if (!is.function(validate_source)) {
            stop(label, " source validator must be a function")
        }
        validate_source(from, to, label)
    }
    python <- Sys.which("python3")
    if (!nzchar(python)) stop("python3 is required for atomic no-replace publication")
    code <- paste(
        "import ctypes, errno, os, sys",
        "src=os.fsencode(sys.argv[1]); dst=os.fsencode(sys.argv[2])",
        "libc=ctypes.CDLL(None, use_errno=True)",
        "if sys.platform == 'darwin':",
        "    fn=libc.renamex_np; fn.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint]",
        "    rc=fn(src,dst,4)",
        "else:",
        "    fn=getattr(libc,'renameat2',None)",
        "    if fn is None: sys.exit(18)",
        "    fn.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint]",
        "    rc=fn(-100,src,-100,dst,1)",
        "if rc != 0:",
        "    value=ctypes.get_errno()",
        "    sys.exit(17 if value in (errno.EEXIST, errno.ENOTEMPTY) else 19)",
        sep = "\n"
    )
    status <- suppressWarnings(system2(
        python, c("-c", shQuote(code), shQuote(from), shQuote(to)),
        stdout = FALSE, stderr = FALSE
    ))
    if (identical(status, 17L)) stop(label, " destination already exists")
    if (!identical(status, 0L)) stop("atomic no-replace publication failed for ", label)
    invisible(TRUE)
}

fertility_publication_test_hook <- function(boundary, context = list()) {
    hook <- getOption("dtaparser.fertility.publication_test_hook")
    if (is.function(hook)) hook(boundary, context)
    invisible(TRUE)
}

fertility_assert_checkout_raw_root <- function(raw_root, checkout_root, create = FALSE) {
    checkout_lexical <- path.expand(checkout_root)
    checkout <- normalizePath(checkout_lexical, winslash = "/", mustWork = TRUE)
    if (!identical(checkout_lexical, checkout) || fertility_path_is_symlink(checkout_lexical)) {
        stop("fertility checkout root must be canonical and non-symlinked")
    }
    expected <- file.path(checkout, "target", "fertility-surveys", "raw")
    if (!identical(path.expand(raw_root), expected)) {
        stop("fertility outputs must use the checkout-local raw root")
    }
    components <- c(
        checkout, file.path(checkout, "target"),
        file.path(checkout, "target", "fertility-surveys"), expected
    )
    existing <- components[file.exists(components) | dir.exists(components)]
    if (length(existing) && any(fertility_path_is_symlink(existing))) {
        stop("fertility output ancestors must not be symlinks")
    }
    if (create) {
        parent <- checkout
        for (name in c("target", "fertility-surveys", "raw")) {
            child <- file.path(parent, name)
            if (fertility_path_is_symlink(child)) {
                stop("fertility output ancestors must not be symlinks")
            }
            if (!dir.exists(child) &&
                !dir.create(child, showWarnings = FALSE, mode = "0700")) {
                stop("could not create checkout-local fertility output directory")
            }
            if (fertility_path_is_symlink(parent) || fertility_path_is_symlink(child) ||
                !identical(
                    dirname(normalizePath(child, winslash = "/", mustWork = TRUE)),
                    normalizePath(parent, winslash = "/", mustWork = TRUE)
                )) stop("fertility raw root escaped the checkout")
            parent <- child
        }
    }
    if (!dir.exists(expected) || any(fertility_path_is_symlink(components)) ||
        !identical(normalizePath(expected, winslash = "/", mustWork = TRUE),
                   expected)) {
        stop("fertility raw root escaped the checkout")
    }
    expected
}

fertility_assert_direct_child <- function(path, parent, label,
                                          must_work = TRUE) {
    parent_lexical <- path.expand(parent)
    path_lexical <- path.expand(path)
    if (!identical(dirname(path_lexical), parent_lexical)) {
        stop(label, " must be directly beneath its expected parent")
    }
    if (!dir.exists(parent_lexical) || fertility_path_is_symlink(parent_lexical)) {
        stop(label, " parent must be an existing non-symlink directory")
    }
    fertility_assert_canonical_components(
        parent_lexical, paste(label, "parent")
    )
    if ((file.exists(path_lexical) || dir.exists(path_lexical)) &&
        fertility_path_is_symlink(path_lexical)) {
        stop(label, " must not be a symlink")
    }
    if (must_work) {
        resolved_parent <- normalizePath(
            parent_lexical, winslash = "/", mustWork = TRUE
        )
        resolved <- normalizePath(path_lexical, winslash = "/", mustWork = TRUE)
        if (!identical(dirname(resolved), resolved_parent)) {
            stop(label, " escaped its expected parent")
        }
    }
    path_lexical
}

fertility_assert_output_parent <- function(raw_root, collection, identity,
                                           create = FALSE) {
    collection_path <- file.path(raw_root, collection)
    fertility_assert_direct_child(
        collection_path, raw_root, paste(collection, "output directory"),
        must_work = FALSE
    )
    if (create && !dir.exists(collection_path) &&
        !dir.create(collection_path, showWarnings = FALSE, mode = "0700")) {
        stop("could not create ", collection, " output directory")
    }
    fertility_assert_direct_child(
        collection_path, raw_root, paste(collection, "output directory")
    )
    parent <- file.path(collection_path, identity)
    fertility_assert_direct_child(
        parent, collection_path, paste(collection, "publication parent"),
        must_work = FALSE
    )
    if (create && !dir.exists(parent) &&
        !dir.create(parent, showWarnings = FALSE, mode = "0700")) {
        stop("could not create ", collection, " publication parent")
    }
    fertility_assert_direct_child(
        parent, collection_path, paste(collection, "publication parent")
    )
}

fertility_resolve_checkpoint_case <- function(
    raw_root, framework_id, config_id, case_id, require_result = TRUE
) {
    if (!grepl("^[0-9a-f]{64}$", framework_id) ||
        !grepl("^[0-9a-f]{64}$", config_id) ||
        !grepl("^F[0-9]{4}$", case_id)) stop("checkpoint identity is invalid")
    checkpoints <- fertility_assert_existing_directory(
        file.path(raw_root, "checkpoints"), raw_root,
        "checkpoints output directory"
    )
    framework <- fertility_assert_existing_directory(
        file.path(checkpoints, framework_id), checkpoints,
        "framework checkpoint directory"
    )
    configuration <- fertility_assert_existing_directory(
        file.path(framework, config_id), framework,
        "configuration checkpoint directory"
    )
    case <- fertility_assert_existing_directory(
        file.path(configuration, case_id), configuration,
        "checkpoint case directory"
    )
    result <- file.path(case, "result.rds")
    if (require_result) result <- fertility_assert_existing_file(
        result, case, "checkpoint case result"
    )
    tiles <- file.path(case, "tiles")
    if (file.exists(tiles) || dir.exists(tiles) || fertility_path_is_symlink(tiles)) {
        tiles <- fertility_assert_existing_directory(
            tiles, case, "checkpoint tile directory"
        )
    } else tiles <- NULL
    list(
        checkpoints = checkpoints, framework = framework,
        configuration = configuration, case = case,
        result = result, tiles = tiles
    )
}

fertility_checkpoint_tile_files <- function(case_paths) {
    if (!is.list(case_paths) || is.null(case_paths$case)) {
        stop("checkpoint case paths are invalid")
    }
    if (is.null(case_paths$tiles)) return(character())
    tile_root <- fertility_assert_existing_directory(
        case_paths$tiles, case_paths$case, "checkpoint tile directory"
    )
    entries <- list.files(tile_root, all.files = TRUE, no.. = TRUE)
    if (any(!grepl("^[A-Za-z0-9._-]+[.]rds$", entries))) {
        stop("checkpoint tile directory contains an invalid entry")
    }
    vapply(entries, function(name) fertility_assert_existing_file(
        file.path(tile_root, name), tile_root, "checkpoint tile file"
    ), character(1))
}

fertility_resolve_build_bundle <- function(raw_root, build_id = NULL,
                                           require_current = FALSE) {
    builds_root <- fertility_assert_existing_directory(
        file.path(raw_root, "builds"), raw_root, "builds output directory"
    )
    current_id <- NULL
    if (require_current) {
        current_path <- fertility_assert_existing_file(
            file.path(builds_root, "CURRENT"), builds_root, "build CURRENT pointer"
        )
        value <- readLines(current_path, warn = FALSE, n = 1L)
        if (length(value) != 1L || !grepl("^[0-9a-f]{64}$", value)) {
            stop("build CURRENT pointer is invalid")
        }
        current_id <- value[[1L]]
        if (!is.null(build_id) && !identical(build_id, current_id)) {
            stop("selected build CURRENT changed")
        }
        build_id <- current_id
    }
    if (is.null(build_id) || length(build_id) != 1L ||
        !grepl("^[0-9a-f]{64}$", build_id)) stop("build identity is invalid")
    generation <- fertility_assert_existing_directory(
        file.path(builds_root, build_id), builds_root, "build generation"
    )
    library <- fertility_assert_existing_directory(
        file.path(generation, "library"), generation, "build library"
    )
    provenance <- fertility_assert_existing_file(
        file.path(generation, "build-provenance.tsv"), generation,
        "build provenance"
    )
    package <- fertility_assert_existing_directory(
        file.path(library, "dtaparser"), library, "installed dtaparser package"
    )
    list(
        builds_root = builds_root, current_id = current_id,
        generation = generation, library = library,
        provenance = provenance, package = package
    )
}

fertility_revalidate_current_bundle <- function(
    parent, expected_run_name, files, label
) {
    current <- fertility_current_bundle_paths(parent, files, label)
    if (!identical(current$run_name, expected_run_name)) {
        stop(label, " CURRENT changed before publication")
    }
    current
}

fertility_probe_current_bundle_family <- function(parent, label) {
    parent <- fertility_assert_canonical_components(parent, paste(label, "parent"))
    if (!dir.exists(parent)) stop(label, " parent must be an existing directory")
    pointer <- fertility_assert_existing_file(
        file.path(parent, "CURRENT"), parent, paste(label, "CURRENT pointer")
    )
    if (!file_test("-f", pointer)) {
        stop(label, " CURRENT pointer must be a regular file")
    }
    run_name <- tryCatch(
        readLines(pointer, warn = FALSE, n = 1L),
        error = function(error) character()
    )
    if (length(run_name) != 1L || !grepl("^[A-Za-z0-9._-]+$", run_name)) {
        stop(label, " CURRENT pointer is invalid")
    }
    bundle <- fertility_assert_direct_child(
        file.path(parent, run_name), parent, paste(label, "bundle"),
        must_work = FALSE
    )
    if (fertility_path_is_symlink(bundle)) {
        stop(label, " bundle must not be a symlink")
    }
    if (!dir.exists(bundle)) {
        if (file.exists(bundle)) stop(label, " bundle must be a directory")
        return(NULL)
    }
    bundle <- fertility_assert_existing_directory(
        bundle, parent, paste(label, "bundle")
    )
    provenance_path <- fertility_assert_direct_child(
        file.path(bundle, "run-provenance.tsv"), bundle,
        paste(label, "provenance"), must_work = FALSE
    )
    if (fertility_path_is_symlink(provenance_path)) {
        stop(label, " provenance must not be a symlink")
    }
    if (!file.exists(provenance_path)) {
        if (dir.exists(provenance_path)) {
            stop(label, " provenance must be a regular file")
        }
        return(NULL)
    }
    provenance_path <- fertility_assert_existing_file(
        provenance_path, bundle, paste(label, "provenance")
    )
    if (!file_test("-f", provenance_path)) {
        stop(label, " provenance must be a regular file")
    }
    provenance <- tryCatch(read.delim(
        provenance_path, colClasses = "character", check.names = FALSE
    ), error = function(error) NULL)
    if (is.null(provenance) || nrow(provenance) != 1L ||
        !"family_id" %in% names(provenance)) return(NULL)
    list(run_name = run_name, family_id = provenance$family_id[[1L]])
}

fertility_current_bundle_paths <- function(parent, files, label) {
    parent <- fertility_assert_canonical_components(parent, paste(label, "parent"))
    if (!dir.exists(parent)) stop(label, " parent must be an existing directory")
    pointer <- fertility_assert_existing_file(
        file.path(parent, "CURRENT"), parent, paste(label, "CURRENT pointer")
    )
    if (!file_test("-f", pointer)) {
        stop(label, " CURRENT pointer must be a regular file")
    }
    run_name <- tryCatch(
        readLines(pointer, warn = FALSE, n = 1L),
        error = function(error) character()
    )
    if (length(run_name) != 1L || !grepl("^[A-Za-z0-9._-]+$", run_name)) {
        stop(label, " CURRENT pointer is invalid")
    }
    bundle <- fertility_assert_existing_directory(
        file.path(parent, run_name), parent, paste(label, "bundle")
    )
    paths <- setNames(file.path(bundle, unname(files)), names(files))
    for (index in seq_along(paths)) {
        paths[[index]] <- fertility_assert_existing_file(
            paths[[index]], bundle, paste(label, names(paths)[[index]])
        )
        if (!file_test("-f", paths[[index]])) {
            stop(label, " ", names(paths)[[index]], " must be a regular file")
        }
    }
    list(bundle = bundle, paths = paths, run_name = run_name)
}

fertility_current_bundle_for_family <- function(
    parent, family_id, files, label
) {
    probe <- fertility_probe_current_bundle_family(parent, label)
    if (is.null(probe) || !identical(probe$family_id, family_id)) return(NULL)
    fertility_revalidate_current_bundle(
        parent, probe$run_name, files, label
    )
}

fertility_assert_manual_run <- function() {
    ci_variables <- c("CI", "GITHUB_ACTIONS", "GITHUB_RUN_ID", "GITHUB_WORKFLOW")
    active <- ci_variables[nzchar(Sys.getenv(ci_variables, unset = ""))]
    if (length(active)) {
        stop("fertility corpus runs are refused in CI and GitHub Actions", call. = FALSE)
    }
    if (!identical(Sys.getenv("DTAPARSER_FERTILITY_CORPUS"), fertility_opt_in_value)) {
        stop(paste0(
            "manual opt-in required: set DTAPARSER_FERTILITY_CORPUS=",
            fertility_opt_in_value
        ), call. = FALSE)
    }
}

fertility_output_requested <- function(options) {
    !is.null(options$output_root) && nzchar(options$output_root)
}

fertility_assert_output_root <- function(path) {
    root <- fertility_assert_canonical_components(path, "fertility output root")
    if (!dir.exists(root) || fertility_path_is_symlink(root)) {
        stop("fertility output root must be a canonical non-symlink directory")
    }
    root
}

fertility_output_inventory_test_hook <- function(boundary, context) {
    hook <- getOption("dtaparser.fertility.output_inventory_test_hook")
    if (is.function(hook)) hook(boundary, context)
    invisible(NULL)
}

fertility_decode_hex_path <- function(value) {
    if (!nzchar(value) || nchar(value) %% 2L != 0L ||
        !grepl("^[0-9a-f]+$", value)) {
        stop("fertility output regular-file attestation is malformed")
    }
    starts <- seq.int(1L, nchar(value), by = 2L)
    bytes <- suppressWarnings(strtoi(substring(value, starts, starts + 1L), 16L))
    if (anyNA(bytes)) stop("fertility output regular-file attestation is malformed")
    result <- rawToChar(as.raw(bytes))
    Encoding(result) <- "UTF-8"
    result
}

fertility_descriptor_timestamp <- function(seconds_text) {
    value <- suppressWarnings(as.double(seconds_text))
    if (length(value) != 1L || is.na(value) || !is.finite(value)) {
        stop("fertility output descriptor timestamp is invalid")
    }
    format(as.POSIXct(value, origin = "1970-01-01", tz = "UTC"),
           "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC")
}

fertility_output_descriptor_manifest <- function(root, include_content = FALSE) {
    root <- fertility_assert_output_root(root)
    if (!is.logical(include_content) || length(include_content) != 1L ||
        is.na(include_content)) stop("invalid output descriptor attestation mode")
    fertility_output_inventory_test_hook(
        if (include_content) "before-descriptor-content-read" else
            "before-descriptor-stat-read",
        list(root = root)
    )
    python <- Sys.which("python3")
    if (!nzchar(python)) stop("python3 is required for output inventory")
    code <- paste(
        "import hashlib, os, stat, sys",
        "root=os.fsencode(sys.argv[1]); include_content=sys.argv[2] == '1'",
        "base_flags=os.O_RDONLY | getattr(os,'O_CLOEXEC',0) | getattr(os,'O_NOFOLLOW',0)",
        "file_flags=base_flags; dir_flags=base_flags | getattr(os,'O_DIRECTORY',0)",
        "def fail(): raise RuntimeError('unsafe output inventory entry')",
        "def identity(value):",
        "    return (value.st_dev,value.st_ino,value.st_mode,value.st_size,value.st_mtime_ns,value.st_ctime_ns)",
        "def release(head):",
        "    if not head: fail()",
        "    if head.startswith(b'<stata_dta>'):",
        "        marker=b'<release>'; start=head.find(marker)",
        "        if start < 0 or head.find(marker,start+1) >= 0: fail()",
        "        value=head[start+len(marker):start+len(marker)+3]",
        "        if len(value) != 3 or not value.isdigit(): fail()",
        "        return value.decode('ascii')",
        "    return str(head[0])",
        "def attest(parent_fd,name,path,expected):",
        "    try: fd=os.open(name,file_flags,dir_fd=parent_fd)",
        "    except OSError: fail()",
        "    try:",
        "        before=os.fstat(fd)",
        "        if not stat.S_ISREG(before.st_mode) or identity(before) != identity(expected): fail()",
        "        if identity(os.stat(name,dir_fd=parent_fd,follow_symlinks=False)) != identity(before): fail()",
        "        digest=hashlib.sha512() if include_content else None; head=b''",
        "        if include_content:",
        "            while True:",
        "                chunk=os.read(fd,1024*1024)",
        "                if not chunk: break",
        "                if len(head) < 256: head += chunk[:256-len(head)]",
        "                digest.update(chunk)",
        "        after=os.fstat(fd); current=os.stat(name,dir_fd=parent_fd,follow_symlinks=False)",
        "        if identity(after) != identity(before) or identity(current) != identity(before): fail()",
        "        fields=[path.hex(),str(before.st_dev),str(before.st_ino),str(before.st_mode),str(before.st_size),str(before.st_mtime_ns),str(before.st_ctime_ns),repr(before.st_mtime)]",
        "        if include_content: fields += [release(head),digest.hexdigest()]",
        "        print('\\t'.join(fields))",
        "    finally: os.close(fd)",
        "def walk(parent_fd,parent_path):",
        "    parent_before=os.fstat(parent_fd)",
        "    try: names=sorted(os.listdir(parent_fd),key=os.fsencode)",
        "    except OSError: fail()",
        "    for text in names:",
        "        name=os.fsencode(text); is_dta=name.lower().endswith(b'.dta')",
        "        try: before=os.stat(name,dir_fd=parent_fd,follow_symlinks=False)",
        "        except OSError: fail()",
        "        if stat.S_ISLNK(before.st_mode):",
        "            try: linked_directory=stat.S_ISDIR(os.stat(name,dir_fd=parent_fd,follow_symlinks=True).st_mode)",
        "            except OSError: linked_directory=False",
        "            if linked_directory or is_dta: fail()",
        "            continue",
        "        path=os.path.join(parent_path,name)",
        "        if stat.S_ISDIR(before.st_mode):",
        "            try: child_fd=os.open(name,dir_flags,dir_fd=parent_fd)",
        "            except OSError: fail()",
        "            try:",
        "                if identity(os.fstat(child_fd)) != identity(before): fail()",
        "                walk(child_fd,path)",
        "                current=os.stat(name,dir_fd=parent_fd,follow_symlinks=False)",
        "                if identity(os.fstat(child_fd)) != identity(before) or identity(current) != identity(before): fail()",
        "            finally: os.close(child_fd)",
        "        elif is_dta:",
        "            if not stat.S_ISREG(before.st_mode): fail()",
        "            attest(parent_fd,name,path,before)",
        "    if identity(os.fstat(parent_fd)) != identity(parent_before): fail()",
        "parts=[part for part in root.split(b'/') if part]",
        "root_chain=[]; descriptors=[]",
        "filesystem_root_expected=os.lstat(b'/')",
        "try: filesystem_root_fd=os.open(b'/',dir_flags)",
        "except OSError: fail()",
        "descriptors.append(filesystem_root_fd)",
        "if identity(os.fstat(filesystem_root_fd)) != identity(filesystem_root_expected): fail()",
        "parent_fd=filesystem_root_fd",
        "try:",
        "    for part in parts:",
        "        expected=os.stat(part,dir_fd=parent_fd,follow_symlinks=False)",
        "        if not stat.S_ISDIR(expected.st_mode): fail()",
        "        child_fd=os.open(part,dir_flags,dir_fd=parent_fd); descriptors.append(child_fd)",
        "        if identity(os.fstat(child_fd)) != identity(expected): fail()",
        "        root_chain.append((parent_fd,part,child_fd,expected)); parent_fd=child_fd",
        "    root_fd=parent_fd; root_expected=os.fstat(root_fd)",
        "    walk(root_fd,root)",
        "    if identity(os.fstat(root_fd)) != identity(root_expected): fail()",
        "    for ancestor_fd,part,child_fd,ancestor_expected in reversed(root_chain):",
        "        current=os.stat(part,dir_fd=ancestor_fd,follow_symlinks=False)",
        "        if identity(os.fstat(child_fd)) != identity(ancestor_expected) or identity(current) != identity(ancestor_expected): fail()",
        "    if identity(os.fstat(filesystem_root_fd)) != identity(filesystem_root_expected) or identity(os.lstat(b'/')) != identity(filesystem_root_expected): fail()",
        "finally:",
        "    for descriptor in reversed(descriptors):",
        "        try: os.close(descriptor)",
        "        except OSError: pass",
        sep = "\n"
    )
    output <- suppressWarnings(system2(
        python, c("-c", shQuote(code), shQuote(root),
                  if (include_content) "1" else "0"),
        stdout = TRUE, stderr = FALSE
    ))
    status <- attr(output, "status", exact = TRUE)
    if ((!is.null(status) && status != 0L) || !length(output)) {
        stop("fertility output inventory could not attest descriptor-bound regular files")
    }
    fields <- strsplit(output, "\t", fixed = TRUE)
    expected_fields <- if (include_content) 10L else 8L
    if (any(lengths(fields) != expected_fields)) {
        stop("fertility output descriptor attestation is malformed")
    }
    result <- data.frame(
        path = vapply(fields, function(value) fertility_decode_hex_path(value[[1L]]),
                      character(1)),
        device = vapply(fields, `[[`, character(1), 2L),
        inode = vapply(fields, `[[`, character(1), 3L),
        mode = vapply(fields, `[[`, character(1), 4L),
        size = vapply(fields, `[[`, character(1), 5L),
        modified_ns = vapply(fields, `[[`, character(1), 6L),
        changed_ns = vapply(fields, `[[`, character(1), 7L),
        modified_seconds = vapply(fields, `[[`, character(1), 8L),
        stringsAsFactors = FALSE, check.names = FALSE
    )
    if (include_content) {
        result$release <- suppressWarnings(as.integer(vapply(
            fields, `[[`, character(1), 9L
        )))
        result$sha512 <- vapply(fields, `[[`, character(1), 10L)
        if (anyNA(result$release) || any(!grepl("^[0-9a-f]{128}$", result$sha512))) {
            stop("fertility output descriptor content attestation is malformed")
        }
    }
    result <- result[order(result$path, method = "radix"), , drop = FALSE]
    rownames(result) <- NULL
    if (anyDuplicated(result$path) || any(!startsWith(result$path, paste0(root, "/"))) ||
        any(!grepl("^[0-9]+$", result$device)) ||
        any(!grepl("^[0-9]+$", result$inode)) ||
        any(!grepl("^[0-9]+$", result$mode)) ||
        any(!grepl("^(0|[1-9][0-9]*)$", result$size)) ||
        any(!grepl("^[0-9]+$", result$modified_ns)) ||
        any(!grepl("^[0-9]+$", result$changed_ns)) ||
        any(!grepl("^[0-9]+([.][0-9]+)?$", result$modified_seconds))) {
        stop("fertility output descriptor attestation is invalid")
    }
    result
}

fertility_output_regular_entries <- function(root) {
    unname(fertility_output_descriptor_manifest(root, FALSE)$path)
}

fertility_nofollow_file_capture <- function(path, include_release = FALSE) {
    if (!is.logical(include_release) || length(include_release) != 1L ||
        is.na(include_release)) stop("invalid descriptor file capture mode")
    path <- fertility_assert_existing_file(path, dirname(path), "descriptor input")
    fertility_output_inventory_test_hook(
        "before-descriptor-file-read", list(path = path)
    )
    python <- Sys.which("python3")
    if (!nzchar(python)) stop("python3 is required for descriptor file capture")
    code <- paste(
        "import hashlib, os, stat, sys",
        "path=os.fsencode(sys.argv[1]); include_release=sys.argv[2] == '1'",
        "base_flags=os.O_RDONLY | getattr(os,'O_CLOEXEC',0) | getattr(os,'O_NOFOLLOW',0)",
        "file_flags=base_flags; dir_flags=base_flags | getattr(os,'O_DIRECTORY',0)",
        "def identity(value):",
        "    return (value.st_dev,value.st_ino,value.st_mode,value.st_size,value.st_mtime_ns,value.st_ctime_ns)",
        "parts=[part for part in path.split(b'/') if part]",
        "if not parts: raise RuntimeError('invalid input path')",
        "directory_parts=parts[:-1]; name=parts[-1]; chain=[]; descriptors=[]",
        "root_expected=os.lstat(b'/'); root_fd=os.open(b'/',dir_flags); descriptors.append(root_fd)",
        "if identity(os.fstat(root_fd)) != identity(root_expected): raise RuntimeError('root changed')",
        "parent_fd=root_fd",
        "try:",
        "    for part in directory_parts:",
        "        expected=os.stat(part,dir_fd=parent_fd,follow_symlinks=False)",
        "        if not stat.S_ISDIR(expected.st_mode): raise RuntimeError('parent is not directory')",
        "        child_fd=os.open(part,dir_flags,dir_fd=parent_fd); descriptors.append(child_fd)",
        "        if identity(os.fstat(child_fd)) != identity(expected): raise RuntimeError('parent changed')",
        "        chain.append((parent_fd,part,child_fd,expected)); parent_fd=child_fd",
        "    expected=os.stat(name,dir_fd=parent_fd,follow_symlinks=False)",
        "    fd=os.open(name,file_flags,dir_fd=parent_fd); descriptors.append(fd)",
        "    before=os.fstat(fd)",
        "    if not stat.S_ISREG(before.st_mode) or identity(before) != identity(expected): raise RuntimeError('not regular')",
        "    digest=hashlib.sha512(); head=b''",
        "    while True:",
        "        chunk=os.read(fd,1024*1024)",
        "        if not chunk: break",
        "        if len(head) < 256: head += chunk[:256-len(head)]",
        "        digest.update(chunk)",
        "    after=os.fstat(fd); current=os.stat(name,dir_fd=parent_fd,follow_symlinks=False)",
        "    if identity(after) != identity(before) or identity(current) != identity(before): raise RuntimeError('identity changed')",
        "    for ancestor_fd,part,child_fd,ancestor_expected in reversed(chain):",
        "        current=os.stat(part,dir_fd=ancestor_fd,follow_symlinks=False)",
        "        if identity(os.fstat(child_fd)) != identity(ancestor_expected) or identity(current) != identity(ancestor_expected): raise RuntimeError('parent changed')",
        "    if identity(os.fstat(root_fd)) != identity(root_expected) or identity(os.lstat(b'/')) != identity(root_expected): raise RuntimeError('root changed')",
        "    fields=[str(before.st_dev),str(before.st_ino),str(before.st_mode),str(before.st_size),str(before.st_mtime_ns),str(before.st_ctime_ns),repr(before.st_mtime),digest.hexdigest()]",
        "    if include_release:",
        "        if not head: raise RuntimeError('empty DTA input')",
        "        if head.startswith(b'<stata_dta>'):",
        "            marker=b'<release>'; start=head.find(marker)",
        "            if start < 0 or head.find(marker,start+1) >= 0: raise RuntimeError('release missing or ambiguous')",
        "            value=head[start+len(marker):start+len(marker)+3]",
        "            if len(value) != 3 or not value.isdigit(): raise RuntimeError('release invalid')",
        "            fields.append(value.decode('ascii'))",
        "        else: fields.append(str(head[0]))",
        "    print('\\t'.join(fields))",
        "finally:",
        "    for descriptor in reversed(descriptors):",
        "        try: os.close(descriptor)",
        "        except OSError: pass",
        sep = "\n"
    )
    output <- suppressWarnings(system2(
        python, c("-c", shQuote(code), shQuote(path),
                  if (include_release) "1" else "0"),
        stdout = TRUE, stderr = FALSE
    ))
    status <- attr(output, "status", exact = TRUE)
    fields <- if (length(output) == 1L) strsplit(output, "\t", fixed = TRUE)[[1L]] else
        character()
    expected_fields <- if (include_release) 9L else 8L
    if ((!is.null(status) && status != 0L) ||
        length(fields) != expected_fields ||
        any(!grepl("^[0-9]+$", fields[seq_len(6L)])) ||
        !grepl("^[0-9]+([.][0-9]+)?$", fields[[7L]]) ||
        !grepl("^[0-9a-f]{128}$", fields[[8L]])) {
        stop("descriptor-bound file capture failed")
    }
    list(
        device = fields[[1L]], inode = fields[[2L]], mode = fields[[3L]],
        size = fields[[4L]], modified_ns = fields[[5L]],
        changed_ns = fields[[6L]], modified_seconds = fields[[7L]],
        sha512 = fields[[8L]],
        release = if (include_release) suppressWarnings(as.integer(fields[[9L]])) else
            NULL
    )
}

fertility_open_bound_input_connection <- function(path, input) {
    if (!requireNamespace("processx", quietly = TRUE)) stop("processx is required")
    required <- c("device", "inode", "mode", "size", "modified_ns", "changed_ns")
    if (!is.list(input) || any(!required %in% names(input)) ||
        any(vapply(input[required], function(value) {
            !is.character(value) || length(value) != 1L || is.na(value) ||
                !grepl("^[0-9]+$", value)
        }, logical(1)))) stop("bound input identity is invalid")
    path <- fertility_assert_existing_file(path, dirname(path), "bound worker input")
    connection <- processx::conn_create_file(path, read = TRUE, write = FALSE)
    close_connection <- TRUE
    on.exit(if (close_connection) {
        try(processx::processx_conn_close(connection), silent = TRUE)
    }, add = TRUE)
    python <- Sys.which("python3")
    if (!nzchar(python)) stop("python3 is required for bound worker input")
    code <- paste(
        "import os,sys",
        "value=os.fstat(3)",
        "print('\\t'.join(str(part) for part in (value.st_dev,value.st_ino,value.st_mode,value.st_size,value.st_mtime_ns,value.st_ctime_ns)))",
        sep = "\n"
    )
    observed <- tryCatch(processx::run(
        python, c("-c", code), stdout = "|", stderr = "|",
        connections = list(connection), poll_connection = FALSE,
        error_on_status = FALSE
    ), error = function(error) NULL)
    fields <- if (is.list(observed) && identical(observed$status, 0L)) {
        strsplit(trimws(observed$stdout), "\t", fixed = TRUE)[[1L]]
    } else character()
    if (length(fields) != length(required) ||
        !identical(unname(fields), unname(unlist(input[required], use.names = FALSE)))) {
        stop("bound worker input does not match captured identity")
    }
    close_connection <- FALSE
    connection
}

fertility_close_bound_input_connection <- function(connection) {
    if (!is.null(connection)) {
        try(processx::processx_conn_close(connection), silent = TRUE)
    }
    invisible(NULL)
}

fertility_bound_input_path <- function() "/dev/fd/3"

fertility_materialize_bound_input <- function(path, input, raw_root,
                                              destination = NULL,
                                              prefer_clone = TRUE) {
    if (!identical(path, fertility_bound_input_path())) {
        stop("bound worker input path is invalid")
    }
    invisible(fertility_assert_tempdir(raw_root))
    required <- c("device", "inode", "mode", "size", "modified_ns", "changed_ns")
    if (!is.list(input) || any(!required %in% names(input)) ||
        any(vapply(input[required], function(value) {
            !is.character(value) || length(value) != 1L || is.na(value) ||
                !grepl("^[0-9]+$", value)
        }, logical(1)))) stop("bound worker input identity is invalid")
    temporary <- normalizePath(Sys.getenv("TMPDIR"), winslash = "/", mustWork = TRUE)
    if (is.null(destination)) {
        destination <- tempfile(
            "bound-worker-input-", tmpdir = temporary, fileext = ".dta"
        )
    } else {
        destination <- path.expand(destination)
        if (!is.character(destination) || length(destination) != 1L ||
            is.na(destination) || !identical(dirname(destination), temporary) ||
            file.exists(destination) || dir.exists(destination) ||
            fertility_path_is_symlink(destination)) {
            stop("bound worker snapshot destination is invalid")
        }
    }
    if (!is.logical(prefer_clone) || length(prefer_clone) != 1L ||
        is.na(prefer_clone)) stop("bound worker clone preference is invalid")
    on.exit(if (file.exists(destination) || fertility_path_is_symlink(destination)) {
        unlink(destination)
    }, add = TRUE)
    python <- Sys.which("python3")
    if (!nzchar(python)) stop("python3 is required for bound worker input")
    code <- paste(
        "import ctypes,os,stat,sys",
        "destination=os.fsencode(sys.argv[1]); expected=tuple(int(value) for value in sys.argv[2:8]); prefer_clone=sys.argv[8]=='1'",
        "def identity(value): return (value.st_dev,value.st_ino,value.st_mode,value.st_size,value.st_mtime_ns,value.st_ctime_ns)",
        "before=os.fstat(3)",
        "if identity(before) != expected or not stat.S_ISREG(before.st_mode): sys.exit(17)",
        "cloned=False",
        "if prefer_clone:",
        "    libc=ctypes.CDLL(None,use_errno=True); clone=getattr(libc,'fclonefileat',None)",
        "    if clone is not None:",
        "        clone.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint]",
        "        cloned=clone(3,-2,destination,0)==0",
        "if not cloned:",
        "    flags=os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_CLOEXEC',0)",
        "    output=os.open(destination,flags,0o600)",
        "    try:",
        "        offset=0",
        "        while offset < before.st_size:",
        "            data=os.pread(3,min(1048576,before.st_size-offset),offset)",
        "            if not data: sys.exit(18)",
        "            view=memoryview(data)",
        "            while view:",
        "                written=os.write(output,view)",
        "                if written <= 0: sys.exit(19)",
        "                view=view[written:]",
        "            offset+=len(data)",
        "        os.fsync(output)",
        "    finally:",
        "        os.close(output)",
        "after=os.fstat(3); copied=os.lstat(destination)",
        "if identity(after) != identity(before) or not stat.S_ISREG(copied.st_mode) or copied.st_size != before.st_size: sys.exit(20)",
        sep = "\n"
    )
    status <- suppressWarnings(system2(
        python, c("-c", shQuote(code), shQuote(destination),
                  unname(unlist(input[required], use.names = FALSE)),
                  if (prefer_clone) "1" else "0"),
        stdout = FALSE, stderr = FALSE
    ))
    if (!identical(status, 0L) || !file.exists(destination) ||
        dir.exists(destination) || fertility_path_is_symlink(destination) ||
        !isTRUE(file_test("-f", destination))) {
        stop("could not materialize descriptor-bound worker input")
    }
    destination <- normalizePath(destination, winslash = "/", mustWork = TRUE)
    on.exit(NULL, add = FALSE)
    destination
}

fertility_reset_bound_input <- function(path) {
    if (!is.character(path) || length(path) != 1L || is.na(path) ||
        !grepl("^/dev/fd/[0-9]+$", path)) return(invisible(FALSE))
    connection <- file(path, open = "rb")
    on.exit(close(connection), add = TRUE)
    seek(connection, where = 0, origin = "start")
    invisible(TRUE)
}

fertility_output_entries <- function(root) {
    root <- fertility_assert_output_root(root)
    paths <- character()
    walk <- function(parent) {
        parent <- fertility_assert_canonical_components(
            parent, "fertility output inventory directory"
        )
        if (file.access(parent, 4L) != 0L || file.access(parent, 1L) != 0L) {
            stop("fertility output inventory directory is not traversable")
        }
        entries <- tryCatch(sort(list.files(
            parent, all.files = TRUE, no.. = TRUE, full.names = TRUE,
            recursive = FALSE, include.dirs = TRUE
        ), method = "radix"), warning = function(condition) {
            stop("could not enumerate fertility output inventory directory")
        }, error = function(condition) {
            stop("could not enumerate fertility output inventory directory")
        })
        for (entry in entries) {
            is_dta <- grepl("[.]dta$", basename(entry), ignore.case = TRUE)
            if (!identical(dirname(entry), parent)) {
                stop("fertility output entry is not a direct descendant")
            }
            fertility_output_inventory_test_hook(
                "before-entry-info", list(parent = parent, entry = entry)
            )
            linked <- fertility_path_is_symlink(entry)
            info <- file.info(entry)
            if (nrow(info) != 1L || is.na(info$isdir[[1L]])) {
                stop("fertility output entry metadata is unavailable")
            }
            if (linked) {
                if (isTRUE(info$isdir[[1L]])) {
                    stop("fertility output inventory refuses symlinked directories")
                }
                if (is_dta) {
                    stop("fertility output inventory refuses DTA symlinks")
                }
                next
            }
            fertility_output_inventory_test_hook(
                "after-entry-info", list(parent = parent, entry = entry)
            )
            entry <- fertility_assert_direct_child(
                entry, parent, "fertility output entry"
            )
            if (fertility_path_is_symlink(entry)) {
                stop("fertility output entry changed to a symlink during inventory")
            }
            confirmed <- file.info(entry)
            if (nrow(confirmed) != 1L || is.na(confirmed$isdir[[1L]]) ||
                !identical(isTRUE(confirmed$isdir[[1L]]),
                           isTRUE(info$isdir[[1L]]))) {
                stop("fertility output entry changed during inventory")
            }
            if (isTRUE(confirmed$isdir[[1L]])) {
                walk(entry)
            } else if (is_dta) {
                if (!startsWith(entry, paste0(root, "/"))) {
                    stop("fertility output DTA escaped its root")
                }
                paths <<- c(paths, entry)
            }
        }
    }
    walk(root)
    paths <- sort(paths, method = "radix")
    attested <- fertility_output_regular_entries(root)
    if (!identical(paths, attested)) {
        stop("fertility output inventory changed during regular-file attestation")
    }
    paths
}

fertility_output_stat_manifest <- function(root) {
    paths <- fertility_output_entries(root)
    attested <- fertility_output_descriptor_manifest(root, FALSE)
    if (!identical(paths, attested$path)) {
        stop("fertility output inventory changed during descriptor stat capture")
    }
    relative <- substring(paths, nchar(root) + 2L)
    if (!length(paths) || anyDuplicated(relative) || any(!nzchar(relative))) {
        stop("fertility output inventory is invalid")
    }
    result <- data.frame(
        relative_path = relative,
        size = attested$size,
        modified = vapply(attested$modified_seconds, fertility_descriptor_timestamp,
                          character(1)),
        stringsAsFactors = FALSE, check.names = FALSE
    )
    rownames(result) <- NULL
    result
}

fertility_output_metadata_equal <- function(left, right) {
    fields <- c("relative_path", "size", "modified")
    if (!is.data.frame(left) || !is.data.frame(right) ||
        !all(fields %in% names(left)) || !all(fields %in% names(right)) ||
        nrow(left) != nrow(right) ||
        !identical(left$relative_path, right$relative_path) ||
        !identical(left$size, right$size)) return(FALSE)
    timestamp <- paste0(
        "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:",
        "[0-9]{2}[.][0-9]{6}Z$"
    )
    if (any(!grepl(timestamp, left$modified)) ||
        any(!grepl(timestamp, right$modified))) return(FALSE)
    left_time <- suppressWarnings(as.numeric(as.POSIXct(
        sub("Z$", "", left$modified), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"
    )))
    right_time <- suppressWarnings(as.numeric(as.POSIXct(
        sub("Z$", "", right$modified), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"
    )))
    !anyNA(left_time) && !anyNA(right_time) &&
        all(abs(left_time - right_time) <= 2e-6)
}

fertility_validate_output_baseline <- function(manifest) {
    sizes <- suppressWarnings(as.double(manifest$size))
    if (nrow(manifest) != fertility_output_expected_files || anyNA(sizes) ||
        sum(sizes) != fertility_output_expected_bytes ||
        max(sizes) != fertility_output_expected_largest) {
        stop(sprintf(
            paste0("fertility output baseline drift: expected %d files, %.0f bytes, ",
                   "largest %.0f bytes; observed %d files, %.0f bytes, largest %.0f bytes"),
            fertility_output_expected_files, fertility_output_expected_bytes,
            fertility_output_expected_largest, nrow(manifest), sum(sizes), max(sizes)
        ))
    }
    invisible(TRUE)
}

fertility_output_inventory_path <- function(raw_root) {
    directory <- fertility_assert_output_parent(
        raw_root, "output-inventory", "wave3", create = TRUE
    )
    file.path(directory, "inventory.rds")
}

fertility_build_output_inventory <- function(root, raw_root) {
    root <- fertility_assert_output_root(root)
    manifest <- fertility_output_stat_manifest(root)
    fertility_validate_output_baseline(manifest)
    path <- fertility_output_inventory_path(raw_root)
    frozen <- if (file.exists(path)) readRDS(fertility_assert_existing_file(
        path, dirname(path), "frozen output inventory"
    )) else NULL
    if (is.list(frozen) && identical(frozen$schema_version, 1L)) {
        superseded <- file.path(dirname(path), "inventory-schema1.rds")
        if (file.exists(superseded) || dir.exists(superseded) ||
            fertility_path_is_symlink(superseded)) {
            stop("superseded output inventory destination already exists")
        }
        fertility_atomic_rename_noreplace(
            path, superseded, "superseded output inventory"
        )
        frozen <- NULL
    }
    if (is.null(frozen)) {
        content <- fertility_output_descriptor_manifest(root, TRUE)
        content_manifest <- data.frame(
            relative_path = substring(content$path, nchar(root) + 2L),
            size = content$size,
            modified = vapply(content$modified_seconds, fertility_descriptor_timestamp,
                              character(1)),
            stringsAsFactors = FALSE, check.names = FALSE
        )
        identity_fields <- c(
            "path", "device", "inode", "mode", "size", "modified_ns",
            "changed_ns"
        )
        after <- fertility_output_descriptor_manifest(root, FALSE)
        fertility_validate_output_baseline(content_manifest)
        if (!fertility_output_metadata_equal(manifest, content_manifest) ||
            !identical(content[identity_fields], after[identity_fields])) {
            stop("fertility output changed during descriptor-bound inventory")
        }
        frozen <- list(
            schema_version = fertility_output_inventory_schema_version,
            root_identity = fertility_filesystem_identity(root, "fertility output root"),
            manifest = transform(
                content_manifest, release = content$release, sha512 = content$sha512
            ),
            created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
        )
        fertility_atomic_save_rds(frozen, path)
    }
    if (is.list(frozen) && is.data.frame(frozen$manifest)) {
        rownames(frozen$manifest) <- NULL
    }
    expected_names <- c("relative_path", "size", "modified", "release", "sha512")
    if (!is.list(frozen) || !identical(
            frozen$schema_version, fertility_output_inventory_schema_version
        ) ||
        !identical(names(frozen$manifest), expected_names) ||
        !identical(frozen$root_identity,
                   fertility_filesystem_identity(root, "fertility output root")) ||
        !fertility_output_metadata_equal(
            frozen$manifest[c("relative_path", "size", "modified")], manifest
        ) ||
        any(!grepl("^[0-9a-f]{128}$", frozen$manifest$sha512)) ||
        any(!(frozen$manifest$release %in% c(111L, fertility_supported_releases)))) {
        stop("frozen fertility output inventory changed or is invalid")
    }
    paths <- file.path(root, frozen$manifest$relative_path)
    level <- ifelse(!grepl("/", frozen$manifest$relative_path, fixed = TRUE),
                    "aggregate", "survey")
    inventory <- data.frame(
        id = sprintf("F%04d", seq_len(nrow(frozen$manifest))),
        program = "output", level = level,
        release = as.integer(frozen$manifest$release), path = paths,
        expected_sha512 = frozen$manifest$sha512,
        stringsAsFactors = FALSE, check.names = FALSE
    )
    attr(inventory, "authority_path") <- path
    inventory
}

fertility_required_paths <- function(options, raw_root = NULL) {
    options <- fertility_validate_source_arguments(options)
    if (fertility_output_requested(options)) {
        if (is.null(raw_root)) stop("raw root is required for output inventory authority")
        return(list(output = fertility_assert_output_root(options$output_root),
                    datasigs = fertility_output_inventory_path(raw_root)))
    }
    list(cache = options$cache_root, datasigs = options$manifest)
}

fertility_build_selected_inventory <- function(options, raw_root) {
    paths <- fertility_required_paths(options, raw_root)
    if (fertility_output_requested(options)) {
        fertility_build_output_inventory(paths$output, raw_root)
    } else fertility_build_inventory(paths)
}

fertility_atomic_save_rds <- function(value, path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
    Sys.chmod(dirname(path), mode = "0700")
    temporary <- tempfile(paste0(basename(path), "."), tmpdir = dirname(path))
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(value, temporary, version = 3L)
    Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) stop("could not atomically replace checkpoint")
    invisible(path)
}

fertility_atomic_write_table <- function(value, path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
    Sys.chmod(dirname(path), mode = "0700")
    temporary <- tempfile(paste0(basename(path), "."), tmpdir = dirname(path))
    on.exit(unlink(temporary), add = TRUE)
    write.table(value, temporary, sep = "\t", row.names = FALSE, quote = FALSE,
                na = "")
    Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) stop("could not atomically replace report")
    invisible(path)
}

fertility_file_sha512 <- function(path) {
    if (!requireNamespace("openssl", quietly = TRUE)) stop("openssl is required")
    fertility_reset_bound_input(path)
    unname(unclass(tolower(as.character(openssl::sha512(file(path))))))
}

fertility_stable_id <- function(fields) {
    values <- vapply(names(fields), function(name) {
        value <- fields[[name]]
        if (length(value) != 1L) stop("stable ID fields must be scalar")
        paste0(name, "=", as.character(value[[1L]]))
    }, character(1))
    unname(unclass(tolower(as.character(openssl::sha256(
        charToRaw(paste(values, collapse = "\n"))
    )))))
}

fertility_release <- function(path) {
    fertility_reset_bound_input(path)
    connection <- file(path, open = "rb")
    on.exit(close(connection), add = TRUE)
    bytes <- readBin(connection, "raw", n = 256L)
    if (!length(bytes)) stop("empty DTA input")
    modern_prefix <- charToRaw("<stata_dta>")
    is_modern <- length(bytes) >= length(modern_prefix) &&
        identical(bytes[seq_along(modern_prefix)], modern_prefix)
    if (is_modern) {
        needle <- charToRaw("<release>")
        starts <- seq_len(length(bytes) - length(needle) + 1L)
        found <- starts[vapply(starts, function(start) {
            identical(bytes[start:(start + length(needle) - 1L)], needle)
        }, logical(1))]
        if (length(found) != 1L) stop("modern DTA release marker is missing")
        release_start <- found[[1L]] + length(needle)
        release <- rawToChar(bytes[release_start:(release_start + 2L)])
        if (!grepl("^[0-9]{3}$", release)) stop("modern DTA release is invalid")
        return(as.integer(release))
    }
    as.integer(bytes[[1L]])
}

fertility_raw_find <- function(bytes, needle) {
    needle <- charToRaw(needle)
    if (length(bytes) < length(needle)) return(integer())
    starts <- which(bytes == needle[[1L]])
    starts <- starts[starts + length(needle) - 1L <= length(bytes)]
    starts[vapply(starts, function(start) {
        identical(bytes[start:(start + length(needle) - 1L)], needle)
    }, logical(1))]
}

fertility_raw_uint <- function(bytes, start, size, byteorder) {
    selected <- as.double(bytes[start:(start + size - 1L)])
    if (identical(byteorder, "MSF")) selected <- rev(selected)
    value <- sum(selected * 256^(seq_along(selected) - 1L))
    if (!is.finite(value) || value > 2^53) stop("DTA count exceeds exact R range")
    value
}

fertility_structural_metadata <- function(path) {
    fertility_reset_bound_input(path)
    connection <- file(path, open = "rb")
    on.exit(close(connection), add = TRUE)
    bytes <- readBin(connection, "raw", n = 4L * 1024L * 1024L)
    release <- fertility_release(path)
    if (release %in% c(113L, 114L, 115L)) {
        if (length(bytes) < 109L) stop("legacy DTA header is truncated")
        byteorder <- if (as.integer(bytes[[2L]]) == 1L) "MSF" else "LSF"
        columns <- fertility_raw_uint(bytes, 5L, 2L, byteorder)
        rows <- fertility_raw_uint(bytes, 7L, 4L, byteorder)
        start <- 110L
        if (start + columns - 1L > length(bytes)) stop("legacy DTA types are truncated")
        codes <- as.integer(bytes[start:(start + columns - 1L)])
        column_bytes <- ifelse(codes <= 244L, pmax(codes, 1L), 8L)
        return(list(rows = rows, columns = as.integer(columns),
                    column_bytes = as.double(column_bytes), strl = rep(FALSE, columns)))
    }
    if (!(release %in% c(117L, 118L))) stop("unsupported structural DTA release")
    first_after <- function(needle, after = 0L) {
        found <- fertility_raw_find(bytes, needle)
        found <- found[found > after]
        if (!length(found)) stop("modern DTA structural tag is missing")
        found[[1L]]
    }
    byte_start <- first_after("<byteorder>")
    byte_end <- first_after("</byteorder>", byte_start)
    order_start <- byte_start + length(charToRaw("<byteorder>"))
    byteorder <- rawToChar(bytes[order_start:(byte_end - 1L)])
    read_tag_uint <- function(tag, size) {
        opening <- first_after(paste0("<", tag, ">"))
        closing <- first_after(paste0("</", tag, ">"), opening)
        start <- opening + length(charToRaw(paste0("<", tag, ">")))
        if (closing - start != size) stop("modern DTA structural field has wrong size")
        fertility_raw_uint(bytes, start, size, byteorder)
    }
    columns <- read_tag_uint("K", 2L)
    rows <- read_tag_uint("N", if (release == 118L) 8L else 4L)
    map_end <- first_after("</map>")
    opening <- first_after("<variable_types>", map_end)
    closing <- first_after("</variable_types>", opening)
    start <- opening + length(charToRaw("<variable_types>"))
    if (closing - start != columns * 2L) stop("modern DTA types have wrong size")
    codes <- vapply(seq_len(columns), function(i) {
        fertility_raw_uint(bytes, start + (i - 1L) * 2L, 2L, byteorder)
    }, numeric(1))
    strl <- codes == 32768L
    column_bytes <- ifelse(strl, Inf, ifelse(codes >= 1L & codes <= 2045L,
                                             codes, 8L))
    list(rows = rows, columns = as.integer(columns),
         column_bytes = as.double(column_bytes), strl = strl)
}

fertility_build_inventory <- function(paths, assert_counts = TRUE) {
    if (!is.list(paths) || !identical(names(paths), c("cache", "datasigs"))) {
        stop("explicit cache and manifest paths are required")
    }
    cache_root <- fertility_assert_canonical_components(
        paths$cache, "fertility cache root"
    )
    if (!dir.exists(cache_root) || fertility_path_is_symlink(cache_root)) {
        stop("fertility cache root must be a canonical non-symlink directory")
    }
    datasigs_path <- fertility_assert_canonical_components(
        paths$datasigs, "fertility manifest"
    )
    if (!file.exists(datasigs_path) || dir.exists(datasigs_path) ||
        fertility_path_is_symlink(datasigs_path) ||
        !isTRUE(file_test("-f", datasigs_path))) {
        stop("fertility manifest must be a canonical non-symlink regular file")
    }
    rows <- read.csv(datasigs_path, colClasses = "character", check.names = FALSE,
                     stringsAsFactors = FALSE)
    required <- c("program", "survey", "level", "sha512")
    if (!all(required %in% names(rows))) stop("datasigs.csv is missing required columns")

    path1 <- c(
        dhs = "DHS/Original_Data", mics = "MICS/Data/Original Data",
        wfs = "WFS/Data", nsfg = "NSFG/Data/Original Data",
        enadid = "ENADID/Data/Original Data"
    )
    path2 <- c(dhs = "DHS/Original_Data_Provenance_Unknown")
    inventory <- vector("list", nrow(rows))
    for (i in seq_len(nrow(rows))) {
        program <- tolower(rows$program[[i]])
        level <- tolower(rows$level[[i]])
        if (!(program %in% fertility_programs) || !(program %in% names(path1))) {
            stop("datasigs.csv contains an unknown program")
        }
        if (!(level %in% fertility_cache_levels)) {
            stop("datasigs.csv contains an unknown cache level")
        }
        folder <- if (identical(program, "wfs")) "" else
            gsub("_", ",", rows$survey[[i]], fixed = TRUE)
        filename <- if (identical(program, "wfs")) {
            paste0(rows$survey[[i]], ".dta")
        } else if (identical(level, "women")) "wm.dta" else "bh.dta"
        candidates <- file.path(paths$cache, unname(path1[[program]]), folder, filename)
        if (program %in% names(path2)) {
            candidates <- c(candidates, file.path(
                paths$cache, unname(path2[[program]]), folder, filename
            ))
        }
        present <- candidates[file.exists(candidates)]
        if (!length(present)) stop(sprintf("inventory row F%04d is missing", i))
        # Match check_raw_data.r exactly: the primary path wins and the DHS
        # provenance-unknown path is consulted only when the primary is absent.
        resolved <- normalizePath(present[[1L]], winslash = "/", mustWork = TRUE)
        if (!startsWith(resolved, paste0(cache_root, "/"))) {
            stop(sprintf("inventory row F%04d resolves outside the cache root", i))
        }
        inventory[[i]] <- data.frame(
            id = sprintf("F%04d", i), program = program, level = level,
            release = fertility_release(resolved), path = resolved,
            expected_sha512 = tolower(rows$sha512[[i]]),
            stringsAsFactors = FALSE
        )
    }
    inventory <- do.call(rbind, inventory)
    if (anyDuplicated(inventory$id) || anyDuplicated(inventory$path)) {
        stop("inventory IDs and resolved input paths must be unique")
    }
    if (assert_counts) {
        if (nrow(inventory) != fertility_expected_rows) {
            stop("expected exactly 1,004 datasigs.csv rows")
        }
        actual <- table(factor(inventory$release,
                               levels = as.integer(names(fertility_expected_releases))))
        names(actual) <- names(fertility_expected_releases)
        if (!identical(as.integer(actual), as.integer(fertility_expected_releases))) {
            stop("DTA release counts do not match the expected corpus inventory")
        }
        if (any(!(inventory$release %in% as.integer(names(fertility_expected_releases))))) {
            stop("corpus contains an unexpected DTA release")
        }
    }
    inventory
}

fertility_public_inventory <- function(inventory) {
    inventory[c("id", "program", "level", "release")]
}
