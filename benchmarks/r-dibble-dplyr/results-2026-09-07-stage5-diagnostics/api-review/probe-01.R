# Development diagnostic only: exact installed predecessor plus current R overlay.
# This does not qualify an installed candidate or the optional-absence matrix.
library(dtatools, lib.loc = '/private/tmp/dta-direct-stage5-validation/root-baseline-f622f1d/library')
library(dplyr)
record <- function(expr) {
  warnings <- character()
  value <- withCallingHandlers(tryCatch(eval(expr, new.env(parent = globalenv())),
    error = function(cnd) list(error = conditionMessage(cnd), call = cnd$call)),
    warning = function(cnd) { warnings <<- c(warnings, conditionMessage(cnd)); invokeRestart('muffleWarning') })
  list(value = value, warnings = warnings)
}
cases <- list(
  ungroup_rename = quote({ d <- group_by(dibble(g = 1:2, x = 3:4), g); group_vars(ungroup(d, renamed = g)) }),
  rowwise_rename = quote({ d <- dibble(g = 1:2, x = 3:4); group_vars(rowwise(d, renamed = g)) }),
  ungroup_selection = quote({ d <- group_by(dibble(g = 1:2, x = 3:4), g, x); group_vars(ungroup(d, starts_with('g'))) }),
  external_group_ref = quote({ d <- dibble(x = 1:2); external <- c(1L, 2L); group_vars(group_by(d, external)) }),
  data_group_ref = quote({ d <- dibble(g = 1:2, x = 3:4); group_vars(group_by(d, .data$g)) }),
  transmute_error = quote(rlang::catch_cnd(transmute(dibble(x=1:2), y=stop('expected')))$call),
  groupby_error = quote(rlang::catch_cnd(group_by(dibble(x=1:2), y=stop('expected')))$call),
  transmute_repeated = quote({ d <- group_by(dibble(g=1:2, x=3:4, y=5:6), g); names(transmute(d, y, x, y=10)) }),
  group_by_null = quote({ d <- group_by(dibble(g=1:2,x=3:4),g); list(names=names(group_by(d,g=NULL)), groups=group_vars(group_by(d,g=NULL))) }),
  group_by_rowwise = quote({ d <- rowwise(dibble(g=1:2,x=list(1:2,3:4))); list(k=as.integer(group_by(d,k=length(x))$k),groups=group_vars(group_by(d,k=length(x)))) })
)
baseline <- lapply(cases, record)
ns <- asNamespace('dtatools')
e <- new.env(parent = ns)
for (file in c('mutate-data.R', 'dibble-dplyr-context.R', 'dibble-expressions.R')) {
  sys.source(file.path('/private/tmp/dta-direct-stage5/r-package/dtatools/R', file), e)
}
for (generic in c('mutate','transmute','group_by','rowwise','ungroup')) {
  registerS3method(generic, 'dtatools_ref_data', get(paste0(generic,'.dtatools_ref_data'),e), asNamespace('dplyr'))
}
candidate <- lapply(cases, record)
for (name in names(cases)) {
  cat('\nCASE ', name, '\n', sep='')
  cat('BASELINE\n'); print(baseline[[name]])
  cat('CANDIDATE DEVELOPMENT OVERLAY\n'); print(candidate[[name]])
}
