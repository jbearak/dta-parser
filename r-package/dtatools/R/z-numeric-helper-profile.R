# Capture canonical helpers at build time, after all definitions are available.
# These package bodies compile identically after source-reference stripping on
# the audited R build. Never capture a replacement on the first numeric call.
.numeric_helper_dependencies <- if (!is.null(.metadata_dependencies)) local({
    package_names <- c(
        ".dta_arith_base", ".dta_read_is_na", ".collapse_missing", ".dta_computed",
        ".tab_missing_codes", ".encode_dta_temporal", ".dta_storage_candidates",
        ".invalid_dta_observed", ".construct_dta_numeric_trusted", ".metadata_copy",
        ".repair_data_table_container", ".construct_dta_numeric", ".dta_storage_holds",
        ".dta_storage_class", ".declared_dta_storage", ".dta_data", ".metadata_view"
    )
    base_names <- c("is.primitive", "rep", "identical", "inherits", "utf8ToInt",
                    "/", "$", ".Call", "::", "isTRUE", "attr<-", "paste0",
                    "names<-", "names", "c", "{", "return", "<-", "if", "[[",
                    "list", ".Internal", "is.null", "typeof", "is.factor", "%in%",
                    "dim", "as.double", "&&", "||", "match", "switch", "attributes<-")
    package <- parent.env(environment())
    snapshot <- function(value) {
        if (is.primitive(value)) return(value)
        value <- compiler::cmpfun(utils::removeSource(value),
                                 options = list(optimize = 2L))
        # Build-time canonical data only. Copy every mutable syntax/constant
        # object while keeping the lexical and source-file environments.
        refs <- list()
        encode <- function(x) {
            if (!is.environment(x)) return(NULL)
            i <- which(vapply(refs, identical, logical(1), x))
            if (!length(i)) { refs[[length(refs) + 1L]] <<- x; i <- length(refs) }
            paste0("environment:", i[[1L]])
        }
        decode <- function(key) refs[[as.integer(sub(
            "environment:", "", key, fixed = TRUE))]]
        unserialize(serialize(value, NULL, refhook = encode), refhook = decode)
    }
    functions <- c(
        lapply(package_names, function(name) snapshot(get(name, package, inherits = FALSE))),
        lapply(base_names, function(name) snapshot(get(name, baseenv(), inherits = FALSE)))
    )
    names(functions) <- c(package_names, base_names)
    c(functions, list(.dta_temporal_none = .dta_temporal_none,
                     .dta_float_max = .dta_float_max, .dta_storage = .dta_storage))
}) else NULL

.numeric_helper_state <- new.env(parent = emptyenv())
.numeric_helper_state$dependencies <- NULL
.numeric_helper_state$proof <- NULL

# A public stack query with a private captured .Internal binding.
.numeric_entry_template <- if (!is.null(.numeric_helper_dependencies)) list(
    compiler::cmpfun(utils::removeSource(base::sys.function), options = list(optimize = 2L)),
    .Primitive(".Internal")
) else NULL
.numeric_helper_state$entry <- NULL
