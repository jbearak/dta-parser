fixture <- function(name) {
    system.file("extdata", name, package = "dtatools", mustWork = TRUE)
}

fixture_with_temporal_storage <- function(column, display_format = "%td") {
    path <- fixture("auto_v118.dta")
    bytes <- readBin(path, "raw", n = file.info(path)[["size"]])

    old_format <- if (identical(column, "foreign")) "%8.0g" else "%8.0gc"
    matches <- grepRaw(
        charToRaw(old_format), bytes, fixed = TRUE, all = TRUE
    )
    minimum_matches <- if (identical(column, "foreign")) 1L else 2L
    stopifnot(length(matches) >= minimum_matches)
    format_start <- if (identical(column, "foreign")) {
        tail(matches, 1L)
    } else {
        matches[[2L]]
    }
    bytes[format_start + seq_len(nchar(old_format)) - 1L] <- c(
        charToRaw(display_format),
        raw(nchar(old_format) - nchar(display_format))
    )

    output <- tempfile(fileext = ".dta")
    writeBin(bytes, output)
    output
}

labelled_for_test <- function(x, labels = NULL, label = NULL) {
    structure(
        x,
        labels = labels,
        label = label,
        class = c("haven_labelled", "vctrs_vctr", typeof(x))
    )
}

tagged_nan_for_test <- function(tag) {
    stopifnot(is.character(tag), length(tag) == 1L, nchar(tag) == 1L)
    code <- utf8ToInt(tag)
    stopifnot(code >= 1L, code <= 127L)
    bytes <- as.raw(c(
        0x7f, 0xf0, 0x00, code, 0x00, 0x00, 0x07, 0xa2
    ))
    readBin(bytes, "double", n = 1L, size = 8L, endian = "big")
}

without_stata_storage <- function(value) {
    has_numeric_storage <- !is.null(attr(
        value, "stata.storage", exact = TRUE
    ))
    has_string_storage <- !is.null(attr(
        value, "stata.string.storage", exact = TRUE
    ))
    has_value_label_name <- !is.null(attr(
        value, "value.label.name", exact = TRUE
    ))
    has_metadata_marker <- inherits(
        value, "dtatools_stata_metadata_vector"
    )
    if (!has_numeric_storage && !has_string_storage &&
        !has_value_label_name && !has_metadata_marker) {
        return(value)
    }

    value <- dtatools:::.metadata_copy(value)
    attr(value, "stata.string.storage") <- NULL
    attr(value, "value.label.name") <- NULL
    if (has_numeric_storage) attr(value, "stata.storage") <- NULL
    classes <- attr(value, "class", exact = TRUE)
    if (!is.null(classes)) {
        classes <- classes[!classes %in% c(
            "dtatools_stata_metadata_vector",
            "stata_string",
            "stata_numeric", "stata_temporal", "stata_date",
            "stata_datetime", paste0("stata_", c(
                "byte", "int", "long", "float", "double"
            ))
        )]
        if (!"haven_labelled" %in% classes) {
            classes <- classes[!classes %in% c(
                "vctrs_vctr", "double", "character"
            )]
        }
        attr(value, "class") <- if (length(classes) == 0L) NULL else classes
    }
    value
}

data_values <- function(data) {
    lapply(data, function(value) {
        if (is.numeric(value)) as.double(value) else as.vector(value)
    })
}

without_stata_storage_data <- function(data) {
    for (index in seq_along(data)) {
        data[[index]] <- without_stata_storage(data[[index]])
    }
    classes <- setdiff(
        attr(data, "class", exact = TRUE),
        "dtatools_stata_metadata"
    )
    attr(data, "class") <- if (length(classes)) classes else NULL
    data
}

without_haven_note_count <- function(data) {
    notes <- attr(data, "notes", exact = TRUE)
    if (is.null(notes)) return(data)

    # Haven exposes Stata's `_dta[note0]` count characteristic as a note value
    # without retaining its characteristic name. Stata and dtatools treat it
    # as framing metadata. In Haven output it is the last all-decimal entry for
    # the checked fixtures, even when the characteristic order differs.
    count_candidates <- which(grepl("^[0-9]+$", notes))
    if (length(count_candidates)) {
        notes <- notes[-tail(count_candidates, 1L)]
    }
    attr(data, "notes") <- if (length(notes)) notes else NULL
    data
}

.raw_little_integer <- function(value, size) {
    writeBin(as.integer(value), raw(), size = size, endian = "little")
}

.numeric_missing_fixture_widths <- c(
    x_double = 8L, x_byte = 1L, x_int = 2L, x_long = 4L, x_float = 4L
)
.numeric_missing_fixture_offsets <- setNames(
    c(0L, head(cumsum(.numeric_missing_fixture_widths), -1L)),
    names(.numeric_missing_fixture_widths)
)
.numeric_missing_fixture_row_width <- sum(.numeric_missing_fixture_widths)
.numeric_missing_fixture_row_count <- 30L

.numeric_missing_fixture_data_start <- function(bytes) {
    data_tag <- charToRaw("<data>")
    matches <- grepRaw(data_tag, bytes, fixed = TRUE, all = TRUE)
    if (length(matches) == 0L) {
        return(length(bytes) - .numeric_missing_fixture_row_width *
            .numeric_missing_fixture_row_count + 1L)
    }
    stopifnot(length(matches) == 1L)
    data_start <- matches[[1L]] + length(data_tag)
    closing_tag <- charToRaw("</data>")
    closing_start <- data_start + .numeric_missing_fixture_row_width *
        .numeric_missing_fixture_row_count
    stopifnot(identical(
        bytes[closing_start + seq_along(closing_tag) - 1L],
        closing_tag
    ))
    data_start
}

.replace_numeric_fixture_values <- function(bytes, data_start, row, values) {
    stopifnot(
        length(row) == 1L, !is.na(row), row >= 0L,
        !is.null(names(values)),
        all(names(values) %in% names(.numeric_missing_fixture_widths))
    )
    for (name in names(values)) {
        value <- values[[name]]
        stopifnot(
            is.raw(value),
            length(value) == .numeric_missing_fixture_widths[[name]]
        )
        start <- data_start + row * .numeric_missing_fixture_row_width +
            .numeric_missing_fixture_offsets[[name]]
        bytes[start + seq_along(value) - 1L] <- value
    }
    bytes
}

patch_numeric_fixture_row <- function(path, row, values) {
    bytes <- readBin(path, "raw", n = file.info(path)[["size"]])
    bytes <- .replace_numeric_fixture_values(
        bytes, .numeric_missing_fixture_data_start(bytes), row, values
    )
    writeBin(bytes, path)
    invisible(path)
}

fixture_with_all_numeric_missing_codes <- function(name) {
    input <- fixture(name)
    bytes <- readBin(input, "raw", n = file.info(input)[["size"]])
    data_start <- .numeric_missing_fixture_data_start(bytes)
    for (code in 0:26) {
        bytes <- .replace_numeric_fixture_values(
            bytes,
            data_start,
            code,
            list(
                x_double = c(
                    raw(4L), .raw_little_integer(0x7fe00000 + code * 0x100, 4L)
                ),
                x_byte = as.raw(101L + code),
                x_int = .raw_little_integer(32741L + code, 2L),
                x_long = .raw_little_integer(2147483621 + code, 4L),
                x_float = .raw_little_integer(0x7f000000 + code * 0x800, 4L)
            )
        )
    }

    output <- tempfile(fileext = ".dta")
    writeBin(bytes, output)
    output
}
