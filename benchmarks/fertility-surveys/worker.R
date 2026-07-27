fertility_worker <- function(item, compare_script, package_library,
                             expected_package_path, framework_id,
                             timeout_seconds, parent_sha512) {
    source(compare_script, local = environment())
    started <- proc.time()[["elapsed"]]
    base <- list(
        schema_version = fertility_schema_version,
        framework_id = framework_id,
        id = item$id,
        program = item$program,
        level = item$level,
        release = as.integer(item$release),
        expected_sha512 = item$expected_sha512,
        timeout_seconds = timeout_seconds
    )
    finish <- function(classification, component = NA_integer_, rows = NA_real_,
                       columns = NA_integer_, actual_sha512 = NA_character_) {
        c(base, list(
            classification = classification,
            component = component,
            rows = rows,
            columns = columns,
            actual_sha512 = actual_sha512,
            elapsed_seconds = unname(proc.time()[["elapsed"]] - started)
        ))
    }
    actual_sha512 <- tryCatch(
        fertility_file_sha512(item$path), error = function(error) NA_character_
    )
    if (is.na(actual_sha512)) return(finish("input-hash-error"))
    if (!identical(actual_sha512, parent_sha512)) {
        return(finish("input-changed-before-read", actual_sha512 = actual_sha512))
    }
    if (nzchar(item$expected_sha512) &&
        !identical(actual_sha512, tolower(item$expected_sha512))) {
        return(finish("input-signature-mismatch", actual_sha512 = actual_sha512))
    }
    if (!(item$release %in% fertility_supported_releases)) {
        return(finish("unsupported-release", actual_sha512 = actual_sha512))
    }

    .libPaths(c(package_library, .libPaths()))
    if (!requireNamespace("dtaparser", quietly = TRUE)) {
        return(finish("dtaparser-load-error", actual_sha512 = actual_sha512))
    }
    loaded <- normalizePath(getNamespaceInfo(asNamespace("dtaparser"), "path"),
                            winslash = "/", mustWork = TRUE)
    if (!identical(loaded, expected_package_path)) {
        return(finish("foreign-dtaparser-installation", actual_sha512 = actual_sha512))
    }
    if (!requireNamespace("haven", quietly = TRUE)) {
        return(finish("haven-load-error", actual_sha512 = actual_sha512))
    }

    direct <- tryCatch(dtaparser::read_dta(item$path), error = identity)
    if (inherits(direct, "error")) {
        return(finish("direct-reader-error", actual_sha512 = actual_sha512))
    }
    rust_vectors <- tryCatch(
        dtaparser:::.read_dta_rust_vectors(item$path), error = identity
    )
    if (inherits(rust_vectors, "error")) {
        return(finish("rust-vector-reader-error", actual_sha512 = actual_sha512))
    }
    internal <- fertility_compare_internal(direct, rust_vectors)
    rm(rust_vectors)
    invisible(gc())
    if (!internal$ok) {
        return(finish(internal$classification, internal$component,
                      nrow(direct), ncol(direct), actual_sha512))
    }

    reference <- tryCatch(haven::read_dta(item$path), error = identity)
    if (inherits(reference, "error")) {
        return(finish("haven-reader-error", rows = nrow(direct),
                      columns = ncol(direct), actual_sha512 = actual_sha512))
    }
    comparison <- fertility_compare_haven(direct, reference)
    rows <- nrow(direct)
    columns <- ncol(direct)
    rm(direct, reference)
    invisible(gc())
    final_sha512 <- tryCatch(
        fertility_file_sha512(item$path), error = function(error) NA_character_
    )
    if (is.na(final_sha512) || !identical(final_sha512, actual_sha512)) {
        return(finish("input-changed-during-read", rows = rows, columns = columns,
                      actual_sha512 = final_sha512))
    }
    finish(comparison$classification, comparison$component, rows, columns,
           actual_sha512)
}
