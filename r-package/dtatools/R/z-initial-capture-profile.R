# Build-time expectations for fresh initial-capture admission.
# Installed profile records are independent of the executable package records.
.initial_capture_profile <- if (!is.null(.metadata_dependencies) &&
    identical(as.character(getNamespaceVersion('rlang')), '1.3.0')) local({
    package <- parent.env(environment())
    compiled <- function(f) compiler::cmpfun(utils::removeSource(f), options = list(optimize = 2L))
    package_names <- c('.data_columns', '.plain_data_columns', '.capture_dibble_nested',
                       '.metadata_copy', '.repair_data_table_container')
    primitive_names <- c('unclass', 'attributes<-', 'names<-', 'attr',
        'emptyenv', '$', '$<-', '[[', '[[<-', 'names', 'c', 'length', '+',
        'is.null', 'is.environment', 'is.function', 'typeof', '!=', '>',
        '.Call', '.Internal', '::', 'for', '{', '<-', 'if', 'return', '||')
    weak <- utils::removeSource(rlang::new_weakref)
    expression <- body(weak)
    while (is.call(expression) && identical(expression[[1L]], as.name('{')) && length(expression) == 2L)
        expression <- expression[[2L]]
    stopifnot(identical(names(formals(weak)), c('key', 'value', 'finalizer', 'on_quit')),
        identical(formals(weak)$value, NULL), identical(formals(weak)$finalizer, NULL),
        identical(formals(weak)$on_quit, FALSE),
        identical(expression, quote(.Call(ffi_new_weakref, key, value, finalizer, on_quit))))
    list(
        compiled(.begin_dibble_result), compiled(.new_dibble_expression_mask),
        compiled(function(name, value, chunks = NULL) {
            generation <- new.env(parent = emptyenv())
            generation$value <- .capture_dibble_nested(value)
            generation$chunks <- if (is.null(chunks)) NULL else
                lapply(chunks, .capture_dibble_nested)
            generation$used <- FALSE
            state$current[[name]] <- generation
            if (!name %in% state$names) state$names <- c(state$names, name)
            state$generations[[length(state$generations) + 1L]] <- rlang::new_weakref(generation)
        }),
        lapply(package_names, function(n) compiled(get(n, package, inherits = FALSE))),
        lapply(primitive_names, function(n) {
            value <- get(n, baseenv(), inherits = FALSE)
            if (is.primitive(value)) value else utils::removeSource(value)
        }),
        asNamespace('rlang'), weak,
        utils::removeSource(base::new.env), utils::removeSource(base::`%in%`)
    )
}) else NULL
