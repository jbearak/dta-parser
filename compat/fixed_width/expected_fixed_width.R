# Read compat/fixed_width/synthetic.dat through synthetic.sas with
# asciiSetupReader (MIT), the oracle for fixed-width reads (ADR 0005), and
# write what it reads to compat/expected/fixed_width.json: per variable,
# the values with the setup's recodes applied (null for missing), the
# value labels, the codes the setup recodes, and the variable label as
# asciiSetupReader gives it (cleaned to a name, so compare letters and
# digits only).
#
# For recodes = "tagged", the expected values are asciiSetupReader's
# codes read without the recodes, with each recoded code made a haven
# tagged NA: per variable, the codes in the order asciiSetupReader's
# parse_setup() lists the recodes take .a, .b, ... ("tagged", and
# "tagged_labels" with the labels of those codes on their letters; a
# recoded code with no label has its number as label text, as plan 0009
# specifies, so every letter can be read back).
# Run from the repository root:
#   Rscript compat/fixed_width/expected_fixed_width.R
library(asciiSetupReader)
library(haven)
dir <- "compat/fixed_width"
data <- file.path(dir, "synthetic.dat")
setup <- file.path(dir, "synthetic.sas")
values <- read_ascii_setup(data, setup, use_value_labels = FALSE, use_clean_names = FALSE)
# The same setup without its recodes gives the codes.
lines <- readLines(setup)
no_recodes <- tempfile(fileext = ".sas")
writeLines(lines[!grepl("^\\s*IF \\(", lines)], no_recodes)
codes <- read_ascii_setup(data, no_recodes, use_value_labels = FALSE, use_clean_names = FALSE)
parsed <- parse_setup(setup)
missing <- parsed$missing

cell <- function(v) {
  if (!is.na(v)) return(unclass(v))
  if (is.na(na_tag(v))) NULL else list(missing = paste0(".", na_tag(v)))
}

vars <- lapply(seq_len(nrow(parsed$setup)), function(i) {
  name <- parsed$setup$column_number[i]
  x <- values[[name]]
  labels <- parsed$value_labels[[name]]
  recoded <- if (is.null(missing)) numeric() else as.numeric(missing$values[missing$variable == name])
  tags <- letters[seq_along(recoded)]
  tagged <- codes[[name]]
  if (length(recoded)) {
    tagged <- as.double(tagged)
    for (j in seq_along(recoded)) tagged[!is.na(tagged) & tagged == recoded[j]] <- tagged_na(tags[j])
  }
  tagged_labels <- list()
  if (!is.null(labels)) {
    for (j in seq_along(labels)) {
      code <- as.numeric(labels[[j]])
      k <- match(code, recoded)
      tagged_labels[[length(tagged_labels) + 1]] <- list(if (is.na(k)) code else paste0(".", tags[k]), names(labels)[j])
    }
  }
  for (j in seq_along(recoded)) {
    if (!recoded[j] %in% as.numeric(labels)) {
      tagged_labels[[length(tagged_labels) + 1]] <- list(paste0(".", tags[j]), format(recoded[j], scientific = FALSE))
    }
  }
  list(
    name = name,
    label = parsed$setup$column_name[i],
    values = lapply(x, function(v) if (is.na(v)) NULL else v),
    labels = if (is.null(labels)) list() else lapply(seq_along(labels), function(j) list(as.numeric(labels[[j]]), names(labels)[j])),
    recoded = as.list(recoded),
    tagged = if (is.character(tagged)) NULL else lapply(tagged, cell),
    tagged_labels = tagged_labels
  )
})
out <- list(oracle = paste("asciiSetupReader", utils::packageVersion("asciiSetupReader"), "and haven",
                           utils::packageVersion("haven")),
            nobs = nrow(values), variables = vars)
writeLines(jsonlite::toJSON(out, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE),
           "compat/expected/fixed_width.json")
