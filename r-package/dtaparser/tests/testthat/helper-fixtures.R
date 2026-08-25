fixture <- function(name) {
    system.file("extdata", name, package = "dtaparser", mustWork = TRUE)
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
