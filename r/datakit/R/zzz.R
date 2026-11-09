# datakit reads Parquet files through dtaparser's C functions (plan
# 0018), and fixed-width files through datparser (ADR 0039). The ABI
# number datakit was built for; dtaparser's must match.
DTAPARSER_ABI <- 4L

.onLoad <- function(libname, pkgname) {
  loadNamespace("dtaparser")
  found <- tryCatch(.Call(C_dta_link), error = function(e) NA_integer_)
  check_abi(found, DTAPARSER_ABI)
}

check_abi <- function(found, wanted) {
  if (!identical(found, wanted)) {
    stop("datakit needs dtaparser built from the same release; reinstall dtaparser", call. = FALSE)
  }
  invisible(TRUE)
}
