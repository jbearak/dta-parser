.labelled_attach_state <- new.env(parent = emptyenv())
.labelled_attach_state$warned <- FALSE

.warn_labelled_masking <- function(...) {
    if (!"package:dtatools" %in% search()) return(invisible(NULL))
    shared <- c(
        "var_label", "var_label<-", "val_labels", "val_labels<-", "val_label"
    )
    masks_dtatools <- any(vapply(shared, function(name) {
        locations <- utils::find(name, mode = "function")
        length(locations) > 0L && identical(locations[[1L]], "package:labelled")
    }, logical(1)))
    if (!masks_dtatools) return(invisible(NULL))
    if (.labelled_attach_state$warned) return(invisible(NULL))
    .labelled_attach_state$warned <- TRUE
    warning(
        paste0(
            "`labelled` was attached after dtatools and now masks ",
            "the dtatools package's same-named label metadata helpers. On dtatools ",
            "data, labelled's setters can materialize compact columns or ",
            "discard Stata metadata. Use qualified calls such as ",
            "dtatools::set_val_labels()."
        ),
        call. = FALSE
    )
    invisible(NULL)
}

.onLoad <- function(libname, pkgname) {
    # Settle this private primitive before an operation can trace lazy loading.
    .native_admission_call
    .native_admission_if
    .native_admission_return
    .native_admission_branches
    C_dtatools_capture_branch_frame
    C_dtatools_select_branch
    .strict_double_dependencies
    .computed_storage_getter
    .computed_numeric_dependencies
    .scalar_arith_dependencies
    complete <- FALSE
    on.exit({
        if (!complete) {
            try(.set_dtatools_optional_hooks(remove = TRUE), silent = TRUE)
            try(.restore_dplyr_methods(), silent = TRUE)
        }
    }, add = TRUE)
    .set_dtatools_optional_hooks()
    .register_dplyr_methods()
    .metadata_state$dependencies <- if (
        identical(as.character(getRversion()), "4.6.1") &&
        identical(as.character(R.version[["svn rev"]]), "90187") &&
        .native_admission_call(C_dtatools_metadata_execution_profile, .metadata_execution_probe)
    ) .metadata_dependencies else NULL
    .numeric_helper_state$dependencies <- if (!is.null(.metadata_state$dependencies)) {
        .numeric_helper_dependencies
    } else NULL
    .numeric_helper_state$proof <- if (!is.null(.numeric_helper_state$dependencies)) {
        .native_admission_call(C_dtatools_expected_numeric_profile,
                               .numeric_helper_dependencies, 50L)
    } else NULL
    .numeric_helper_state$entry <- if (!is.null(.numeric_helper_state$dependencies)) {
        .native_admission_call(C_dtatools_numeric_entry_state, .numeric_entry_template)
    } else NULL
    .double_combine_state$dependencies <- if (
        identical(as.character(getNamespaceVersion("vctrs")), "0.7.3")
    ) .native_admission_call(C_dtatools_double_combine_dependencies, .double_combine_expected) else NULL
    # Settle the admission helper before a first indexed operation can trace
    # the lazy-load machinery used to restore its namespace environment.
    .try_combine_dta_double_indexed
    .initial_capture_profile
    C_dtatools_initial_capture_shell
    C_dtatools_initial_capture_initial
    C_dtatools_initial_capture_stats
    C_dtatools_initial_capture_mode
    complete <- TRUE
}

.onUnload <- function(libpath) {
    .set_dtatools_optional_hooks(remove = TRUE)
    .restore_dplyr_methods()
}
