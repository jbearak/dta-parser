.labelled_attach_state <- new.env(parent = emptyenv())
.labelled_attach_state$warned <- FALSE

.warn_labelled_masking <- function(...) {
    if (!"package:dtatools" %in% search()) return(invisible(NULL))
    shared <- c(
        "var_label", "var_label<-", "val_labels", "val_labels<-"
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
    complete <- FALSE
    on.exit({
        if (!complete) {
            try(.set_dtatools_optional_hooks(remove = TRUE), silent = TRUE)
            try(.restore_dplyr_methods(), silent = TRUE)
        }
    }, add = TRUE)
    .set_dtatools_optional_hooks()
    .register_dplyr_methods()
    complete <- TRUE
}

.onUnload <- function(libpath) {
    .set_dtatools_optional_hooks(remove = TRUE)
    .restore_dplyr_methods()
}
