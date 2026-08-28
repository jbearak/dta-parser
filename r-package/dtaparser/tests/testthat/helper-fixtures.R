fixture <- function(name) {
    system.file("extdata", name, package = "dtaparser", mustWork = TRUE)
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
    bytes <- as.raw(c(
        0x7f, 0xf0, 0x00, utf8ToInt(tag), 0x00, 0x00, 0x07, 0xa2
    ))
    readBin(bytes, "double", n = 1L, size = 8L, endian = "big")
}

without_stata_storage <- function(value) {
    if (is.null(attr(value, "stata.storage", exact = TRUE))) return(value)

    value <- dtaparser:::.metadata_copy(value)
    attr(value, "stata.storage") <- NULL
    classes <- attr(value, "class", exact = TRUE)
    if (!is.null(classes)) {
        classes <- classes[!classes %in% c(
            "stata_numeric", "stata_temporal", "stata_date",
            "stata_datetime", paste0("stata_", c(
                "byte", "int", "long", "float", "double"
            ))
        )]
        if (!"haven_labelled" %in% classes) {
            classes <- classes[!classes %in% c("vctrs_vctr", "double")]
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
    data
}

without_haven_note_count <- function(data) {
    notes <- attr(data, "notes", exact = TRUE)
    if (is.null(notes)) return(data)

    # Haven exposes Stata's `_dta[note0]` count characteristic as a note value
    # without retaining its characteristic name. Stata and dtaparser treat it
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
