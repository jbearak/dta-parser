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
probe<-function(){d<-rowwise(dibble(a=1:2,b=3:4,x=5:6),b,a);list(before=group_vars(d),after=group_vars(mutate(d,a=a+1)),transmute=group_vars(transmute(d,a=a+1,y=1)))}
activate(FALSE);baseline<-probe();activate(TRUE);candidate<-probe();print(list(baseline=baseline,candidate=candidate))
