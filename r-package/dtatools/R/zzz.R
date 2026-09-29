.labelled_attach_state <- new.env(parent = emptyenv())
.labelled_attach_state$warned <- FALSE
.probe_s3_state <- new.env(parent = emptyenv())
.probe_s3_state$tables <- NULL
.probe_s3_state$live <- NULL
.probe_s3_state$namespaces <- NULL
.probe_base_state <- new.env(parent = emptyenv())
.probe_base_state$live <- NULL
.probe_base_state$frozen <- NULL
.probe_base16_state <- new.env(parent = emptyenv())
.probe_base16_state$source <- NULL
.probe_base16_state$compiled <- NULL
.probe_base16_state$live <- NULL
.probe_rlang_state <- new.env(parent = emptyenv())
.probe_rlang_state$namespace <- NULL
.probe_rlang_state$frozen <- NULL
.probe_rlang_state$live <- NULL
.probe_vctrs_size_state <- new.env(parent = emptyenv())
.probe_vctrs_size_state$namespace <- NULL
.probe_vctrs_size_state$frozen_source <- NULL
.probe_vctrs_size_state$frozen_code <- NULL
.probe_vctrs_size_state$proxy_namespace <- NULL
.probe_vctrs_size_state$proxy_table <- NULL
.probe_vctrs_size_state$proxy_source <- NULL
.probe_vctrs_size_state$proxy_code <- NULL
.probe_public48_state <- new.env(parent = emptyenv())
.probe_public48_state$envs <- NULL
.probe_public48_state$labels <- NULL
.probe_public48_state$expected <- NULL
.probe_public48_state$compiled <- NULL
.probe_public48_state$sourcefiles <- NULL
.probe_public48_state$debug_supported <- FALSE
.probe_public48_state$live <- NULL
.probe_public48_state$bodies <- NULL
.probe_public48_state$closure_envs <- NULL
.probe_wrapper_state <- new.env(parent = emptyenv())
.probe_wrapper_state$frozen <- NULL
.probe_wrapper_state$internal <- NULL
.probe_wrapper_state$live <- NULL
.probe_wrapper_state$repl <- NULL
.probe_wrapper_state$helper <- NULL
.probe_wrapper_state$body <- NULL
.probe_wrapper_state$repl_body <- NULL
.probe_wrapper_state$formals <- NULL

.probe_wrapper_init <- function() {
    tryCatch({
        ns <- asNamespace("dtatools")
        if (bindingIsActive("replace_values", ns) ||
            bindingIsActive("repl", ns) ||
            bindingIsActive(".Internal", baseenv()))
            stop("active public wrapper or primitive")
        current <- get("replace_values", envir = ns, inherits = FALSE)
        repl_current <- get("repl", envir = ns, inherits = FALSE)
        .probe_wrapper_state$frozen <- readRDS(system.file(
            "extdata", "probe-wrapper-clean.rds", package = "dtatools"))
        .probe_wrapper_state$internal <- readRDS(system.file(
            "extdata", "probe-base-internal-clean.rds", package = "dtatools"))
        .probe_wrapper_state$live <- current
        .probe_wrapper_state$repl <- repl_current
        if (!isTRUE(.Call(C_dtatools_probe_wrapper_capture,
                          .probe_wrapper_state)))
            stop("public wrapper source mismatch")
    }, error = function(e) NULL)
    invisible(NULL)
}

.probe_public48_init <- function() {
    tryCatch({
        source_profile <- .probe_installed_public_profile()
        compiled <- lapply(source_profile, `[[`, "canonical")
        records <- list()
        add <- function(name, env, frozen) {
            if (!exists(name, envir = env, inherits = FALSE) ||
                bindingIsActive(name, env)) stop("non-value public binding")
            current <- get(name, envir = env, inherits = FALSE)
            if (!identical(typeof(current), "closure") ||
                !identical(typeof(frozen), "closure"))
                stop("public closure type mismatch: ", name)
            index <- length(records) + 1L
            code <- .Call(C_probe_public48_source_qualification,
                          current, compiled[[index]])
            if (!is.logical(code) || length(code) != 4L || !all(code))
                stop("public bytecode mismatch: ", name)
            records[[index]] <<- list(
                name = name, env = env, live = current,
                expected = formals(frozen))
        }
        for (root in source_profile)
            add(root$name, root$env, root$canonical)
        if (length(records) != 58L) stop("public manifest count")
        .probe_public48_state$envs <- lapply(records, `[[`, "env")
        .probe_public48_state$labels <- vapply(records, `[[`, "", "name")
        .probe_public48_state$expected <- lapply(records, `[[`, "expected")
        .probe_public48_state$compiled <- compiled
        .probe_public48_state$sourcefiles <- lapply(records, function(record) {
            attr(attr(record$live, "srcref"), "srcfile")
        })
        .probe_public48_state$debug_supported <-
            identical(as.character(getRversion()), "4.6.1") &&
            identical(as.character(R.version[["svn rev"]]), "90187") &&
            isTRUE(.Call(C_probe_public48_debug_available, NULL))
        .probe_public48_state$live <- lapply(records, `[[`, "live")
        if (!isTRUE(.Call(C_probe_48_expected_plain,
                          .probe_public48_state$expected)) ||
            !isTRUE(.Call(C_dtatools_probe_public48_capture,
                          .probe_public48_state)))
            stop("public manifest not plain or changed at capture")
    }, error = function(e) NULL)
    invisible(NULL)
}

.probe_public_s3_init <- function() {
    if (!identical(as.character(getRversion()), "4.6.1")) return(invisible(NULL))
    tryCatch({
        dtans <- asNamespace("dtatools")
        vns <- asNamespace("vctrs")
        tbl <- function(env) get(".__S3MethodsTable__.", envir = env, inherits = FALSE)
        base_table <- tbl(baseenv())
        vctrs_table <- tbl(vns)
        dta_table <- tbl(dtans)
        live <- list(
            ops = get0("Ops.dta_numeric", base_table, inherits = FALSE),
            plus_vctr = get0("+.vctrs_vctr", base_table, inherits = FALSE),
            vec_arith = get("vec_arith", vns, inherits = FALSE),
            arith1 = get0("vec_arith.dta_numeric", vctrs_table, inherits = FALSE),
            arith2 = get0("vec_arith.dta_numeric.numeric", dta_table, inherits = FALSE),
            arith2_generic = get("vec_arith.dta_numeric", dtans, inherits = FALSE),
            base_plus = .Primitive("+")
        )
        # Namespace closures passed the independent full-bytecode check above.
        # A table entry must be that very closure, not a source-equivalent copy.
        same_pointer <- function(a, b) isTRUE(.Call(C_probe_public48_same_pointer,
                                                     a, b))
        if (is.null(.probe_public48_state$live) ||
            !same_pointer(live$ops, get("Ops.dta_numeric", dtans,
                                        inherits = FALSE)) ||
            !same_pointer(live$plus_vctr, get("+.vctrs_vctr", vns,
                                              inherits = FALSE)) ||
            !same_pointer(live$vec_arith, get("vec_arith", vns,
                                             inherits = FALSE)) ||
            !same_pointer(live$arith1, get("vec_arith.dta_numeric", dtans,
                                         inherits = FALSE)) ||
            !same_pointer(live$arith2, get("vec_arith.dta_numeric.numeric",
                                         dtans, inherits = FALSE)))
            return(invisible(NULL))
        .probe_s3_state$tables <- list(base_table, vctrs_table, dta_table)
        .probe_s3_state$live <- live
        .probe_s3_state$namespaces <- list(vns, dtans)
    }, error = function(e) NULL)
    invisible(NULL)
}

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
    .native_admission_missing
    .native_admission_is_null
    .native_admission_not
    .native_admission_and
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
    .probe_base_state$frozen <- readRDS(system.file(
        "extdata", "probe-frozen-base.rds", package = "dtatools"))
    .probe_base16_state$source <- readRDS(system.file(
        "extdata", "probe-base16-source.rds", package = "dtatools"))
    .probe_base16_state$compiled <- readRDS(system.file(
        "extdata", "probe-base16-compiled.rds", package = "dtatools"))
    .probe_rlang_state$namespace <- asNamespace("rlang")
    invisible(lapply(c("is_bool", "is_formula", "is_quosure", "quo_get_env",
                       "quo_get_expr", "quo_is_missing"), get,
                     envir = .probe_rlang_state$namespace, inherits = FALSE))
    .probe_rlang_state$frozen <- readRDS(system.file(
        "extdata", "probe-frozen-rlang-public.rds", package = "dtatools"))
    .probe_vctrs_size_state$namespace <- asNamespace("vctrs")
    .probe_vctrs_size_state$proxy_namespace <- asNamespace("dtatools")
    .probe_vctrs_size_state$proxy_table <- get(
        ".__S3MethodsTable__.", .probe_vctrs_size_state$namespace,
        inherits = FALSE)
    invisible(get("vec_size", .probe_vctrs_size_state$namespace,
                  inherits = FALSE))
    invisible(get("vec_proxy.dta_numeric", .probe_vctrs_size_state$proxy_table,
                  inherits = FALSE))
    .probe_vctrs_size_state$frozen_source <- readRDS(system.file(
        "extdata", "frozen-vec-size-source.rds", package = "dtatools"))
    .probe_vctrs_size_state$frozen_code <- readRDS(system.file(
        "extdata", "frozen-vec-size-compiled.rds", package = "dtatools"))
    .probe_vctrs_size_state$proxy_source <- readRDS(system.file(
        "extdata", "frozen-proxy-source.rds", package = "dtatools"))
    .probe_vctrs_size_state$proxy_code <- readRDS(system.file(
        "extdata", "frozen-proxy-compiled.rds", package = "dtatools"))
    .probe_public48_init()
    .probe_public_s3_init()
    .probe_wrapper_init()
    .probe_gen_extra_init()
    .probe_bracket_public_init()
    .probe_grouped_gen_init()
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
    .grouped_probe_state$libname <- libname
    .grouped_probe_state$pkgname <- pkgname
    .grouped_probe_pin_if_ready()
    .ungrouped_mutate_state$libname <- libname
    .ungrouped_mutate_state$pkgname <- pkgname
    .ungrouped_mutate_pin_if_ready()
    complete <- TRUE
}


.onUnload <- function(libpath) {
    .set_dtatools_optional_hooks(remove = TRUE)
    .restore_dplyr_methods()
}
