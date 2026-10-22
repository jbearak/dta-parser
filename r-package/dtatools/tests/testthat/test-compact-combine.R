# Grouped mutate() and gen() hand the combine of their per-group results to
# the native check that list_unchop() would otherwise run through the
# vec_ptype2(), vec_cast() and vec_restore() methods. These cases cover
# compact pieces. The check reads chunks and mask, or pieces, as ordinary
# bindings in the frame that calls it, and assigns value or result there.
.compact_indexed <- function(x, rows) {
    chunks <- x
    mask <- list(rows = rows)
    if (.try_combine_dta_double_indexed(chunks, mask)) value else NULL
}

.compact_concat <- function(x) {
    pieces <- x
    if (.Call(C_dtatools_combine_double_into_current, FALSE,
              .double_combine_state, .metadata_state)) result else NULL
}

.compact_bits <- function(value) writeBin(as.double(value), raw(), size = 8L)

.compact_expect_unchop <- function(native, pieces, indices = NULL, info = NULL) {
    expected <- if (is.null(indices)) vctrs::list_unchop(pieces) else
        vctrs::list_unchop(pieces, indices = indices)
    if (.dtatools_numeric_entry_expected()) {
        expect_true(identical(native, expected, attrib.as.set = FALSE), info = info)
        expect_identical(.compact_bits(native), .compact_bits(expected), info = info)
    } else {
        expect_null(native, info = info)
        expect_s3_class(expected, "dta_numeric")
    }
}

# Mutate chunks are usually metadata proxies over compact vectors.
.compact_combine_shapes <- list(
    bytes = function() list(dta_byte(c(1, NA)), dta_byte(tagged_missing("b")),
        dta_byte(numeric()), dta_byte(c(-127, 100, 3))),
    proxies = function() c(lapply(1:3, function(i) .metadata_copy(dta_byte(c(i, -i)))),
                           list(dta_int(c(32740, tagged_missing("z"))))),
    means = function() list(.metadata_copy(dta_float(c(1.5, 2.25))),
        .metadata_copy(dta_int(c(4, NA))), .metadata_copy(dta_byte(c(7, 8)))),
    longs = function() list(.metadata_copy(dta_long(c(1e5, 2147483620))),
        dta_byte(c(1, 2)), .metadata_copy(dta_int(c(-32767, NA))))
)

.compact_partition <- function(pieces) {
    sizes <- lengths(pieces)
    order <- rev(seq_len(sum(sizes)))
    ends <- cumsum(sizes)
    lapply(seq_along(sizes), function(i) order[seq_len(sizes[[i]]) + ends[[i]] - sizes[[i]]])
}

.compact_warm <- function(make) {
    # Settle the lazily loaded bindings that admission reads, as a first
    # grouped mutate would, on pieces the checks never see.
    for (i in 1:3) {
        pieces <- make()
        vctrs::list_unchop(pieces, indices = .compact_partition(pieces))
    }
}

test_that("compact combination matches list_unchop() with and without indices", {
    for (name in names(.compact_combine_shapes)) {
        make <- .compact_combine_shapes[[name]]
        .compact_warm(make)
        rows <- .compact_partition(make())
        .compact_expect_unchop(.compact_indexed(make(), rows), make(), rows, info = name)
        .compact_expect_unchop(.compact_concat(make()), make(), info = name)
    }
    rows <- list(c(2L, 4L), c(1L, 3L))
    pieces <- list(dta_int(c(1, 2)), dta_int(c(3, 4)))
    .compact_expect_unchop(.compact_indexed(pieces, rows), pieces, rows)
})

test_that("compact combination gives each result its own attribute vectors", {
    make <- .compact_combine_shapes$proxies
    .compact_warm(make)
    pieces <- make()
    first <- .compact_indexed(pieces, .compact_partition(pieces))
    second <- .compact_indexed(pieces, .compact_partition(pieces))
    if (.dtatools_numeric_entry_expected()) {
        expect_false(identical(rlang::obj_address(attr(first, "class")),
                               rlang::obj_address(attr(second, "class"))))
        expect_false(identical(rlang::obj_address(attr(first, "stata.storage")),
                               rlang::obj_address(attr(second, "stata.storage"))))
        expect_identical(.compact_bits(first), .compact_bits(second))
    } else {
        expect_null(first)
        expect_null(second)
        expect_null(.compact_concat(pieces))
    }
})

test_that("compact combination declines pieces it cannot construct as the casts do", {
    make <- .compact_combine_shapes$proxies
    .compact_warm(make)
    rows <- .compact_partition(make())
    expect_identical(is.null(.compact_indexed(make(), rows)),
                     !.dtatools_numeric_entry_expected())
    labelled <- make()
    attr(labelled[[2L]], "label") <- "Score"
    expect_null(.compact_indexed(labelled, rows))
    expect_null(.compact_concat(labelled))
    decoded <- make()
    .Call(C_dtatools_force_altrep_materialization, decoded[[1L]])
    expect_null(.compact_indexed(decoded, rows))
    # A long and a float meet at double, which these pieces do not hold.
    mixed <- list(dta_long(c(1, 2)), dta_float(c(1.5, 2.5)))
    expect_null(.compact_indexed(mixed, list(1:2, 3:4)))
    expect_null(.compact_concat(mixed))
    expect_identical(dta_storage_type(vctrs::list_unchop(mixed)), "double")
    for (pieces in list(list(dta_byte(1), dta_double(2)), list(dta_double(1), dta_byte(2)),
                        list(dta_byte(1), 2), list(dta_byte(1), NULL))) {
        expect_null(.compact_indexed(pieces, list(1L, 2L)))
    }
    pieces <- list(dta_int(c(1, 2)), dta_int(c(3, 4)))
    for (indices in list(list(c(1L, 1L), c(3L, 4L)), list(c(0L, 2L), c(3L, 4L)),
                         list(c(NA_integer_, 2L), c(3L, 4L)), list(c(1L, 2L), c(3L, 5L)),
                         list(1L, c(2L, 3L, 4L)), list(c(1, 2), c(3, 4)),
                         list(c(1L, 2L)))) {
        expect_null(.compact_indexed(pieces, indices))
    }
    for (method in c("names.dta_int", "dim.dta_byte", "vec_ptype_finalise.dta_int",
                     "vec_ptype.dta_byte", "names<-.dta_int")) {
        assign(method, function(x, ...) NextMethod(), envir = globalenv())
        expect_null(.compact_indexed(make(), rows), info = method)
        rm(list = method, envir = globalenv())
    }
})

test_that("compact combination runs every cast of a replaced Stata method", {
    table <- get(".__S3MethodsTable__.", asNamespace("vctrs"), inherits = FALSE)
    canonical <- get("vec_cast.dta_numeric.dta_numeric", envir = table, inherits = FALSE)
    casts <- 0L
    assign("vec_cast.dta_numeric.dta_numeric", function(x, to, ...) {
        casts <<- casts + 1L
        canonical(x, to, ...)
    }, envir = table)
    on.exit(assign("vec_cast.dta_numeric.dta_numeric", canonical, envir = table))
    pieces <- lapply(1:9, dta_byte)
    rows <- as.list(9:1)
    casts <- 0L
    expect_null(.compact_indexed(pieces, rows))
    expect_null(.compact_concat(pieces))
    expect_identical(casts, 0L)
    expect_identical(as.double(vctrs::list_unchop(pieces, indices = rows)), as.double(9:1))
    expect_gte(casts, 9L)
})

test_that("grouped mutate and gen combine compact results as the R methods do", {
    skip_if_not_installed("dplyr", "1.2.1")
    withr::local_seed(12)
    data <- dibble(g = sample(1:40, 400, TRUE), b = dta_byte(sample(c(0:90, NA), 400, TRUE)),
                   i = dta_int(sample(0:30000, 400, TRUE)), f = dta_float(round(runif(400), 2)))
    run <- function() dplyr::mutate(data, m = mean(b), x = max(b, na.rm = TRUE),
        s = i + 1L, w = f * 2, k = { x[1] <- 0; x }, .by = g)
    generate <- function() gen(copy_data(data), y = i - 1, by = g)
    run()
    generate()
    admitted <- logical()
    suppressMessages(trace(".try_combine_dta_double_indexed", where = asNamespace("dtatools"),
        print = FALSE, exit = bquote(assign("admitted", c(get("admitted", envir = .(environment())),
            returnValue()), envir = .(environment())))))
    settled <- run()
    suppressMessages(untrace(".try_combine_dta_double_indexed", where = asNamespace("dtatools")))
    generated <- generate()
    expect_identical(admitted, rep(.dtatools_numeric_entry_expected(), 5L))
    dependencies <- .double_combine_state$dependencies
    .double_combine_state$dependencies <- NULL
    full <- tryCatch(run(), finally = .double_combine_state$dependencies <- dependencies)
    .double_combine_state$dependencies <- NULL
    full_generated <- tryCatch(generate(),
        finally = .double_combine_state$dependencies <- dependencies)
    for (pair in list(list(settled, full), list(generated, full_generated))) {
        expect_identical(lapply(.data_columns(pair[[1L]]), attributes),
                         lapply(.data_columns(pair[[2L]]), attributes))
        expect_identical(lapply(.data_columns(pair[[1L]]), .compact_bits),
                         lapply(.data_columns(pair[[2L]]), .compact_bits))
    }
    expect_identical(dta_storage_type(settled$m), "float")
    expect_identical(dta_storage_type(settled$s), "int")
    expect_identical(as.double(settled$k)[!duplicated(data$g)], rep(0, 40))
    expect_false(any(as.double(settled$x) == 0, na.rm = TRUE))
})

test_that("a fresh session's first grouped mutate of a read file combines natively", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("callr")
    # Lazy bindings exist only in an installed copy, which loads its
    # namespace lazily, so the check sees them there.
    package_path <- getNamespaceInfo(asNamespace("dtatools"), "path")
    auto <- fixture("auto_v118.dta")
    observed <- callr::r(function(package_path, load_package, path) {
        load_package(package_path)
        record <- new.env()
        record$admitted <- logical()
        suppressMessages(trace(".try_combine_dta_double_indexed",
            where = asNamespace("dtatools"), print = FALSE,
            exit = bquote(assign("admitted", c(get("admitted", envir = .(record)),
                returnValue()), envir = .(record)))))
        # The reader builds these columns, so the R constructor never runs.
        data <- dplyr::group_by(read_dta(path, col_select = c("foreign", "weight", "mpg")),
                                foreign)
        result <- dplyr::mutate(data, v = weight - min(weight), m = mean(mpg))
        list(admitted = record$admitted,
             storage = c(dta_storage_type(result$v), dta_storage_type(result$m)),
             values = list(as.double(result$v), as.double(result$m)))
    }, args = list(package_path = package_path, load_package = load_dtatools_for_subprocess,
                   path = auto), libpath = .libPaths())
    expect_identical(observed$admitted, rep(.dtatools_numeric_entry_expected(), 2L))
    expect_identical(observed$storage, c("int", "float"))
    cars <- read_dta(auto, col_select = c("foreign", "weight", "mpg"))
    group <- as.double(cars$foreign)
    weight <- as.double(cars$weight)
    expect_identical(observed$values[[1L]], weight - ave(weight, group, FUN = min))
    expect_equal(observed$values[[2L]], ave(as.double(cars$mpg), group), tolerance = 1e-6)
})
