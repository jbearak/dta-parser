args <- commandArgs(trailingOnly = TRUE)
library(dplyr)
source(args[[1L]])
output <- args[[2L]]
events <- list()
make_fn <- function() {
  events[[length(events) + 1L]] <<- list(group = dplyr::cur_group_id(), calls = sys.calls())
  function(value) value
}
alias <- dplyr::across
d <- tibble(g = c("a", "a", "b"), x = 1:3, y = 4:6)
q <- rlang::quo(alias(x:y, make_fn()))
own <- proof_eval(d, list(1:2, 3L), tibble(g = c("a", "b")), "g", q, named = FALSE)
own_events <- events
events <- list()
ref <- dplyr::mutate(group_by(d, g), !!q)
source_root <- "/private/tmp/dta-direct-stage1-validation/upstream/dplyr"
matches <- list()
for (file in c("R/context.R", "R/across.R", "R/pick.R")) {
  parsed <- parse(file.path(source_root, file), keep.source = FALSE)
  for (expr in parsed) {
    if (!is.call(expr) || !identical(expr[[1L]], quote(`<-`)) ||
        !is.symbol(expr[[2L]]) || !is.call(expr[[3L]]) ||
        !identical(expr[[3L]][[1L]], quote(`function`))) next
    name <- as.character(expr[[2L]])
    fn <- get(name, asNamespace("dplyr"))
    matches[[paste(file, name, sep = "::")]] <- list(
      formals = identical(formals(fn), expr[[3L]][[2L]]),
      body = identical(body(fn), expr[[3L]][[3L]]))
  }
}
dput(list(own = own_events, reference = events, parsed_source_matches = matches),
     file = file.path(output, "factory-calls.R"))
cat("OWN_FACTORY_CALLS", length(own_events), "REFERENCE_FACTORY_CALLS", length(events), "\n")
cat("PARSED_FUNCTIONS", length(matches), "BODY_MATCHES", sum(vapply(matches, `[[`, logical(1), "body")),
    "FORMALS_MATCHES", sum(vapply(matches, `[[`, logical(1), "formals")), "\n")
