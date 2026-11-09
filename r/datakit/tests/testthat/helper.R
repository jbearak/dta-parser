# datakit's tests read and check columns with dtaparser's functions.
library(dtaparser)

# Run R code in a fresh R process with this session's library paths;
# returns its output lines. The code goes in a file and R_LIBS through
# the environment, since system2() quotes differently on Windows and
# ignores its `env` there.
fresh_r <- function(code) {
  script <- tempfile(fileext = ".R")
  writeLines(code, script)
  old <- Sys.getenv("R_LIBS", unset = NA)
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  on.exit(if (is.na(old)) Sys.unsetenv("R_LIBS") else Sys.setenv(R_LIBS = old))
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(rscript, shQuote(script), stdout = TRUE, stderr = TRUE))
  out[!grepl("^OMP:", out)]
}

# Skip a test of the polars functions without polars, nanoarrow or R
# 4.3; with DATAKIT_REQUIRE_POLARS=true (CI) fail instead, so that they
# cannot be skipped silently.
skip_without_polars <- function() {
  missing <- c(if (getRversion() < "4.3") "R 4.3",
               if (!requireNamespace("polars", quietly = TRUE)) "polars",
               if (!requireNamespace("nanoarrow", quietly = TRUE)) "nanoarrow")
  if (!length(missing)) return(invisible(TRUE))
  if (identical(tolower(Sys.getenv("DATAKIT_REQUIRE_POLARS")), "true")) {
    stop("DATAKIT_REQUIRE_POLARS is set, but this needs ", paste(missing, collapse = ", "), call. = FALSE)
  }
  testthat::skip(paste("needs", paste(missing, collapse = ", ")))
}
