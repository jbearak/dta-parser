library(dtatools, lib.loc='/private/tmp/dta-direct-stage4-validation/candidate-c8ca0a4-library')
library(dplyr)
e <- new.env(parent=asNamespace('dtatools'))
for(f in c('mutate-data.R','dibble-dplyr-context.R','dibble-expressions.R'))sys.source(file.path('/private/tmp/dta-direct-stage5/r-package/dtatools/R',f),e)
probe <- function(kind, fail=FALSE) {
 sentinel <- new.env(parent=emptyenv()); wref <- rlang::new_weakref(sentinel)
 value <- dta_double(1:3); attr(value,'review_lifetime') <- sentinel
 columns<-list(x=value)
 groups<-list(rows=list(1:3),names=character(),keys=tibble::new_tibble(list(),nrow=1L),type='ungrouped')
 mask<-e$.new_dibble_expression_mask(columns,groups,3L,'mutate()')
 captured<-switch(kind,
  closure=mask$evaluate(rlang::quo(function()x),1L),
  pronoun=mask$evaluate(rlang::quo(.data),1L),
  quosure=mask$evaluate(rlang::quo(rlang::quo(x)),1L),
  promise={target<-new.env(parent=emptyenv()); capture<-function(value){delayedAssign('v',value,eval.env=environment(),assign.env=target);0L};mask$evaluate(rlang::quo(capture(x)),1L);target})
 if(fail) tryCatch(mask$evaluate(rlang::quo(stop('failure')),1L),error=function(c)NULL)
 mask$forget()
 rm(sentinel,value,columns,groups,mask)
 if(kind=='promise')rm(target,capture)
 list(weak=wref,captured=captured)
}
for(kind in c('closure','pronoun','quosure','promise')) for(fail in c(FALSE,TRUE)) {
 result<-probe(kind,fail)
 invisible(gc());invisible(gc())
 alive<-!is.null(rlang::wref_key(result$weak))
 read<-tryCatch({switch(kind,closure=result$captured(),pronoun=result$captured$x,quosure=rlang::eval_tidy(result$captured),promise=result$captured$v);FALSE},error=function(err)grepl('Obsolete data mask',conditionMessage(err),fixed=TRUE))
 cat(kind,' fail=',fail,' retained=',alive,' obsolete=',read,'\n',sep='')
 if(alive||!read)stop('Lifetime or invalidation failure')
 result<-NULL
}
