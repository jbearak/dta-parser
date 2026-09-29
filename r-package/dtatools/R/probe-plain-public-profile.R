# Plain columns reach public cast/math and vector helpers that the owned
# routes can bypass. Qualify that additional surface before admitting them.
.plain_public_state <- new.env(parent = emptyenv())
.plain_public_state$error <- NULL

.plain_public_init <- function(libname, pkgname) {
    tryCatch({
        shared <- .probe_installed_public_profile()
        manifest <- utils::read.csv(file.path(libname, pkgname, 'extdata',
            'plain-public-roots.csv'), stringsAsFactors = FALSE)
        records <- list()
        for (pkg in unique(manifest$package)) {
            db <- new.env(parent = emptyenv())
            base::lazyLoad(system.file('R', pkg, package = pkg), envir = db)
            ns <- asNamespace(pkg)
            for (name in manifest$name[manifest$package == pkg]) {
                actual <- get(name, ns, inherits = FALSE)
                frozen <- get(name, db, inherits = FALSE)
                check <- .native_admission_call(C_probe_public48_source_qualification,
                    actual, frozen)
                stopifnot(is.logical(check), length(check) == 4L, all(check))
                records[[length(records) + 1L]] <- list(name = name, env = ns,
                    live = actual, frozen = frozen)
            }
        }
        for (root in shared) {
            duplicate <- any(vapply(records, function(record)
                identical(record$env, root$env) && identical(record$name, root$name), logical(1)))
            if (duplicate) next
            actual <- get(root$name, root$env, inherits = FALSE)
            check <- .native_admission_call(C_probe_public48_source_qualification,
                actual, root$canonical)
            stopifnot(is.logical(check), length(check) == 4L, all(check))
            records[[length(records) + 1L]] <- list(name = root$name, env = root$env,
                live = actual, frozen = root$canonical)
        }
        methods <- c('Ops.dta_numeric', 'vec_cast.dta_numeric.double', 'vec_cast.dta_numeric.dta_numeric',
            'vec_math.dta_numeric', 'vec_arith.dta_numeric',
            'vec_arith.dta_numeric.numeric', 'vec_proxy.dta_numeric',
            'as.double.dta_numeric', 'is.na.dta_numeric')
        for (name in methods) {
            owner <- asNamespace('dtatools')
            actual <- get(name, owner, inherits = FALSE)
            generic_pkg <- if (name %in% c('Ops.dta_numeric', 'as.double.dta_numeric', 'is.na.dta_numeric'))
                'base' else if (name == 'vec_arith.dta_numeric.numeric') 'dtatools' else 'vctrs'
            table <- get('.__S3MethodsTable__.', asNamespace(generic_pkg), inherits = FALSE)
            stopifnot(identical(get(name, table, inherits = FALSE), actual))
            db <- new.env(parent = emptyenv())
            base::lazyLoad(system.file('R', 'dtatools', package = 'dtatools'), envir = db)
            frozen <- get(name, db, inherits = FALSE)
            check <- .native_admission_call(C_probe_public48_source_qualification, actual, frozen)
            stopifnot(is.logical(check), length(check) == 4L, all(check))
            if (!any(vapply(records, function(record)
                    identical(record$env, owner) && identical(record$name, name), logical(1))))
                records[[length(records) + 1L]] <- list(name = name, env = owner,
                    live = actual, frozen = frozen)
            records[[length(records) + 1L]] <- list(name = name, env = table,
                live = actual, frozen = frozen)
        }
        state <- .plain_public_state
        state$labels <- vapply(records, `[[`, '', 'name')
        state$envs <- lapply(records, `[[`, 'env')
        state$frozen <- lapply(records, `[[`, 'frozen')
        state$live <- lapply(records, `[[`, 'live')
        state$bodies <- state$environments <- state$attributes <- NULL
        state$primitive_names <- c('is.na', 'is.infinite', 'is.finite', 'any', 'abs',
            'floor', '!', '|', '&', '==', '>', '<', '>=', '<=', '[', '[<-',
            'attr', 'names', 'names<-', '[[', 'length', 'as.double', 'is.object',
            'is.numeric', 'is.atomic', 'is.symbol', 'dim', 'attributes')
        state$primitive_values <- lapply(state$primitive_names, .Primitive)
        stopifnot(isTRUE(.native_admission_call(C_dtatools_probe_gen_extra_capture, state)),
                  isTRUE(.native_admission_call(C_dtatools_probe_plain_public_pin, state)))
    }, error = function(e) .plain_public_state$error <- conditionMessage(e))
    invisible(NULL)
}
