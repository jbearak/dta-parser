test_that("var_label returns a vector's variable label", {
    values <- structure(c(1, 2), label = "Interview status")

    expect_identical(var_label(values), "Interview status")
})

test_that("val_labels returns a vector's value-label table", {
    values <- structure(c(1, 2), labels = c(Complete = 1, Refused = 2))

    expect_identical(val_labels(values), dta_double(c(Complete = 1, Refused = 2)))
})

test_that("dataset_label returns a data frame's dataset label", {
    data <- structure(data.frame(x = 1), label = "Baseline survey")

    expect_identical(dataset_label(data), "Baseline survey")
})

test_that("data-frame getters retain names and NULL entries", {
    data <- data.frame(labelled = c(0, 1), plain = c(2, 3))
    attr(data$labelled, "label") <- "Status"
    attr(data$labelled, "labels") <- c(No = 0, Yes = 1)

    expect_identical(
        list(variable = var_label(data), values = val_labels(data)),
        list(
            variable = list(labelled = "Status", plain = NULL),
            values = list(labelled = dta_double(c(No = 0, Yes = 1)), plain = NULL)
        )
    )
})

test_that("var_label replacement preserves vector values and attributes", {
    values <- structure(
        c(1, 2),
        label = "Old label",
        format.stata = "%9.0g",
        provenance = "imported"
    )

    var_label(values) <- "Interview status"

    expect_identical(
        list(
            values = unclass(values),
            label = var_label(values),
            format = attr(values, "format.stata", exact = TRUE),
            provenance = attr(values, "provenance", exact = TRUE)
        ),
        list(
            values = structure(
                c(1, 2),
                label = "Interview status",
                format.stata = "%9.0g",
                provenance = "imported"
            ),
            label = "Interview status",
            format = "%9.0g",
            provenance = "imported"
        )
    )
})

test_that("dataset_label replacement sets and removes dataset metadata", {
    data <- data.frame(x = 1)

    dataset_label(data) <- "Baseline survey"
    labelled <- dataset_label(data)
    dataset_label(data) <- NA_character_

    expect_identical(
        list(labelled = labelled, removed = dataset_label(data)),
        list(labelled = "Baseline survey", removed = NULL)
    )
})

test_that("replacement syntax follows R copy semantics", {
    data <- data.frame(x = c(0, 1))
    alias <- data

    dataset_label(data) <- "Assigned dataset"
    var_label(data) <- list(x = "Assigned variable")
    val_labels(data) <- list(x = c(No = 0, Yes = 1))

    expect_identical(dataset_label(data), "Assigned dataset")
    expect_identical(var_label(data$x), "Assigned variable")
    expect_identical(val_labels(data$x), dta_double(c(No = 0, Yes = 1)))
    expect_null(dataset_label(alias))
    expect_null(var_label(alias$x))
    expect_null(val_labels(alias$x))

    reference <- dibble(x = c(0, 1))
    gen(reference, y, x + 1)
    reference_alias <- reference
    var_label(reference) <- list(x = "X", y = "Y")
    val_labels(reference) <- list(x = c(No = 0, Yes = 1))

    expect_true(is_dibble(reference))
    expect_identical(var_label(reference), list(x = "X", y = "Y"))
    expect_identical(val_labels(reference$x), dta_double(c(No = 0, Yes = 1)))
    expect_identical(
        var_label(reference_alias), list(x = NULL, y = NULL)
    )
    expect_null(val_labels(reference_alias$x))
})

test_that("label replacement isolates metadata and later value writes", {
    data <- dibble(
        labelled = dta_byte(1:3),
        untouched = dta_byte(4:6)
    )
    alias <- data

    var_label(data) <- list(labelled = "Labelled")
    replace_values(data, labelled, 8, where = 2)
    replace_values(data, untouched, 9, where = 1)

    expect_identical(as.double(data$untouched), c(9, 5, 6))
    expect_identical(as.double(alias$untouched), c(4, 5, 6))
    expect_identical(as.double(data$labelled), c(1, 8, 3))
    expect_identical(as.double(alias$labelled), c(1, 2, 3))
})

test_that("dataset-label replacement detaches a dibble from its aliases", {
    data <- dibble(x = dta_byte(1:3))
    gen(data, y, x + 1)
    alias <- data

    dataset_label(data) <- "Labelled"
    replace_values(data, x, 9, where = 1)
    replace_values(alias, x, 8, where = 2)

    expect_true(is_dibble(data))
    expect_identical(as.double(data$x), c(9, 2, 3))
    expect_identical(as.double(alias$x), c(1, 8, 3))
    expect_identical(as.double(data$y), c(2, 3, 4))
    expect_identical(as.double(alias$y), c(2, 3, 4))
    expect_identical(dataset_label(data), "Labelled")
    expect_null(dataset_label(alias))
})

test_that("var_label replacement updates named columns and can clear all", {
    data <- data.frame(x = 1, y = 2)
    attr(data$x, "label") <- "Old x"
    attr(data$y, "label") <- "Old y"

    var_label(data) <- list(x = "New x", y = NULL)
    updated <- var_label(data)
    var_label(data) <- NULL

    expect_identical(
        list(updated = updated, cleared = var_label(data)),
        list(
            updated = list(x = "New x", y = NULL),
            cleared = list(x = NULL, y = NULL)
        )
    )
})

test_that("set_var_labels combines named dots and .labels", {
    data <- dibble(x = 1, y = 2)

    updated <- set_var_labels(
        data,
        x = "Interview status",
        .labels = list(y = "Sampling stratum")
    )

    expect_identical(
        var_label(updated),
        list(x = "Interview status", y = "Sampling stratum")
    )
})

test_that("set_var_labels supports vector pipelines", {
    values <- c(1, 2)

    updated <- set_var_labels(values, "Interview status")

    expect_identical(
        list(values = as.vector(updated), label = var_label(updated)),
        list(values = c(1, 2), label = "Interview status")
    )
})

test_that("bulk variable-label limits produce one complete portability warning", {
    data <- dibble(x = 1, y = 2)
    over_limit <- paste(rep("é", 81), collapse = "")
    messages <- character()

    updated <- withCallingHandlers(
        set_var_labels(data, x = over_limit, y = over_limit),
        warning = function(condition) {
            messages <<- c(messages, conditionMessage(condition))
            invokeRestart("muffleWarning")
        }
    )

    expect_identical(
        list(
            warning_count = length(messages),
            mentions_x = grepl("variable label for `x`", messages,
                               fixed = TRUE),
            mentions_y = grepl("variable label for `y`", messages,
                               fixed = TRUE),
            mentions_limit = grepl("80 Unicode characters", messages,
                                   fixed = TRUE),
            stored_characters = nchar(var_label(updated$x), type = "chars")
        ),
        list(
            warning_count = 1L,
            mentions_x = TRUE,
            mentions_y = TRUE,
            mentions_limit = TRUE,
            stored_characters = 81L
        )
    )
})

test_that("variable-label setters keep imported numeric storage compact", {
    source <- read_dta(fixture("value_labels_v118.dta"))$foreign

    updated <- set_var_labels(source, "Vehicle origin")

    expect_identical(
        list(
            source_is_native_altrep = dtatools:::.is_numeric_altrep(source),
            source_is_unmaterialized =
                dtatools:::.is_unmaterialized_numeric_altrep(source),
            result_is_altrep = dtatools:::.is_altrep(updated),
            result_is_unmaterialized =
                dtatools:::.is_unmaterialized_numeric_altrep(updated),
            values = as.vector(updated),
            label = var_label(updated)
        ),
        list(
            source_is_native_altrep = TRUE,
            source_is_unmaterialized = TRUE,
            result_is_altrep = TRUE,
            result_is_unmaterialized = TRUE,
            values = rep(c(1, 0), 5L),
            label = "Vehicle origin"
        )
    )
})

test_that("val_labels replacement labels ordinary numeric vectors in place", {
    values <- structure(
        c(0, 1),
        format.stata = "%8.0g",
        provenance = "imported"
    )

    val_labels(values) <- c(No = 0, Yes = 1)

    expect_identical(
        list(
            values = as.vector(values),
            labels = val_labels(values),
            class = class(values),
            format = attr(values, "format.stata", exact = TRUE),
            provenance = attr(values, "provenance", exact = TRUE)
        ),
        list(
            values = c(0, 1),
            labels = dta_double(c(No = 0, Yes = 1)),
            class = c("haven_labelled", "vctrs_vctr", "double"),
            format = "%8.0g",
            provenance = "imported"
        )
    )
})

test_that("val_labels replacement updates named columns and can clear all", {
    data <- data.frame(x = c(0, 1), y = c(1, 2))
    val_labels(data$x) <- c(No = 0, Yes = 1)
    val_labels(data$y) <- c(First = 1, Second = 2)

    val_labels(data) <- list(x = c(Absent = 0, Present = 1), y = NULL)
    updated <- val_labels(data)
    updated_classes <- lapply(data, class)
    val_labels(data) <- NULL

    expect_identical(
        list(
            updated = updated,
            updated_classes = updated_classes,
            cleared = val_labels(data),
            cleared_classes = lapply(data, class)
        ),
        list(
            updated = list(x = dta_double(c(Absent = 0, Present = 1)), y = NULL),
            updated_classes = list(
                x = c("haven_labelled", "vctrs_vctr", "double"),
                y = "numeric"
            ),
            cleared = list(x = NULL, y = NULL),
            cleared_classes = list(x = "numeric", y = "numeric")
        )
    )
})

test_that("set_val_labels combines named dots and .labels", {
    data <- dibble(x = c(0, 1), y = c(1, 2))

    updated <- set_val_labels(
        data,
        x = c(No = 0, Yes = 1),
        .labels = list(y = c(First = 1, Second = 2))
    )

    expect_identical(
        val_labels(updated),
        list(
            x = dta_double(c(No = 0, Yes = 1)),
            y = dta_double(c(First = 1, Second = 2))
        )
    )
})

test_that("set_val_labels supports vector pipelines", {
    values <- c(0, 1)

    updated <- set_val_labels(values, No = 0, Yes = 1)

    expect_identical(
        list(values = as.vector(updated), labels = val_labels(updated)),
        list(values = c(0, 1), labels = dta_double(c(No = 0, Yes = 1)))
    )
})

test_that("bulk value-label limits produce one complete portability warning", {
    data <- dibble(x = 1, y = 1)
    overlong_text <- iconv(
        paste(rep("é", 16001), collapse = ""),
        from = "UTF-8",
        to = "latin1"
    )
    too_many <- seq_len(65537L) - 1
    names(too_many) <- paste0("Label ", seq_along(too_many))
    messages <- character()

    updated <- withCallingHandlers(
        set_val_labels(
            data,
            x = stats::setNames(1, overlong_text),
            y = too_many
        ),
        warning = function(condition) {
            messages <<- c(messages, conditionMessage(condition))
            invokeRestart("muffleWarning")
        }
    )

    expect_identical(
        list(
            warning_count = length(messages),
            mentions_x = grepl("value-label text for `x`", messages,
                               fixed = TRUE),
            mentions_y = grepl("value-label table for `y`", messages,
                               fixed = TRUE),
            mentions_text_limit = grepl(
                "32,000 UTF-8 bytes", messages, fixed = TRUE
            ),
            mentions_table_limit = grepl(
                "65,536 entries", messages, fixed = TRUE
            ),
            stored_text_bytes = nchar(
                enc2utf8(names(val_labels(updated$x))),
                type = "bytes"
            ),
            stored_entries = length(val_labels(updated$y))
        ),
        list(
            warning_count = 1L,
            mentions_x = TRUE,
            mentions_y = TRUE,
            mentions_text_limit = TRUE,
            mentions_table_limit = TRUE,
            stored_text_bytes = 32002L,
            stored_entries = 65537L
        )
    )
})

test_that("Stata 19 metadata boundaries do not warn", {
    data <- dibble(x = 1, y = 1)
    exact_variable <- paste(rep("é", 80), collapse = "")
    exact_text <- paste(rep("é", 16000), collapse = "")
    exact_table <- seq_len(65536L) - 1
    names(exact_table) <- paste0("Label ", seq_along(exact_table))

    expect_no_warning({
        dataset_label(data) <- exact_variable
        data <- set_var_labels(data, x = exact_variable)
        data <- set_val_labels(
            data,
            x = stats::setNames(1, exact_text),
            y = exact_table
        )
    })

    expect_identical(
        c(
            dataset = nchar(dataset_label(data), type = "chars"),
            variable = nchar(var_label(data$x), type = "chars"),
            value_text = nchar(names(val_labels(data$x)), type = "bytes"),
            table_entries = length(val_labels(data$y))
        ),
        c(
            dataset = 80L,
            variable = 80L,
            value_text = 32000L,
            table_entries = 65536L
        )
    )
})

test_that("value-label codes cover Stata long boundaries and extended missings", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    missing <- read_dta(path, col_select = x_byte, n_max = 27)$x_byte[c(2, 27)]
    labels <- c(
        Minimum = -2147483647,
        Maximum = 2147483620,
        MissingA = missing[[1L]],
        MissingZ = missing[[2L]]
    )

    updated <- set_val_labels(c(1, 2), .labels = labels)

    expect_identical(
        list(
            observed = as.double(val_labels(updated)[1:2]),
            missing_codes = unname(dtatools:::.tab_missing_codes(
                val_labels(updated)[3:4]
            ))
        ),
        list(
            observed = c(-2147483647, 2147483620),
            missing_codes = c(utf8ToInt("a"), utf8ToInt("z"))
        )
    )
})

test_that("value-label setters reject codes outside Stata's label domain", {
    invalid <- list(
        fraction = c(Label = 1.5),
        system_missing = c(Label = NA_real_),
        r_nan = c(Label = NaN),
        infinity = c(Label = Inf),
        below_long = c(Label = -2147483648),
        above_long = c(Label = 2147483621),
        duplicate = c(First = 1, Second = 1)
    )

    rejected <- vapply(invalid, function(labels) {
        inherits(
            try(set_val_labels(c(0, 1), .labels = labels), silent = TRUE),
            "try-error"
        )
    }, logical(1))

    expect_identical(unname(rejected), rep(TRUE, length(invalid)))
})

test_that("empty value-label text is discarded and duplicate text is allowed", {
    labels <- stats::setNames(
        c(1, 2, 3, 4), c("Shared", "Shared", "", NA_character_)
    )

    updated <- set_val_labels(c(1, 2, 3, 4), .labels = labels)
    removed <- set_val_labels(
        updated,
        .labels = stats::setNames(c(1, 2), c("", NA_character_))
    )

    expect_identical(
        list(labels = val_labels(updated), removed_class = class(removed)),
        list(labels = dta_double(c(Shared = 1, Shared = 2)), removed_class = "numeric")
    )
})

test_that("value-label setters preserve Date and POSIXct classes", {
    dates <- structure(
        as.Date(c("1970-01-01", "1970-01-02")),
        format.stata = "%td"
    )
    times <- as.POSIXct(c("1970-01-01", "1970-01-02"), tz = "UTC")
    attr(times, "format.stata") <- "%tc"

    val_labels(dates) <- c(Epoch = 0)
    val_labels(times) <- c(Epoch = 0)

    expect_identical(
        list(
            date_class = class(dates),
            date_format = attr(dates, "format.stata", exact = TRUE),
            time_class = class(times),
            time_zone = attr(times, "tzone", exact = TRUE),
            time_format = attr(times, "format.stata", exact = TRUE)
        ),
        list(
            date_class = "Date",
            date_format = "%td",
            time_class = c("POSIXct", "POSIXt"),
            time_zone = "UTC",
            time_format = "%tc"
        )
    )
})

test_that("removing value labels retains unrelated numeric classes", {
    values <- structure(
        c(0, 1),
        class = c("dta_custom", "vctrs_vctr")
    )

    labelled <- set_val_labels(values, No = 0, Yes = 1)
    removed <- set_val_labels(labelled)

    expect_identical(
        list(labelled_class = class(labelled), removed_class = class(removed)),
        list(
            labelled_class = c("dta_custom", "vctrs_vctr"),
            removed_class = c("dta_custom", "vctrs_vctr")
        )
    )
})

test_that("value-label setters keep imported numeric storage compact", {
    source <- read_dta(fixture("value_labels_v118.dta"))$foreign

    updated <- set_val_labels(source, Domestic = 0, Imported = 1)

    expect_identical(
        list(
            source_is_native_altrep = dtatools:::.is_numeric_altrep(source),
            source_is_unmaterialized =
                dtatools:::.is_unmaterialized_numeric_altrep(source),
            result_is_altrep = dtatools:::.is_altrep(updated),
            result_is_unmaterialized =
                dtatools:::.is_unmaterialized_numeric_altrep(updated),
            source_labels = val_labels(source),
            result_labels = val_labels(updated),
            result_format = attr(updated, "format.stata", exact = TRUE)
        ),
        list(
            source_is_native_altrep = TRUE,
            source_is_unmaterialized = TRUE,
            result_is_altrep = TRUE,
            result_is_unmaterialized = TRUE,
            source_labels = dta_double(c(Domestic = 0, Foreign = 1)),
            result_labels = dta_double(c(Domestic = 0, Imported = 1)),
            result_format = "%8.0g"
        )
    )
})

test_that("repeated metadata setters keep numeric backing unmaterialized", {
    source <- read_dta(fixture("value_labels_v118.dta"))$foreign

    updated <- source
    for (index in seq_len(100L)) {
        updated <- set_var_labels(updated, paste("Vehicle origin", index))
    }
    updated <- set_val_labels(updated, Domestic = 0, Imported = 1)

    expect_identical(
        list(
            unmaterialized =
                dtatools:::.is_unmaterialized_numeric_altrep(updated),
            proxy_depth = dtatools:::.metadata_proxy_depth(updated),
            variable = var_label(updated),
            values = val_labels(updated),
            format = attr(updated, "format.stata", exact = TRUE)
        ),
        list(
            unmaterialized = TRUE,
            proxy_depth = 1L,
            variable = "Vehicle origin 100",
            values = dta_double(c(Domestic = 0, Imported = 1)),
            format = "%8.0g"
        )
    )
})

test_that("aggregate operations keep metadata proxies unmaterialized", {
    source <- read_dta(fixture("auto_v118.dta"))$price
    updated <- set_var_labels(source, "Price")
    invisible(dtatools:::.metadata_proxy_aggregate_mask(TRUE))
    on.exit(
        invisible(dtatools:::.metadata_proxy_aggregate_mask(FALSE)),
        add = TRUE
    )

    results <- list(
        sum = sum(updated),
        min = min(updated),
        max = max(updated),
        any_na = anyNA(updated)
    )
    aggregate_mask <- dtatools:::.metadata_proxy_aggregate_mask(FALSE)

    expect_identical(
        list(
            results = lapply(results[1:3], as.double),
            storage = vapply(
                results[1:3], dta_storage_type, character(1)
            ),
            any_na = results$any_na,
            aggregate_mask = aggregate_mask,
            unmaterialized =
                dtatools:::.is_unmaterialized_numeric_altrep(updated)
        ),
        list(
            results = list(
                sum = 456229,
                min = 3291,
                max = 15906
            ),
            storage = c(sum = "long", min = "int", max = "int"),
            any_na = FALSE,
            aggregate_mask = 15L,
            unmaterialized = TRUE
        )
    )
})

test_that("compactness probe detects materialized metadata proxies", {
    source <- read_dta(fixture("value_labels_v118.dta"))$foreign
    updated <- set_var_labels(source, "Vehicle origin")

    updated <- dtatools:::.force_altrep_materialization(updated)

    expect_identical(
        list(
            is_altrep = dtatools:::.is_altrep(updated),
            is_unmaterialized =
                dtatools:::.is_unmaterialized_numeric_altrep(updated),
            proxy_depth = dtatools:::.metadata_proxy_depth(updated),
            values = as.numeric(unclass(updated))
        ),
        list(
            is_altrep = TRUE,
            is_unmaterialized = FALSE,
            proxy_depth = 1L,
            values = rep(c(1, 0), 5L)
        )
    )
})

test_that("metadata proxies preserve copy-on-write in both directions", {
    source <- read_dta(fixture("value_labels_v118.dta"))$foreign
    updated <- set_var_labels(source, "Vehicle origin")
    updated[[1L]] <- 99

    second_source <- read_dta(fixture("value_labels_v118.dta"))$foreign
    second_updated <- set_var_labels(second_source, "Vehicle origin")
    second_source[[1L]] <- 99

    expect_identical(
        list(
            source_value = unclass(source)[[1L]],
            updated_value = unclass(updated)[[1L]],
            updated_is_unmaterialized =
                dtatools:::.is_unmaterialized_numeric_altrep(updated),
            second_source_value = unclass(second_source)[[1L]],
            second_updated_value = unclass(second_updated)[[1L]]
        ),
        list(
            source_value = 1,
            updated_value = 99,
            updated_is_unmaterialized = TRUE,
            second_source_value = 99,
            second_updated_value = 1
        )
    )
})

test_that("tab consumes value labels created by dtatools helpers", {
    values <- set_val_labels(c(0, 1, 0), Domestic = 0, Imported = 1)

    expect_identical(
        dimnames(tab(values))[[1L]],
        c("Domestic", "Imported")
    )
})

test_that("bulk setters reject ambiguous column updates atomically", {
    data <- dibble(x = c(0, 1), y = c(1, 2))
    attr(data$x, "label") <- "Original x"
    original <- copy_data(data)

    calls <- list(
        function() set_var_labels(
            data, x = "From dots", .labels = list(x = "From list")
        ),
        function() set_var_labels(data, x = "First", x = "Second"),
        function() set_var_labels(data, unknown = "Unknown"),
        function() set_var_labels(data, "Positional"),
        function() set_val_labels(
            data, x = c(No = 0), .labels = list(x = c(Yes = 1))
        )
    )

    rejected <- vapply(calls, function(call) {
        inherits(try(call(), silent = TRUE), "try-error")
    }, logical(1))

    expect_identical(
        list(rejected = rejected, data = as.data.frame(data)),
        list(rejected = rep(TRUE, length(calls)), data = as.data.frame(original))
    )
})

test_that("table label setters reject plain containers before any update", {
    makers <- list(data.frame, tibble::tibble)
    if (requireNamespace("data.table", quietly = TRUE)) {
        makers <- c(makers, data.table::data.table)
    }
    for (make in makers) {
        data <- make(x = c(0, 1))
        expect_error(set_var_labels(data, x = "Label"), "must be a dibble")
        expect_error(set_var_label(data, x, "Label"), "must be a dibble")
        expect_error(set_val_labels(data, x = c(No = 0)), "must be a dibble")
        expect_false(inherits(data, "dtatools_ref_data"))
        expect_null(var_label(data$x))
        expect_null(val_labels(data$x))
    }
})

test_that("whole-table label clearing handles duplicated column names", {
    data <- data.frame(x = c(0, 1), x = c(1, 2), check.names = FALSE)
    attr(data[[1L]], "label") <- "First"
    attr(data[[2L]], "label") <- "Second"
    attr(data[[1L]], "labels") <- c(No = 0, Yes = 1)
    attr(data[[2L]], "labels") <- c(First = 1, Second = 2)

    var_label(data) <- NULL
    val_labels(data) <- NULL
    expect_identical(
        list(variable = var_label(data), values = val_labels(data)),
        list(
            variable = list(x = NULL, x = NULL),
            values = list(x = NULL, x = NULL)
        )
    )
})

test_that("value labels can only be attached to numeric Stata variables", {
    expect_error(
        set_val_labels(c("No", "Yes"), No = 0, Yes = 1),
        "numeric"
    )
    expect_error(
        set_val_labels(factor(c("No", "Yes")), No = 1, Yes = 2),
        "numeric Stata variable"
    )
    expect_error(
        set_val_labels(matrix(c(0, 1), ncol = 1), No = 0, Yes = 1),
        "numeric Stata variable"
    )
})

test_that("value-label tables must be numeric vectors", {
    invalid <- list(
        empty_character = character(),
        empty_list = list(),
        empty_raw = raw(),
        factor = stats::setNames(factor(c("1", "2")), c("No", "Yes")),
        matrix = matrix(c(0, 1), ncol = 1,
                        dimnames = list(c("No", "Yes"), NULL))
    )

    rejected <- vapply(invalid, function(labels) {
        inherits(
            try(set_val_labels(c(0, 1), .labels = labels), silent = TRUE),
            "try-error"
        )
    }, logical(1))

    expect_identical(unname(rejected), rep(TRUE, length(invalid)))
})

test_that("label helpers reject non-vector reference objects", {
    value <- new.env(parent = emptyenv())
    attr(value, "label") <- "Original"
    attr(value, "labels") <- c(No = 0, Yes = 1)

    calls <- list(
        function() var_label(value),
        function() val_labels(value),
        function() set_var_labels(value, "Changed"),
        function() set_val_labels(value)
    )
    rejected <- vapply(calls, function(call) {
        inherits(try(call(), silent = TRUE), "try-error")
    }, logical(1))

    expect_identical(
        list(
            rejected = rejected,
            variable = attr(value, "label", exact = TRUE),
            values = attr(value, "labels", exact = TRUE)
        ),
        list(
            rejected = rep(TRUE, length(calls)),
            variable = "Original",
            values = c(No = 0, Yes = 1)
        )
    )
})

test_that("bulk value-label setters normalize each table once", {
    counter <- new.env(parent = emptyenv())
    counter$calls <- 0L
    suppressMessages(trace(
        ".tab_missing_codes",
        tracer = function() counter$calls <- counter$calls + 1L,
        where = asNamespace("dtatools"),
        print = FALSE
    ))
    on.exit(suppressMessages(untrace(
        ".tab_missing_codes", where = asNamespace("dtatools")
    )), add = TRUE)

    updated <- set_val_labels(
        dibble(x = c(0, 1)), x = c(No = 0, Yes = 1)
    )

    expect_identical(
        list(calls = counter$calls, labels = val_labels(updated$x)),
        list(calls = 1L, labels = dta_double(c(No = 0, Yes = 1)))
    )
})

test_that("dibble set functions mutate by reference", {
    data <- dibble(a = 1:3, b = c(10, 20, 30))
    alias <- data

    set_var_labels(data, a = "Alpha")
    expect_identical(var_label(data$a), "Alpha")
    expect_identical(var_label(alias$a), "Alpha")

    set_val_labels(data, a = c(One = 1L))
    expect_identical(val_labels(data$a), dta_long(c(One = 1L)))
    expect_identical(val_labels(alias$a), dta_long(c(One = 1L)))

    set_var_label(data, b, "Beta")
    expect_identical(var_label(data$b), "Beta")
    expect_identical(var_label(alias$b), "Beta")
})

test_that("label setters still return the dibble for pipeline use", {
    data <- dibble(a = 1:3)
    expect_identical(var_label(set_var_labels(data, a = "Alpha")$a), "Alpha")
    expect_identical(var_label(set_var_label(data, a, "Beta")$a), "Beta")
})

test_that("copy_data isolates a dibble from later label setters", {
    source <- dibble(a = 1:3)
    isolated <- copy_data(source)
    set_var_labels(source, a = "Alpha")
    expect_identical(var_label(source$a), "Alpha")
    expect_null(var_label(isolated$a))
})

test_that("vector label setters keep copy semantics", {
    values <- 1:3
    invisible(set_var_labels(values, "Alpha"))
    expect_null(var_label(values))
    invisible(set_val_labels(values, One = 1L))
    expect_null(val_labels(values))
})

test_that("set_var_label requires one unquoted existing column", {
    data <- dibble(a = 1:3)
    expect_error(set_var_label(data, missing_column, "Alpha"),
                 "Unknown column")
    expect_error(set_var_label(data, a + 1, "Alpha"),
                 "unquoted column name")
    expect_error(set_var_label(1:3, a, "Alpha"), "must be a data frame")
})

test_that("set_var_label labels a generated reference column", {
    data <- dibble(a = 1:3)
    gen(data, doubled, a * 2)

    set_var_label(data, doubled, "Doubled")
    expect_identical(var_label(data$doubled), "Doubled")

    set_var_label(data, a, "Alpha")
    expect_identical(var_label(data$a), "Alpha")
})

test_that("val_labels returns a Stata numeric that compares and prints as Stata", {
    # ADR 0040: the codes are Stata values, so a tagged missing is found by
    # `==` and prints as `.a`, where the bare double compared `NA == NA`.
    x <- set_val_labels(
        dta_byte(c(1, 2, tagged_missing("a"), NA)),
        One = 1, Refused = tagged_missing("a")
    )
    labels <- val_labels(x)
    expect_s3_class(labels, "dta_double")
    expect_identical(names(labels), c("One", "Refused"))
    expect_identical(names(labels)[labels == tagged_missing("a")], "Refused")
    expect_identical(names(labels)[labels == .a], "Refused")
    expect_identical(names(labels)[labels == 1], "One")
    expect_identical(format(labels), c(One = " 1", Refused = ".a"))
    expect_output(print(labels), ".a", fixed = TRUE)
    expect_identical(as.double(labels), c(1, tagged_missing("a")))
    expect_type(attr(x, "labels"), "double")
    expect_null(attr(attr(x, "labels"), "class"))

    # The table goes back into any setter and lands as the bare attribute.
    y <- set_val_labels(c(1, 2), .labels = labels)
    expect_identical(attr(y, "labels"), attr(x, "labels"))
    y <- dibble(y = c(1, 2))
    set_val_labels(y, y, labels)
    expect_identical(attr(y$y, "labels"), attr(x, "labels"))

    # Data frame and (data, variable) shapes agree.
    data <- dibble(x = x, plain = 1:4)
    expect_identical(val_labels(data, x), labels)
    expect_identical(val_labels(data), list(x = labels, plain = NULL))
    expect_null(val_labels(data$plain))

    # An integer-coded haven table reads as a double table; an empty
    # declared table stays an empty table.
    integers <- set_val_labels(1:2, .labels = c(one = 1L, two = 2L))
    expect_identical(val_labels(integers), dta_long(c(one = 1, two = 2)))
    empty <- dibble(z = 1:2)
    set_dta_metadata(
        empty, variable = "z", labels = stats::setNames(double(), character()),
        value.label.name = "empty"
    )
    expect_identical(
        val_labels(empty$z), dta_double(stats::setNames(double(), character()))
    )

    # Reading the table does not materialize a compact column.
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(data.frame(x = x), path)
    read <- read_dta(path)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(read$x))
    expect_identical(val_labels(read$x), labels)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(read$x))
})

test_that("a label table Stata could not hold is returned as haven stores it", {
    x <- structure(c("a", "b"), labels = c(A = "a"),
                   class = c("haven_labelled", "vctrs_vctr", "character"))
    expect_identical(val_labels(x), c(A = "a"))
    expect_identical(val_labels(data.frame(x = x, y = 1:2)), list(x = c(A = "a"), y = NULL))
    # Numeric codes outside Stata's label range come back bare too, so the
    # table stays usable rather than a Stata numeric with an invalid payload.
    wide <- structure(1L, labels = c(Bad = .Machine$integer.max),
                      class = c("haven_labelled", "vctrs_vctr", "integer"))
    expect_identical(val_labels(wide), c(Bad = .Machine$integer.max))
    expect_identical(val_labels(wide)[1], c(Bad = .Machine$integer.max))
    infinite <- structure(c(1, 2), labels = c(Forever = Inf),
                          class = c("haven_labelled", "vctrs_vctr", "double"))
    expect_identical(sort(val_labels(infinite)), c(Forever = Inf))
})

test_that("a table remembers its codes' type so setting it back is exact", {
    # haven stores integer codes on an integer vector and writes that
    # vector only with integer codes. The table reads as a `long`, and any
    # setter stores it back as the integers it came from.
    integers <- set_val_labels(1:2, .labels = c(one = 1L, two = 2L))
    before <- attr(integers, "labels")
    expect_identical(val_labels(integers), dta_long(c(one = 1, two = 2)))
    val_labels(integers) <- val_labels(integers)
    expect_identical(attr(integers, "labels"), before)
    integers <- set_val_labels(integers, .labels = val_labels(integers))
    expect_identical(attr(integers, "labels"), before)
    bundled <- set_dta_metadata(1:2, labels = val_labels(integers))
    expect_identical(attr(bundled, "labels"), before)
    empty <- set_dta_metadata(1:2, labels = stats::setNames(integer(), character()),
                              value.label.name = "empty")
    empty <- set_dta_metadata(empty, labels = val_labels(empty))
    expect_identical(attr(empty, "labels"), stats::setNames(integer(), character()))
    # The plain setters keep a declared empty table too, with its name and
    # class, while an unnamed `numeric()` still clears the table.
    val_labels(empty) <- val_labels(empty)
    expect_identical(attr(empty, "labels"), stats::setNames(integer(), character()))
    expect_identical(attr(empty, "value.label.name"), "empty")
    expect_s3_class(empty, "haven_labelled")
    empty <- set_val_labels(empty, val_labels(empty))
    expect_identical(attr(empty, "labels"), stats::setNames(integer(), character()))
    frame <- data.frame(z = 1:2)
    val_labels(frame) <- list(z = val_labels(empty))
    expect_identical(attr(frame$z, "labels"), stats::setNames(integer(), character()))
    val_labels(empty) <- numeric()
    expect_null(attr(empty, "labels"))
    expect_null(attr(empty, "value.label.name"))

    # A `long` table edited to hold a tagged missing stays double, so `.a`
    # is stored as `.a` and not collapsed to `.`.
    edited <- val_labels(integers)
    edited[2] <- .a
    expect_s3_class(edited, "dta_long")
    back <- set_val_labels(c(1, 2), .labels = edited)
    expect_identical(attr(back, "labels"), c(one = 1, two = .a))
    expect_identical(unname(missing_tag(attr(back, "labels"))), c(NA, "a"))
    bundled <- set_dta_metadata(c(1, 2), labels = edited)
    expect_identical(attr(bundled, "labels"), c(one = 1, two = .a))

    # Double codes stay double whatever the vector, as before, and a table
    # is never stored as the classed object it was read as.
    doubles <- set_val_labels(1:2, .labels = c(one = 1, two = 2))
    expect_identical(attr(doubles, "labels"), c(one = 1, two = 2))
    expect_identical(val_labels(doubles), dta_double(c(one = 1, two = 2)))
    tagged <- set_val_labels(c(1, 2), .labels = c(one = 1, refused = .a))
    stored <- set_dta_metadata(c(1, 2), labels = val_labels(tagged))
    expect_identical(attr(stored, "labels"), c(one = 1, refused = .a))
    expect_null(attr(attr(stored, "labels"), "class"))
    data <- dibble(g = 1:2, h = c(1, 2))
    set_val_labels(data, g = val_labels(integers), h = val_labels(doubles))
    expect_identical(attr(data$g, "labels"), before)
    expect_identical(attr(data$h, "labels"), c(one = 1, two = 2))
    val_labels(data) <- list(g = val_labels(data$g))
    expect_identical(attr(data$g, "labels"), before)
    # The variadic setter keeps a whole table's storage too.
    h <- structure(c(1L, 2L), labels = c(One = 1L, Two = 2L),
                   class = c("haven_labelled", "vctrs_vctr", "integer"))
    back <- set_val_labels(h, val_labels(h))
    expect_identical(attr(back, "labels"), c(One = 1L, Two = 2L))
    # Combining a table with further pairs joins them as `c()` would.
    extended <- set_val_labels(h, val_labels(h), Three = 3L)
    expect_identical(attr(extended, "labels"), c(One = 1, Two = 2, Three = 3))
})
