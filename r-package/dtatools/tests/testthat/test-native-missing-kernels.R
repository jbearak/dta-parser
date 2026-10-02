native_missing_call <- function(name, ...) .Call(get(name, asNamespace('dtatools')), ...)
native_missing_freeze <- function(x, rows) native_missing_call('C_dtatools_owned_numeric_freeze', x, rows)

test_that('native missing kernels preserve all codes across compact spans', {
    values <- rep(c(-1, 0, 1, NA_real_, tagged_missing(letters)), 150L)
    for (ctor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (chunk in c(0, 1, 31, 1023, 1024, 4097)) {
            x <- ctor(values)
            if (chunk > 0) x <- native_missing_freeze(x, chunk)
            expect_identical(is_tagged_missing(x), is_tagged_missing(values))
            expect_identical(is_tagged_missing(x, c('A', 'z')), is_tagged_missing(values, c('A', 'z')))
            expect_identical(missing_tag(x), missing_tag(values))
            expect_identical(native_missing_call('C_dtatools_missing_codes', x),
                             native_missing_call('C_dtatools_missing_codes', values))
            expect_identical(anyNA(x), TRUE)
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        }
    }
})

test_that('anyNA uses live values after compact materialization and mutation', {
    for (ctor in list(dta_byte, dta_int, dta_long, dta_float, dta_double)) {
        for (values in list(numeric(), c(1, 2, 3), c(1, 2, NA_real_), c(1, tagged_missing('z')))) {
            x <- ctor(values)
            expect_identical(anyNA(x), anyNA(values))
            expect_identical(anyNA(x, recursive=TRUE), anyNA(values, recursive=TRUE))
            if (length(x)) {
                x[1] <- NA_real_
                expect_true(anyNA(x))
                x[] <- 1
                expect_false(anyNA(x))
            }
        }
    }
})

test_that('anyNA respects a replacement primitive in its fallback binding', {
    method <- dtatools:::anyNA.dta_numeric
    scope <- new.env(parent = environment(method))
    scope$anyNA <- .Primitive('sum')
    environment(method) <- scope
    for (ctor in list(dta_byte, dta_int, dta_long, dta_float, dta_double)) {
        value <- ctor(c(1, 2, 3))
        expect_identical(method(value), 6)
        expect_identical(method(value, recursive = TRUE), 7)
    }
})

test_that('anyNA fallback does not force recursive before its replacement', {
    method <- dtatools:::anyNA.dta_numeric
    scope <- new.env(parent = environment(method))
    calls <- 0L
    scope$anyNA <- function(x, recursive) {
        calls <<- calls + 1L
        as.double(x)
    }
    environment(method) <- scope
    value <- dta_byte(c(1, NA_real_, 3))
    expect_identical(method(value, recursive = stop('recursive was forced')),
                     c(1, NA_real_, 3))
    expect_identical(calls, 1L)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
})

test_that('missing kernels retain ordinary NA and noncanonical NaN policy', {
    x <- c(0, -0, NA_real_, NaN, Inf, -Inf, tagged_missing(letters))
    expect_identical(native_missing_call('C_dtatools_missing_codes', x),
                     c(NA_integer_, NA_integer_, 0L, 256L, NA_integer_, NA_integer_, utf8ToInt(paste0(letters,collapse=''))))
    expect_identical(is_tagged_missing(x), c(rep(FALSE,6),rep(TRUE,26)))
    expect_identical(missing_tag(x), c(rep(NA_character_,6),letters))
    expect_identical(native_missing_call('C_dtatools_has_tagged_na', x), TRUE)
    expect_identical(native_missing_call('C_dtatools_has_tagged_na', x[1:6]), FALSE)
})

test_that('compact tag inspectors preserve names and dimensions without labels', {
    values <- c(1, tagged_missing('a'), NA_real_, tagged_missing('z'))
    for (ctor in list(dta_byte, dta_int, dta_long, dta_float)) {
        value <- as.double(native_missing_freeze(ctor(values), 3))
        dim(value) <- c(2L, 2L)
        dimnames(value) <- list(c('first', 'second'), c('left', 'right'))
        names(value) <- letters[1:4]
        attr(value, 'label') <- 'Input label'
        plain <- structure(values, dim = dim(value), dimnames = dimnames(value),
                           names = names(value), label = 'Input label')
        expect_identical(missing_tag(value), missing_tag(plain))
        expect_identical(is_tagged_missing(value), is_tagged_missing(plain))
        expect_identical(is_tagged_missing(value, character()),
                         is_tagged_missing(plain, character()))
        expect_null(attr(missing_tag(value), 'label', exact = TRUE))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
    }
})

test_that('compact missing kernels preserve legacy observed and missing domains', {
    for (version in c(105L, 108L, 110L, 111L)) {
        path <- fixture(paste0('synthetic_v', version, '.dta'))
        compact <- read_dta(path, output = 'tibble')
        eager <- read_dta(path, output = 'tibble', use_numeric_altrep = FALSE)
        for (name in names(compact)) {
            source <- compact[[name]]
            if (!dtatools:::.is_unmaterialized_numeric_altrep(source)) next
            plain <- as.double(eager[[name]])
            for (value in list(source, native_missing_freeze(source, 1))) {
                expect_identical(missing_tag(value), missing_tag(plain))
                expect_identical(is_tagged_missing(value), is_tagged_missing(plain))
                expect_identical(native_missing_call('C_dtatools_missing_codes', value),
                                 native_missing_call('C_dtatools_missing_codes', plain))
                expect_identical(anyNA(value), anyNA(plain))
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
            }
        }
    }
})

test_that('compact float IEEE NaNs are missing without becoming tagged values', {
    path <- fixture_with_all_numeric_missing_codes('missing_values_v118.dta')
    on.exit(unlink(path), add = TRUE)
    bits <- list(as.raw(c(0, 0, 0, 0)), as.raw(c(1, 0, 192, 127)),
                 as.raw(c(1, 0, 192, 255)), as.raw(c(0, 0, 128, 127)))
    for (i in seq_along(bits)) {
        patch_numeric_fixture_row(path, i - 1L, list(x_float = bits[[i]]))
    }
    source <- read_dta(path, col_select = 'x_float', n_max = 4L)$x_float
    for (value in list(source, native_missing_freeze(source, 1))) {
        expect_identical(native_missing_call('C_dtatools_missing_codes', value),
                         c(NA_integer_, 256L, 256L, NA_integer_))
        expect_identical(missing_tag(value), rep(NA_character_, 4L))
        expect_identical(is_tagged_missing(value), rep(FALSE, 4L))
        expect_false(native_missing_call('C_dtatools_has_tagged_na', value))
        expect_true(anyNA(value))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
    }
})

test_that('tag-selection callbacks may materialize the compact source', {
    for (ctor in list(dta_byte, dta_int, dta_long, dta_float)) {
        source <- native_missing_freeze(ctor(c(1, tagged_missing('a'), NA_real_, tagged_missing('z'))), 2)
        calls <- 0L
        tags <- native_missing_call('C_dtatools_callback_character', c('a', 'z'), function() {
            calls <<- calls + 1L
            .force_altrep_materialization(source)
            gc()
        })
        expect_identical(is_tagged_missing(source, tags), c(FALSE, TRUE, FALSE, TRUE))
        expect_identical(calls, 1L)
        expect_identical(missing_tag(source), c(NA_character_, 'a', NA_character_, 'z'))
    }
})

test_that('anyNA compact counts follow live mutation views', {
    for (ctor in list(dta_byte, dta_int, dta_long, dta_float)) {
        source <- ctor(c(1, 2, 3))
        view <- native_missing_call('C_dtatools_mutation_views', list(x = source))[[1L]]
        expect_false(anyNA(view))
        native_missing_call('C_dtatools_patch_vector', source, 2L, tagged_missing('z'))
        expect_true(anyNA(view))
        native_missing_call('C_dtatools_patch_vector', source, 2L, 4)
        expect_false(anyNA(view))
    }
})
