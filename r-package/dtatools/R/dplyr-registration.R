# Optional dplyr methods use removable hooks. Base R's qualified delayed S3
# directives retain their onLoad closures after dtatools unloads. Keep this
# lifecycle separate from the required pillar/tibble/vctrs registrations.
.dplyr_method_classes <- list(
    recode = c("Date", "POSIXct", "dtatools_dta_metadata_vector",
               "haven_labelled", "numeric", "dta_numeric"),
    arrange = "dtatools_ref_data",
    distinct = "dtatools_ref_data",
    group_modify = "dtatools_ref_data",
    group_nest = "dtatools_ref_data",
    nest_by = "dtatools_ref_data",
    reframe = "dtatools_ref_data",
    dplyr_col_modify = "dtatools_ref_data",
    dplyr_reconstruct = "dtatools_ref_data",
    dplyr_row_slice = "dtatools_ref_data",
    filter = "dtatools_ref_data",
    filter_out = "dtatools_ref_data",
    group_by = "dtatools_ref_data",
    relocate = "dtatools_ref_data",
    rename = "dtatools_ref_data",
    rowwise = "dtatools_ref_data",
    select = "dtatools_ref_data",
    slice = "dtatools_ref_data",
    slice_head = "dtatools_ref_data",
    slice_max = "dtatools_ref_data",
    slice_min = "dtatools_ref_data",
    slice_sample = "dtatools_ref_data",
    slice_tail = "dtatools_ref_data",
    summarise = "dtatools_ref_data",
    transmute = "dtatools_ref_data",
    ungroup = "dtatools_ref_data",
    mutate = "dtatools_ref_data",
    inner_join = "dtatools_ref_data",
    left_join = "dtatools_ref_data",
    right_join = "dtatools_ref_data",
    full_join = "dtatools_ref_data",
    semi_join = "dtatools_ref_data",
    anti_join = "dtatools_ref_data",
    nest_join = "dtatools_ref_data",
    cross_join = "dtatools_ref_data",
    rows_insert = "dtatools_ref_data",
    rows_append = "dtatools_ref_data",
    rows_update = "dtatools_ref_data",
    rows_patch = "dtatools_ref_data",
    rows_upsert = "dtatools_ref_data",
    rows_delete = "dtatools_ref_data"
)

.dplyr_registration_state <- new.env(parent = emptyenv())
.dplyr_registration_state$namespace <- NULL
.dplyr_registration_state$previous <- list()

.write_dplyr_method <- function(generic, class, method, namespace) {
    # A non-namespace environment resolves the real generic without appending
    # our closure to dplyr's own persistent namespace registration metadata.
    registerS3method(generic, class, method,
        envir = new.env(parent = namespace))
}

.register_dplyr_methods <- function(..., only = NULL) {
    if (!isNamespaceLoaded("dplyr")) return(invisible(NULL))
    namespace <- asNamespace("dplyr")
    if (package_version(getNamespaceVersion(namespace)) < "1.2.1") {
        stop("Dibble integration requires dplyr 1.2.1 or newer.", call. = FALSE)
    }
    for (generic in names(.dplyr_method_classes)) {
        if (!is.function(getExportedValue("dplyr", generic))) {
            stop("Missing dplyr generic: ", generic, call. = FALSE)
        }
    }
    state <- .dplyr_registration_state
    previous_namespace <- state$namespace
    previous_methods <- state$previous
    changed <- list()
    complete <- FALSE
    on.exit({
        if (!complete) {
            for (key in rev(names(changed))) {
                entry <- changed[[key]]
                if (!identical(get0(key, table, inherits = FALSE), entry$method)) next
                if (is.null(entry$previous)) rm(list = key, envir = table)
                else .write_dplyr_method(entry$generic, entry$class, entry$previous, namespace)
            }
            state$namespace <- previous_namespace
            state$previous <- previous_methods
        }
    }, add = TRUE)
    if (!identical(state$namespace, namespace)) {
        state$namespace <- namespace
        state$previous <- list()
    }
    table <- get(".__S3MethodsTable__.", namespace, inherits = FALSE)
    own_namespace <- environment(.register_dplyr_methods)
    for (generic in names(.dplyr_method_classes)) {
        for (class in .dplyr_method_classes[[generic]]) {
            key <- paste0(generic, ".", class)
            if (!is.null(only) && !key %in% only) next
            method <- get(key, own_namespace, inherits = FALSE)
            current <- get0(key, table, inherits = FALSE)
            if (identical(current, method)) next
            entry <- list(generic = generic, class = class,
                previous = current, method = method)
            changed[[key]] <- entry
            state$previous[[key]] <- entry
            .write_dplyr_method(generic, class, method, namespace)
        }
    }
    complete <- TRUE
    invisible(NULL)
}

.register_dtatools_labelled_recode <- function(...) {
    .register_dplyr_methods(only = "recode.haven_labelled")
}

.clear_dplyr_registrations <- function(...) {
    .dplyr_registration_state$namespace <- NULL
    .dplyr_registration_state$previous <- list()
    invisible(NULL)
}

.registration_method_namespace <- function(method) {
    if (!is.function(method) || is.null(environment(method))) return(NULL)
    owner <- topenv(environment(method))
    if (isNamespace(owner)) owner else NULL
}

.discard_labelled_registration <- function(...) {
    state <- .dplyr_registration_state
    for (key in names(state$previous)) {
        owner <- .registration_method_namespace(state$previous[[key]]$previous)
        if (!is.null(owner) && identical(unname(getNamespaceName(owner)), "labelled")) {
            state$previous[[key]]$previous <- NULL
        }
    }
    invisible(NULL)
}

.restore_dplyr_methods <- function() {
    state <- .dplyr_registration_state
    if (isNamespaceLoaded("dplyr") &&
        identical(state$namespace, asNamespace("dplyr"))) {
        namespace <- state$namespace
        table <- get(".__S3MethodsTable__.", namespace, inherits = FALSE)
        for (key in names(state$previous)) {
            entry <- state$previous[[key]]
            if (!identical(get0(key, table, inherits = FALSE), entry$method)) next
            previous <- entry$previous
            owner <- .registration_method_namespace(previous)
            if (!is.null(owner)) {
                name <- getNamespaceName(owner)
                if (!isNamespaceLoaded(name) || !identical(asNamespace(name), owner)) {
                    previous <- NULL
                }
            }
            if (is.null(previous)) {
                rm(list = key, envir = table)
            } else {
                .write_dplyr_method(entry$generic, entry$class, previous, namespace)
            }
        }
    }
    .clear_dplyr_registrations()
}

.dtatools_optional_hooks <- function() {
    list(
        list("dplyr", "onLoad", .register_dplyr_methods),
        list("dplyr", "onUnload", .clear_dplyr_registrations),
        list("labelled", "onLoad", .register_dtatools_labelled_recode),
        list("labelled", "onUnload", .discard_labelled_registration),
        list("labelled", "attach", .warn_labelled_masking)
    )
}

.set_dtatools_optional_hooks <- function(remove = FALSE) {
    for (spec in .dtatools_optional_hooks()) {
        event <- packageEvent(spec[[1L]], spec[[2L]])
        hooks <- getHook(event)
        ours <- vapply(hooks, identical, logical(1), y = spec[[3L]])
        if (remove) {
            setHook(event, hooks[!ours], action = "replace")
        } else if (!any(ours)) {
            setHook(event, spec[[3L]], action = "append")
        }
    }
    invisible(NULL)
}
