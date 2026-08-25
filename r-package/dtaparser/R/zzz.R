.register_labelled_recode_method <- function(method) {
    registration_environment <- new.env(parent = asNamespace("dplyr"))
    registerS3method(
        "recode",
        "haven_labelled",
        method,
        envir = registration_environment
    )
    invisible(NULL)
}

.register_dtaparser_labelled_recode <- function(...) {
    if (!isNamespaceLoaded("dtaparser") || !isNamespaceLoaded("dplyr")) {
        return(invisible(NULL))
    }

    .register_labelled_recode_method(get(
        "recode.haven_labelled",
        envir = asNamespace("dtaparser"),
        inherits = FALSE
    ))
}

.onLoad <- function(libname, pkgname) {
    # labelled registers the same generic/class pair. If its optional namespace
    # loads later, reapply dtaparser's tag- and metadata-preserving contract.
    setHook(
        packageEvent("labelled", "onLoad"),
        .register_dtaparser_labelled_recode,
        action = "append"
    )
    if (isNamespaceLoaded("labelled")) {
        .register_dtaparser_labelled_recode()
    }
}

.onUnload <- function(libpath) {
    hook_name <- packageEvent("labelled", "onLoad")
    hooks <- getHook(hook_name)
    keep <- !vapply(
        hooks,
        identical,
        logical(1),
        y = .register_dtaparser_labelled_recode
    )
    setHook(hook_name, hooks[keep], action = "replace")

    # Do not leave the optional package pointing at an unloaded namespace.
    if (isNamespaceLoaded("labelled") && isNamespaceLoaded("dplyr") &&
        exists(
            "recode.haven_labelled",
            envir = asNamespace("labelled"),
            inherits = FALSE
        )) {
        .register_labelled_recode_method(get(
            "recode.haven_labelled",
            envir = asNamespace("labelled"),
            inherits = FALSE
        ))
    }
}
