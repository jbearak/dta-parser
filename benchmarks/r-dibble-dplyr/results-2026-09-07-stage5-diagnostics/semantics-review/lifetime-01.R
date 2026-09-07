library(dtatools, lib.loc='/private/tmp/dta-direct-stage4-validation/candidate-c8ca0a4-library')
library(dplyr)
e <- new.env(parent=asNamespace('dtatools'))
for(f in c('mutate-data.R','dibble-dplyr-context.R','dibble-expressions.R'))sys.source(file.path('/private/tmp/dta-direct-stage5/r-package/dtatools/R',f),e)
probe <- function() {
 sentinel <- new.env(parent=emptyenv())
 wref <- rlang::new_weakref(sentinel)
 value <- dta_double(1:3)
 attr(value, 'review_lifetime') <- sentinel
 columns <- list(x=value)
 groups <- list(rows=list(1:3),names=character(),keys=tibble::new_tibble(list(),nrow=1L),type='ungrouped')
 mask <- e$.new_dibble_expression_mask(columns, groups, 3L, 'mutate()')
 captured <- mask$helpers$get_rlang_mask()
 mask$forget()
 list(weak=wref,captured=captured)
}
result <- probe()
invisible(gc());invisible(gc())
cat('sentinel alive after forget and two GCs: ',!is.null(rlang::wref_key(result$weak)),'\n',sep='')
cat('late read: ',tryCatch(rlang::eval_tidy(rlang::quo(x),result$captured),error=function(e)conditionMessage(e)),'\n',sep='')
weak<-result$weak
result<-NULL
invisible(gc());invisible(gc())
cat('sentinel alive after dropping captured mask: ',!is.null(rlang::wref_key(weak)),'\n',sep='')
