# Read the Parquet files dta-parquet wrote with arrow and nanoparquet,
# and check their values and types against what the writer was given
# (expected.json from the samples example) and against plan 0018's table
# "What other tools see in our files".
#
# Run from the repository root:
#
#     cargo run -p dta-parquet --example samples -- DIR
#     Rscript compat/parquet/readback.R DIR
#
# Needs arrow, nanoparquet, haven and jsonlite.

args <- commandArgs(trailingOnly = TRUE)
dir <- args[[1]]
expected <- jsonlite::fromJSON(file.path(dir, "expected.json"), simplifyVector = FALSE)

failures <- character()
checked <- c(arrow = 0L, nanoparquet = 0L)
skipped <- character()
fail <- function(tool, file, what) {
  failures <<- c(failures, sprintf("%s: %s: %s", tool, file, what))
}

per_second <- c(ms = 1e3, us = 1e6, ns = 1e9)

# A column's values as plain R values, comparable with the JSON's.
normal <- function(x, spec) {
  t <- spec$type
  if (t == "timestamp") return(round(as.numeric(x) * per_second[[spec$unit]]))
  if (t == "date") return(as.numeric(x))
  if (t == "categorical") return(as.character(x))
  if (t == "binary") return(lapply(x, function(v) if (is.null(v)) NULL else as.integer(v)))
  if (inherits(x, "integer64")) return(as.numeric(as.character(x)))
  if (t == "int64") return(as.numeric(x))
  x
}

same <- function(want, got) {
  if (is.null(want)) return(is.null(got) || (length(got) == 1 && is.na(got) && !is.nan(got)))
  if (identical(want, "NaN")) return(is.numeric(got) && is.nan(got))
  if (is.list(want)) return(identical(as.integer(unlist(want)), as.integer(got)))
  if (is.null(got) || is.na(got)) return(FALSE)
  if (is.numeric(want) && want == 0 && is.numeric(got)) return(got == 0 && (1 / want) == (1 / got))
  isTRUE(all.equal(want, got, tolerance = 0))
}

compare <- function(tool, file, name, want, got) {
  if (length(want) != length(got)) {
    fail(tool, file, sprintf("%s: %d rows, not %d", name, length(got), length(want)))
    return(invisible())
  }
  for (i in seq_along(want)) {
    g <- if (is.list(got)) got[[i]] else got[i]
    if (!same(want[[i]], g)) {
      fail(tool, file, sprintf("%s: row %d is %s, not %s", name, i, format(g), format(want[[i]])))
      return(invisible())
    }
  }
}

# The R class each reader gives (plan 0018's table).
want_class <- function(tool, spec) {
  t <- spec$type
  switch(t,
    int8 = , int16 = , int32 = "integer",
    # arrow gives int64 as integer when every value fits in 32 bits.
    int64 = "integer64|numeric|integer",
    float32 = , float64 = "numeric",
    bool = "logical",
    text = "character",
    binary = if (tool == "arrow") "arrow_binary" else "list",
    date = "Date",
    timestamp = "POSIXct",
    # nanoparquet 0.5 reads dictionary columns as factors too, but never
    # ordered (plan 0018's table, written for 0.4, says character).
    categorical = if (tool == "arrow" && isTRUE(spec$ordered)) "ordered" else "factor"
  )
}

check <- function(tool, file, spec, df) {
  if (nrow(df) != spec$rows) fail(tool, file, sprintf("%d rows", nrow(df)))
  for (name in names(spec$columns)) {
    s <- spec$columns[[name]]
    x <- df[[name]]
    cls <- want_class(tool, s)
    if (!any(vapply(strsplit(cls, "|", fixed = TRUE)[[1]], function(c) inherits(x, c) || (c == "numeric" && is.double(x)) || (c == "integer" && is.integer(x)) || (c == "character" && is.character(x)) || (c == "logical" && is.logical(x)), logical(1)))) {
      fail(tool, file, sprintf("%s: class %s, not %s", name, paste(class(x), collapse = "/"), cls))
    }
    if (s$type == "categorical" && spec$rows > 0) {
      # Every level, unused ones too, in order; a table without rows has
      # no row groups, so its levels are only in the profile.
      if (!identical(levels(x), unlist(s$levels))) fail(tool, file, sprintf("%s: levels %s", name, paste(levels(x), collapse = ",")))
      if (tool == "nanoparquet" && is.ordered(x)) fail(tool, file, sprintf("%s: ordered", name))
    }
    if (s$type == "timestamp") {
      zone <- if (!is.null(s$zone)) s$zone else if (isTRUE(s$utc)) "UTC" else NULL
      got_zone <- attr(x, "tzone")
      # nanoparquet shows every instant in UTC; arrow keeps the zone.
      want_zone <- if (tool == "nanoparquet" && !is.null(zone)) "UTC" else zone
      if (!is.null(want_zone) && !identical(got_zone, want_zone)) {
        fail(tool, file, sprintf("%s: zone %s, not %s", name, format(got_zone), want_zone))
      }
    }
    compare(tool, file, name, s$values, normal(x, s))
    if (!is.null(s$letters)) {
      # .a to .z are haven's tagged NAs, with their letters; `.` and every
      # value have no tag.
      want <- vapply(s$letters, function(l) if (is.null(l)) NA_character_ else substring(l, 2), "")
      got <- haven::na_tag(x)
      ok <- (is.na(want) & is.na(got)) | (!is.na(want) & !is.na(got) & want == got)
      bad <- which(!ok)
      if (length(bad) > 0) {
        fail(tool, file, sprintf("%s: row %d has tag %s, not %s", name, bad[1], got[bad[1]], want[bad[1]]))
      }
    }
  }
  checked[[tool]] <<- checked[[tool]] + 1L
}

for (file in names(expected)) {
  spec <- expected[[file]]
  path <- file.path(dir, paste0(file, ".parquet"))
  tryCatch({
    table <- arrow::read_parquet(path, as_data_frame = FALSE)
    if (is.null(table$metadata$dta)) fail("arrow", file, "no dta key in the file metadata")
    # A date or timestamp written as DOUBLE says what it was in the
    # profile, for our readers to restore; arrow sees a double.
    profile <- jsonlite::fromJSON(table$metadata$dta, simplifyVector = FALSE)
    for (name in names(spec$columns)) {
      want <- spec$columns[[name]]$logical
      got <- profile$columns[[name]]$logical
      if (!identical(got, want)) fail("arrow", file, sprintf("%s: profile logical %s, not %s", name, format(got), format(want)))
    }
    check("arrow", file, spec, as.data.frame(table))
  }, error = function(e) fail("arrow", file, conditionMessage(e)))
  if (grepl("lz4_raw", file)) {
    # nanoparquet 0.5 does not read LZ4_RAW ("Compression is not
    # supported yet").
    skipped <- c(skipped, paste0("nanoparquet: ", file, " (LZ4_RAW not supported)"))
    next
  }
  tryCatch({
    df <- nanoparquet::read_parquet(path)
    kv <- nanoparquet::read_parquet_metadata(path)$file_meta_data$key_value_metadata[[1]]
    if (!"dta" %in% kv$key) fail("nanoparquet", file, "no dta key in the file metadata")
    check("nanoparquet", file, spec, df)
  }, error = function(e) fail("nanoparquet", file, conditionMessage(e)))
}

cat(sprintf(
  "arrow %s, nanoparquet %s: arrow read %d files, nanoparquet read %d files\n",
  packageVersion("arrow"), packageVersion("nanoparquet"), checked[["arrow"]], checked[["nanoparquet"]]
))
if (length(skipped) > 0) cat("skipped:", skipped, sep = "\n  ")
if (length(failures) > 0) {
  cat(failures, sep = "\n")
  quit(status = 1)
}
