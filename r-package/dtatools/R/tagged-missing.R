#' Create and inspect Stata tagged missing values
#'
#' `tagged_missing()` creates the R double representation of Stata extended
#' missing values `.a` through `.z`. `missing_tag()` extracts their letters,
#' and `is_tagged_missing()` selects any tagged missing value or a requested
#' set of tags. The inspectors read compact dtatools columns without
#' materializing their decoded double backing.
#'
#' Tags must be one ASCII letter from `a` through `z`. Uppercase letters are
#' normalized to lowercase. Use ordinary `NA_real_` for Stata system missing
#' (`.`); it is not a tagged missing value. The inspectors recognize only
#' canonical tagged-missing payloads with Stata's `.a` through `.z` tags. They do
#' not classify arbitrary R `NaN` payloads as Stata missing codes.
#'
#' @param tag For `tagged_missing()`, a character vector containing one tag per
#'   element. For `is_tagged_missing()`, tags to match or `NULL` to match any
#'   tagged missing value.
#' @param x A numeric vector.
#' @return `tagged_missing()` returns a double vector. `missing_tag()` returns
#'   each tag letter or `NA_character_`. `is_tagged_missing()` returns a
#'   logical vector. Results retain names, dimensions, and dimension names but
#'   not other attributes from their input.
#' @examples
#' values <- c(1, NA_real_, tagged_missing(c("a", "f", "z")))
#' is.na(values)
#' missing_tag(values)
#' is_tagged_missing(values)
#' is_tagged_missing(values, c("a", "f"))
#' @export
tagged_missing <- function(tag) {
    .Call(C_dtatools_tagged_missing, tag)
}

#' @rdname tagged_missing
#' @export
missing_tag <- function(x) {
    .Call(C_dtatools_missing_tag, x)
}

#' @rdname tagged_missing
#' @export
is_tagged_missing <- function(x, tag = NULL) {
    .Call(C_dtatools_is_tagged_missing, x, tag)
}

#' Stata extended missing-value constants
#'
#' `.a` through `.z` are scalar shorthand for
#' `tagged_missing("a")` through `tagged_missing("z")`. They make literal
#' vectors and assignments read like their Stata equivalents. Use
#' [tagged_missing()] when tags come from data or when creating more than one
#' tagged missing value at a time.
#'
#' @return A length-one double containing the corresponding tagged missing
#'   value.
#' @examples
#' values <- c(1, NA_real_, .a, .z)
#' missing_tag(values)
#' identical(.f, tagged_missing("f"))
#' @name tagged_missing_constants
NULL

.tagged_missing_constant <- function(tag) {
    readBin(
        as.raw(c(0x7f, 0xf0, 0x00, utf8ToInt(tag), 0x00, 0x00, 0x07, 0xa2)),
        double(), n = 1L, size = 8L, endian = "big"
    )
}

#' @rdname tagged_missing_constants
#' @export
.a <- .tagged_missing_constant("a")

#' @rdname tagged_missing_constants
#' @export
.b <- .tagged_missing_constant("b")

#' @rdname tagged_missing_constants
#' @export
.c <- .tagged_missing_constant("c")

#' @rdname tagged_missing_constants
#' @export
.d <- .tagged_missing_constant("d")

#' @rdname tagged_missing_constants
#' @export
.e <- .tagged_missing_constant("e")

#' @rdname tagged_missing_constants
#' @export
.f <- .tagged_missing_constant("f")

#' @rdname tagged_missing_constants
#' @export
.g <- .tagged_missing_constant("g")

#' @rdname tagged_missing_constants
#' @export
.h <- .tagged_missing_constant("h")

#' @rdname tagged_missing_constants
#' @export
.i <- .tagged_missing_constant("i")

#' @rdname tagged_missing_constants
#' @export
.j <- .tagged_missing_constant("j")

#' @rdname tagged_missing_constants
#' @export
.k <- .tagged_missing_constant("k")

#' @rdname tagged_missing_constants
#' @export
.l <- .tagged_missing_constant("l")

#' @rdname tagged_missing_constants
#' @export
.m <- .tagged_missing_constant("m")

#' @rdname tagged_missing_constants
#' @export
.n <- .tagged_missing_constant("n")

#' @rdname tagged_missing_constants
#' @export
.o <- .tagged_missing_constant("o")

#' @rdname tagged_missing_constants
#' @export
.p <- .tagged_missing_constant("p")

#' @rdname tagged_missing_constants
#' @export
.q <- .tagged_missing_constant("q")

#' @rdname tagged_missing_constants
#' @export
.r <- .tagged_missing_constant("r")

#' @rdname tagged_missing_constants
#' @export
.s <- .tagged_missing_constant("s")

#' @rdname tagged_missing_constants
#' @export
.t <- .tagged_missing_constant("t")

#' @rdname tagged_missing_constants
#' @export
.u <- .tagged_missing_constant("u")

#' @rdname tagged_missing_constants
#' @export
.v <- .tagged_missing_constant("v")

#' @rdname tagged_missing_constants
#' @export
.w <- .tagged_missing_constant("w")

#' @rdname tagged_missing_constants
#' @export
.x <- .tagged_missing_constant("x")

#' @rdname tagged_missing_constants
#' @export
.y <- .tagged_missing_constant("y")

#' @rdname tagged_missing_constants
#' @export
.z <- .tagged_missing_constant("z")
