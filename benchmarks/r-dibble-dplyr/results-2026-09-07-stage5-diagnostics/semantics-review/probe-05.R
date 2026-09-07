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
cases<-list(
 ungroup_rename=quote(ungroup(group_by(dibble(g=1:3,x=4:6),g),new=g)),
 across_logical_predicate=quote(mutate(group_by(dibble(g=c(1,1,2),x=1:3),g),y={if_any(x,~.x>2)},z=cur_column())),
 rowwise_nested_df=quote(mutate(rowwise(dibble(x=data.frame(a=1:3,b=4:6))),y=list(x))),
 delete_group=quote(mutate(group_by(dibble(g=1:3,x=4:6),g),g=NULL)),
 grouped_full_value=quote({x<-dta_double(1:3);attr(x,'other')<-'kept';attributes(mutate(group_by(dibble(g=c(1,1,2),x=x),g),y=x)$y)})
)
for(name in names(cases)){cat('\nCASE ',name,'\n',sep='');activate(FALSE);baseline<-record(cases[[name]]);activate(TRUE);candidate<-record(cases[[name]]);cat('BASELINE\n');print(baseline);cat('CANDIDATE\n');print(candidate)}
