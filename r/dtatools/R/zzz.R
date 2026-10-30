# dtatools reads and writes through dtaparser's C functions (ADR 0015).
# The ABI number dtatools was built for; dtaparser's must match.
DTAPARSER_ABI <- 1L

.onLoad <- function(libname, pkgname) {
  loadNamespace("dtaparser")
  found <- tryCatch(.Call(C_dta_link), error = function(e) NA_integer_)
  check_abi(found, DTAPARSER_ABI)
}

check_abi <- function(found, wanted) {
  if (!identical(found, wanted)) {
    stop("dtatools needs dtaparser built from the same release; reinstall dtaparser", call. = FALSE)
  }
  invisible(TRUE)
}
