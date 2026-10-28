#' Stata's missing values
#'
#' `is_missing()` is TRUE for `.` and `.a` to `.z` (and for `""` in a
#' character vector, as in Stata). `is_tagged_missing()` is TRUE for `.a`
#' to `.z`, or for the letters in `tag`. Both read the codes from any
#' numeric vector, so they work on plain doubles such as `c(NA, .i)`.
#'
#' `%in%` and `match()` keep the codes apart only when both sides are
#' `dta_num` or plain numbers: base R transforms only classed values for
#' matching, so in `x %in% c(1, .a)` (a plain double, since `c()` takes
#' its class from `1`) the `.a` is just `NA`. Put a code first,
#' `c(.a, 1)`, or use [dta_setdiff()] and friends, which read the codes
#' from plain doubles too.
#'
#' @param x A vector.
#' @param tag Letters, such as `"g"`; NULL for any of them.
#' @return A logical vector as long as `x`.
#' @export
is_missing <- function(x) {
  if (is.character(x)) return(unname(!is.na(x) & x == ""))
  dta_codes(x) > 0
}

#' @rdname is_missing
#' @export
is_tagged_missing <- function(x, tag = NULL) {
  codes <- dta_codes(x)
  if (is.null(tag)) return(codes >= 2)
  codes %in% (match(tag, letters) + 1)
}

# `.a` to `.z`, as one-element dta_num vectors. Built in plain R at
# install time: NA_real_ with the letter in bits 32 to 39.
tagged_na <- function(letter) {
  bytes <- c(as.raw(c(0xa2, 0x07, 0, 0)), charToRaw(letter), as.raw(c(0, 0xf0, 0x7f)))
  readBin(bytes, "double", size = 8, endian = "little")
}
for (letter in letters) assign(paste0(".", letter), dta_num(tagged_na(letter)))
rm(letter)
