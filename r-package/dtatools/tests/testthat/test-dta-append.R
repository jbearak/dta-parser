master_frame <- function() {
    tibble::tibble(
        id = dta_byte(c(1, 2)),
        name = dta_string(c("ann", "bo"), storage = "str3")
    )
}

using_frame <- function() {
    tibble::tibble(
        id = dta_byte(c(3, 4)),
        note = dta_string(c("kept", "held"), storage = "str4")
    )
}

test_that("the result is the union of variables in first-appearance order", {
    result <- dta_append(list(master_frame(), using_frame()))

    expect_identical(names(result), c("id", "name", "note"))
    expect_identical(nrow(result), 4L)
    expect_identical(as.numeric(result$id), c(1, 2, 3, 4))
})

test_that("duplicate source columns survive planning until name repair", {
    first <- data.frame(
        left = dta_byte(c(1, 2)), right = dta_long(c(10, 20))
    )
    names(first) <- c("v", "v")
    second <- data.frame(
        left = dta_byte(3), right = dta_long(30), extra = "kept"
    )
    names(second) <- c("v", "v", "extra")

    result <- dta_append(list(first, second))
    expect_identical(names(result), c("v...1", "v...2", "extra"))
    expect_identical(as.numeric(result[[1L]]), c(1, 2, 3))
    expect_identical(as.numeric(result[[2L]]), c(10, 20, 30))

    # Duplicate names cannot index a dibble's reference state, so the
    # default container refuses them and a tibble carries them through.
    expect_error(
        dta_append(list(first, second), .name_repair = "minimal"),
        "unique, non-missing column names"
    )
    minimal <- dta_append(
        list(first, second), .name_repair = "minimal", output = "tibble"
    )
    expect_identical(names(minimal), c("v", "v", "extra"))
    expect_identical(as.numeric(minimal[[1L]]), c(1, 2, 3))
    expect_identical(as.numeric(minimal[[2L]]), c(10, 20, 30))

    one_occurrence <- dta_append(list(
        first, data.frame(v = dta_byte(4))
    ))
    expect_identical(as.numeric(one_occurrence[[1L]]), c(1, 2, 4))
    expect_identical(is_missing(one_occurrence[[2L]]), c(FALSE, FALSE, TRUE))

    blank <- first
    names(blank) <- c("", "")
    expect_identical(
        names(dta_append(blank, .name_repair = "minimal", output = "tibble")),
        c("", "")
    )
})

test_that("a source missing a variable contributes missing values", {
    result <- dta_append(list(master_frame(), using_frame()))

    # Stata strings use "" rather than NA for missing.
    expect_identical(as.character(result$name), c("ann", "bo", "", ""))
    expect_identical(as.character(result$note), c("", "", "kept", "held"))
})

test_that("string storage and format widen to the widest contributor", {
    narrow <- tibble::tibble(v = dta_string("ab", storage = "str2"))
    wide <- tibble::tibble(v = dta_string("abcdefg", storage = "str7"))

    result <- dta_append(list(narrow, wide))
    expect_identical(attr(result$v, "stata.string.storage"), "str7")
    expect_identical(as.character(result$v), c("ab", "abcdefg"))
})

test_that("numeric storage promotes along the Stata lattice", {
    byte_source <- tibble::tibble(v = dta_byte(c(1, 2)))
    long_source <- tibble::tibble(v = dta_long(c(100000, 200000)))

    result <- dta_append(list(byte_source, long_source))
    expect_identical(dta_storage_type(result$v), "long")
    expect_identical(as.numeric(result$v), c(1, 2, 100000, 200000))
})

test_that("promotion clears the int ceiling into long", {
    small <- tibble::tibble(v = dta_int(c(1, 32740)))
    big <- tibble::tibble(v = dta_long(32741))

    result <- dta_append(list(small, big))
    expect_identical(dta_storage_type(result$v), "long")
    expect_identical(as.numeric(result$v), c(1, 32740, 32741))
})

test_that("the numeric result keeps compact unmaterialized storage", {
    result <- dta_append(list(
        tibble::tibble(v = dta_byte(c(1, 2))),
        tibble::tibble(v = dta_byte(c(3, 4)))
    ))

    # Assert the ALTREP state before any content comparison, because
    # reading the values would materialize it permanently.
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(result$v))
    expect_identical(as.numeric(result$v), c(1, 2, 3, 4))
})

test_that("the missing fill for an absent numeric stays compact", {
    result <- dta_append(list(
        tibble::tibble(v = dta_byte(c(1, 2))),
        tibble::tibble(other = dta_byte(9))
    ))

    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(result$v))
    expect_identical(is_missing(result$v), c(FALSE, FALSE, TRUE))
})

test_that("a missing temporal contribution preserves the Stata type", {
    date_path <- fixture_with_temporal_storage("foreign", "%td")
    datetime_path <- fixture_with_temporal_storage("foreign", "%tc")
    withr::defer(unlink(c(date_path, datetime_path)))

    for (path in c(date_path, datetime_path)) {
        value <- read_dta(path, n_max = 1L)$foreign
        result <- dta_append(list(
            tibble::tibble(v = value),
            tibble::tibble(other = dta_byte(1))
        ))

        expect_s3_class(result$v, "dta_temporal")
        expect_identical(
            dta_storage_type(result$v), dta_storage_type(value)
        )
        expect_identical(is_missing(result$v), c(FALSE, TRUE))
    }
})

test_that("the combined row count cannot exceed R's frame limit", {
    schemas <- list(list(rows = 2^30), list(rows = 2^30))
    plan <- list(
        names = character(), prototypes = list(), dropped = list(),
        source_columns = list(integer(), integer()), force = TRUE
    )

    expect_error(
        dtatools:::.append_fill_columns(schemas, plan),
        "maximum data-frame row count"
    )
})

test_that("force fills a string/numeric conflict with missing values", {
    text <- tibble::tibble(v = dta_string(c("ab", "cd")))
    number <- tibble::tibble(v = dta_byte(c(1, 2)))

    expect_message(
        result <- dta_append(list(text, number)),
        "stored differently"
    )
    # The first contributor's type wins, as the master's does in Stata.
    expect_s3_class(result$v, "dta_string")
    expect_identical(as.character(result$v), c("ab", "cd", "", ""))

    expect_message(
        reversed <- dta_append(list(number, text)),
        "stored differently"
    )
    expect_identical(dta_storage_type(reversed$v), "byte")
    expect_identical(is_missing(reversed$v), c(FALSE, FALSE, TRUE, TRUE))
})

test_that("force = FALSE makes a storage conflict an error", {
    expect_error(
        dta_append(
            list(
                tibble::tibble(v = dta_string("ab")),
                tibble::tibble(v = dta_byte(1))
            ),
            force = FALSE
        ),
        "incompatible storage"
    )
})

test_that("variable labels come from the first contributor", {
    first <- tibble::tibble(v = dta_byte(1))
    var_label(first$v) <- "first label"
    second <- tibble::tibble(v = dta_byte(2))
    var_label(second$v) <- "second label"

    result <- dta_append(list(first, second))
    expect_identical(var_label(result$v), "first label")

    unlabeled <- tibble::tibble(v = dta_byte(3))
    result <- dta_append(list(unlabeled, second))
    expect_null(var_label(result$v))
})

test_that("formats come from the first contributor after promotion", {
    first <- tibble::tibble(v = dta_byte(1))
    attr(first$v, "format.stata") <- "%8.0g"
    second <- tibble::tibble(v = dta_long(100000))
    attr(second$v, "format.stata") <- "%12.0g"

    result <- dta_append(list(first, second))
    expect_identical(dta_storage_type(result$v), "long")
    expect_identical(attr(result$v, "format.stata"), "%8.0g")
})

labelled_byte <- function(values, labels, table = NULL) {
    result <- dta_byte(values)
    val_labels(result) <- labels
    if (!is.null(table)) attr(result, "value.label.name") <- table
    result
}

test_that("the first source to define a value-label table owns it", {
    # Stata's `append` keeps the master's `xl` and drops the using
    # file's definition of the same name with "(label xl already
    # defined)"; the two are never merged.
    first <- tibble::tibble(v = labelled_byte(c(1, 2), c(yes = 1), "xl"))
    second <- tibble::tibble(v = labelled_byte(c(2, 3), c(no = 2), "xl"))

    expect_silent(result <- dta_append(list(first, second)))
    expect_identical(val_labels(result$v), c(yes = 1))
    expect_identical(attr(result$v, "value.label.name"), "xl")

    # Conflicting text for a shared code is not a warning either: the
    # later definition is discarded whole.
    third <- tibble::tibble(v = labelled_byte(1, c(oui = 1), "xl"))
    expect_silent(result <- dta_append(list(first, third)))
    expect_identical(val_labels(result$v), c(yes = 1))

    unlabeled <- tibble::tibble(v = dta_byte(1))
    result <- dta_append(list(unlabeled, second))
    expect_null(val_labels(result$v))
    expect_null(attr(result$v, "value.label.name"))
})

test_that("a variable takes the owning definition of its table name", {
    # The shape from the MICS corpus: one source defines `labb` for
    # `ma7m`, a later source assigns its own `labb` to other variables.
    # Stata displays the first `labb` for all of them.
    months <- c(January = 1, February = 2, March = 3)
    yes_no <- c(yes = 1, no = 2)
    first <- tibble::tibble(ma7m = labelled_byte(c(1, 3), months, "labb"))
    second <- tibble::tibble(
        ma6a2 = labelled_byte(1, yes_no, "labb"),
        cm11c = labelled_byte(2, yes_no, "labb"),
        y = labelled_byte(1, c(why = 1), "yl")
    )

    result <- dta_append(list(first, second))
    for (my_name in c("ma7m", "ma6a2", "cm11c")) {
        expect_identical(val_labels(result[[my_name]]), months, info = my_name)
        expect_identical(
            attr(result[[my_name]], "value.label.name"), "labb", info = my_name
        )
    }
    # A table the master does not define is taken from the later
    # source that does.
    expect_identical(val_labels(result$y), c(why = 1))
    expect_identical(attr(result$y, "value.label.name"), "yl")

    # Every variable sharing `labb` now carries the same definition, so
    # writing the result never falls back to per-variable table names.
    path <- withr::local_tempfile(fileext = ".dta")
    expect_no_warning(save_dta(result, path))
    written <- read_dta(path)
    expect_identical(val_labels(written$ma6a2), months)
    expect_identical(attr(written$ma6a2, "value.label.name"), "labb")
})

test_that("unnamed labels define a table named after the variable", {
    # `save_dta()` names an unnamed table after its variable, so the
    # append treats an unnamed first contributor as owning that name.
    first <- tibble::tibble(v = labelled_byte(1, c(one = 1)))
    named_later <- tibble::tibble(
        v = labelled_byte(2, c(two = 2), "vl"),
        w = labelled_byte(2, c(deux = 2), "v")
    )

    result <- dta_append(list(first, named_later))
    expect_identical(val_labels(result$v), c(one = 1))
    expect_null(attr(result$v, "value.label.name"))
    # `w` is assigned the table `v`, which the first source owns.
    expect_identical(val_labels(result$w), c(one = 1))
    expect_identical(attr(result$w, "value.label.name"), "v")

    # The same rule from the other direction: an unnamed later
    # contributor's table `v` is discarded when the master defines `v`.
    owner <- tibble::tibble(w = labelled_byte(1, c(uno = 1), "v"))
    result <- dta_append(list(owner, first))
    expect_identical(val_labels(result$w), c(uno = 1))
    expect_identical(val_labels(result$v), c(uno = 1))
    expect_null(attr(result$v, "value.label.name"))
})

test_that("value-label ownership survives a file round trip", {
    directory <- withr::local_tempdir()
    first <- tibble::tibble(
        x = labelled_byte(1, c(one = 1), "xl"),
        u = dta_byte(1)
    )
    second <- tibble::tibble(
        x = labelled_byte(2, c(two = 2), "xl"),
        u = labelled_byte(2, c(two = 2), "ul")
    )
    master <- file.path(directory, "master.dta")
    using <- file.path(directory, "using.dta")
    save_dta(first, master)
    save_dta(second, using)

    result <- dta_append(list(master, using))
    expect_identical(val_labels(result$x), c(one = 1))
    expect_identical(attr(result$x, "value.label.name"), "xl")
    expect_null(val_labels(result$u))
})

test_that("a widened string format takes the new width and keeps its flag", {
    widen <- function(master_format, using_storage = "str20",
                      using_format = NULL) {
        first <- tibble::tibble(v = dta_string("ab", storage = "str2"))
        attr(first$v, "format.stata") <- master_format
        second <- tibble::tibble(v = dta_string("abc", storage = using_storage))
        if (!is.null(using_format)) {
            attr(second$v, "format.stata") <- using_format
        }
        result <- dta_append(list(first, second))
        expect_identical(
            attr(result$v, "stata.string.storage"), using_storage
        )
        attr(result$v, "format.stata")
    }

    # The using source's format is never taken.
    expect_identical(widen("%9s", using_format = "%25s"), "%20s")
    expect_identical(widen("%-9s", using_format = "%20s"), "%-20s")
    expect_identical(widen("%9s", using_format = "%-30s"), "%20s")
    expect_identical(widen("%~9s"), "%~20s")
    # A master width wider than the new storage is still reset, and the
    # width never drops below Stata's default of 9.
    expect_identical(widen("%12s", using_storage = "str10"), "%10s")
    expect_identical(widen("%12s", using_storage = "str5"), "%9s")
    expect_identical(widen("%-12s", using_storage = "str5"), "%-9s")
    # Widening to strL takes strL's default width.
    expect_identical(widen("%-3s", using_storage = "strL"), "%-9s")
})

test_that("a string format is kept when storage does not widen", {
    first <- tibble::tibble(v = dta_string("abcde", storage = "str12"))
    attr(first$v, "format.stata") <- "%5s"
    second <- tibble::tibble(v = dta_string("ab", storage = "str2"))
    attr(second$v, "format.stata") <- "%20s"

    result <- dta_append(list(first, second))
    expect_identical(attr(result$v, "stata.string.storage"), "str12")
    expect_identical(attr(result$v, "format.stata"), "%5s")

    same <- tibble::tibble(v = dta_string("xy", storage = "str12"))
    attr(same$v, "format.stata") <- "%-40s"
    result <- dta_append(list(first, same))
    expect_identical(attr(result$v, "format.stata"), "%5s")

    long <- tibble::tibble(v = dta_string("xy", storage = "strL"))
    attr(long$v, "format.stata") <- "%-15s"
    result <- dta_append(list(long, second))
    expect_identical(attr(result$v, "stata.string.storage"), "strL")
    expect_identical(attr(result$v, "format.stata"), "%-15s")

    unformatted <- tibble::tibble(v = dta_string("ab", storage = "str2"))
    result <- dta_append(list(unformatted, first))
    expect_null(attr(result$v, "format.stata"))
})

test_that("logical placeholders do not clear temporal structure", {
    path <- fixture_with_temporal_storage("foreign", "%tc")
    withr::defer(unlink(path))
    value <- read_dta(path, n_max = 1L)$foreign

    result <- dta_append(list(
        tibble::tibble(v = NA), tibble::tibble(v = value)
    ))

    expect_s3_class(result$v, "dta_datetime")
    expect_identical(attr(result$v, "tzone"), "UTC")
    expect_identical(attr(result$v, "format.stata"), "%tc")
    expect_identical(is_missing(result$v), c(TRUE, FALSE))
})

test_that("a logical first contributor retains its user metadata", {
    first <- tibble::tibble(v = c(TRUE, FALSE))
    var_label(first$v) <- "logical first"
    attr(first$v, "notes") <- "first note"
    first$v <- dtatools:::.as_dta_metadata_vector(first$v)
    second <- tibble::tibble(v = dta_byte(c(1, 0)))
    var_label(second$v) <- "second"
    attr(second$v, "notes") <- "second note"
    second$v <- dtatools:::.as_dta_metadata_vector(second$v)

    result <- dta_append(list(first, second))
    expect_identical(as.numeric(result$v), c(1, 0, 1, 0))
    expect_identical(var_label(result$v), "logical first")
    expect_identical(attr(result$v, "notes"), "first note")

    wrong <- tibble::tibble(v = dta_string("x"))
    var_label(wrong$v) <- "dropped owner"
    right <- tibble::tibble(v = dta_byte(1))
    var_label(right$v) <- "later compatible"
    expect_message(
        result <- dta_append(list(tibble::tibble(v = NA), wrong, right)),
        "stored differently"
    )
    expect_identical(as.numeric(result$v), c(NA, NA, 1))
    expect_null(var_label(result$v))
    expect_null(attr(result$v, "format.stata"))
})

test_that("a variable label survives a missing-fill contribution", {
    first <- tibble::tibble(v = dta_string("ab"))
    var_label(first$v) <- "kept"

    result <- dta_append(list(first, tibble::tibble(w = dta_byte(1))))
    expect_identical(var_label(result$v), "kept")
    expect_identical(as.character(result$v), c("ab", ""))
})

test_that(".dta and .arrow paths append like in-memory frames", {
    directory <- withr::local_tempdir()
    dta <- file.path(directory, "master.dta")
    arrow <- file.path(directory, "using.arrow")
    save_dta(master_frame(), dta)
    save_arrow(using_frame(), arrow)

    dta_schema <- dtatools:::.append_read_schema(dta, 1L)
    arrow_schema <- dtatools:::.append_read_schema(arrow, 2L)
    expect_identical(dta_schema$rows, 2L)
    expect_identical(arrow_schema$rows, 2L)
    expect_null(attr(read_dta(dta, n_max = 0L), "dtatools.source.rows"))
    expect_null(attr(read_arrow(arrow, n_max = 0L), "dtatools.source.rows"))

    withr::local_options(dtatools.output = "data.table")
    expect_s3_class(dta_append(dta), "data.table")

    options(dtatools.output = "invalid")
    expect_s3_class(dta_append(dta, output = "tibble"), "tbl_df")
    options(dtatools.output = "data.table")

    from_memory <- dta_append(list(master_frame(), using_frame()))
    from_files <- dta_append(list(dta, arrow))

    expect_identical(names(from_files), names(from_memory))
    expect_identical(nrow(from_files), nrow(from_memory))
    expect_identical(
        as.character(from_files$name), as.character(from_memory$name)
    )
    expect_identical(as.numeric(from_files$id), as.numeric(from_memory$id))
})

test_that("mixed memory and file sources dispatch per element", {
    directory <- withr::local_tempdir()
    path <- file.path(directory, "using.dta")
    save_dta(using_frame(), path)

    result <- dta_append(list(master_frame(), path))
    expect_identical(names(result), c("id", "name", "note"))
    expect_identical(nrow(result), 4L)
})

test_that("dataset notes follow the requested policy", {
    first <- master_frame()
    attr(first, "notes") <- "master note"
    attr(first, "stata.note.numbers") <- 1L
    second <- using_frame()
    attr(second, "notes") <- "using note"
    attr(second, "stata.note.numbers") <- 1L
    the_sources <- list(first, second)

    expect_identical(
        attr(dta_append(the_sources), "notes"), "master note"
    )
    expect_identical(
        attr(dta_append(the_sources, dataset_notes = "all"), "notes"),
        c("master note", "using note")
    )
    expect_null(
        attr(dta_append(the_sources, dataset_notes = "none"), "notes")
    )
})

test_that("the output container is honoured", {
    the_sources <- list(master_frame(), using_frame())

    expect_s3_class(
        dta_append(the_sources, output = "tibble"), "tbl_df"
    )
    result <- dta_append(the_sources, output = "data.table")
    expect_s3_class(result, "data.table")
    expect_false(inherits(result, "dtatools_dta_metadata"))
})

test_that("a single source is returned unchanged in shape", {
    result <- dta_append(master_frame())
    expect_identical(names(result), c("id", "name"))
    expect_identical(nrow(result), 2L)
})

test_that("invalid input is rejected", {
    expect_error(dta_append(list()), "at least one source")
    expect_error(dta_append(list(1L)), "data frame or one file path")
    expect_error(
        dta_append(list(master_frame()), force = NA), "`force` must be"
    )
    expect_error(
        dta_append(list(master_frame()), dataset_notes = "some"),
        class = "rlang_error"
    )
})

test_that("appending in either order stacks the rows in source order", {
    forward <- dta_append(list(master_frame(), using_frame()))
    backward <- dta_append(list(using_frame(), master_frame()))

    expect_identical(names(backward), c("id", "note", "name"))
    expect_identical(as.numeric(forward$id), c(1, 2, 3, 4))
    expect_identical(as.numeric(backward$id), c(3, 4, 1, 2))
})

test_that("a wrapped and a bare Stata string column append together", {
    # The shape that used to fail on real MICS data: one source labels
    # the column, so read_dta() wraps it in the metadata vector class,
    # and the other leaves it a bare dta_string.
    labelled <- tibble::tibble(cp3k = dta_string("ab", storage = "str2"))
    attr(labelled$cp3k, "notes") <- "labelled source"
    labelled$cp3k <- dtatools:::.as_dta_metadata_vector(labelled$cp3k)
    bare <- tibble::tibble(cp3k = dta_string("cdefg"))

    result <- dta_append(list(labelled, bare))
    expect_identical(as.character(result$cp3k), c("ab", "cdefg"))
    expect_identical(attr(result$cp3k, "stata.string.storage"), "str5")
})

test_that("a buffered column is written in place, not duplicated", {
    prototype <- dta_byte()
    buffer <- dtatools:::.append_allocate_buffer(prototype, 4L)
    expect_identical(attr(buffer, "dtatools.storage"), "byte")

    expect_true(dtatools:::.append_fits_buffer(dta_byte(1), dta_long()))
    expect_false(dtatools:::.append_fits_buffer(1, dta_long()))
    expect_null(dtatools:::.append_allocate_buffer(factor("a"), 4L))
})

test_that("a buffered column keeps values that do not fit the buffer", {
    # The buffer/pieces choice is made from the prototype alone, so a
    # source whose column does not share the buffer's layout - a bare
    # double, or a named Stata numeric - must still be cast into the
    # buffer rather than left at its missing initialization.
    declared <- tibble::tibble(v = dta_byte(c(1, 2)))
    bare <- tibble::tibble(v = c(5, 6))

    result <- dta_append(list(declared, bare))
    expect_identical(as.numeric(result$v), c(1, 2, 5, 6))

    named <- dta_byte(c(5, 6))
    names(named) <- c("x", "y")
    result <- dta_append(list(declared, tibble::tibble(v = named)))
    expect_identical(as.numeric(result$v), c(1, 2, 5, 6))

    plain <- tibble::tibble(s = c("cc", "dd"))
    result <- dta_append(
        list(tibble::tibble(s = dta_string(c("a", "b"))), plain)
    )
    expect_identical(as.character(result$s), c("a", "b", "cc", "dd"))
})

test_that("an undeclared numeric widens a declared Stata prototype", {
    declared <- tibble::tibble(v = dta_byte(c(1, 2)))
    wide <- tibble::tibble(v = c(50000, 60000))

    result <- dta_append(list(declared, wide))
    expect_identical(dta_storage_type(result$v), "double")
    expect_identical(as.numeric(result$v), c(1, 2, 50000, 60000))

    reversed <- dta_append(list(wide, declared))
    expect_identical(dta_storage_type(reversed$v), "double")
    expect_identical(as.numeric(reversed$v), c(50000, 60000, 1, 2))

    integers <- tibble::tibble(v = c(50000L, 60000L))
    result <- dta_append(list(declared, integers))
    expect_identical(dta_storage_type(result$v), "double")
    expect_identical(as.numeric(result$v), c(1, 2, 50000, 60000))
})

test_that("widening an undeclared numeric preserves variable metadata", {
    noted <- data.frame(v = c(1, 2))
    attr(noted$v, "notes") <- "source note"
    attr(noted$v, "stata.characteristics") <- c(origin = "memory")
    noted$v <- dtatools:::.as_dta_metadata_vector(noted$v)
    labelled <- data.frame(v = c(5, 6))
    var_label(labelled$v) <- "first label"

    result <- dta_append(list(
        noted, tibble::tibble(v = dta_byte(c(3, 4)))
    ))
    expect_identical(as.numeric(result$v), c(1, 2, 3, 4))
    expect_identical(attr(result$v, "notes"), "source note")
    expect_identical(
        attr(result$v, "stata.characteristics"), c(origin = "memory")
    )

    result <- dta_append(list(
        labelled, tibble::tibble(v = dta_byte(c(7, 8)))
    ))
    expect_identical(as.numeric(result$v), c(5, 6, 7, 8))
    expect_identical(var_label(result$v), "first label")
})

test_that("values outside Stata double storage obey force", {
    declared <- tibble::tibble(v = dta_byte(1))
    outside <- tibble::tibble(v = 1e308)

    expect_message(
        result <- dta_append(list(declared, outside)),
        "those observations are missing"
    )
    expect_identical(as.numeric(result$v), c(1, NA))
    expect_error(
        dta_append(list(declared, outside), force = FALSE),
        "incompatible storage"
    )
})

test_that("a character source holding NA obeys force like the pieces path", {
    declared <- tibble::tibble(s = dta_string(c("a", "b")))
    with_na <- tibble::tibble(s = c("cc", NA))

    expect_message(
        result <- dta_append(list(declared, with_na)),
        "those observations are missing"
    )
    expect_identical(as.character(result$s), c("a", "b", "", ""))
    expect_error(
        dta_append(list(declared, with_na), force = FALSE),
        "incompatible storage"
    )
})

test_that("append name repair preserves implicit label-table identity", {
    value <- dta_byte(1)
    val_labels(value) <- c(one = 1)
    shared <- value
    attr(shared, "value.label.name") <- "v"
    source <- tibble::tibble(v = value, w = shared)
    for (output in c("dibble", "tibble", "data.table")) {
        if (output == "data.table") skip_if_not_installed("data.table")
        calls <- 0L
        repair <- function(names) { calls <<- calls + 1L; toupper(names) }
        result <- dta_append(source, output = output, .name_repair = repair)
        expect_identical(calls, 1L)
        expect_identical(names(result), c("V", "W"))
        expect_identical(attr(result$V, "value.label.name"), "v")
        expect_identical(attr(result$W, "value.label.name"), "v")
        expect_identical(val_labels(result$V), c(one = 1))
        path <- tempfile(fileext = ".dta")
        save_dta(result, path)
        restored <- read_dta(path)
        expect_identical(attr(restored$V, "value.label.name"), "v")
        expect_identical(attr(restored$W, "value.label.name"), "v")
        unlink(path)
    }
    unchanged <- dta_append(source)
    expect_null(attr(unchanged$v, "value.label.name"))
    expect_null(attr(source$v, "value.label.name"))
})


test_that("append gives blank implicit label names a stable repaired identity", {
    value <- dta_byte(1:2)
    val_labels(value) <- c(one = 1, two = 2)
    source <- vctrs::new_data_frame(stats::setNames(list(value), ""))
    for (output in c("dibble", "tibble", "data.table")) {
        if (output == "data.table") skip_if_not_installed("data.table")
        result <- suppressMessages(dta_append(source, output = output))
        table_name <- names(result)[[1L]]
        expect_identical(attr(result[[1L]], "value.label.name"), table_name)
        repeated <- dta_append(result, output = output,
            .name_repair = function(names) paste0("renamed_", names))
        expect_identical(attr(repeated[[1L]], "value.label.name"), table_name)
        expect_identical(val_labels(repeated[[1L]]), c(one = 1, two = 2))
    }
    expect_null(attr(source[[1L]], "value.label.name"))
})
