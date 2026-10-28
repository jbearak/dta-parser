# Base R has %||% only from 4.4.
`%||%` <- function(x, y) if (is.null(x)) y else x
