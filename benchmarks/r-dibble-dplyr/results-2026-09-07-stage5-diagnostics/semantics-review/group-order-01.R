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
 d<-group_by(dibble(g=c(1,1,2),x=1:3),g)
 attr(d,'groups')<-attr(d,'groups')[2:1,]
 out<-mutate(d,y=cur_group_id())
 list(input_keys=as.double(group_keys(d)$g),output_keys=as.double(group_keys(out)$g),ids=as.double(out$y),later_ids=as.double(mutate(out,z=cur_group_id())$z))
}
activate(FALSE);baseline<-probe();activate(TRUE);candidate<-probe()
print(list(baseline=baseline,candidate=candidate))
