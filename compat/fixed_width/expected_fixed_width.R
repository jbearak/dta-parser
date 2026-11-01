# Read compat/fixed_width/synthetic.dat through synthetic.sas with
# asciiSetupReader (MIT), the oracle for fixed-width reads (ADR 0005), and
# write what it reads to compat/expected/fixed_width.json: per variable,
# the values with the setup's recodes applied (null for missing), the
# value labels, the codes the setup recodes, and the variable label as
# asciiSetupReader gives it (cleaned to a name, so compare letters and
# digits only). Run from the repository root:
#   Rscript compat/fixed_width/expected_fixed_width.R
library(asciiSetupReader)
dir <- "compat/fixed_width"
data <- file.path(dir, "synthetic.dat")
setup <- file.path(dir, "synthetic.sas")
values <- read_ascii_setup(data, setup, use_value_labels = FALSE, use_clean_names = FALSE)
parsed <- parse_setup(setup)
missing <- parsed$missing
vars <- lapply(seq_len(nrow(parsed$setup)), function(i) {
  name <- parsed$setup$column_number[i]
  x <- values[[name]]
  labels <- parsed$value_labels[[name]]
  list(
    name = name,
    label = parsed$setup$column_name[i],
    values = lapply(x, function(v) if (is.na(v)) NULL else v),
    labels = if (is.null(labels)) list() else lapply(seq_along(labels), function(j) list(as.numeric(labels[[j]]), names(labels)[j])),
    recoded = if (is.null(missing)) list() else as.list(as.numeric(missing$values[missing$variable == name]))
  )
})
out <- list(oracle = paste("asciiSetupReader", utils::packageVersion("asciiSetupReader")), nobs = nrow(values), variables = vars)
writeLines(jsonlite::toJSON(out, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE),
           "compat/expected/fixed_width.json")
