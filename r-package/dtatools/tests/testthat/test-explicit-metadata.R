metadata_containers <- function() {
    makers <- list(dibble = dibble, tibble = tibble::tibble, frame = data.frame)
    if (requireNamespace("data.table", quietly = TRUE)) {
        makers$table <- data.table::data.table
    }
    makers
}

test_that("all table metadata setters reach aliases and function callers", {
    for (make in metadata_containers()) {
        for (variable in list(NULL, "x", 1L)) {
            data <- make(x = 1:2, y = c("a", "b"))
            alias <- data
            column <- data$x
            before <- copy_data(data)
            address <- rlang::obj_address(data)
            edit <- function(x) {
                set_dta_note(x, 4L, "four", variable)
                add_dta_note(x, "five", variable)
                renumber_dta_notes(x, 2L, variable)
                drop_dta_notes(x, 2L, variable)
                set_dta_characteristic(x, "source", "survey", variable)
                drop_dta_characteristics(x, "source", variable)
                set_dta_characteristic(x, "role", "id", variable)
            }
            result <- withVisible(edit(data))
            expect_false(result$visible)
            expect_identical(rlang::obj_address(result$value), address)
            expect_identical(dta_notes(alias, variable), c(`3` = "five"))
            expect_identical(dta_characteristics(alias, variable), c(role = "id"))
            expect_length(dta_notes(before, variable), 0L)
            expect_length(dta_notes(column), 0L)
            drop_dta_notes(data, variable = variable)
            drop_dta_characteristics(data, variable = variable)
            expect_identical(class(data), class(before))
        }
    }
})

test_that("format setters support literal and runtime target forms", {
    for (make in metadata_containers()) {
        data <- make(x = 1:2, y = 3:4)
        alias <- data
        original_classes <- lapply(data, class)
        name <- "x"
        edit <- function(data) set_var_format(data, .(name), "%9.0g")
        expect_false(withVisible(edit(data))$visible)
        expect_identical(attr(alias$x, "format.stata"), "%9.0g")
        set_var_format(data, !!name, "%10.0g")
        set_var_format(data, "x", "%11.0g")
        set_var_format(data, x, "%12.0g")
        set_var_formats(data, x, "%8.0g")
        set_var_formats(data, .(name) := "%6.0g", .formats = list(y = "%5.0g"))
        expect_identical(attr(alias$x, "format.stata"), "%6.0g")
        expect_identical(attr(alias$y, "format.stata"), "%5.0g")
        expect_identical(lapply(data, class), original_classes)
        set_var_formats(data, .formats = list(x = NULL, y = NULL))
        expect_null(attr(alias$x, "format.stata"))
        expect_null(attr(alias$y, "format.stata"))
    }
    x <- dta_float(1:2)
    changed <- set_var_format(x, "%9.0g")
    expect_null(attr(x, "format.stata"))
    expect_identical(attr(changed, "format.stata"), "%9.0g")
    expect_identical(set_var_formats(x, .formats = "%9.0g"), changed)
})

test_that("metadata bundles restore downstream runtime column metadata atomically", {
    for (make in metadata_containers()) {
        data <- make(x = 1:2)
        alias <- data
        my_name <- "x"
        edit <- function(data) {
            set_dta_metadata(data, variable = my_name,
                labels = c(Complete = 1, Refused = 2), value.label.name = "status",
                notes = c("first", "fourth"), stata.note.numbers = c(1L, 4L),
                stata.characteristics = c(source = "survey"), custom = list(a = 1))
        }
        expect_false(withVisible(edit(data))$visible)
        expect_identical(val_labels(alias$x), c(Complete = 1, Refused = 2))
        expect_identical(attr(alias$x, "value.label.name"), "status")
        expect_identical(dta_notes(alias, my_name), c(`1` = "first", `4` = "fourth"))
        expect_identical(dta_characteristics(alias, my_name), c(source = "survey"))
        set_dta_metadata(data, variable = my_name, .metadata = list(
            notes = NULL, stata.note.numbers = NULL, stata.characteristics = NULL))
        expect_length(dta_notes(alias, my_name), 0L)
        expect_null(attr(alias$x, "stata.note.numbers"))
        expect_length(dta_characteristics(alias, my_name), 0L)
        set_dta_metadata(data, variable = my_name, labels = stats::setNames(double(), character()), value.label.name = "empty")
        expect_identical(val_labels(alias$x), stats::setNames(double(), character()))
        expect_identical(attr(alias$x, "value.label.name"), "empty")
        set_dta_metadata(data, label = "Dataset label", source = "interviews")
        expect_identical(dataset_label(alias), "Dataset label")
        expect_identical(attr(alias, "source"), "interviews")
    }
})

test_that("failed metadata bundles and plural formats leave all state unchanged", {
    data <- dibble(x = 1:2, y = 3:4)
    alias <- data
    before <- copy_data(data)
    state <- dtatools:::.reference_state(data)
    expect_error(set_var_formats(data, x = "%9.0g", y = 1), "Stata format")
    expect_error(set_var_formats(data, x = "%9.0g", x = "%8.0g"), "duplicate")
    expect_error(set_var_formats(data, absent = "%9.0g"), "Unknown")
    expect_error(set_dta_metadata(data, label = "changed", class = "broken"), "Structural")
    for (key in c("names", "dim", "row.names", "levels", "tzone", "groups",
                  "units", "tsp", "contrasts", ".dtatools_ref_state",
                  ".internal.selfref", "stata.type", "sorted", "index")) {
        expect_error(set_dta_metadata(data, .metadata = setNames(list(NULL), key)), "Structural")
    }
    expect_error(set_dta_metadata(data, variable = "x", labels = c(bad = 1.5)), "integers")
    expect_error(set_dta_metadata(data, variable = "x", value.label.name = "1bad"), "valid Stata")
    expect_error(set_dta_metadata(data, notes = "one", stata.note.numbers = c(1L, 2L)), "malformed")
    expect_error(set_dta_metadata(data, notes = NULL, stata.note.numbers = 1L), "require notes")
    expect_error(set_dta_metadata(data, stata.characteristics = c(note1 = "bad")), "malformed")
    expect_error(set_dta_metadata(data, source = "one", .metadata = list(source = "two")), "unique")
    expect_identical(dtatools:::.reference_state(data), state)
    expect_identical(as.data.frame(alias), as.data.frame(before))
})

test_that("declared empty label tables reject nonnumeric targets atomically", {
    empty <- stats::setNames(double(), character())
    for (column in list(c("a", "b"), factor(c("a", "b")), c(TRUE, FALSE))) {
        data <- data.frame(x = column)
        before <- copy_data(data)
        expect_error(set_dta_metadata(data, variable = "x", label = "changed",
                                      labels = empty, value.label.name = "empty"),
                     "numeric Stata variable")
        expect_identical(data, before)
    }
    data <- data.frame(x = 1:2)
    set_dta_metadata(data, variable = "x", labels = c(One = 1), value.label.name = "named")
    set_dta_metadata(data, variable = "x", labels = empty)
    expect_identical(val_labels(data$x), empty)
    expect_identical(attr(data$x, "value.label.name"), "named")
    for (writer in list(save_dta, save_arrow)) {
        path <- tempfile(fileext = if (identical(writer, save_dta)) ".dta" else ".arrow")
        on.exit(unlink(path), add = TRUE)
        expect_silent(writer(data, path))
    }
    expect_error(set_dta_metadata(data, variable = "x", labels = NULL,
                                  value.label.name = "missing"), "requires a labels mapping")
    expect_identical(val_labels(data$x), empty)
})

test_that("metadata bundles preserve complete raw value-label mappings", {
    mapping <- stats::setNames(c(1, 2, tagged_missing("a")), c("", "Two", ""))
    for (make in metadata_containers()) {
        data <- make(x = dta_long(c(1, 2, tagged_missing("a")))); alias <- data
        my_name <- "x"
        set_dta_metadata(data, variable = my_name, labels = mapping,
                         value.label.name = "codes")
        expect_identical(val_labels(alias$x), mapping)
        expect_identical(attr(alias$x, "value.label.name"), "codes")
        for (writer in list(save_dta, save_arrow)) {
            path <- tempfile(fileext = if (identical(writer, save_dta)) ".dta" else ".arrow")
            on.exit(unlink(path), add = TRUE)
            writer(data, path)
            restored <- if (identical(writer, save_dta)) read_dta(path) else read_arrow(path)
            expect_identical(val_labels(restored$x), mapping)
            expect_identical(attr(restored$x, "value.label.name"), "codes")
        }
        before <- copy_data(data)
        expect_error(set_dta_metadata(data, variable = my_name,
                                      labels = stats::setNames(c(1, 1), c("", "One"))),
                     "duplicate")
        expect_error(set_dta_metadata(data, variable = my_name,
                                      labels = stats::setNames(c(1, 2), c(NA, "Two"))),
                     "non-missing text")
        expect_error(set_dta_metadata(data, variable = my_name,
                                      labels = stats::setNames(1, strrep("x", 32001L))),
                     "32,000 UTF-8 bytes")
        expect_identical(val_labels(data$x), val_labels(before$x))
        set_val_labels(data, .labels = stats::setNames(list(mapping), my_name))
        expect_identical(val_labels(data$x), c(Two = 2))
    }
})

test_that("metadata setters isolate copied and serialized bookkeeping both ways", {
    for (change in list(
        function(x) set_var_label(x, a, "Age"),
        function(x) set_val_labels(x, a, c(One = 1, Two = 2)),
        function(x) set_var_format(x, a, "%9.0g"),
        function(x) set_dta_note(x, 3L, "three", "a"),
        function(x) set_dta_note(x, 3L, "three"),
        function(x) set_dta_metadata(x, variable = "a", source = "survey")
    )) {
        for (direction in c("source", "copy")) {
            original <- dibble(a = 1:2)
            copied <- original
            attr(copied, "copied") <- TRUE
            target <- if (direction == "source") original else copied
            other <- if (direction == "source") copied else original
            physical_before <- dtatools:::.metadata_table_snapshot(other)
            state_before <- dtatools:::.reference_state(other)
            state_columns <- as.list(state_before$columns)
            change(target)
            expect_identical(dtatools:::.metadata_table_snapshot(other), physical_before)
            expect_identical(as.list(state_before$columns), state_columns)
            expect_false(identical(dtatools:::.reference_state(target), state_before))
        }
        restored <- unserialize(serialize(dibble(a = 1:2), NULL))
        address <- rlang::obj_address(restored)
        change(restored)
        expect_identical(rlang::obj_address(restored), address)
        expect_identical(rlang::obj_address(dtatools:::.reference_state(restored)$object), address)
        prepared <- reserve_columns(restored, 2L)
        expect_silent(gen(prepared, b = 1))
        expect_identical(names(prepared), c("a", "b"))
    }
})

test_that("metadata edits preserve compact storage, capacity, and data.table indexes", {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(dibble(x = dta_float(1:2), y = dta_string(c("a", "b"))), path)
    data <- read_dta(path)
    alias <- data
    capacity <- .Call(dtatools:::C_dtatools_column_capacity, data)
    numeric_compact <- dtatools:::.is_unmaterialized_numeric_altrep(data$x)
    string_compact <- dtatools:::.is_unmaterialized_dictstring(data$y)
    expect_true(numeric_compact)
    expect_true(string_compact)
    set_var_formats(data, x = "%9.0g", y = "%8s")
    set_dta_note(data, 1L, "dataset")
    set_dta_note(data, 4L, "string", "y")
    set_dta_characteristic(data, "source", "survey", "y")
    vector <- set_dta_note(data$y, 5L, "assigned vector")
    vector <- set_dta_characteristic(vector, "role", "id")
    expect_true(dtatools:::.is_unmaterialized_dictstring(vector))
    expect_null(dta_note(data$y, 5L))
    expect_identical(dtatools:::.is_unmaterialized_numeric_altrep(data$x), numeric_compact)
    expect_identical(dtatools:::.is_unmaterialized_dictstring(data$y), string_compact)
    expect_identical(.Call(dtatools:::C_dtatools_column_capacity, data), capacity)
    expect_silent((function(x) gen(x, added = 1))(data))
    expect_identical(names(alias), c("x", "y", "added"))
    skip_if_not_installed("data.table")
    dt <- data.table::data.table(x = 1:2, y = c("a", "b"))
    data.table::setkeyv(dt, "x")
    data.table::setindexv(dt, "y")
    key <- data.table::key(dt)
    index <- data.table::indices(dt)
    selfref <- attr(dt, ".internal.selfref")
    set_var_format(dt, x, "%9.0g")
    set_dta_note(dt, 1L, "note", "x")
    expect_identical(data.table::key(dt), key)
    expect_identical(data.table::indices(dt), index)
    expect_identical(attr(dt, ".internal.selfref"), selfref)
    # Run data.table NSE in a user frame; this package deliberately is not
    # marked data.table-aware and package-namespace calls use frame semantics.
    expect_identical(eval(quote(dt[list(1L), y]), list(dt = dt), globalenv()), "a")
})
