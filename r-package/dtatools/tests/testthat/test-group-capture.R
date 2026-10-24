.capture_facts <- function(x) list(
    value = x, attributes = attributes(x), altrep = .is_altrep(x),
    compact = .is_unmaterialized_numeric_altrep(x)
)

test_that("atomic values capture as `.metadata_copy()` copies them", {
    data <- read_dta(system.file("extdata", "all_types_v118.dta", package = "dtatools"))
    calls <- 0L
    values <- list(
        int = dta_int(c(1, NA)), mean = mean(dta_int(c(1, 2, 4))),
        proxy = set_var_labels(dta_byte(c(1, 2)), "label"), double = dta_double(c(a = 1.5)),
        integer = 1L, numeric = c(x = 2.5), character = c("a", NA), logical = NA,
        complex = 1i, raw = as.raw(1:2), factor = factor(c("a", "b")), date = Sys.Date(),
        matrix = matrix(1:4, 2L), sequence = 1:10, string = dta_string("a"),
        foreign = .Call(C_dtatools_callback_double, c(1, 2), function() calls <<- calls + 1L, FALSE)
    )
    for (name in names(data)) values[[paste("file", name)]] <- .subset2(data, name)
    for (name in names(values)) {
        value <- values[[name]]
        expected <- .capture_facts(.metadata_copy(value))
        captured <- .Call(C_dtatools_capture_atomic, value)
        expect_false(is.null(captured), info = name)
        expect_true(identical(.capture_facts(captured), expected, num.eq = FALSE,
                              single.NA = FALSE, attrib.as.set = FALSE), info = name)
        expect_true(identical(.capture_facts(.capture_dibble_nested(value)), expected,
                              num.eq = FALSE, single.NA = FALSE, attrib.as.set = FALSE),
                    info = name)
    }
})

test_that("other values keep the R capture", {
    reads <- 0L
    foreign_class <- 1
    attr(foreign_class, "class") <- .Call(C_dtatools_callback_character, "probe",
                                          function() reads <<- reads + 1L)
    values <- list(
        list = list(1), frame = data.frame(x = 1), environment = new.env(),
        closure = function() NULL, builtin = sum, s4 = asS4(1), null = NULL,
        table = structure(1, class = "data.table"), symbol = quote(x),
        foreign_class = foreign_class
    )
    # Setting the class read it, which spent the probe's one callback.
    .Call(C_dtatools_arm_callback_character, attr(foreign_class, "class", exact = TRUE),
          function() reads <<- reads + 1L)
    reads <- 0L
    for (name in names(values))
        expect_null(.Call(C_dtatools_capture_atomic, values[[name]]), info = name)
    expect_identical(reads, 0L)
})

test_that("a summary that replaces a column types it against that column", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(g = c(1, 1, 2), x = dta_byte(c(1, 2, 3)), y = dta_int(c(4, 5, 6)))
    result <- dplyr::summarise(data, x = 300L, z = 1.5, y = dplyr::first(y), .by = g)
    expect_identical(dta_storage_type(result$x), "int")
    expect_identical(dta_storage_type(result$z), "double")
    expect_identical(dta_storage_type(result$y), "int")
    reused <- dplyr::summarise(data, x = max(x), w = x + 1L, .by = g)
    expect_identical(as.double(reused$w), c(3, 4))
})
