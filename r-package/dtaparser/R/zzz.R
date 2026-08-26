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

.labelled_attach_state <- new.env(parent = emptyenv())
.labelled_attach_state$warned <- FALSE

.warn_labelled_masking <- function(...) {
    if (!"package:dtaparser" %in% search()) return(invisible(NULL))
    shared <- c(
        "var_label", "var_label<-", "val_labels", "val_labels<-",
        "set_variable_labels", "set_value_labels"
    )
    masks_dtaparser <- any(vapply(shared, function(name) {
        locations <- utils::find(name, mode = "function")
        length(locations) > 0L && identical(locations[[1L]], "package:labelled")
    }, logical(1)))
    if (!masks_dtaparser) return(invisible(NULL))
    if (.labelled_attach_state$warned) return(invisible(NULL))
    .labelled_attach_state$warned <- TRUE
    warning(
        paste0(
            "`labelled` was attached after dtaparser and now masks ",
            "dtaparser's same-named label metadata helpers. On dtaparser ",
            "data, labelled's setters can materialize compact columns or ",
            "discard Stata metadata. Use qualified calls such as ",
            "dtaparser::set_value_labels()."
        ),
        call. = FALSE
    )
    invisible(NULL)
}

.onLoad <- function(libname, pkgname) {
    # labelled registers the same generic/class pair. If its optional namespace
    # loads later, reapply dtaparser's tag- and metadata-preserving contract.
    setHook(
        packageEvent("labelled", "onLoad"),
        .register_dtaparser_labelled_recode,
        action = "append"
    )
    setHook(
        packageEvent("labelled", "attach"),
        .warn_labelled_masking,
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

    hook_name <- packageEvent("labelled", "attach")
    hooks <- getHook(hook_name)
    keep <- !vapply(
        hooks,
        identical,
        logical(1),
        y = .warn_labelled_masking
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
