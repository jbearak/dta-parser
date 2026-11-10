# What datakit's read_parquet() and read_parquet_info() give for the
# Parquet file `f`, with the options a later reader must match: a list
# of the info and of each reading's value and warnings, or its error.
# make.R saves this for every legacy fixture as <name>.read.rds, and
# datakit's tests check that the reader still gives it. Messages name
# the file without its directory. A window crosses row groups where the
# file has them.
legacy_readings <- function(f) {
  info <- datakit::read_parquet_info(f)
  n <- info$rows
  path <- normalizePath(f)
  unpath <- function(m) gsub(path, basename(f), m, fixed = TRUE)
  reading <- function(...) {
    warnings <- character()
    tryCatch({
      value <- withCallingHandlers(datakit::read_parquet(f, ...), warning = function(w) {
        warnings <<- c(warnings, unpath(conditionMessage(w)))
        invokeRestart("muffleWarning")
      })
      list(value = value, warnings = warnings)
    }, error = function(e) list(error = unpath(conditionMessage(e)), warnings = warnings))
  }
  last_two <- utils::tail(info$columns$name, 2)
  list(
    info = info,
    default = reading(),
    factors = reading(factors = TRUE),
    integer64 = reading(int64 = "integer64"),
    character = reading(int64 = "character"),
    truncate = reading(int64 = "integer64", timestamps = "truncate"),
    window = reading(skip = n %/% 3, n_max = max(1, n %/% 2)),
    select = reading(col_select = rev(last_two))
  )
}
