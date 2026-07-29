fertility_schema_version <- 10L
fertility_expected_rows <- 1004L
fertility_expected_releases <- c(`111` = 130L, `113` = 475L, `114` = 23L,
                                  `117` = 150L, `118` = 226L)
fertility_supported_releases <- c(113L, 114L, 117L, 118L)
fertility_programs <- c("dhs", "mics", "wfs", "nsfg", "enadid")
fertility_levels <- c("women", "births")
fertility_opt_in_value <- "I_UNDERSTAND_THIS_READS_PROPRIETARY_DATA"

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

fertility_current_bundle_paths <- function(parent, files, label) {
    parent <- fertility_assert_canonical_components(parent, paste(label, "parent"))
    if (!dir.exists(parent)) stop(label, " parent must be an existing directory")
    pointer <- fertility_assert_existing_file(
        file.path(parent, "CURRENT"), parent, paste(label, "CURRENT pointer")
    )
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
    }
    list(bundle = bundle, paths = paths, run_name = run_name)
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

fertility_required_paths <- function() {
    home <- normalizePath("~", winslash = "/", mustWork = TRUE)
    list(
        cache = "/opt/aww_cache",
        datasigs = file.path(home, "repos", "fertility_surveys", "datasigs.csv")
    )
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
    connection <- file(path, open = "rb")
    on.exit(close(connection), add = TRUE)
    bytes <- readBin(connection, "raw", n = 4L * 1024L * 1024L)
    release <- fertility_release(path)
    if (release %in% c(113L, 114L)) {
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

fertility_build_inventory <- function(paths = fertility_required_paths(),
                                      assert_counts = TRUE,
                                      enforce_required_paths = TRUE) {
    expected_cache <- "/opt/aww_cache"
    expected_datasigs <- file.path(normalizePath("~", winslash = "/", mustWork = TRUE),
                                   "repos", "fertility_surveys", "datasigs.csv")
    if (enforce_required_paths &&
        (!identical(paths$cache, expected_cache) ||
         !identical(paths$datasigs, expected_datasigs))) {
        stop("corpus paths are fixed to /opt/aww_cache and ~/repos/fertility_surveys/datasigs.csv")
    }
    if (!dir.exists(paths$cache)) stop("required /opt/aww_cache directory is missing")
    cache_root <- normalizePath(paths$cache, winslash = "/", mustWork = TRUE)
    if (!file.exists(paths$datasigs)) {
        stop("required ~/repos/fertility_surveys/datasigs.csv file is missing")
    }
    rows <- read.csv(paths$datasigs, colClasses = "character", check.names = FALSE,
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
        if (!(level %in% fertility_levels)) stop("datasigs.csv contains an unknown level")
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
