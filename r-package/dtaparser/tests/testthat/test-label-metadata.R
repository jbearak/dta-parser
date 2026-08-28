test_that("var_label returns a vector's variable label", {
    values <- structure(c(1, 2), label = "Interview status")

    expect_identical(var_label(values), "Interview status")
})

test_that("val_labels returns a vector's value-label table", {
    values <- structure(c(1, 2), labels = c(Complete = 1, Refused = 2))

    expect_identical(val_labels(values), c(Complete = 1, Refused = 2))
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
            values = list(labelled = c(No = 0, Yes = 1), plain = NULL)
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

test_that("set_variable_labels combines named dots and .labels", {
    data <- data.frame(x = 1, y = 2)

    updated <- set_variable_labels(
        data,
        x = "Interview status",
        .labels = list(y = "Sampling stratum")
    )

    expect_identical(
        var_label(updated),
        list(x = "Interview status", y = "Sampling stratum")
    )
})

test_that("set_variable_labels supports vector pipelines", {
    values <- c(1, 2)

    updated <- set_variable_labels(values, "Interview status")

    expect_identical(
        list(values = as.vector(updated), label = var_label(updated)),
        list(values = c(1, 2), label = "Interview status")
    )
})

test_that("bulk variable-label limits produce one complete portability warning", {
    data <- data.frame(x = 1, y = 2)
    over_limit <- paste(rep("é", 81), collapse = "")
    messages <- character()

    updated <- withCallingHandlers(
        set_variable_labels(data, x = over_limit, y = over_limit),
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

    updated <- set_variable_labels(source, "Vehicle origin")

    expect_identical(
        list(
            source_is_native_altrep = dtaparser:::.is_numeric_altrep(source),
            source_is_unmaterialized =
                dtaparser:::.is_unmaterialized_numeric_altrep(source),
            result_is_altrep = dtaparser:::.is_altrep(updated),
            result_is_unmaterialized =
                dtaparser:::.is_unmaterialized_numeric_altrep(updated),
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
            labels = c(No = 0, Yes = 1),
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
            updated = list(x = c(Absent = 0, Present = 1), y = NULL),
            updated_classes = list(
                x = c("haven_labelled", "vctrs_vctr", "double"),
                y = "numeric"
            ),
            cleared = list(x = NULL, y = NULL),
            cleared_classes = list(x = "numeric", y = "numeric")
        )
    )
})

test_that("set_value_labels combines named dots and .labels", {
    data <- data.frame(x = c(0, 1), y = c(1, 2))

    updated <- set_value_labels(
        data,
        x = c(No = 0, Yes = 1),
        .labels = list(y = c(First = 1, Second = 2))
    )

    expect_identical(
        val_labels(updated),
        list(
            x = c(No = 0, Yes = 1),
            y = c(First = 1, Second = 2)
        )
    )
})

test_that("set_value_labels supports vector pipelines", {
    values <- c(0, 1)

    updated <- set_value_labels(values, No = 0, Yes = 1)

    expect_identical(
        list(values = as.vector(updated), labels = val_labels(updated)),
        list(values = c(0, 1), labels = c(No = 0, Yes = 1))
    )
})

test_that("bulk value-label limits produce one complete portability warning", {
    data <- data.frame(x = 1, y = 1)
    overlong_text <- iconv(
        paste(rep("é", 16001), collapse = ""),
        from = "UTF-8",
        to = "latin1"
    )
    too_many <- seq_len(65537L) - 1
    names(too_many) <- paste0("Label ", seq_along(too_many))
    messages <- character()

    updated <- withCallingHandlers(
        set_value_labels(
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
    data <- data.frame(x = 1, y = 1)
    exact_variable <- paste(rep("é", 80), collapse = "")
    exact_text <- paste(rep("é", 16000), collapse = "")
    exact_table <- seq_len(65536L) - 1
    names(exact_table) <- paste0("Label ", seq_along(exact_table))

    expect_no_warning({
        dataset_label(data) <- exact_variable
        data <- set_variable_labels(data, x = exact_variable)
        data <- set_value_labels(
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

    updated <- set_value_labels(c(1, 2), .labels = labels)

    expect_identical(
        list(
            observed = unname(val_labels(updated)[1:2]),
            missing_codes = unname(dtaparser:::.tab_missing_codes(
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
            try(set_value_labels(c(0, 1), .labels = labels), silent = TRUE),
            "try-error"
        )
    }, logical(1))

    expect_identical(unname(rejected), rep(TRUE, length(invalid)))
})

test_that("empty value-label text is discarded and duplicate text is allowed", {
    labels <- stats::setNames(
        c(1, 2, 3, 4), c("Shared", "Shared", "", NA_character_)
    )

    updated <- set_value_labels(c(1, 2, 3, 4), .labels = labels)
    removed <- set_value_labels(
        updated,
        .labels = stats::setNames(c(1, 2), c("", NA_character_))
    )

    expect_identical(
        list(labels = val_labels(updated), removed_class = class(removed)),
        list(labels = c(Shared = 1, Shared = 2), removed_class = "numeric")
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
        class = c("stata_custom", "vctrs_vctr")
    )

    labelled <- set_value_labels(values, No = 0, Yes = 1)
    removed <- set_value_labels(labelled)

    expect_identical(
        list(labelled_class = class(labelled), removed_class = class(removed)),
        list(
            labelled_class = c("stata_custom", "vctrs_vctr"),
            removed_class = c("stata_custom", "vctrs_vctr")
        )
    )
})

test_that("value-label setters keep imported numeric storage compact", {
    source <- read_dta(fixture("value_labels_v118.dta"))$foreign

    updated <- set_value_labels(source, Domestic = 0, Imported = 1)

    expect_identical(
        list(
            source_is_native_altrep = dtaparser:::.is_numeric_altrep(source),
            source_is_unmaterialized =
                dtaparser:::.is_unmaterialized_numeric_altrep(source),
            result_is_altrep = dtaparser:::.is_altrep(updated),
            result_is_unmaterialized =
                dtaparser:::.is_unmaterialized_numeric_altrep(updated),
            source_labels = val_labels(source),
            result_labels = val_labels(updated),
            result_format = attr(updated, "format.stata", exact = TRUE)
        ),
        list(
            source_is_native_altrep = TRUE,
            source_is_unmaterialized = TRUE,
            result_is_altrep = TRUE,
            result_is_unmaterialized = TRUE,
            source_labels = c(Domestic = 0, Foreign = 1),
            result_labels = c(Domestic = 0, Imported = 1),
            result_format = "%8.0g"
        )
    )
})

test_that("repeated metadata setters keep numeric backing unmaterialized", {
    source <- read_dta(fixture("value_labels_v118.dta"))$foreign

    updated <- source
    for (index in seq_len(100L)) {
        updated <- set_variable_labels(updated, paste("Vehicle origin", index))
    }
    updated <- set_value_labels(updated, Domestic = 0, Imported = 1)

    expect_identical(
        list(
            unmaterialized =
                dtaparser:::.is_unmaterialized_numeric_altrep(updated),
            proxy_depth = dtaparser:::.metadata_proxy_depth(updated),
            variable = var_label(updated),
            values = val_labels(updated),
            format = attr(updated, "format.stata", exact = TRUE)
        ),
        list(
            unmaterialized = TRUE,
            proxy_depth = 1L,
            variable = "Vehicle origin 100",
            values = c(Domestic = 0, Imported = 1),
            format = "%8.0g"
        )
    )
})

test_that("aggregate operations keep metadata proxies unmaterialized", {
    source <- read_dta(fixture("auto_v118.dta"))$price
    updated <- set_variable_labels(source, "Price")
    invisible(dtaparser:::.metadata_proxy_aggregate_mask(TRUE))
    on.exit(
        invisible(dtaparser:::.metadata_proxy_aggregate_mask(FALSE)),
        add = TRUE
    )

    results <- list(
        sum = sum(updated),
        min = min(updated),
        max = max(updated),
        any_na = anyNA(updated)
    )
    aggregate_mask <- dtaparser:::.metadata_proxy_aggregate_mask(FALSE)

    expect_identical(
        list(
            results = lapply(results[1:3], as.double),
            storage = vapply(
                results[1:3], stata_storage_type, character(1)
            ),
            any_na = results$any_na,
            aggregate_mask = aggregate_mask,
            unmaterialized =
                dtaparser:::.is_unmaterialized_numeric_altrep(updated)
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
    updated <- set_variable_labels(source, "Vehicle origin")

    updated <- dtaparser:::.force_altrep_materialization(updated)

    expect_identical(
        list(
            is_altrep = dtaparser:::.is_altrep(updated),
            is_unmaterialized =
                dtaparser:::.is_unmaterialized_numeric_altrep(updated),
            proxy_depth = dtaparser:::.metadata_proxy_depth(updated),
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
    updated <- set_variable_labels(source, "Vehicle origin")
    updated[[1L]] <- 99

    second_source <- read_dta(fixture("value_labels_v118.dta"))$foreign
    second_updated <- set_variable_labels(second_source, "Vehicle origin")
    second_source[[1L]] <- 99

    expect_identical(
        list(
            source_value = unclass(source)[[1L]],
            updated_value = unclass(updated)[[1L]],
            updated_is_unmaterialized =
                dtaparser:::.is_unmaterialized_numeric_altrep(updated),
            second_source_value = unclass(second_source)[[1L]],
            second_updated_value = unclass(second_updated)[[1L]]
        ),
        list(
            source_value = 1,
            updated_value = 99,
            updated_is_unmaterialized = FALSE,
            second_source_value = 99,
            second_updated_value = 1
        )
    )
})

test_that("tab consumes value labels created by dtaparser helpers", {
    values <- set_value_labels(c(0, 1, 0), Domestic = 0, Imported = 1)

    expect_identical(
        dimnames(tab(values))[[1L]],
        c("Domestic", "Imported")
    )
})

test_that("bulk setters reject ambiguous column updates atomically", {
    data <- data.frame(x = c(0, 1), y = c(1, 2))
    attr(data$x, "label") <- "Original x"
    original <- data

    calls <- list(
        function() set_variable_labels(
            data, x = "From dots", .labels = list(x = "From list")
        ),
        function() set_variable_labels(data, x = "First", x = "Second"),
        function() set_variable_labels(data, unknown = "Unknown"),
        function() set_variable_labels(data, "Positional"),
        function() set_value_labels(
            data, x = c(No = 0), .labels = list(x = c(Yes = 1))
        )
    )

    rejected <- vapply(calls, function(call) {
        inherits(try(call(), silent = TRUE), "try-error")
    }, logical(1))

    expect_identical(
        list(rejected = rejected, data = data),
        list(rejected = rep(TRUE, length(calls)), data = original)
    )
})

test_that("named updates reject duplicated data-frame column names", {
    data <- data.frame(x = c(0, 1), x = c(1, 2), check.names = FALSE)
    attr(data[[1L]], "label") <- "First"
    attr(data[[2L]], "label") <- "Second"
    attr(data[[1L]], "labels") <- c(No = 0, Yes = 1)
    attr(data[[2L]], "labels") <- c(First = 1, Second = 2)
    original <- data

    expect_error(set_variable_labels(data, x = "Ambiguous"), "ambiguous")
    expect_error(set_value_labels(data, x = c(Zero = 0)), "ambiguous")
    expect_identical(data, original)

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
        set_value_labels(c("No", "Yes"), No = 0, Yes = 1),
        "numeric"
    )
    expect_error(
        set_value_labels(factor(c("No", "Yes")), No = 1, Yes = 2),
        "numeric Stata variable"
    )
    expect_error(
        set_value_labels(matrix(c(0, 1), ncol = 1), No = 0, Yes = 1),
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
            try(set_value_labels(c(0, 1), .labels = labels), silent = TRUE),
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
        function() set_variable_labels(value, "Changed"),
        function() set_value_labels(value)
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
        where = asNamespace("dtaparser"),
        print = FALSE
    ))
    on.exit(suppressMessages(untrace(
        ".tab_missing_codes", where = asNamespace("dtaparser")
    )), add = TRUE)

    updated <- set_value_labels(
        data.frame(x = c(0, 1)), x = c(No = 0, Yes = 1)
    )

    expect_identical(
        list(calls = counter$calls, labels = val_labels(updated$x)),
        list(calls = 1L, labels = c(No = 0, Yes = 1))
    )
})
