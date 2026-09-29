# Complete the graph only after every package helper has been defined. These
# are build-time expectations; a first operation never blesses current code.
if (!is.null(.double_combine_expected) &&
    identical(as.character(getNamespaceVersion("rlang")), "1.3.0")) {
    .double_combine_expected[[3L]][2:6] <- lapply(
        .double_combine_expected[[3L]][2:6], function(value) {
            compiler::cmpfun(value, options = list(optimize = 2L))
        }
    )
    .double_combine_expected[[9L]] <- local({
        package_names <- c(
            '.dta_promote', '.dta_common_ptype', '.dta_ptype',
            '.reconcile_dta_metadata', '.restore_dta_metadata',
            '.dta_classes_from', '.dta_combine_value_labels',
            '.reconcile_dta_metadata_attributes', '.apply_haven_labelled_class',
            '.dta_snapshot', '.cast_to_dta', '.compact_dta_storage_matches'
        )
        package <- lapply(package_names, function(name) {
            compiler::cmpfun(utils::removeSource(get(name)),
                             options = list(optimize = 2L))
        })
        base_names <- c('double', 'is.factor', 'paste0', 'identical',
                        'NextMethod', 'environment', 'parent.frame', 'sys.frame')
        base <- lapply(base_names, function(name) {
            compiler::cmpfun(utils::removeSource(get(name, baseenv())),
                             options = list(optimize = 2L))
        })
        external <- list(
            utils::removeSource(vctrs:::names_repair_missing),
            utils::removeSource(rlang::check_dots_empty0),
            utils::removeSource(rlang::current_env)
        )
        # The tiny external helpers are qualified across standard public R
        # compiler modes by checking every reached lexical operation. Their
        # source references therefore need no bytecode normalization.
        primitive_names <- c('list', 'c', '.Call', 'is.null', 'nargs', 'length',
                             '!=', '&&', 'if', '{', 'return', '<-', 'UseMethod',
                             '.Internal', 'attributes<-', '-', '.subset', 'attr')
        primitive <- lapply(primitive_names, .Primitive)
        list(package, base, external, primitive, asNamespace('rlang'))
    })
}
