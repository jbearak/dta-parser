# Run `code` with the grouped summary declined, so that egen() evaluates
# the calculation once per group.
.egen_per_group <- function(code) {
    local_mocked_bindings(.egen_group_summary = function(...) NULL,
                          .package = "dtatools")
    code
}

# A table's columns and attributes, without the reference state that each
# dibble owns.
.egen_table_parts <- function(data) {
    parts <- attributes(data)
    parts$.dtatools_ref_state <- NULL
    list(columns = lapply(as.list(unclass(data)), identity), attributes = parts)
}

.egen_summary_table <- function() {
    values <- c(3, NA, tagged_missing("a"), 1, -2, 7, tagged_missing("z"), 0,
                5, NA, 2, 9)
    dibble(
        key = c(2, 1, 2, 3, 1, 1, 3, 2, 3, 4, 4, 4),
        text = rep(c("b", "a", "c"), 4),
        byte = dta_byte(values), int = dta_int(values * 100),
        long = dta_long(values * 1e5), float = dta_float(values / 8),
        double = dta_double(values / 3), plain = values,
        integer = as.integer(values), logical = values > 2,
        date = as.Date("2020-01-01") + ifelse(is.na(values), NA, values),
        missing = dta_double(rep(NA_real_, 12))
    )
}

test_that("grouped summaries of one column match evaluation per group", {
    columns <- c("byte", "int", "long", "float", "double", "plain", "integer",
                 "logical", "date", "missing")
    groupings <- list(by = quote(key), by = quote(text),
                      bysort = quote(c(text, key)))
    original <- .egen_group_summary
    summaries <- 0L
    for (fn in c("dta_mean", "dta_min", "dta_max", "dta_total")) {
        for (column in columns) for (i in seq_along(groupings)) {
            call <- as.call(c(quote(egen), quote(data),
                              z = call(fn, as.name(column)), groupings[i]))
            data <- .egen_summary_table()
            local({
                local_mocked_bindings(.egen_group_summary = function(...) {
                    result <- original(...)
                    summaries <<- summaries + !is.null(result)
                    result
                }, .package = "dtatools")
                eval(call)
            })
            expected <- .egen_summary_table()
            .egen_per_group(eval(call, list(data = expected)))
            expect_identical(.egen_table_parts(data), .egen_table_parts(expected),
                             info = deparse(call))
        }
    }
    expect_identical(summaries, 4L * length(columns) * length(groupings))
})

test_that("grouped summaries follow dplyr groups, empty groups and missing keys", {
    grouped <- function() {
        data <- .egen_summary_table()
        data$level <- factor(data$key %% 3, levels = 0:4)
        dplyr::group_by(data, level, .drop = FALSE)
    }
    fast <- egen(grouped(), z = dta_total(int))
    slow <- .egen_per_group(egen(grouped(), z = dta_total(int)))
    expect_identical(.egen_table_parts(fast), .egen_table_parts(slow))
    data <- .egen_summary_table()
    data$key[c(2, 5)] <- NA
    expected <- .egen_summary_table()
    expected$key[c(2, 5)] <- NA
    egen(data, z = dta_mean(byte), by = key)
    .egen_per_group(egen(expected, z = dta_mean(byte), by = key))
    expect_identical(.egen_table_parts(data), .egen_table_parts(expected))
})

test_that("grouped summaries raise the shadowing error of evaluation per group", {
    byte <- 1
    fast <- tryCatch(egen(.egen_summary_table(), z = dta_mean(byte), by = key),
                     error = conditionMessage)
    slow <- .egen_per_group(tryCatch(
        egen(.egen_summary_table(), z = dta_mean(byte), by = key),
        error = conditionMessage))
    expect_match(fast, "both a column and an object")
    expect_identical(fast, slow)
})

test_that("grouped summaries leave compact source columns untouched", {
    d <- read_dta(fixture("auto_v118.dta"))
    source <- d$price
    address <- rlang::obj_address(source)
    egen(d, average = dta_mean(price), by = foreign)
    expect_identical(rlang::obj_address(d$price), address)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source))
    expected <- ave(as.double(source), as.double(d$foreign), FUN = mean)
    expect_equal(as.double(d$average), as.double(dta_float(expected)))
})

test_that("the grouped summary kernel declines groups it cannot read in order", {
    summary <- function(groups) {
        .Call(C_dtatools_egen_group_summary, dta_byte(c(4, 1, NA, 2, 8)),
              groups, 3L, FALSE, TRUE)
    }
    expect_identical(summary(list(c(1L, 3L, 5L), c(2L, 4L))),
                     list(c(12, 3, 12, 3, 12), NULL))
    # Rows no group lists are left out, and the listed rows are returned.
    expect_identical(summary(list(c(2L, 5L), integer(), 3L)),
                     list(c(9, 0, 9), c(2L, 3L, 5L)))
    for (groups in list(list(c(3L, 1L)), list(c(1L, 2L), 2L), list(6L),
                        list(0L), list(c(1, 2)), list(1:5), 1:5)) {
        expect_null(summary(groups))
    }
})
