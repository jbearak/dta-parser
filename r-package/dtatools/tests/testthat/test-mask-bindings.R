.mask_binding_frame <- function() {
    frame <- new.env(parent = baseenv())
    frame$read <- function(generation, name, id) list(generation, name, id)
    frame$.metadata_state <- .metadata_state
    factory <- utils::removeSource(function(generation, name, id) {
        force(generation); force(name); force(id)
        function() read(generation, name, id)
    })
    environment(factory) <- frame
    frame$binding <- compiler::cmpfun(factory)
    frame
}
.mask_binding_context <- function(current, id = 1L, reader = .mask_binding_frame()) {
    state <- new.env(parent = emptyenv())
    state$current <- current
    state$id <- id
    reader$state <- state
    frame <- new.env(parent = reader)
    delayedAssign('id', state$id, eval.env = frame, assign.env = frame)
    list(frame = frame, reader = reader, state = state)
}
.mask_binding_attempt <- function(current, id = 1L, reader = .mask_binding_frame(),
                                  dependencies = .mask_bindings_expected) {
    context <- .mask_binding_context(current, id, reader)
    .Call(C_dtatools_try_mask_bindings, context$frame, context$reader, dependencies)
}

test_that('native bindings capture fixed generations names and groups', {
    supported <- .dtatools_execution_profile_expected()
    frame <- .mask_binding_frame()
    generations <- setNames(lapply(1:100, function(i) new.env(parent = emptyenv())),
                            c('a b', 'read', 'generation', 'id', paste0('v', 5:100)))
    bindings <- .mask_binding_attempt(generations, 3L, frame)
    if (supported) {
        expect_true(is.environment(bindings))
        expect_identical(parent.env(bindings), emptyenv())
        expect_true(bindingIsActive('a b', bindings))
        saved <- generations[[1L]]
        generations[[1L]] <- new.env(parent = emptyenv())
        expect_identical(bindings[['a b']], list(saved, 'a b', 3L))
        expect_identical(bindings[['read']], list(generations[[2L]], 'read', 3L))
        frame$read <- function(generation, name, id) list('new reader', generation, name, id)
        expect_identical(bindings[['a b']], list('new reader', saved, 'a b', 3L))
    } else {
        expect_null(bindings)
    }
    empty <- .mask_binding_attempt(setNames(list(), character()), 0L)
    if (supported) expect_true(is.environment(empty)) else expect_null(empty)
})

test_that('interpreted public masks retain executable names callbacks', {
    skip_if_not_installed('dplyr', '1.2.1')
    skip_if_not_installed('callr')
    observed <- callr::r(function() {
        library(dtatools)
        loadNamespace('dplyr')
        data <- dibble(x = c(1, 2, 3))
        calls <- 0L
        trace('names', tracer = function() {
            target <- quote(names(state$current))
            stack <- sys.calls()
            if (any(vapply(stack, identical, logical(1), target)) &&
                any(vapply(stack, identical, logical(1), quote(make_mask())))) {
                calls <<- calls + 1L
            }
        }, where = baseenv(), print = FALSE)
        result <- tryCatch(dplyr::mutate(data, y = x + 1),
                           finally = untrace('names', where = baseenv()))
        list(calls = calls, values = as.double(result$y))
    }, libpath = .libPaths(), env = c(R_DISABLE_BYTECODE = '1'))
    expect_identical(observed$calls, 1L)
    expect_identical(observed$values, c(2, 3, 4))
})

test_that('native binding admission declines unsupported containers and names', {
    first <- new.env(parent = emptyenv())
    second <- new.env(parent = emptyenv())
    current <- list(x = first, y = second)
    for (bad in list(unname(current), structure(current, class = 'foreign'),
                     structure(current, note = TRUE), list(x = first, y = 1),
                     setNames(list(first, second), c('x', 'x')),
                     setNames(list(first), ''), setNames(list(first), NA_character_))) {
        expect_null(.mask_binding_attempt(bad))
    }
    for (id in list(NA_integer_, -1L, 1, integer(), structure(1L, note = TRUE))) {
        expect_null(.mask_binding_attempt(current, id))
    }
    calls <- 0L
    foreign <- .Call(C_dtatools_callback_character, c('x', 'y'), function() {
        calls <<- calls + 1L
    })
    attr(current, 'names') <- foreign
    calls <- 0L
    expect_true(.is_altrep(names(current)))
    declined <- .mask_binding_attempt(current)
    expect_identical(calls, 0L)
    expect_null(declined)
})

test_that('native binding admission never invokes unknown constructor bindings', {
    current <- list(x = new.env(parent = emptyenv()))
    calls <- 0L
    for (key in c('new.env', 'makeActiveBinding')) {
        active <- new.env(parent = .mask_binding_frame())
        makeActiveBinding(key, function() { calls <<- calls + 1L; stop('forced') }, active)
        expect_null(.mask_binding_attempt(current, reader = active))
        expect_identical(calls, 0L)
        delayed <- new.env(parent = .mask_binding_frame())
        delayedAssign(key, { calls <<- calls + 1L; stop('forced') }, assign.env = delayed)
        expect_null(.mask_binding_attempt(current, reader = delayed))
        expect_identical(calls, 0L)
        replaced <- new.env(parent = .mask_binding_frame())
        assign(key, function(...) stop('called'), replaced)
        expect_null(.mask_binding_attempt(current, reader = replaced))
    }
    for (dependencies in list(NULL, list(), structure(.mask_bindings_expected, class = 'foreign'))) {
        expect_null(.mask_binding_attempt(current, dependencies = dependencies))
    }
})

test_that('binding construction retains traced constructors without admission callbacks', {
    current <- list(x = new.env(parent = emptyenv()))
    reader <- .mask_binding_frame()
    for (key in c('new.env', 'makeActiveBinding')) {
        context <- .mask_binding_context(current, reader = reader)
        calls <- 0L
        trace(key, tracer = function() { calls <<- calls + 1L }, where = baseenv(), print = FALSE)
        observed <- tryCatch({
            declined <- .Call(C_dtatools_try_mask_bindings, context$frame,
                              context$reader, .mask_bindings_expected)
            list(declined = declined, calls = calls)
        }, finally = untrace(key, where = baseenv()))
        expect_null(observed$declined)
        expect_identical(observed$calls, 0L)
    }
})

test_that('binding fallback retains encoded-name diagnostics', {
    name <- rawToChar(as.raw(233)); Encoding(name) <- 'bytes'
    current <- setNames(list(new.env(parent = emptyenv())), name)
    expect_null(.mask_binding_attempt(current))
    capture <- function(thunk) tryCatch({ thunk(); NULL }, error = function(condition)
        list(class = class(condition), message = conditionMessage(condition), call = conditionCall(condition)))
    legacy <- capture(function() makeActiveBinding(name, function() 1, new.env()))
    groups <- list(rows = list(1L), names = character(),
                   keys = tibble::new_tibble(list(), nrow = 1L), type = 'ungrouped')
    mask <- .new_dibble_expression_mask(list(x = dta_double(1)), groups, 1L, 'mutate()')
    withr::defer(mask$forget())
    # Initial column capture already rejects bytes names. Exercise the binding
    # constructor's own boundary without failing earlier in column lookup.
    state <- get('state', environment(mask$evaluate))
    names(state$current) <- name
    actual <- capture(function() mask$helpers$get_rlang_mask())
    expect_identical(actual, legacy)
})

test_that('non-ASCII binding names retain the original reader path', {
    name <- '\u00e9'
    expect_null(.mask_binding_attempt(setNames(list(new.env(parent = emptyenv())), name)))
    groups <- list(rows = list(1L), names = character(),
                   keys = tibble::new_tibble(list(), nrow = 1L), type = 'ungrouped')
    mask <- .new_dibble_expression_mask(setNames(list(dta_double(1)), name), groups, 1L, 'mutate()')
    withr::defer(mask$forget())
    expect_identical(as.double(mask$evaluate(rlang::quo(.data[[name]]), 1L)), 1)
    saved <- mask$evaluate(rlang::quo(function() .data[[name]]), 1L)
    mask$forget()
    expect_error(saved(), 'Obsolete data mask')
})

test_that('changed constructors run before the fallback group promise is forced', {
    groups <- list(rows = list(1L, 2L), names = 'g',
                   keys = tibble::tibble(g = 1:2), type = 'grouped')
    for (key in c('new.env', 'makeActiveBinding')) {
        mask <- .new_dibble_expression_mask(list(x = dta_double(c(10, 20))),
                                             groups, 2L, 'mutate()')
        original <- get(key, baseenv())
        assign(key, function(...) { mask$set_group(2L); original(...) },
               environment(mask$evaluate))
        mask$set_group(1L)
        bindings <- mask$helpers$get_rlang_mask()
        actual <- rlang::eval_tidy(rlang::quo(x), bindings)
        expect_identical(mask$current_id(), 2L)
        expect_identical(as.double(actual), 20)
        mask$forget()
    }
})

test_that('long ASCII names retain the original symbol-conversion diagnostics', {
    name <- strrep('x', 10001L)
    current <- setNames(list(new.env(parent = emptyenv())), name)
    observed <- tryCatch(.mask_binding_attempt(current), error = identity)
    expect_null(observed)
    capture <- function(thunk) tryCatch({ thunk(); NULL }, error = function(condition)
        list(class = class(condition), message = conditionMessage(condition), call = conditionCall(condition)))
    legacy <- capture(function() makeActiveBinding(name, function() 1, new.env()))
    groups <- list(rows = list(1L), names = character(),
                   keys = tibble::new_tibble(list(), nrow = 1L), type = 'ungrouped')
    mask <- .new_dibble_expression_mask(setNames(list(dta_double(1)), name), groups, 1L, 'mutate()')
    withr::defer(try(mask$forget(), silent = TRUE))
    actual <- capture(function() mask$helpers$get_rlang_mask())
    expect_identical(actual, legacy)
})

test_that('foreign names run before a declined binding attempt forces its group', {
    groups <- list(rows = list(1L, 2L), names = 'g',
                   keys = tibble::tibble(g = 1:2), type = 'grouped')
    mask <- .new_dibble_expression_mask(list(x = dta_double(c(10, 20))),
                                         groups, 2L, 'mutate()')
    withr::defer(mask$forget())
    state <- get('state', environment(mask$evaluate))
    calls <- 0L
    armed <- FALSE
    foreign <- .Call(C_dtatools_callback_character, 'x', function() {
        if (armed) {
            calls <<- calls + 1L
            mask$set_group(2L)
        }
    })
    attr(state$current, 'names') <- foreign
    mask$set_group(1L)
    armed <- TRUE
    bindings <- mask$helpers$get_rlang_mask()
    actual <- rlang::eval_tidy(rlang::quo(x), bindings)
    armed <- FALSE
    expect_identical(calls, 1L)
    expect_identical(mask$current_id(), 2L)
    expect_identical(as.double(actual), 20)
})

test_that('binding admission leaves unfamiliar promises and state fields untouched', {
    current <- list(x = new.env(parent = emptyenv()))
    attempts <- 0L
    unexpected <- function() { attempts <<- attempts + 1L; stop('unexpected read') }
    for (target in c('id', 'state', 'current', 'state_id', 'accessor')) {
        context <- .mask_binding_context(current)
        if (target == 'id') {
            delayedAssign('id', unexpected(), eval.env = environment(),
                          assign.env = context$frame)
        } else if (target == 'accessor') {
            assign('$', unexpected, context$reader)
        } else {
            location <- if (target == 'state') context$reader else context$state
            name <- if (target == 'state_id') 'id' else target
            rm(list = name, envir = location)
            makeActiveBinding(name, unexpected, location)
        }
        expect_null(.Call(C_dtatools_try_mask_bindings, context$frame,
                          context$reader, .mask_bindings_expected))
        expect_identical(attempts, 0L)
    }
})

test_that("binding admission accepts settled IDs and settles successful default IDs", {
    supported <- .dtatools_execution_profile_expected()
    current <- list(x = new.env(parent = emptyenv()))
    context <- .mask_binding_context(current, 1L)
    bindings <- .Call(C_dtatools_try_mask_bindings, context$frame,
                      context$reader, .mask_bindings_expected)
    if (supported) expect_true(is.environment(bindings)) else expect_null(bindings)
    context$state$id <- 2L
    # A nonempty successful loop forces the caller's default id as well as
    # every capture's id. A declined attempt leaves that promise untouched.
    expect_identical(context$frame$id, if (supported) 1L else 2L)
    if (supported) expect_identical(bindings$x[[3L]], 1L)
    direct <- .Call(C_dtatools_try_mask_bindings, context$frame,
                    context$reader, .mask_bindings_expected)
    if (supported) expect_identical(direct$x[[3L]], 1L) else expect_null(direct)
    assign('id', 3L, context$frame)
    direct <- .Call(C_dtatools_try_mask_bindings, context$frame,
                    context$reader, .mask_bindings_expected)
    if (supported) expect_identical(direct$x[[3L]], 3L) else expect_null(direct)
})

test_that('foreign initial names cannot interrupt mask expiration', {
    groups <- list(rows = list(1:2), names = character(),
                   keys = tibble::new_tibble(list(), nrow = 1L), type = 'ungrouped')
    foreign <- .Call(C_dtatools_callback_character, 'x', function() NULL)
    columns <- list(dta_double(c(10, 20)))
    attr(columns, 'names') <- foreign
    mask <- .new_dibble_expression_mask(columns, groups, 2L, 'mutate()')
    saved <- mask$evaluate(rlang::quo(function() x), 1L)
    state <- get('state', environment(mask$evaluate))
    withr::defer({
        .Call(C_dtatools_arm_callback_character, foreign, function() NULL)
        mask$forget()
    })
    .Call(C_dtatools_arm_callback_character, foreign,
          function() stop('foreign names read during cleanup'))
    cleanup <- tryCatch({ mask$forget(); NULL }, error = identity)
    expect_null(cleanup)
    expect_false(state$alive)
    expect_error(saved(), 'Obsolete data mask')
    expect_length(state$generations, 0L)
    expect_length(state$current, 0L)
})

test_that('mask registries keep captured names after an input rename by reference', {
    groups <- list(rows = list(1:2), names = character(),
                   keys = tibble::new_tibble(list(), nrow = 1L), type = 'ungrouped')
    data <- dibble(x = c(10, 20))
    mask <- .new_dibble_expression_mask(.data_columns(data), groups, 2L, 'mutate()')
    withr::defer(mask$forget())
    saved <- mask$evaluate(rlang::quo(function() x), 1L)
    data.table::setnames(data, 'x', 'q')
    expect_identical(names(data), 'q')
    expect_identical(names(mask$values()), 'x')
    actual <- tryCatch(as.double(mask$evaluate(rlang::quo(x + 1), 1L)), error = identity)
    expect_identical(actual, c(11, 21))
    expect_identical(as.double(saved()), c(10, 20))
    mask$forget()
    expect_error(saved(), 'Obsolete data mask')
})

test_that('initial capture records the column names actually consumed', {
    groups <- list(rows = list(1:2), names = character(),
                   keys = tibble::new_tibble(list(), nrow = 1L), type = 'ungrouped')
    for (renamed in c('x', 'y')) {
        armed <- FALSE
        calls <- 0L
        foreign <- .Call(C_dtatools_callback_double, c(1, 2), function() {
            if (armed) {
                armed <<- FALSE
                calls <<- calls + 1L
                data.table::setnames(carrier, renamed, 'q')
            }
        }, FALSE)
        columns <- list(x = foreign, y = dta_double(c(3, 4)))
        # A real data.frame header can share the initial column-name vector.
        carrier <- structure(list(1:2, 3:4), names = names(columns),
                             class = 'data.frame', row.names = c(NA_integer_, -2L))
        armed <- TRUE
        mask <- .new_dibble_expression_mask(columns, groups, 2L, 'mutate()')
        expected_names <- if (renamed == 'x') c('x', 'y') else c('x', 'q')
        saved <- mask$evaluate(rlang::new_quosure(
            as.call(list(as.name('function'), pairlist(), as.name(expected_names[[2L]]))),
            environment()), 1L)
        expect_identical(calls, 1L)
        expect_identical(names(mask$values()), expected_names)
        expect_identical(lapply(mask$values(), as.double),
                         setNames(list(c(1, 2), c(3, 4)), expected_names))
        expect_identical(as.double(saved()), c(3, 4))
        mask$forget()
        expect_error(saved(), 'Obsolete data mask')
    }
})

test_that('initial capture registers a name repeated during capture once', {
    groups <- list(rows = list(1:2), names = character(),
                   keys = tibble::new_tibble(list(), nrow = 1L), type = 'ungrouped')
    armed <- FALSE
    foreign <- .Call(C_dtatools_callback_double, c(1, 2), function() {
        if (armed) {
            armed <<- FALSE
            data.table::setnames(carrier, 'z', 'y')
        }
    }, FALSE)
    columns <- list(x = foreign, y = dta_double(c(3, 4)), z = dta_double(c(5, 6)))
    # A real data.frame header can share the initial column-name vector.
    carrier <- structure(list(1:2, 3:4, 5:6), names = names(columns),
                         class = 'data.frame', row.names = c(NA_integer_, -2L))
    armed <- TRUE
    mask <- .new_dibble_expression_mask(columns, groups, 2L, 'mutate()')
    withr::defer(mask$forget())
    state <- get('state', environment(mask$evaluate))
    # Each consumed name keeps the column at its position. A repeated name
    # registers as add() would: first position, last column captured.
    expect_false(armed)
    expect_identical(state$names, c('x', 'y'))
    expect_identical(lapply(mask$values(), as.double), list(x = c(1, 2), y = c(5, 6)))
    expect_length(state$generations, 3L)
})

test_that("mutation can retain initial column names across caller renames", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(x = c(1, 2))
    result <- tryCatch(dplyr::mutate(data,
        y = { data.table::setnames(data, 'x', 'q'); x + 1 }, z = x + 2), error = identity)
    expect_s3_class(result, 'dibble')
    if (!inherits(result, 'error')) {
        expect_identical(names(result), c('x', 'y', 'z'))
        expect_identical(lapply(.data_columns(result), as.double),
                         list(x = c(1, 2), y = c(2, 3), z = c(3, 4)))
    }
    expect_identical(names(data), 'q')
})

test_that('public masks preserve executable nested constructor callbacks', {
    skip_if_not_installed('dplyr', '1.2.1')
    skip_if_not_installed('callr')
    for (key in c('as.name', 'force')) for (replace in c(FALSE, TRUE)) {
        observed <- callr::r(function(key, replace) {
            library(dtatools)
            loadNamespace('dplyr')
            data <- dibble(x = c(1, 2, 3))
            calls <- 0L
            target <- if (key == 'as.name') quote(as.name(sym)) else
                quote(binding(state$current[[name]], name, id))
            record <- compiler::cmpfun(function() {
                if (any(vapply(sys.calls(), identical, logical(1), target)))
                    calls <<- calls + 1L
            })
            original <- get(key, baseenv())
            if (replace) {
                replacement <- compiler::cmpfun(function(...) { record(); original(...) })
                unlockBinding(key, baseenv())
                assign(key, replacement, baseenv())
                lockBinding(key, baseenv())
                on.exit({
                    unlockBinding(key, baseenv())
                    assign(key, original, baseenv())
                    lockBinding(key, baseenv())
                }, add = TRUE)
            } else {
                trace(key, tracer = function() {
                    if (any(vapply(sys.calls(), identical, logical(1), target)))
                        calls <<- calls + 1L
                }, where = baseenv(), print = FALSE)
                on.exit(untrace(key, where = baseenv()), add = TRUE)
            }
            calls <- 0L
            result <- dplyr::mutate(data, y = x + 1)
            list(calls = calls, values = as.double(result$y))
        }, args = list(key, replace), libpath = .libPaths())
        expect_identical(observed$calls, if (key == 'as.name') 1L else 3L,
                         info = paste(key, if (replace) 'replaced' else 'traced'))
        expect_identical(observed$values, c(2, 3, 4))
    }
})

test_that('public masks preserve callbacks exposed by standard wrapper recompilation', {
    skip_if_not_installed('dplyr', '1.2.1')
    skip_if_not_installed('callr')
    for (compile in c(FALSE, TRUE)) {
        observed <- callr::r(function(compile) {
            library(dtatools)
            loadNamespace('dplyr')
            data <- dibble(x = c(1, 2, 3))
            original <- base::makeActiveBinding
            replacement <- original
            body(replacement) <- body(replacement)
            if (compile) replacement <- compiler::cmpfun(replacement,
                                                        options = list(optimize = 0L))
            unlockBinding('makeActiveBinding', baseenv())
            assign('makeActiveBinding', replacement, baseenv())
            lockBinding('makeActiveBinding', baseenv())
            on.exit({
                unlockBinding('makeActiveBinding', baseenv())
                assign('makeActiveBinding', original, baseenv())
                lockBinding('makeActiveBinding', baseenv())
            }, add = TRUE)
            calls <- 0L
            trace('is.character', tracer = function() {
                if (any(vapply(sys.calls(), identical, logical(1), quote(is.character(sym)))))
                    calls <<- calls + 1L
            }, where = baseenv(), print = FALSE)
            on.exit(untrace('is.character', where = baseenv()), add = TRUE)
            calls <- 0L
            result <- dplyr::mutate(data, y = x + 1)
            list(calls = calls, values = as.double(result$y))
        }, args = list(compile), libpath = .libPaths())
        expect_identical(observed$calls, 1L)
        expect_identical(observed$values, c(2, 3, 4))
    }
})

test_that('binding admission checks actual factory code without invoking it', {
    current <- list(x = new.env(parent = emptyenv()))
    calls <- 0L
    for (mode in c('active', 'delayed', 'replaced', 'interpreted', 'recompiled')) {
        reader <- .mask_binding_frame()
        original <- reader$binding
        if (mode == 'active') {
            rm('binding', envir = reader)
            makeActiveBinding('binding', function() { calls <<- calls + 1L; original }, reader)
        } else if (mode == 'delayed') {
            delayedAssign('binding', { calls <<- calls + 1L; original }, assign.env = reader)
        } else if (mode == 'replaced') {
            reader$binding <- function(...) { calls <<- calls + 1L; original(...) }
        } else {
            body(original) <- body(original)
            if (mode == 'recompiled') original <- compiler::cmpfun(original,
                                                        options = list(optimize = 0L))
            reader$binding <- original
        }
        expect_null(.mask_binding_attempt(current, reader = reader), info = mode)
        expect_identical(calls, 0L)
    }
    # Canonical inputs admit only on the independently established profile.
    canonical <- .mask_binding_attempt(current)
    if (.dtatools_execution_profile_expected()) {
        expect_true(is.environment(canonical))
    } else {
        expect_null(canonical)
    }
})

test_that('public masks retain executable changes to their actual local factory', {
    skip_if_not_installed('dplyr', '1.2.1')
    skip_if_not_installed('callr')
    observed <- callr::r(function() {
        library(dtatools)
        loadNamespace('dplyr')
        data <- dibble(x = c(1, 2, 3))
        calls <- 0L
        # The exit tracer changes the factory in the real call-local reader
        # before the public mutation starts evaluating its first expression.
        on.exit(untrace('.new_dibble_expression_mask', where = asNamespace('dtatools')))
        trace('.new_dibble_expression_mask', exit = function() {
            frame <- parent.frame()
            original <- get('binding', frame)
            replacement <- function(...) { calls <<- calls + 1L; original(...) }
            assign('binding', replacement, frame)
        }, where = asNamespace('dtatools'), print = FALSE)
        result <- dplyr::mutate(data, y = x + 1)
        list(calls = calls, values = as.double(result$y))
    }, libpath = .libPaths())
    expect_identical(observed$calls, 1L)
    expect_identical(observed$values, c(2, 3, 4))
})


test_that('canonical masks admit their actual local binding factory', {
    supported <- .dtatools_execution_profile_expected()
    expect_identical(!is.null(.metadata_state$dependencies), supported)
    groups <- list(rows = list(1L), keys = tibble::new_tibble(list(), nrow = 1L),
                   names = character(), type = 'ungrouped')
    mask <- .new_dibble_expression_mask(list(x = dta_double(1)), groups, 1L, 'mutate()')
    withr::defer(mask$forget())
    mask$set_group(1L)
    bindings <- parent.env(mask$helpers$get_rlang_mask())
    getter <- activeBindingFunction('x', bindings)
    # Native and R getters retain the same capture frame and reader call.
    # Probe admission separately using the actual local binding factory.
    reader <- environment(mask$evaluate)
    frame <- new.env(parent = reader)
    delayedAssign('id', state$id, eval.env = frame, assign.env = frame)
    native <- .Call(C_dtatools_try_mask_bindings, frame, reader, .mask_bindings_expected)
    if (supported) {
        expect_true(is.environment(native))
    } else {
        expect_null(native)
    }
    expect_identical(parent.env(environment(getter)), reader)
    expect_null(formals(getter))
    expect_identical(body(getter), quote(read(generation, name, id)))
    expect_identical(substitute(generation, environment(getter)), quote(state$current[[name]]))
    expect_identical(substitute(name, environment(getter)), quote(name))
    expect_identical(substitute(id, environment(getter)), quote(id))
    expect_identical(as.double(bindings$x), 1)
})


test_that('public mask admission does not add environment callbacks', {
    skip_if_not_installed('dplyr', '1.2.1')
    skip_if_not_installed('callr')
    observed <- callr::r(function() {
        library(dtatools)
        loadNamespace('dplyr')
        data <- dibble(x = c(1, 2, 3))
        calls <- c(reader = 0L, make_mask = 0L)
        trace('environment', tracer = function() {
            stack <- sys.calls()
            if (!any(vapply(stack, identical, logical(1), quote(environment())))) return()
            if (any(vapply(stack, identical, logical(1),
                           quote(.new_dibble_expression_mask(columns, groups, size, caller)))))
                calls[['reader']] <<- calls[['reader']] + 1L
            if (any(vapply(stack, identical, logical(1), quote(make_mask()))))
                calls[['make_mask']] <<- calls[['make_mask']] + 1L
        }, where = baseenv(), print = FALSE)
        on.exit(untrace('environment', where = baseenv()))
        result <- dplyr::mutate(data, y = x + 1)
        list(calls = calls, values = as.double(result$y))
    }, libpath = .libPaths())
    expect_identical(observed$calls, c(reader = 0L, make_mask = 0L))
    expect_identical(observed$values, c(2, 3, 4))
})

test_that('public masks add no predicates when their enclosing helper is interpreted', {
    skip_if_not_installed('dplyr', '1.2.1')
    skip_if_not_installed('callr')
    for (disabled in c(FALSE, TRUE)) {
        observed <- callr::r(function() {
            library(dtatools)
            loadNamespace('dplyr')
            compiler::enableJIT(0L)
            data <- dibble(g = c(1, 1, 2), x = c(1, 2, 3))
            ns <- asNamespace('dtatools')
            trace('.new_dibble_expression_mask', tracer = function() NULL,
                  where = ns, print = FALSE)
            on.exit(untrace('.new_dibble_expression_mask', where = ns), add = TRUE)
            observe <- function(target) {
                calls <- c(setup = 0L, bindings = 0L)
                trace(target, tracer = function() {
                    stack <- sys.calls()
                    for (i in seq_along(stack)) {
                        call <- stack[[i]]
                        if (i > 1L && is.call(call) && typeof(call[[1L]]) == 'symbol' &&
                            as.character(call[[1L]]) == target) {
                            caller <- stack[[i - 1L]]
                            if (is.call(caller) && typeof(caller[[1L]]) == 'symbol') {
                                name <- as.character(caller[[1L]])
                                if (name == '.new_dibble_expression_mask')
                                    calls[['setup']] <<- calls[['setup']] + 1L
                                if (name == 'make_mask')
                                    calls[['bindings']] <<- calls[['bindings']] + 1L
                            }
                        }
                    }
                }, where = baseenv(), print = FALSE)
                on.exit(untrace(target, where = baseenv()), add = TRUE)
                result <- dplyr::mutate(data, y = x + 1, .by = g)
                list(calls = calls, values = as.double(result$y))
            }
            lapply(c('is.null', 'isTRUE', 'identical'), observe)
        }, libpath = .libPaths(),
        env = c(R_DISABLE_BYTECODE = if (disabled) '1' else NA_character_))
        expect_identical(observed[[1L]]$calls, c(setup = 1L, bindings = 0L))
        expect_identical(observed[[2L]]$calls, c(setup = 0L, bindings = 0L))
        expect_identical(observed[[3L]]$calls, c(setup = 1L, bindings = 0L))
        for (result in observed) expect_identical(result$values, c(2, 3, 4))
    }
})

test_that('production mask status commits only to an absent local result binding', {
    supported <- .dtatools_execution_profile_expected()
    for (slot in c('absent', 'value', 'active', 'delayed', 'locked')) {
        context <- .mask_binding_context(list(x = new.env(parent = emptyenv())))
        probe <- new.env(parent = emptyenv())
        context$reader$probe <- probe
        context$reader$native_entry <- C_dtatools_try_mask_bindings
        context$reader$dependencies <- .mask_bindings_expected
        context$reader$slot <- slot
        context$state$callbacks <- 0L
        attempt <- eval(quote(function(id = state$id) {
            # Assign through a separate probe so complex assignment does not
            # create a local state binding in the production-like frame.
            probe$frame <- environment()
            if (slot == 'value') bindings <- 'existing'
            if (slot == 'active') makeActiveBinding('bindings', function(...) {
                state$callbacks <- state$callbacks + 1L
                stop('result binding invoked')
            }, environment())
            if (slot == 'delayed') delayedAssign('bindings', {
                state$callbacks <- state$callbacks + 1L
                stop('result binding forced')
            }, assign.env = environment())
            if (slot == 'locked') lockEnvironment(environment())
            .Call(native_entry, NULL, NULL, dependencies)
        }), context$reader)
        status <- attempt()
        expect_identical(status, supported && slot == 'absent', info = slot)
        expect_identical(context$state$callbacks, 0L, info = slot)
        if (slot == 'absent') {
            if (supported) {
                expect_true(is.environment(probe$frame$bindings))
            } else {
                expect_false(exists('bindings', probe$frame, inherits = FALSE))
            }
        } else if (slot == 'value') {
            expect_identical(probe$frame$bindings, 'existing')
        }
    }
})

test_that('public masks retain history and values bookkeeping callbacks', {
    skip_if_not_installed('dplyr', '1.2.1')
    skip_if_not_installed('callr')
    for (disabled in c(FALSE, TRUE)) {
        observed <- callr::r(function() {
            library(dtatools)
            loadNamespace('dplyr')
            compiler::enableJIT(0L)
            data <- dibble(g = c(1, 1, 2), x = c(1, 2, 3))
            ns <- asNamespace('dtatools')
            trace('.new_dibble_expression_mask', tracer = function() NULL,
                  where = ns, print = FALSE)
            on.exit(untrace('.new_dibble_expression_mask', where = ns), add = TRUE)
            observe <- function(target) {
                calls <- c(names_columns = 0L, length_columns = 0L,
                           attributes_initial = 0L, length_history = 0L, names_current = 0L)
                trace(target, tracer = function() {
                    stack <- sys.calls()
                    in_setup <- FALSE
                    for (call in stack) {
                        if (is.call(call) && identical(call[[1L]],
                                quote(.new_dibble_expression_mask))) in_setup <- TRUE
                    }
                    for (i in seq_along(stack)) {
                        call <- stack[[i]]
                        if (in_setup && identical(call, quote(names(columns))))
                            calls[['names_columns']] <<- calls[['names_columns']] + 1L
                        if (in_setup && identical(call, quote(length(columns))))
                            calls[['length_columns']] <<- calls[['length_columns']] + 1L
                        if (identical(call, quote(attributes(initial_names))))
                            calls[['attributes_initial']] <<- calls[['attributes_initial']] + 1L
                        if (identical(call, quote(length(state$generations))))
                            calls[['length_history']] <<- calls[['length_history']] + 1L
                        if (identical(call, quote(names(state$current))))
                            calls[['names_current']] <<- calls[['names_current']] + 1L
                    }
                }, where = baseenv(), print = FALSE)
                on.exit(untrace(target, where = baseenv()), add = TRUE)
                result <- dplyr::mutate(data, y = x + 1, .by = g)
                list(calls = unname(calls), values = as.double(result$y))
            }
            lapply(c('names', 'length', 'attributes'), observe)
        }, libpath = .libPaths(),
        env = c(R_DISABLE_BYTECODE = if (disabled) '1' else NA_character_))
        expect_identical(observed[[1L]]$calls, c(5L, 0L, 0L, 0L, 5L))
        # Initial capture registers its history at once; only the added
        # column reads its length.
        expect_identical(observed[[2L]]$calls, c(0L, 0L, 0L, 1L, 0L))
        expect_identical(observed[[3L]]$calls, c(0L, 0L, 0L, 0L, 0L))
        for (result in observed) expect_identical(result$values, c(2, 3, 4))
    }
})

test_that("public mask constructors see the original forced group argument", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(x = c(10, 20), g = c(1, 2))
    original <- rlang::new_data_mask
    events <- integer()
    replacement <- function(bottom, top = bottom) {
        frame <- parent.frame()
        if (exists("id", frame, inherits = FALSE)) {
            state <- get("state", parent.env(frame), inherits = FALSE)
            previous <- state$id
            state$id <- previous + 1L
            current <- get("id", frame, inherits = FALSE)
            events <<- c(events, current)
            state$id <- previous
        }
        result <- original(bottom, top)
        if (exists("current", inherits = FALSE)) result$.observed_group <- current
        result
    }
    local_mocked_bindings(new_data_mask = replacement, .package = "rlang")
    result <- dplyr::mutate(data, y = x + .observed_group, .by = g)
    expect_identical(events, c(1L, 2L))
    expect_identical(as.double(result$y), c(11, 22))
    expect_identical(as.double(data$x), c(10, 20))
})

test_that("successful nonempty native masks settle only their default group promise", {
    supported <- .dtatools_execution_profile_expected()
    current <- list(x = new.env(parent = emptyenv()))
    for (kind in c("default", "forced", "value", "locked forced", "locked value")) {
        context <- .mask_binding_context(current, 3L)
        if (kind %in% c("forced", "locked forced")) force(context$frame$id)
        if (kind %in% c("value", "locked value")) assign("id", 3L, context$frame)
        if (startsWith(kind, "locked")) lockBinding("id", context$frame)
        expression <- substitute(id, context$frame)
        bindings <- .Call(C_dtatools_try_mask_bindings, context$frame,
                          context$reader, .mask_bindings_expected)
        if (supported) {
            expect_true(is.environment(bindings), info = kind)
            expect_identical(bindings$x[[3L]], 3L, info = kind)
        } else expect_null(bindings, info = kind)
        expect_identical(substitute(id, context$frame), expression, info = kind)
        context$state$id <- 7L
        expect_identical(context$frame$id,
                         if (kind == "default" && !supported) 7L else 3L,
                         info = kind)
    }
})

test_that("empty and declined native masks leave group promises untouched", {
    supported <- .dtatools_execution_profile_expected()
    current <- list(x = new.env(parent = emptyenv()))
    for (kind in c("empty", "duplicate", "unknown expression", "locked default", "active")) {
        value <- switch(kind, empty = setNames(list(), character()),
                        duplicate = setNames(c(current, current), c("x", "x")), current)
        context <- .mask_binding_context(value, 1L)
        calls <- 0L
        if (kind == "unknown expression") delayedAssign("id", {
            calls <<- calls + 1L
            context$state$id
        }, assign.env = context$frame)
        if (kind == "locked default") lockBinding("id", context$frame)
        if (kind == "active") {
            rm("id", envir = context$frame)
            makeActiveBinding("id", function() {
                calls <<- calls + 1L
                context$state$id
            }, context$frame)
        }
        bindings <- .Call(C_dtatools_try_mask_bindings, context$frame,
                          context$reader, .mask_bindings_expected)
        expect_identical(calls, 0L, info = kind)
        if (kind == "empty" && supported) expect_true(is.environment(bindings)) else
            expect_null(bindings, info = kind)
        context$state$id <- 7L
        expect_identical(context$frame$id, 7L, info = kind)
    }
})

test_that("public mask constructors see the original final loop name", {
    skip_if_not_installed("dplyr", "1.2.1")
    invisible(loadNamespace("dplyr"))
    original <- rlang::new_data_mask
    observations <- list()
    replacement <- function(bottom, top = bottom) {
        frame <- parent.frame()
        is_mask <- exists("id", frame, inherits = FALSE)
        if (is_mask) {
            present <- exists("name", frame, inherits = FALSE)
            name <- if (present) get("name", frame, inherits = FALSE) else "missing"
            observations[[length(observations) + 1L]] <<- list(present = present, name = name)
        }
        result <- original(bottom, top)
        if (is_mask) result$.observed_name <- if (is.null(name)) "empty" else name
        result
    }
    local_mocked_bindings(new_data_mask = replacement, .package = "rlang")
    for (empty in c(FALSE, TRUE)) {
        data <- if (empty) as_dibble(tibble::new_tibble(list(), nrow = 2L)) else
            dibble(x = c(1, 2), zz = c(3, 4))
        observations <- list()
        result <- dplyr::mutate(data, y = .observed_name)
        expect_identical(as.character(result$y), rep(if (empty) "empty" else "zz", 2L))
        expect_identical(observations, list(list(present = TRUE,
                                               name = if (empty) NULL else "zz")))
    }
})

test_that("native masks preserve loop names and decline unsafe name bindings", {
    supported <- .dtatools_execution_profile_expected()
    for (empty in c(FALSE, TRUE)) for (slot in c("absent", "value", "forced", "active",
                                               "delayed", "locked", "environment locked")) {
        current <- if (empty) setNames(list(), character()) else
            list(x = new.env(parent = emptyenv()), zz = new.env(parent = emptyenv()))
        context <- .mask_binding_context(current, 3L)
        calls <- 0L
        if (slot %in% c("value", "locked")) assign("name", "old", context$frame)
        if (slot == "forced") {
            delayedAssign("name", "old", assign.env = context$frame)
            force(context$frame$name)
        }
        if (slot == "active") makeActiveBinding("name", function(...) {
            calls <<- calls + 1L
            stop("loop name binding invoked")
        }, context$frame)
        if (slot == "delayed") delayedAssign("name", {
            calls <<- calls + 1L
            stop("loop name promise forced")
        }, assign.env = context$frame)
        if (slot == "locked") lockBinding("name", context$frame)
        if (slot == "environment locked") lockEnvironment(context$frame)
        bindings <- .Call(C_dtatools_try_mask_bindings, context$frame,
                          context$reader, .mask_bindings_expected)
        admitted <- supported && slot %in% c("absent", "value", "forced")
        expect_identical(calls, 0L, info = paste(empty, slot))
        if (admitted) {
            expect_true(is.environment(bindings), info = paste(empty, slot))
            expect_true(exists("name", context$frame, inherits = FALSE))
            expect_identical(context$frame$name, if (empty) NULL else "zz")
        } else {
            expect_null(bindings, info = paste(empty, slot))
            if (slot %in% c("value", "forced", "locked"))
                expect_identical(context$frame$name, "old")
        }
        context$state$id <- 7L
        expect_identical(context$frame$id, if (admitted && !empty) 3L else 7L)
    }
})
