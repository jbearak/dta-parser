library(dtatools, lib.loc='/private/tmp/dta-direct-stage4-validation/candidate-c8ca0a4-library')
library(dplyr)
ns <- asNamespace('dtatools')
e <- new.env(parent=ns)
for (f in c('mutate-data.R','dibble-dplyr-context.R','dibble-expressions.R')) sys.source(file.path('/private/tmp/dta-direct-stage5/r-package/dtatools/R', f),e)
generics <- c('mutate','transmute','group_by','rowwise','ungroup')
activate <- function(candidate) for(generic in generics) registerS3method(generic,'dtatools_ref_data',get(paste0(generic,'.dtatools_ref_data'),if(candidate)e else ns),asNamespace('dplyr'))
record <- function(expr) {
 warnings <- list(); messages <- list()
 value <- withCallingHandlers(tryCatch(eval(expr),error=function(err)list(error=conditionMessage(err),class=class(err))),warning=function(w){warnings[[length(warnings)+1L]]<<-conditionMessage(w);invokeRestart('muffleWarning')},message=function(m){messages[[length(messages)+1L]]<<-conditionMessage(m);invokeRestart('muffleMessage')})
 list(value=value,warnings=warnings,messages=messages)
}
probe<-function(){
 d<-group_by(dibble(g=1:2,x=c(10,20),z=c(30,40)),g)
 fs<-list();zs<-list();pronouns<-list();qs<-list();late<-new.env(parent=emptyenv())
 capture<-function(v,id){delayedAssign(id,v,eval.env=environment(),assign.env=late);0L}
 out<-mutate(d,y={i<-cur_group_id();fs[[i]]<<-function()x;zs[[i]]<<-function()z;pronouns[[i]]<<-.data;qs[[i]]<<-rlang::quo(x);capture(x,paste0('g',i));0L})
 observe<-function(f){warnings<-character();err<-withCallingHandlers(tryCatch({f();NULL},error=identity),warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart('muffleWarning')});list(warnings=warnings,obsolete=inherits(err,'error')&&grepl('Obsolete data mask',conditionMessage(err),fixed=TRUE),classes=class(err))}
 list(first_promise=observe(function()late$g1),second_promise=observe(function()late$g2),first_closure=observe(fs[[1L]]),second_closure=observe(fs[[2L]]),repeated_user_promise=observe(function()late$g1),other_column_first=observe(zs[[1L]]),other_column_second=observe(zs[[2L]]),pronoun=observe(function()pronouns[[1L]]$x),quosure=observe(function()rlang::eval_tidy(qs[[1L]])))
}
activate(FALSE);baseline<-probe();activate(TRUE);candidate<-probe()
print(list(baseline=baseline,candidate=candidate))
stopifnot(identical(baseline,candidate))
cat('Exact error classes, obsolete outcomes and interrupted-promise warning vectors match for 9 repeated-read cases.\n')
