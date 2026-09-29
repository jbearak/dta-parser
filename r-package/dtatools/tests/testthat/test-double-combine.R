.combine_attempt <- function(pieces, indices = NULL) {
    .Call(C_dtatools_try_combine_double, pieces, indices, vctrs::list_unchop,
          .double_combine_state$dependencies, .metadata_state$dependencies)
}
.combine_bits <- function(value) writeBin(as.double(value), raw(), size = 8L)
.combine_profile_expected <- function() {
    identical(as.character(getNamespaceVersion('vctrs')), '0.7.3') &&
        identical(as.character(getNamespaceVersion('rlang')), '1.3.0') &&
        .dtatools_execution_profile_expected()
}
.combine_profile_result <- function(pieces, indices = NULL,
                                    native_expected = .combine_profile_expected()) {
    native <- .combine_attempt(pieces, indices)
    if (native_expected) {
        expect_false(is.null(native))
        native
    } else {
        expect_null(native)
        if (is.null(indices)) .combine_dta_double(pieces) else
            .combine_dta_double_indexed(pieces, list(rows = indices))
    }
}
.combine_warm <- function() {
    pieces <- list(dta_double(c(1, 2)), dta_double(c(3, 4)))
    for (i in 1:3) .combine_dta_double(pieces)
    pieces
}
.combine_with_method <- function(generic, class, method, code, namespace = 'vctrs') {
    ns <- asNamespace(namespace)
    table <- get('.__S3MethodsTable__.', envir = ns)
    key <- paste(generic, class, sep = '.')
    had <- exists(key, envir = table, inherits = FALSE)
    old <- if (had) get(key, envir = table, inherits = FALSE)
    on.exit(if (had) assign(key, old, envir = table) else rm(list = key, envir = table))
    registerS3method(generic, class, method, envir = ns)
    code()
}

test_that('double combination preserves bytes, order and independent backing', {
    .combine_warm()
    values <- c(0, -0, .Machine$double.xmin / 2, .Machine$double.xmax / 2,
                -.Machine$double.xmax / 2, NA_real_, tagged_missing(letters),
                -tagged_missing('a'))
    pieces <- list(dta_double(values[seq_len(7)]), dta_double(double()),
                   dta_double(values[-seq_len(7)]))
    expected <- vctrs::list_unchop(pieces)
    actual <- .combine_profile_result(pieces)
    expect_identical(.combine_bits(actual), .combine_bits(expected))
    expect_identical(attributes(actual), attributes(expected))
    order <- rev(seq_along(values))
    indices <- list(order[seq_len(7)], integer(), order[-seq_len(7)])
    indexed <- .combine_profile_result(pieces, indices)
    expect_identical(.combine_bits(indexed),
                     .combine_bits(vctrs::list_unchop(pieces, indices = indices)))
    expect_identical(attributes(indexed), attributes(expected))
    source_pointer <- .Call(C_dtatools_owned_pointer, pieces[[1]], TRUE)
    .Call(C_dtatools_owned_pointer_write, source_pointer, 1L, 91)
    expect_identical(.combine_bits(actual), .combine_bits(expected))
    result_pointer <- .Call(C_dtatools_owned_pointer, actual, TRUE)
    .Call(C_dtatools_owned_pointer_write, result_pointer, 2L, 92)
    expect_identical(as.double(pieces[[1]])[1:2], c(91, -0))
    expect_identical(as.double(actual)[1:2], c(0, 92))
    expect_identical(as.double(.combine_profile_result(list(pieces[[1]], pieces[[1]]))),
                     rep(as.double(pieces[[1]]), 2L))
    empty <- .combine_profile_result(list(dta_double(double()), dta_double(double())))
    expect_identical(as.double(empty), double())
    expect_identical(attributes(empty), attributes(dta_double(double())))
})

test_that('double combination declines unsupported shapes before foreign reads', {
    pieces <- .combine_warm()
    reads <- 0L
    foreign <- .Call(C_dtatools_callback_double, c(5, 6), function() {
        reads <<- reads + 1L
    }, FALSE)
    attr(foreign, 'stata.storage') <- 'double'
    class(foreign) <- .dta_storage_class('double')
    reads <- 0L
    before <- .Call(C_dtatools_owned_info, pieces[[1]])
    expect_null(.combine_attempt(c(pieces, list(foreign))))
    expect_identical(reads, 0L)
    expect_identical(.Call(C_dtatools_owned_info, pieces[[1]]), before)
    named <- pieces[[2]]; names(named) <- c('a', 'b')
    labelled <- pieces[[2]]; attr(labelled, 'label') <- 'values'
    subclass <- pieces[[2]]; class(subclass) <- c('custom', class(subclass))
    for (last in list(named, labelled, subclass, dta_int(c(3, 4)), c(3, 4), NULL)) {
        expect_null(.combine_attempt(list(pieces[[1]], last)))
    }
    for (indices in list(list(c(1L, 1L), c(3L, 4L)),
                        list(c(0L, 2L), c(3L, 4L)),
                        list(c(NA_integer_, 2L), c(3L, 4L)),
                        list(c(1L, 2L), c(3L, 5L)),
                        list(1L, c(2L, 3L, 4L)),
                        structure(list(c(1L, 2L), c(3L, 4L)), class = 'custom'))) {
        expect_null(.combine_attempt(pieces, indices))
    }
})

test_that('strict combination leaves invalid-value diagnostics to vctrs', {
    pieces <- .combine_warm()
    invalid_tag <- readBin(as.raw(c(0xa2, 0x07, 0, 0, 0x41, 0, 0xf0, 0x7f)),
                           'double', n = 1L, size = 8L, endian = 'little')
    message <- function(code) tryCatch({force(code); NULL}, error = conditionMessage)
    for (value in list(NaN, Inf, -Inf, .Machine$double.xmax, invalid_tag)) {
        invalid <- structure(value, stata.storage = 'double',
                             class = .dta_storage_class('double'))
        input <- c(pieces, list(invalid))
        expect_null(.combine_attempt(input))
        expect_identical(message(.combine_dta_double(input)),
                         message(vctrs::list_unchop(input)))
    }
    withr::local_options(vctrs.no_guessing = TRUE)
    expect_null(.combine_attempt(pieces))
    expect_identical(message(.combine_dta_double(pieces)),
                     message(vctrs::list_unchop(pieces)))
})

test_that('combination preserves registered vctrs callbacks without speculative calls', {
    pieces <- .combine_warm()
    specifications <- list(
        c('vec_ptype2', 'dta_numeric.dta_numeric'),
        c('vec_cast', 'dta_numeric.dta_numeric'),
        c('vec_proxy', 'dta_numeric'), c('vec_restore', 'dta_numeric'))
    for (specification in specifications) {
        generic <- specification[[1]]; class <- specification[[2]]
        original <- get(paste(generic, class, sep = '.'), asNamespace('dtatools'))
        events <- 0L
        method <- function(...) {events <<- events + 1L; original(...)}
        .combine_with_method(generic, class, method, function() {
            expect_null(.combine_attempt(pieces))
            expect_identical(events, 0L)
            expected <- vctrs::list_unchop(pieces)
            expected_events <- events; events <<- 0L
            actual <- .combine_dta_double(pieces)
            expect_identical(events, expected_events)
            expect_gt(events, 0L)
            expect_identical(.combine_bits(actual), .combine_bits(expected))
            expect_identical(attributes(actual), attributes(expected))
        })
    }
})

test_that('combination retains active and delayed global pair-method lookup', {
    pieces <- .combine_warm()
    key <- 'vec_ptype2.dta_numeric.dta_numeric'
    original <- get(key, asNamespace('dtatools'))
    had <- exists(key, .GlobalEnv, inherits = FALSE)
    old <- if (had) get(key, .GlobalEnv, inherits = FALSE)
    if (had) rm(list = key, envir = .GlobalEnv)
    withr::defer({
        if (exists(key, .GlobalEnv, inherits = FALSE)) rm(list = key, envir = .GlobalEnv)
        if (had) assign(key, old, .GlobalEnv)
    })
    for (active in c(TRUE, FALSE)) {
        events <- 0L
        read_method <- function() {events <<- events + 1L; original}
        if (active) makeActiveBinding(key, read_method, .GlobalEnv) else
            delayedAssign(key, read_method(), eval.env = environment(),
                          assign.env = .GlobalEnv)
        expect_null(.combine_attempt(pieces))
        expect_identical(events, 0L)
        result <- .combine_dta_double(pieces)
        expect_gt(events, 0L)
        expect_identical(as.double(result), c(1, 2, 3, 4))
        rm(list = key, envir = .GlobalEnv)
    }
})

test_that('combination calls a replaced external combiner once on fallback', {
    pieces <- .combine_warm()
    calls <- list()
    original <- vctrs::list_unchop
    local_mocked_bindings(list_unchop = function(x, ...) {
        calls[[length(calls) + 1L]] <<- list(...)
        original(x, ...)
    }, .package = 'vctrs')
    expect_identical(as.double(.combine_dta_double(pieces)), c(1, 2, 3, 4))
    expect_identical(calls, list(list()))
    indices <- list(c(4L, 2L), c(3L, 1L))
    expect_identical(as.double(.combine_dta_double_indexed(pieces, list(rows = indices))), c(4, 2, 3, 1))
    expect_identical(calls[[2L]], list(indices = indices))
})

test_that('combination retains strict-validator trace callbacks', {
    withr::local_options(dtatools.generate_type = 'double')
    pieces <- .combine_warm()
    for (i in 1:3) gen(dibble(x = c(1, 2, 3, 4), g = c(1, 1, 2, 2)),
                       y = x + 1, by = g)
    data <- dibble(x = c(1, 2, 3, 4), g = c(1, 1, 2, 2))
    calls <- 0L
    trace('utf8ToInt', tracer = function() { calls <<- calls + 1L },
          where = baseenv(), print = FALSE)
    observed <- tryCatch({
        declined <- .combine_attempt(pieces)
        speculative <- calls
        calls <- 0L
        expected <- vctrs::list_unchop(pieces)
        expected_calls <- calls
        calls <- 0L
        actual <- .combine_dta_double(pieces)
        actual_calls <- calls
        calls <- 0L
        public <- gen(data, y = x + 1, by = g)
        list(declined = declined, speculative = speculative,
             expected = expected, expected_calls = expected_calls,
             actual = actual, actual_calls = actual_calls,
             public = public, public_calls = calls)
    }, finally = untrace('utf8ToInt', where = baseenv()))
    expect_null(observed$declined)
    expect_identical(observed$speculative, 0L)
    expect_gt(observed$expected_calls, 0L)
    expect_identical(observed$actual_calls, observed$expected_calls)
    expect_identical(.combine_bits(observed$actual), .combine_bits(observed$expected))
    expect_identical(observed$public_calls, 2L)
    expect_identical(as.double(observed$public$y), c(2, 3, 4, 5))
})

test_that("combination retains registered character methods used by metadata", {
    pieces <- .combine_warm()
    calls <- 0L
    method <- function(x, ...) {
        calls <<- calls + 1L
        base::unique.default(x, ...)
    }
    .combine_with_method("unique", "character", method, function() {
        declined <- .combine_attempt(pieces)
        speculative <- calls
        calls <<- 0L
        expected <- vctrs::list_unchop(pieces)
        expected_calls <- calls
        calls <<- 0L
        actual <- .combine_dta_double(pieces)
        actual_calls <- calls
        expect_null(declined)
        expect_identical(speculative, 0L)
        expect_gt(expected_calls, 0L)
        expect_identical(actual_calls, expected_calls)
        expect_identical(.combine_bits(actual), .combine_bits(expected))
        expect_identical(attributes(actual), attributes(expected))
    }, namespace = "base")
})

test_that("real grouped generation uses one combination payload", {
    withr::local_options(dtatools.generate_type = 'double')
    .combine_warm()
    data <- dibble(x = rep(c(1, 4, 2, 8), 25), g = rep(1:10, 10))
    .Call(C_dtatools_native_copy_stats, TRUE)
    result <- gen(data, y = x + 1, by = g)
    counters <- .Call(C_dtatools_native_copy_stats, FALSE)
    native_expected <- .combine_profile_expected()
    expect_identical(as.double(result$y), rep(c(2, 5, 3, 9), 25))
    expect_identical(counters[['combine_copied_payload_bytes']], if (native_expected) 800 else 0)
    expect_identical(counters[['combine_root_r_bytes']],
                     if (native_expected) 10 * .Machine$sizeof.pointer else 0)
    expect_identical(counters[['combine_partition_r_bytes']], 0)
})

test_that("real grouped dplyr mutation uses one combination payload", {
    skip_if_not_installed("dplyr", "1.2.1")
    withr::local_options(dtatools.generate_type = 'double')
    .combine_warm()
    data <- dibble(x = rep(c(1, 4, 2, 8), 25), g = rep(1:10, 10))
    .Call(C_dtatools_native_copy_stats, TRUE)
    result <- dplyr::mutate(data, y = x + 1, .by = g)
    counters <- .Call(C_dtatools_native_copy_stats, FALSE)
    native_expected <- .combine_profile_expected()
    expect_identical(as.double(result$y), rep(c(2, 5, 3, 9), 25))
    expect_identical(counters[['combine_copied_payload_bytes']], if (native_expected) 800 else 0)
    expect_identical(counters[['combine_root_r_bytes']],
                     if (native_expected) 10 * .Machine$sizeof.pointer else 0)
    expect_identical(counters[['combine_partition_r_bytes']], if (native_expected) 13 else 0)
})

test_that('combination respects reachable prototype and finalise methods', {
    pieces <- .combine_warm()
    for (generic in c('vec_ptype', 'vec_ptype_finalise')) {
        for (class in c('dta_numeric', 'dta_double', 'vctrs_vctr', 'double')) {
            events <- 0L
            method <- if (generic == 'vec_ptype') function(x, ...) {
                events <<- events + 1L; dta_double(double())
            } else function(x, ...) {events <<- events + 1L; x}
            .combine_with_method(generic, class, method, function() {
                expect_null(.combine_attempt(pieces))
                expect_identical(events, 0L)
                expected <- vctrs::list_unchop(pieces)
                expected_events <- events; events <<- 0L
                actual <- .combine_dta_double(pieces)
                expect_identical(events, expected_events)
                expect_identical(.combine_bits(actual), .combine_bits(expected))
                expect_identical(attributes(actual), attributes(expected))
            })
        }
    }
})

test_that('combination respects names, dimensions and name assignment methods', {
    pieces <- .combine_warm()
    for (generic in c('names', 'dim', 'names<-')) {
        for (class in c('dta_numeric', 'dta_double', 'vctrs_vctr', 'double', 'default')) {
            events <- 0L
            method <- if (generic == 'names<-') function(x, value) {
                events <<- events + 1L; if (is.null(value)) x else NextMethod()
            } else function(x) {events <<- events + 1L; NULL}
            .combine_with_method(generic, class, method, function() {
                expect_null(.combine_attempt(pieces))
                expect_identical(events, 0L)
                expected <- vctrs::list_unchop(pieces)
                expected_events <- events; events <<- 0L
                actual <- .combine_dta_double(pieces)
                expect_identical(events, expected_events)
                expect_identical(.combine_bits(actual), .combine_bits(expected))
                expect_identical(attributes(actual), attributes(expected))
            }, namespace = 'base')
        }
    }
})

test_that('combination retains the namespace numeric coercion method', {
    pieces <- .combine_warm()
    original <- as.double.dta_numeric
    events <- 0L
    local_mocked_bindings(as.double.dta_numeric = function(x, ...) {
        events <<- events + 1L; original(x, ...)
    }, .package = 'dtatools')
    expect_null(.combine_attempt(pieces))
    expect_identical(events, 0L)
    expected <- vctrs::list_unchop(pieces)
    expected_events <- events; events <- 0L
    actual <- .combine_dta_double(pieces)
    expect_identical(events, expected_events)
    expect_gt(events, 0L)
    expect_identical(.combine_bits(actual), .combine_bits(expected))
})

test_that("fresh public grouped generation reaches combination without test-only warming", {
    observed <- .dtatools_child_r('double-combine-clean-session', function() {
        library(dtatools)
        options(dtatools.generate_type = 'double')
        copies <- numeric()
        values <- list()
        for (i in 1:2) {
            data <- dibble(x = rep(c(1, 4, 2, 8), 25), g = rep(1:10, 10))
            .Call(dtatools:::C_dtatools_native_copy_stats, TRUE)
            result <- gen(data, y = x + 1, by = g)
            copies <- c(copies, .Call(dtatools:::C_dtatools_native_copy_stats, FALSE)[['combine_copied_payload_bytes']])
            values[[i]] <- as.double(result$y)
        }
        list(copies = copies, values = values, dplyr_loaded = isNamespaceLoaded('dplyr'))
    }, libpath = .libPaths())
    native_expected <- .combine_profile_expected()
    expect_identical(observed$copies[[2L]], if (native_expected) 800 else 0)
    expect_true(observed$copies[[1]] %in% if (native_expected) c(0, 800) else 0)
    expect_identical(observed$values, rep(list(rep(c(2, 5, 3, 9), 25)), 2L))
    expect_false(observed$dplyr_loaded)
})

test_that("fresh public grouped dplyr calls reach combination without test-only warming", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("callr")
    observed <- callr::r(function() {
        library(dtatools)
        options(dtatools.generate_type = 'double')
        copies <- numeric()
        values <- list()
        for (i in 1:3) {
            data <- dibble(x = rep(c(1, 4, 2, 8), 25), g = rep(1:10, 10))
            .Call(dtatools:::C_dtatools_native_copy_stats, TRUE)
            result <- if (i < 3L) gen(data, y = x + 1, by = g) else
                dplyr::mutate(data, y = x + 1, .by = g)
            copies <- c(copies, .Call(dtatools:::C_dtatools_native_copy_stats, FALSE)[['combine_copied_payload_bytes']])
            values[[i]] <- as.double(result$y)
        }
        list(copies = copies, values = values)
    }, libpath = .libPaths())
    native_expected <- .combine_profile_expected()
    expect_identical(observed$copies[2:3], if (native_expected) c(800, 800) else c(0, 0))
    expect_true(observed$copies[[1]] %in% if (native_expected) c(0, 800) else 0)
    expect_identical(observed$values, rep(list(rep(c(2, 5, 3, 9), 25)), 3L))
})

test_that('ordinary canonical sources copy once and unsupported profiles decline', {
    .combine_warm()
    ordinary <- structure(c(7, 8), stata.storage = 'double',
                          class = .dta_storage_class('double'))
    expect_false(.is_altrep(ordinary))
    result <- .combine_profile_result(list(ordinary, dta_double(c(9, 10))))
    expect_identical(as.double(result), c(7, 8, 9, 10))
    for (dependencies in list(NULL, list(), .double_combine_expected)) {
        expect_null(.Call(C_dtatools_try_combine_double, list(ordinary), NULL,
                          vctrs::list_unchop, dependencies, .metadata_state$dependencies))
    }
    changed <- .double_combine_expected
    changed[[7L]] <- 'unsupported-vctrs-profile'
    expect_null(.Call(C_dtatools_double_combine_dependencies, changed))
})

test_that('disabled combination profiles retain public fallback and isolation', {
    .combine_warm()
    dependencies <- .double_combine_state$dependencies
    with_disabled_profile <- function(code) {
        on.exit(.double_combine_state$dependencies <- dependencies)
        .double_combine_state$dependencies <- NULL
        force(code)
    }
    with_disabled_profile({
        pieces <- list(dta_double(c(-0, 1, tagged_missing('a'))),
                       dta_double(c(NA_real_, 2, tagged_missing('z'))))
        indices <- list(c(6L, 2L, 4L), c(1L, 5L, 3L))
        expected <- vctrs::list_unchop(pieces)
        expected_indexed <- vctrs::list_unchop(pieces, indices = indices)
        .Call(C_dtatools_native_copy_stats, TRUE)
        actual <- .combine_profile_result(pieces, native_expected = FALSE)
        indexed <- .combine_profile_result(pieces, indices, native_expected = FALSE)
        counters <- .Call(C_dtatools_native_copy_stats, FALSE)
        expect_identical(.combine_bits(actual), .combine_bits(expected))
        expect_identical(attributes(actual), attributes(expected))
        expect_identical(.combine_bits(indexed), .combine_bits(expected_indexed))
        expect_identical(attributes(indexed), attributes(expected_indexed))
        expect_identical(unname(counters[c('combine_copied_payload_bytes',
            'combine_root_r_bytes', 'combine_partition_r_bytes')]), c(0, 0, 0))
        source_pointer <- .Call(C_dtatools_owned_pointer, pieces[[1L]], TRUE)
        .Call(C_dtatools_owned_pointer_write, source_pointer, 1L, 91)
        expect_identical(.combine_bits(actual), .combine_bits(expected))
        expect_identical(.combine_bits(indexed), .combine_bits(expected_indexed))
        result_pointer <- .Call(C_dtatools_owned_pointer, actual, TRUE)
        .Call(C_dtatools_owned_pointer_write, result_pointer, 2L, 92)
        expect_identical(as.double(pieces[[1L]])[1:2], c(91, 1))
        expect_identical(as.double(actual)[1:2], c(-0, 92))

        data <- dibble(x = c(10, 20, 30, 40), g = c(1L, 2L, 1L, 2L))
        .Call(C_dtatools_native_copy_stats, TRUE)
        generated <- gen(data, y = x + 1, by = g)
        counters <- .Call(C_dtatools_native_copy_stats, FALSE)
        expect_identical(as.double(generated$y), c(11, 21, 31, 41))
        expect_identical(dta_storage_type(generated$y), 'double')
        expect_identical(as.double(generated$x), c(10, 20, 30, 40))
        expect_identical(counters[['combine_copied_payload_bytes']], 0)
    })
    expect_identical(.double_combine_state$dependencies, dependencies)
})

test_that("combination fallback preserves public generation error attribution", {
    capture <- function(expr) tryCatch({force(expr); NULL}, error = identity)
    pieces <- list(dta_double(1), factor('a'))
    expected <- capture(vctrs::list_unchop(pieces))
    gathered <- capture(.mutation_gather_values(pieces))
    expect_identical(conditionMessage(gathered), conditionMessage(expected))
    expect_identical(conditionCall(gathered), conditionCall(expected))
    expect_identical(class(gathered), class(expected))
    data <- dibble(x = 1:4, g = c(1, 1, 2, 2))
    generated <- capture(gen(data, y = if (g[1] == 1) dta_double(1) else factor('a'), by = g))
    expect_identical(conditionMessage(generated), conditionMessage(expected))
    expect_identical(conditionCall(generated), conditionCall(expected))
})

test_that("combination fallback preserves public dplyr error attribution", {
    skip_if_not_installed("dplyr", "1.2.1")
    capture <- function(expr) tryCatch({force(expr); NULL}, error = identity)
    pieces <- list(dta_double(1), factor('a'))
    expected <- capture(vctrs::list_unchop(pieces))
    data <- dibble(x = 1:4, g = c(1, 1, 2, 2))
    mutated <- capture(dplyr::mutate(data,
        y = if (g[1] == 1) dta_double(1) else factor('a'), .by = g))
    expect_identical(conditionMessage(mutated$parent), conditionMessage(expected))
    expect_identical(conditionCall(mutated$parent),
                     quote(vctrs::list_unchop(chunks, indices = mask$rows)))
    expect_match(conditionMessage(mutated), 'Caused by error in `vctrs::list_unchop()`',
                 fixed = TRUE)
})

test_that('combination fallback preserves expressions and resolves operands once', {
    local_mocked_bindings(list_unchop = function(x, ...) {
        list(call = sys.call(), expressions = substitute(list(x, ...)),
             value = x, dots = list(...))
    }, .package = 'vctrs')
    record <- .combine_dta_double(list(1, 2))
    expect_identical(record$call, quote(vctrs::list_unchop(pieces)))
    expect_identical(record$expressions, quote(list(pieces)))
    expect_identical(record$value, list(1, 2))
    expect_identical(record$dots, list())
    reads <- 0L
    lookup_environment <- new.env(parent = asNamespace('dtatools'))
    lookup <- get('::', baseenv())
    makeActiveBinding('::', function() {reads <<- reads + 1L; lookup}, lookup_environment)
    adapter <- .combine_dta_double_indexed
    environment(adapter) <- lookup_environment
    piece_reads <- index_reads <- 0L
    record <- adapter({piece_reads <- piece_reads + 1L; list(1, 2)},
                      {index_reads <- index_reads + 1L; list(rows = list(2L, 1L))})
    expect_identical(reads, 1L)
    expect_identical(piece_reads, 1L)
    expect_identical(index_reads, 1L)
    expect_identical(record$call, quote(vctrs::list_unchop(chunks, indices = mask$rows)))
    expect_identical(record$expressions, quote(list(chunks, indices = mask$rows)))
    expect_identical(record$value, list(1, 2))
    expect_identical(record$dots, list(indices = list(2L, 1L)))
})

test_that('combination retains executable callbacks throughout its successful helper graph', {
    pieces <- .combine_warm()
    package_helpers <- c(
        '.declared_dta_storage', '.dta_promote', '.dta_common_ptype', '.dta_ptype',
        '.reconcile_dta_metadata', '.restore_dta_metadata', '.dta_classes_from',
        '.dta_combine_value_labels', '.reconcile_dta_metadata_attributes',
        '.apply_haven_labelled_class', '.dta_snapshot', '.cast_to_dta',
        '.compact_dta_storage_matches', '.construct_dta_numeric', '.metadata_copy',
        '.repair_data_table_container', '.dta_storage_class', '.tab_missing_codes',
        '.encode_dta_temporal', '.invalid_dta_observed'
    )
    cases <- c(
        lapply(package_helpers, function(name) c('dtatools', name)),
        lapply(c('double', 'is.factor', 'paste0', 'NextMethod', 'environment'),
               function(name) c('base', name)),
        list(c('vctrs', 'names_repair_missing'), c('rlang', 'check_dots_empty0'),
             c('rlang', 'current_env'))
    )
    check <- function(specification) {
        where <- asNamespace(specification[[1L]])
        target <- specification[[2L]]
        events <- 0L
        trace(target, tracer = function() { events <<- events + 1L },
              where = where, print = FALSE)
        on.exit(untrace(target, where = where))
        events <- 0L
        declined <- .combine_attempt(pieces)
        speculative_events <- events
        events <- 0L
        expected <- vctrs::list_unchop(pieces)
        expected_events <- events
        events <- 0L
        actual <- .combine_dta_double(pieces)
        actual_events <- events
        expect_null(declined, info = target)
        expect_identical(speculative_events, 0L, info = target)
        expect_gt(expected_events, 0L, label = target)
        expect_identical(actual_events, expected_events, info = target)
        expect_identical(.combine_bits(actual), .combine_bits(expected), info = target)
        expect_identical(attributes(actual), attributes(expected), info = target)
    }
    for (specification in cases) check(specification)
})

test_that('compilation changes cannot hide callbacks below package combination helpers', {
    pieces <- .combine_warm()
    ns <- asNamespace('dtatools')
    original <- get('.repair_data_table_container', ns)
    interpreted <- original
    body(interpreted) <- body(interpreted)
    variants <- list(interpreted, compiler::cmpfun(interpreted, options = list(optimize = 0L)))
    for (variant in variants) {
        local_mocked_bindings(.repair_data_table_container = variant, .package = 'dtatools')
        expect_null(.combine_attempt(pieces))
        expect_identical(.combine_bits(.combine_dta_double(pieces)),
                         .combine_bits(vctrs::list_unchop(pieces)))
    }
})

test_that('ordinary external helper compiler forms preserve callback admission', {
    pieces <- .combine_warm()
    original <- vctrs:::names_repair_missing
    body(original) <- body(original)
    for (variant in list(original, compiler::cmpfun(original, options = list(optimize = 0L)))) {
        local_mocked_bindings(names_repair_missing = variant, .package = 'vctrs')
        # All reached operations of this NULL-names branch are explicitly
        # qualified. Source references or ordinary compiler modes need no
        # disassembly normalization and should not disable the clean profile.
        .combine_profile_result(pieces)
    }
})

test_that('combination adds no predicate callbacks before its original fallback calls', {
    skip_if_not_installed('callr')
    observed <- .dtatools_child_r('combination-predicate-prefix', function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0L)
        ns <- asNamespace('dtatools')
        pieces <- list(dta_double(c(1, 2)), dta_double(c(3, 4)))
        indices <- list(c(4L, 2L), c(3L, 1L))
        mask <- list(rows = indices)
        invisible(dtatools:::.combine_dta_double(pieces))
        invisible(dtatools:::.combine_dta_double_indexed(pieces, mask))
        rows <- list()
        for (helper_traced in c(FALSE, TRUE)) {
            if (helper_traced) {
                trace('.combine_dta_double', tracer = function() NULL,
                      where = ns, print = FALSE)
                trace('.combine_dta_double_indexed', tracer = function() NULL,
                      where = ns, print = FALSE)
            }
            for (indexed in c(FALSE, TRUE)) {
                calls <- 0L
                trace('is.null', tracer = function() {calls <<- calls + 1L},
                      where = baseenv(), print = FALSE)
                record <- tryCatch({
                    calls <- 0L
                    expected <- if (indexed) {
                        vctrs::list_unchop(pieces, indices = indices)
                    } else vctrs::list_unchop(pieces)
                    expected_calls <- calls
                    calls <- 0L
                    actual <- if (indexed) {
                        dtatools:::.combine_dta_double_indexed(pieces, mask)
                    } else dtatools:::.combine_dta_double(pieces)
                    actual_calls <- calls
                    list(expected = expected, actual = actual,
                         expected_calls = expected_calls, actual_calls = actual_calls)
                }, finally = untrace('is.null', where = baseenv()))
                rows[[length(rows) + 1L]] <- list(
                    expected_calls = record$expected_calls,
                    actual_calls = record$actual_calls,
                    expected = as.double(record$expected),
                    actual = as.double(record$actual),
                    expected_attributes = attributes(record$expected),
                    actual_attributes = attributes(record$actual)
                )
            }
            if (helper_traced) {
                untrace('.combine_dta_double', where = ns)
                untrace('.combine_dta_double_indexed', where = ns)
            }
        }
        rows
    }, args = list(.libPaths()))
    for (record in observed) {
        expect_identical(record$actual_calls, record$expected_calls)
        expect_identical(record$actual, record$expected)
        expect_identical(record$actual_attributes, record$expected_attributes)
    }
})

test_that("combination callbacks run before unresolved operand promises", {
    calls <- character()
    trace("list_unchop", tracer = function() {
        calls <<- c(calls, "combiner")
        stop("combiner callback first")
    }, where = asNamespace("vctrs"), print = FALSE)
    on.exit(untrace("list_unchop", where = asNamespace("vctrs")), add = TRUE)
    expect_error(.mutation_gather_values({
        calls <- c(calls, "pieces")
        stop("pieces forced first")
    }), "combiner callback first", fixed = TRUE)
    expect_identical(calls, "combiner")
    calls <- character()
    expect_error(.combine_dta_double_indexed({
        calls <- c(calls, "chunks")
        stop("chunks forced first")
    }, {
        calls <- c(calls, "mask")
        stop("mask forced first")
    }), "combiner callback first", fixed = TRUE)
    expect_identical(calls, "combiner")
})

test_that("replaced combiners receive the original lazy argument expressions", {
    local_mocked_bindings(list_unchop = function(x, ...) {
        list(call = sys.call(), expressions = substitute(list(x, ...)))
    }, .package = "vctrs")
    unindexed <- .combine_dta_double(stop("unused pieces"))
    indexed <- .combine_dta_double_indexed(stop("unused chunks"), stop("unused mask"))
    expect_identical(unindexed$call, quote(vctrs::list_unchop(pieces)))
    expect_identical(unindexed$expressions, quote(list(pieces)))
    expect_identical(indexed$call, quote(vctrs::list_unchop(chunks, indices = mask$rows)))
    expect_identical(indexed$expressions, quote(list(chunks, indices = mask$rows)))
})

test_that("indexed combination reads active rows once after combiner entry", {
    pieces <- list(dta_double(c(1, 2)), dta_double(c(3, 4)))
    events <- character()
    mask <- new.env(parent = emptyenv())
    makeActiveBinding("rows", function() {
        events <<- c(events, "rows")
        list(c(4L, 2L), c(3L, 1L))
    }, mask)
    trace("list_unchop", tracer = function() events <<- c(events, "combiner"),
          where = asNamespace("vctrs"), print = FALSE)
    on.exit(untrace("list_unchop", where = asNamespace("vctrs")), add = TRUE)
    expected <- vctrs::list_unchop(pieces, indices = mask$rows)
    expected_events <- events
    events <- character()
    actual <- .combine_dta_double_indexed(pieces, mask)
    expect_identical(events, expected_events)
    expect_identical(events, c("combiner", "rows"))
    expect_identical(actual, expected)
})

test_that("interpreted public combination preserves mask row callback order", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("callr")
    observed <- callr::r(function() {
        library(dtatools)
        loadNamespace("dplyr")
        compiler::enableJIT(0L)
        data <- dibble(g = c(1, 1, 2, 2), x = c(1, 2, 3, 4))
        events <- character()
        trace("list_unchop", tracer = function() events <<- c(events, "combiner"),
              where = asNamespace("vctrs"), print = FALSE)
        on.exit(untrace("list_unchop", where = asNamespace("vctrs")), add = TRUE)
        original <- .Primitive("$")
        replacement <- function(x, name) {
            if (identical(substitute(x), quote(mask)) &&
                identical(substitute(name), quote(rows)))
                events <<- c(events, "mask$rows")
            do.call(original, list(x, as.character(substitute(name))))
        }
        unlockBinding("$", baseenv())
        assign("$", replacement, baseenv())
        lockBinding("$", baseenv())
        on.exit({
            unlockBinding("$", baseenv())
            assign("$", original, baseenv())
            lockBinding("$", baseenv())
        }, add = TRUE)
        result <- dplyr::mutate(data, y = x + 1, .by = g)
        list(events = events, values = as.double(result$y))
    }, libpath = .libPaths(), env = c(R_DISABLE_BYTECODE = "1"))
    expect_identical(observed$events,
                     c(rep("mask$rows", 4L), "combiner", "mask$rows"))
    expect_identical(observed$values, c(2, 3, 4, 5))
})

test_that("public combination callbacks retain the original caller frame", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(g = c(1, 1, 2, 2), x = c(1, 2, 3, 4))
    original <- vctrs::list_unchop
    local_mocked_bindings(list_unchop = function(x, ...) {
        frame <- parent.frame()
        mask <- get("mask", frame, inherits = TRUE)
        mask$values <- function(...) stop("caller mask changed")
        assign("mask", mask, frame)
        original(x, ...)
    }, .package = "vctrs")
    expect_error(dplyr::mutate(data, y = x + 1, .by = g),
                 "caller mask changed", fixed = TRUE)
})

test_that("native combination reuses ordinary assignment targets safely", {
    pieces <- .combine_warm()
    supported <- .combine_profile_expected()
    attempt <- function(indexed, slot, pieces, events) {
        chunks <- pieces
        mask <- list(rows = list(c(4L, 2L), c(3L, 1L)))
        target <- if (indexed) "value" else "result"
        status <- FALSE
        if (slot == "value") assign(target, "existing", environment())
        if (slot == "active") makeActiveBinding(target, function(...) {
            events$calls <- events$calls + 1L
            stop("assignment target invoked")
        }, environment())
        if (slot == "delayed") delayedAssign(target, {
            events$calls <- events$calls + 1L
            stop("assignment target forced")
        }, assign.env = environment())
        if (slot == "binding_locked") {
            assign(target, "existing", environment())
            lockBinding(target, environment())
        }
        if (slot == "environment_locked") lockEnvironment(environment())
        status <- if (indexed) .try_combine_dta_double_indexed(chunks, mask) else
            .Call(C_dtatools_combine_double_into_current,
                  FALSE, .double_combine_state, .metadata_state)
        list(status = status, frame = environment(), target = target)
    }
    environment(attempt) <- asNamespace("dtatools")
    for (indexed in c(FALSE, TRUE)) {
        for (slot in c("absent", "value", "active", "delayed",
                       "binding_locked", "environment_locked")) {
            events <- new.env(parent = emptyenv())
            events$calls <- 0L
            observed <- attempt(indexed, slot, pieces, events)
            admitted <- supported && slot %in% c("absent", "value")
            expect_identical(observed$status, admitted, info = paste(indexed, slot))
            expect_identical(events$calls, 0L, info = paste(indexed, slot))
            if (admitted) {
                expect_identical(as.double(get(observed$target, observed$frame)),
                                 if (indexed) c(4, 2, 3, 1) else c(1, 2, 3, 4))
            } else if (slot %in% c("value", "binding_locked")) {
                expect_identical(get(observed$target, observed$frame), "existing")
            }
        }
    }
})

test_that("public indexed combination admits five expressions in one run frame", {
    skip_if_not_installed("dplyr", "1.2.1")
    withr::local_options(dtatools.generate_type = "double")
    .combine_warm()
    data <- dibble(x = rep(c(1, 4, 2, 8), 25), g = rep(1:10, 10))
    .Call(C_dtatools_native_copy_stats, TRUE)
    result <- dplyr::mutate(data, y1 = x + 1, y2 = y1 + 1, y3 = y2 + 1,
                           y4 = y3 + 1, y5 = y4 + 1, .by = g)
    counters <- .Call(C_dtatools_native_copy_stats, FALSE)
    expect_identical(counters[["combine_copied_payload_bytes"]],
                     if (.combine_profile_expected()) 4000 else 0)
    for (i in 1:5) expect_identical(as.double(result[[paste0("y", i)]]),
                                   rep(c(1, 4, 2, 8), 25) + i)
})

test_that("combination namespace admission leaves active exports untouched", {
    pieces <- .combine_warm()
    exports <- getNamespaceInfo(asNamespace("vctrs"), "exports")
    alias <- get("list_unchop", exports, inherits = FALSE)
    old_locked <- bindingIsLocked("list_unchop", exports)
    if (old_locked) unlockBinding("list_unchop", exports)
    rm("list_unchop", envir = exports)
    on.exit({
        rm("list_unchop", envir = exports)
        assign("list_unchop", alias, exports)
        if (old_locked) lockBinding("list_unchop", exports)
    }, add = TRUE)
    calls <- 0L
    makeActiveBinding("list_unchop", function() {
        calls <<- calls + 1L
        alias
    }, exports)
    attempt <- function(pieces) {
        .Call(C_dtatools_combine_double_into_current,
              FALSE, .double_combine_state, .metadata_state)
    }
    environment(attempt) <- asNamespace("dtatools")
    expect_false(attempt(pieces))
    expect_identical(calls, 0L)
    expected <- vctrs::list_unchop(pieces)
    expected_calls <- calls
    calls <- 0L
    actual <- .combine_dta_double(pieces)
    expect_identical(calls, expected_calls)
    expect_identical(calls, 1L)
    expect_identical(actual, expected)
})

test_that("indexed admission never forces unfamiliar operand bindings", {
    pieces <- .combine_warm()
    events <- new.env(parent = emptyenv())
    events$calls <- 0L
    caller <- new.env(parent = asNamespace("dtatools"))
    caller$chunks <- pieces
    caller$mask <- list(rows = list(c(4L, 2L), c(3L, 1L)))
    caller$events <- events
    expect_false(eval(quote(.try_combine_dta_double_indexed({
        events$calls <- events$calls + 1L
        stop("chunks expression forced")
    }, mask)), caller))
    expect_false(eval(quote(.try_combine_dta_double_indexed(chunks, {
        events$calls <- events$calls + 1L
        stop("mask expression forced")
    })), caller))
    expect_identical(events$calls, 0L)
    for (name in c("chunks", "mask")) for (kind in c("active", "delayed")) {
        frame <- new.env(parent = asNamespace("dtatools"))
        frame$chunks <- pieces
        frame$mask <- caller$mask
        frame$events <- events
        rm(list = name, envir = frame)
        if (kind == "active") makeActiveBinding(name, function() {
            events$calls <- events$calls + 1L
            stop("operand binding invoked")
        }, frame) else delayedAssign(name, {
            events$calls <- events$calls + 1L
            stop("operand promise forced")
        }, assign.env = frame)
        expect_false(eval(quote(.try_combine_dta_double_indexed(chunks, mask)), frame))
        expect_identical(events$calls, 0L)
    }
})

test_that("production namespace tracing retains values and the original caller", {
    gather <- .mutation_gather_values
    pieces <- .combine_warm()
    observe <- function(fail) {
        active <- FALSE
        events <- list()
        suppressWarnings(trace("::", tracer = function() if (active) {
            events[[length(events) + 1L]] <<- vapply(sys.calls(), function(call) {
                paste(deparse(call), collapse = " ")
            }, character(1))
            if (fail) stop("namespace lookup callback")
        }, where = baseenv(), print = FALSE))
        on.exit(untrace("::", where = baseenv()), add = TRUE)
        active <- TRUE
        actual <- tryCatch(gather(pieces), error = conditionMessage)
        active <- FALSE
        list(events = events,
             value = if (is.character(actual)) actual else as.double(actual))
    }
    success <- observe(FALSE)
    failure <- observe(TRUE)
    expect_identical(success$value, if (.dtatools_bytecode_execution_expected())
        c(1, 2, 3, 4) else "object 'vctrs' not found")
    expect_identical(failure$value, "namespace lookup callback")
    for (record in list(success, failure)) {
        expect_length(record$events, 1L)
        stack <- record$events[[1L]]
        position <- match("vctrs::list_unchop", stack)
        expect_false(is.na(position))
        expect_identical(stack[[position - 1L]], "gather(pieces)")
    }
})

test_that("public combination settles piece promises before later metadata callbacks", {
    data <- dibble(x = c(1, 2), g = c(1, 2))
    invisible(gen(data, z = x + 1, by = g))
    replacement_pieces <- list(dta_double(100), dta_double(200))
    observe <- function() {
        jit <- compiler::enableJIT(0L)
        on.exit(compiler::enableJIT(jit), add = TRUE)
        gather <- .mutation_gather_values
        body(gather) <- body(gather)
        local_mocked_bindings(.mutation_gather_values = gather, .package = "dtatools")
        original <- .Primitive("attributes")
        replacement <- function(obj) {
            if (identical(substitute(obj), quote(pieces[[1L]]))) {
                assign("value_pieces", replacement_pieces, parent.frame(2L))
                stop(if (identical(as.double(obj), 100)) "observed late pieces" else
                     "observed original pieces")
            }
            original(obj)
        }
        local_mocked_bindings(attributes = replacement, .package = "base")
        tryCatch(gen(data, y = x + 1, by = g), error = conditionMessage)
    }
    expect_identical(observe(), "observed original pieces")
})

test_that("successful combination settles original forwarded operands", {
    pieces <- .combine_warm()
    supported <- .combine_profile_expected()
    attempt <- function(chunks, mask) {
        status <- .try_combine_dta_double_indexed(chunks, mask)
        list(status = status, read = function() list(chunks = chunks, mask = mask))
    }
    environment(attempt) <- asNamespace("dtatools")
    initial_mask <- list(rows = list(c(4L, 2L), c(3L, 1L)))
    upstream <- list2env(list(input = pieces, rows = initial_mask), parent = environment())
    retained <- evalq(attempt(input, rows), upstream)
    expect_identical(retained$status, supported)
    upstream$input <- list(dta_double(100))
    upstream$rows <- list(rows = list(1L))
    expect_identical(retained$read(), if (supported)
        list(chunks = pieces, mask = initial_mask) else
        list(chunks = upstream$input, mask = upstream$rows))
})
