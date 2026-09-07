source('/private/tmp/dta-direct-stage5-minimum-preflight/runtime-clean-probe/check.R')
smoke_error <- tryCatch({
  source('/private/tmp/dta-direct-stage5-minimum-preflight/runtime-smoke.R')
  NULL
}, error = identity)
source('/private/tmp/dta-direct-stage5-minimum-preflight/runtime-clean-probe/check.R')
if (!is.null(smoke_error)) stop(smoke_error)
cat('PASS older unmodified CRAN dplyr binary: bounded runtime feasibility only.\n')
