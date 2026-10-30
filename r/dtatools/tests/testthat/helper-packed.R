# Packed string columns (src/strings.c).

# -2: not a packed column; -1: packed once, now made; else the number of
# cache slots made so far (one per row, or per distinct value for a
# dictionary column).
state <- function(x) .Call(dtaparser:::C_dta_packed_state, x)[[1]]
# Whether a packed column has a dictionary.
has_dictionary <- function(x) .Call(dtaparser:::C_dta_packed_state, x)[[2]] == 1
# The values without read_dta's attributes.
values <- function(x) as.vector(x)

# read_dta with the dictionary limits set by DTAPARSER_DICT_WINDOW and
# DTAPARSER_DICT_LIMIT (unset when NULL), restored afterwards.
read_with <- function(path, window = NULL, limit = NULL, ...) {
  vars <- c(DTAPARSER_DICT_WINDOW = window, DTAPARSER_DICT_LIMIT = limit)
  old <- Sys.getenv(c("DTAPARSER_DICT_WINDOW", "DTAPARSER_DICT_LIMIT"), unset = NA)
  on.exit({
    for (name in names(old)) if (is.na(old[[name]])) Sys.unsetenv(name) else do.call(Sys.setenv, as.list(old[name]))
  })
  Sys.unsetenv(names(old))
  if (length(vars)) do.call(Sys.setenv, as.list(vapply(vars, format, "", scientific = FALSE)))
  read_dta(path, ...)
}

# read_dta with no dictionaries: every string column one value per row.
read_plain <- function(path, ...) read_with(path, limit = 0, ...)
