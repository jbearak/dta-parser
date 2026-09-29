# The audited helper graph assumes bytecode execution. Build this probe at
# optimization level 3: lower levels can guard vector() and would conservatively
# disable the shortcuts on a normal installation. Loading never compiles code.
.metadata_execution_probe <- if (!is.null(.metadata_dependencies)) {
    compiler::cmpfun(function() vector("list", 1L), options = list(optimize = 3L))
} else NULL

# These two helpers enclose or are skipped by native metadata shortcuts.
# Their executable trace wrappers must take the ordinary path as well.
# environment() is reached by tryCatch's nested doTryCatch in set operations.
if (!is.null(.metadata_dependencies)) {
    .metadata_dependencies <- c(.metadata_dependencies, list(
        .generate_attributes = compiler::cmpfun(utils::removeSource(.generate_attributes), options = list(optimize = 2L)),
        .dta_attribute_plan = compiler::cmpfun(utils::removeSource(.dta_attribute_plan), options = list(optimize = 2L)),
        environment = utils::removeSource(base::environment)
    ), local({
        # Compiled set operations can settle these bindings without invoking
        # their executable tracers. The last four occur only in generation.
        names <- c("==", "all", "c", "dim", "isS4", "length", "missing",
                   "names", "UseMethod", "!", ">", "any", "class")
        functions <- lapply(names, function(name) {
            value <- get(name, envir = baseenv(), inherits = FALSE)
            if (is.primitive(value)) value else utils::removeSource(value)
        })
        names(functions) <- names
        functions
    }))
}
