fixture <- function(name) {
    system.file("extdata", name, package = "dtaparser", mustWork = TRUE)
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

fixture_with_all_numeric_missing_codes <- function(name) {
    input <- fixture(name)
    bytes <- readBin(input, "raw", n = file.info(input)[["size"]])
    row_width <- 19L
    row_count <- 30L
    if (identical(name, "missing_values_v115.dta")) {
        data_start <- length(bytes) - row_width * row_count + 1L
    } else {
        data_tag <- charToRaw("<data>")
        matches <- grepRaw(data_tag, bytes, fixed = TRUE, all = TRUE)
        stopifnot(length(matches) == 1L)
        data_start <- matches[[1L]] + length(data_tag)
        closing_tag <- charToRaw("</data>")
        closing_start <- data_start + row_width * row_count
        stopifnot(identical(
            bytes[closing_start + seq_along(closing_tag) - 1L],
            closing_tag
        ))
    }

    raw_integer <- function(value, size) {
        writeBin(as.integer(value), raw(), size = size, endian = "little")
    }
    assign_raw <- function(row, offset, value) {
        start <- data_start + row * row_width + offset
        bytes[start + seq_along(value) - 1L] <<- value
    }
    for (code in 0:26) {
        assign_raw(
            code, 0L,
            c(raw(4L), raw_integer(0x7fe00000 + code * 0x100, 4L))
        )
        assign_raw(code, 8L, as.raw(101L + code))
        assign_raw(code, 9L, raw_integer(32741L + code, 2L))
        assign_raw(code, 11L, raw_integer(2147483621 + code, 4L))
        assign_raw(
            code, 15L,
            raw_integer(0x7f000000 + code * 0x800, 4L)
        )
    }

    output <- tempfile(fileext = ".dta")
    writeBin(bytes, output)
    output
}
