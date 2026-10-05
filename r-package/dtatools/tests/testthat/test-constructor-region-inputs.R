.constructor_region_bytes <- function(x) {
    writeBin(as.double(x), raw(), size = 8L, endian = "little")
}

.constructor_region_expected <- function(values, kind) {
    observed <- !is.na(values)
    if (kind == "float") {
        values[observed] <- readBin(writeBin(values[observed], raw(), size = 4L,
                                           endian = "little"), double(),
                                    sum(observed), size = 4L, endian = "little")
    } else values[observed & values == 0] <- 0
    values
}

.constructor_region_facts <- function(values, kind) {
    maximum <- minimum <- 0
    if (kind == "float") {
        bytes <- matrix(as.numeric(writeBin(values[!is.na(values)], raw(), size = 4L,
                                             endian = "little")), nrow = 4L)
        magnitudes <- colSums(bytes * 256^(0:3)) %% 2^31
        maximum <- if (length(magnitudes)) max(magnitudes) else 0
        nonzero <- magnitudes[magnitudes != 0]
        minimum <- if (length(nonzero)) min(nonzero) else 0xffffffff
    }
    c(flags = if (kind == "float") 7 else 4,
      max_magnitude_bound = maximum, min_nonzero_magnitude_bound = minimum,
      zero_count = as.double(sum(values == 0, na.rm = TRUE)))
}

test_that("constructor chunk readers preserve final encoded values and facts", {
    cases <- list(
        byte = list(construct = dta_byte, observed = c(-127, -3, -0, 0, 3, 100)),
        int = list(construct = dta_int, observed = c(-32767, -3, -0, 0, 3, 32740)),
        long = list(construct = dta_long,
                    observed = c(-2147483647, -3, -0, 0, 3, 2147483620)),
        float = list(construct = dta_float,
                     observed = c(-3, -0, 0, 3, -2^-150, 2^-150, -2^-149, 2^-149, 1.01))
    )
    state <- function(x) c(unmaterialized = dtatools:::.is_unmaterialized_numeric_altrep(x),
                           materialized = .Call(C_dtatools_is_materialized_numeric_altrep, x))
    for (kind in names(cases)) {
        case <- cases[[kind]]
        for (n in c(0L, 2047L, 2048L, 2049L, 16383L, 16384L, 16385L)) {
            values <- rep(c(case$observed, NA_real_, tagged_missing(letters)), length.out = n)
            expected <- .constructor_region_expected(values, kind)
            for (backing in c("plain", "owned", "retained")) {
                source <- switch(backing,
                    plain = values,
                    owned = .Call(C_dtatools_capture_column, values),
                    retained = as.double(.Call(C_dtatools_owned_numeric_freeze,
                                               case$construct(values), 7L)))
                before <- state(source)
                source_expected <- if (backing == "retained") expected else values
                result <- case$construct(source)
                expect_identical(dta_storage_type(result), kind)
                expect_identical(.constructor_region_bytes(result), .constructor_region_bytes(expected))
                expect_identical(missing_tag(result), missing_tag(expected))
                expect_identical(anyNA(result), anyNA(expected))
                expect_identical(.Call(C_dtatools_numeric_facts_info, result),
                                 .constructor_region_facts(expected, kind))
                expect_identical(state(source), before)
                expect_identical(.constructor_region_bytes(source), .constructor_region_bytes(source_expected))
            }
        }
    }
})

test_that("constructor region reads support partial fallback and changing input", {
    skip_if_not_installed("callr")
    if (!nzchar(Sys.which("make")) ||
        !any(nzchar(Sys.which(c("cc", "gcc", "clang")))))
        skip("constructor region probe requires a C compiler")
    fixture <- normalizePath(test_path("fixtures", "constructor-region-probe.c"))
    scratch <- tempfile("constructor-region-probe-")
    dir.create(scratch)
    withr::defer(unlink(scratch, recursive = TRUE))
    observed <- .dtatools_child_r("constructor-region-inputs", function(libraries, fixture, scratch) {
        .libPaths(libraries)
        library(dtatools)
        prior <- setwd(scratch)
        on.exit(setwd(prior))
        stopifnot(file.copy(fixture, "constructor_region_probe.c"))
        output <- system2(file.path(R.home("bin"), "R"),
                          c("CMD", "SHLIB", "constructor_region_probe.c", "-o",
                            paste0("constructor_region_probe", .Platform$dynlib.ext)),
                          stdout = TRUE, stderr = TRUE)
        if (!is.null(attr(output, "status"))) stop(paste(output, collapse = "\n"))
        dll <- dyn.load(file.path(scratch, paste0("constructor_region_probe", .Platform$dynlib.ext)))
        # Keep this ALTREP method DLL loaded until the isolated process exits.
        # The parent removes the temporary build only after the child returns.
        create <- getNativeSymbolInfo("C_constructor_probe", dll)$address
        info <- getNativeSymbolInfo("C_constructor_probe_info", dll)$address
        construct <- dtatools:::C_dtatools_construct_numeric
        bytes <- function(x) writeBin(as.double(x), raw(), 8L, endian = "little")
        n <- 4097L
        patterns <- list(c(-3, -0, 0, 1, 3, NA_real_, tagged_missing(letters)),
                         c(-3, -0, 0, 1, 3, NA_real_, tagged_missing(letters)),
                         c(-3, -0, 0, 1, 3, NA_real_, tagged_missing(letters)),
                         c(-3, -0, 0, 1.01, -2^-150, 2^-150, -2^-149, 2^-149,
                           NA_real_, tagged_missing(letters)))
        cases <- list()
        for (kind in 0:3) for (mode in 0:3) {
            values <- rep(patterns[[kind + 1L]], length.out = n)
            x <- .Call(create, values, NULL, mode, 7L, NULL)
            result <- .Call(construct, x, kind, 0L)
            facts <- .Call(dtatools:::C_dtatools_numeric_facts_info, result)
            cases[[length(cases) + 1L]] <- list(kind = kind, mode = mode, values = values,
                bytes = bytes(result), missing = is.na(result), any_missing = anyNA(result),
                facts = facts,
                counts = .Call(info, x))
        }
        invalid <- lapply(4:5, function(mode) {
            x <- .Call(create, rep(1, n), NULL, mode, 7L, NULL)
            message <- tryCatch(.Call(construct, x, 0L, 0L), error = conditionMessage)
            list(message = message, counts = .Call(info, x))
        })
        # A zero-region reader must stop at the first invalid scalar, retaining
        # the old scalar-read validation order rather than prefetching a chunk.
        x <- .Call(create, c(NaN, rep(1, n - 1L)), NULL, 3L, 7L, NULL)
        early <- list(message = tryCatch(.Call(construct, x, 0L, 0L), error = conditionMessage),
                      counts = .Call(info, x))
        changed <- list()
        for (kind in c(0L, 3L)) for (mode in 0:3) {
            first <- rep(c(1, NA_real_, tagged_missing("z")), length.out = n)
            second <- rep(if (kind == 0L) c(-3, -0, 0, 3) else
                          c(-3, -0, 0, 3, -2^-150, 2^-150), length.out = n)
            fired <- 0L
            x <- .Call(create, first, second, mode, 7L, function() {
                fired <<- fired + 1L
                gc()
            })
            result <- .Call(construct, x, kind, 0L)
            facts <- .Call(dtatools:::C_dtatools_numeric_facts_info, result)
            changed[[length(changed) + 1L]] <- list(kind = kind, mode = mode, values = second,
                bytes = bytes(result), any_missing = anyNA(result), fired = fired,
                facts = facts, counts = .Call(info, x))
        }
        rejected <- list()
        for (mode in c(1L, 3L)) for (bad in c(NaN, 101)) {
            x <- .Call(create, rep(1, n), c(bad, rep(1, n - 1L)), mode, 7L, NULL)
            rejected[[length(rejected) + 1L]] <- list(bad = bad,
                message = tryCatch(.Call(construct, x, 0L, 0L), error = conditionMessage),
                counts = .Call(info, x))
        }
        list(cases = cases, invalid = invalid, early = early, changed = changed, rejected = rejected)
    }, args = list(libraries = .libPaths(), fixture = fixture, scratch = scratch), timeout = 60)
    names <- c("byte", "int", "long", "float")
    for (case in observed$cases) {
        kind <- names[[case$kind + 1L]]
        expected <- .constructor_region_expected(case$values, kind)
        expect_identical(case$bytes, .constructor_region_bytes(expected))
        expect_identical(case$missing, is.na(expected))
        expect_identical(case$any_missing, anyNA(expected))
        expect_identical(case$facts, .constructor_region_facts(expected, kind))
        expect_identical(case$counts[["passes"]], 2L)
        expect_identical(case$counts[["forced"]], 0L)
        expect_identical(case$counts[["scalars"]], if (case$mode == 3L) 8194L else 0L)
        regions <- switch(as.character(case$mode), `0` = 0L, `1` = 6L,
                          `2` = 1172L, `3` = 6L)
        expect_identical(case$counts[["regions"]], regions)
        if (case$mode == 0L) expect_identical(case$counts[["pointers"]], 2L)
        else {
            expect_gte(case$counts[["pointers"]], regions)
            expect_lte(case$counts[["pointers"]], 2L * regions)
        }
        expect_identical(case$counts[["max_request"]], if (case$mode == 0L) 0L else 2048L)
    }
    for (case in observed$invalid) {
        expect_identical(case$message, "invalid compact Stata numeric input region length")
        expect_identical(case$counts[["regions"]], 1L)
        expect_identical(case$counts[["scalars"]], 0L)
        expect_identical(case$counts[["forced"]], 0L)
    }
    expect_match(observed$early$message, "No Stata numeric storage")
    expect_identical(observed$early$counts[["scalars"]], 1L)
    expect_identical(observed$early$counts[["regions"]], 1L)
    for (case in observed$changed) {
        kind <- names[[case$kind + 1L]]
        expected <- .constructor_region_expected(case$values, kind)
        expect_identical(case$bytes, .constructor_region_bytes(expected))
        expect_identical(case$facts, .constructor_region_facts(expected, kind))
        expect_false(case$any_missing)
        expect_identical(case$fired, 1L)
        expect_identical(case$counts[["passes"]], 2L)
        expect_identical(case$counts[["forced"]], 0L)
    }
    for (case in observed$rejected) {
        expect_match(case$message, if (is.nan(case$bad)) "accept only system missing" else
                     "Stata byte storage cannot represent the value")
        expect_identical(case$counts[["passes"]], 2L)
        expect_identical(case$counts[["forced"]], 0L)
    }
})

test_that("constructor chunk boundaries retain strict diagnostics", {
    cases <- list(
        list(construct = dta_byte, bad = 101, message = "dta_int\\(x\\)"),
        list(construct = dta_int, bad = 32741, message = "dta_long\\(x\\)"),
        list(construct = dta_long, bad = 2147483621, message = "dta_double\\(x\\)"),
        list(construct = dta_float, bad = 2^127, message = "dta_double\\(x\\)"),
        list(construct = dta_float, bad = NaN, message = "No Stata numeric storage"),
        list(construct = dta_byte, bad = tagged_nan_for_test("?"), message = "accept only system missing")
    )
    for (case in cases) for (position in c(2048L, 2049L, 16384L, 16385L)) {
        values <- rep(1, 16385L)
        values[[position]] <- case$bad
        expect_error(case$construct(values), case$message)
        expect_error(case$construct(.Call(C_dtatools_capture_column, values)), case$message)
    }
})
