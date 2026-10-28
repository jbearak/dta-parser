# Dump what haven and readstata13 read from each fixture to JSON, as
# expected values for this library's tests. Run from the repository root:
#   Rscript compat/expected.R [fixture.dta ...]
# A field a reader does not expose is null.
library(haven)
library(readstata13)

code_text <- function(tag) if (is.na(tag)) "." else paste0(".", tag)

# A cell: a number, a string, or {"missing": ".a"}.
cells <- function(x, tags) {
  lapply(seq_along(x), function(i) {
    if (is.character(x)) return(x[[i]])
    if (!is.na(x[[i]])) return(unclass(x)[[i]])
    list(missing = code_text(tags[[i]]))
  })
}

# Value labels as [[code, text], ...], codes as numbers or ".a".
label_pairs <- function(codes, texts) {
  lapply(seq_along(codes), function(i) list(codes[[i]], texts[[i]]))
}

from_haven <- function(path) {
  d <- read_dta(path)
  vars <- lapply(names(d), function(name) {
    x <- d[[name]]
    labels <- attr(x, "labels")
    list(
      name = name,
      type = NULL,
      format = attr(x, "format.stata"),
      label = attr(x, "label", exact = TRUE) %||% "",
      labels = if (is.null(labels)) list() else label_pairs(
        lapply(seq_along(labels), function(i) {
          if (is.na(labels[[i]])) code_text(na_tag(labels[[i]])) else unclass(labels)[[i]]
        }),
        names(labels)
      )
    )
  })
  values <- lapply(d, function(x) {
    if (inherits(x, "Date")) x <- as.numeric(x - as.Date("1960-01-01"))
    if (inherits(x, "POSIXct")) x <- as.numeric(x) * 1000 + 315619200000
    cells(x, if (is.character(x)) NULL else na_tag(x))
  })
  list(
    reader = paste("haven", packageVersion("haven")),
    release = NULL, nobs = nrow(d),
    data_label = attr(d, "label", exact = TRUE) %||% "",
    timestamp = NULL,
    variables = vars, values = values,
    notes = attr(d, "notes")
  )
}

from_readstata13 <- function(path) {
  d <- suppressWarnings(read.dta13(path, convert.factors = FALSE,
                                   convert.dates = FALSE, missing.type = TRUE,
                                   replace.strl = TRUE))
  a <- attributes(d)
  # readstata13 numbers missing values 0 for . and 1 to 26 for .a to .z,
  # and leaves label codes for missing values as stored longs.
  missing_name <- function(k) if (k == 0) "." else paste0(".", letters[k])
  label_code <- function(v) {
    if (v >= 2147483621) missing_name(v - 2147483621) else v
  }
  type_name <- function(t, release) {
    if (release >= 117) {
      switch(as.character(t), `65530` = "byte", `65529` = "int", `65528` = "long",
             `65527` = "float", `65526` = "double", `32768` = "strL",
             paste0("str", t))
    } else {
      switch(as.character(t), `251` = "byte", `252` = "int", `253` = "long",
             `254` = "float", `255` = "double", paste0("str", t))
    }
  }
  vars <- lapply(seq_along(d), function(i) {
    set <- a$val.labels[[i]]
    table <- if (nzchar(set)) a$label.table[[set]] else NULL
    list(
      name = names(d)[[i]],
      type = type_name(a$types[[i]], a$version),
      format = a$formats[[i]],
      label = a$var.labels[[i]],
      value_labels = set,
      labels = if (is.null(table)) list() else label_pairs(
        lapply(unname(table), label_code), names(table))
    )
  })
  # Before 113, readstata13 leaves a missing value as the stored
  # sentinel: the integer type's maximum, or for floats and doubles the
  # bit pattern of `.` and anything above it. Map those to `.` by the
  # variable's own storage type.
  old_missing <- function(x, type) {
    if (a$version >= 113) return(rep(FALSE, length(x)))
    switch(type,
      byte = x == 127, int = x == 32767, long = x == 2147483647,
      float = x >= 2^127, double = x >= 2^1023,
      rep(FALSE, length(x)))
  }
  values <- lapply(seq_along(d), function(j) {
    name <- names(d)[[j]]
    x <- d[[name]]
    m <- a$missing[[name]]
    sentinel <- if (is.character(x)) logical(length(x)) else old_missing(x, vars[[j]]$type) %in% TRUE
    lapply(seq_along(x), function(i) {
      if (is.character(x)) return(x[[i]])
      if (sentinel[[i]]) return(list(missing = "."))
      if (!is.na(x[[i]])) return(x[[i]])
      list(missing = missing_name(if (is.null(m) || is.na(m[[i]])) 0 else m[[i]]))
    })
  })
  names(values) <- names(d)
  chars <- a$expansion.fields
  list(
    reader = paste("readstata13", packageVersion("readstata13")),
    release = a$version, nobs = nrow(d),
    data_label = a$datalabel, timestamp = a$time.stamp,
    variables = vars, values = values,
    characteristics = lapply(chars, function(ch) list(variable = ch[[1]], name = ch[[2]], value = ch[[3]]))
  )
}

args <- commandArgs(trailingOnly = TRUE)
paths <- if (length(args)) args else Sys.glob(file.path("compat", "fixtures", "*.dta"))
for (path in paths) {
  stem <- sub("\\.dta$", "", basename(path))
  for (reader in c("haven", "readstata13")) {
    result <- tryCatch(
      if (reader == "haven") from_haven(path) else from_readstata13(path),
      error = function(e) list(reader = reader, error = conditionMessage(e))
    )
    jsonlite::write_json(result, file.path("compat", "expected", paste0(stem, ".", reader, ".json")),
                         auto_unbox = TRUE, null = "null", digits = I(17), pretty = TRUE)
  }
}
