.ptype_kept_native <- function(chunks) .Call(C_dtatools_summary_ptype_kept, chunks)

.ptype_kept_cases <- function() {
    attributed <- function(value, ...) {
        pairs <- list(...)
        for (name in names(pairs)) attr(value, name) <- pairs[[name]]
        value
    }
    means <- lapply(c(1, 1.5, 2, NA, 2.5, rep(c(3, 3.5), 20)), function(value) {
        if (is.na(value) || value == round(value)) dta_byte(value) else dta_float(value)
    })
    list(
        means = means,
        computed = lapply(1:30, function(i) mean(dta_int(c(i, i + 1)))),
        late = c(lapply(1:20, dta_byte), lapply(21:40, dta_int)),
        four = lapply(1:40, function(i) switch(i %% 4 + 1, dta_byte(i), dta_int(i),
                                               dta_long(i), dta_float(i))),
        five = lapply(1:40, function(i) switch(i %% 5 + 1, dta_byte(i), dta_int(i),
                                               dta_long(i), dta_float(i), dta_double(i))),
        bytes = lapply(1:8, dta_byte),
        costly = c(lapply(1:6, dta_byte), list(dta_float(0.5), dta_byte(1))),
        empty = list(), one = list(dta_byte(1)), two = list(1, 2), nulls = list(NULL, NULL, 1, NULL),
        bare = as.list(1:20), strings = as.list(letters),
        labelled = lapply(1:12, function(i) set_val_labels(dta_byte(i), c(Low = 1))),
        labels = lapply(1:12, function(i) set_var_labels(dta_byte(i), if (i %% 2) "a" else "b")),
        factors = lapply(1:12, function(i) factor(letters[i %% 3 + 1], levels = letters[1:3])),
        dates = lapply(1:12, function(i) Sys.Date() + i),
        # `attributes()` lists a vector's attributes as stored, names
        # included, so their order tells the sets apart.
        names_first = lapply(1:12, function(i) if (i %% 2) {
            attributed(1, a = 1, names = "n")
        } else attributed(1, names = "n", a = 1)),
        order = lapply(1:12, function(i) if (i %% 2) attributed(1, a = 1, b = 2) else
            attributed(1, b = 2, a = 1)),
        storage = lapply(1:12, function(i) attributed(1, a = if (i %% 2) 1L else 1)),
        missing = lapply(1:12, function(i) attributed(1, a = if (i %% 2) NA_real_ else NaN)),
        lists = lapply(1:12, function(i) structure(list(i), class = "probe_list")),
        environments = lapply(1:12, function(i) attributed(1, a = globalenv())),
        # `identical()` compares closures' environments by default.
        closures = lapply(1:12, function(i) attributed(1, a = local(function() NULL))),
        shared = rep(list(attributed(1, a = local(function() NULL))), 12L)
    )
}

test_that("the native scan matches the R scan", {
    cases <- .ptype_kept_cases()
    for (name in names(cases)) {
        chunks <- cases[[name]]
        native <- .ptype_kept_native(chunks)
        expect_false(is.logical(native), info = name)
        expect_identical(native, .summary_ptype_kept_r(chunks), info = name)
        expect_identical(.summary_ptype_kept(chunks), native, info = name)
    }
})

test_that("row names, dimensions and other types leave the scan to the R code", {
    many <- function(value) rep(list(value), 12L)
    cases <- list(
        frame = many(data.frame(x = 1)), matrix = many(matrix(1:4, 2L)),
        array = many(array(1:2, 2L, list(c("a", "b")))),
        late_frame = c(lapply(1:6, dta_byte), many(data.frame(x = 1))),
        environment = many(new.env()), closure = many(function() NULL),
        symbol = many(quote(x)), wide = many(do.call(structure,
            c(list(1), stats::setNames(as.list(1:17), paste0("a", 1:17)))))
    )
    for (name in names(cases)) {
        chunks <- cases[[name]]
        expect_false(.ptype_kept_native(chunks), info = name)
        expect_identical(.summary_ptype_kept(chunks), .summary_ptype_kept_r(chunks), info = name)
    }
    expect_false(.ptype_kept_native(structure(list(1, 2, 3), class = "probe_list")))
    expect_false(.ptype_kept_native(1:3))
})

test_that("grouped summaries scan their chunks natively", {
    skip_if_not_installed("dplyr", "1.2.1")
    local_mocked_bindings(.summary_ptype_kept_r = function(chunks) stop("the R scan ran"),
                          .package = "dtatools")
    data <- dibble(g = rep(1:12, each = 2L), x = dta_int(seq_len(24L)))
    result <- dplyr::summarise(data, m = mean(x), h = max(x), n = dplyr::n(), .by = g)
    expect_identical(as.double(result$m), seq(1.5, 23.5, by = 2))
    expect_identical(as.double(result$h), as.double(seq(2L, 24L, by = 2L)))
})
