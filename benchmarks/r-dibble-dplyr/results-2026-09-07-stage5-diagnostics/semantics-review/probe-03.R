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
cases <- list(
 rowwise_nested_df=quote(mutate(rowwise(dibble(x=data.frame(a=1:3,b=4:6))),y=list(x))),
 rowwise_nested_df_next=quote(mutate(rowwise(dibble(x=1:3)),z=data.frame(a=x,b=x+1),q=list(z))),
 rowwise_nested_pick=quote(mutate(rowwise(dibble(x=data.frame(a=1:3,b=4:6))),y=list(pick(x)))),
 rowwise_matrix=quote(mutate(rowwise(dibble(x=I(matrix(1:6,nrow=3)))),y=list(x))),
 grouped_names_metadata=quote({x<-dta_double(1:3);attr(x,'other')<-list(a=1:3);d<-group_by(dibble(g=c(1,1,2),x=x),g);attributes(mutate(d,y=x)$y)}),
 retained_mask=quote({d<-group_by(dibble(g=c(1,1,2),x=1:3),g);f<-list();out<-mutate(d,y={f[[cur_group_id()]]<<-function()x;x},x=x+10);lapply(f,function(g)tryCatch(g(),error=function(e)conditionMessage(e)))}),
 duplicate_df=quote(mutate(dibble(x=1:3),tibble::new_tibble(list(a=1:3,a=4:6),nrow=3L)))
)
for(name in names(cases)){
 cat('\nCASE ',name,'\n',sep='');activate(FALSE);baseline<-record(cases[[name]]);activate(TRUE);candidate<-record(cases[[name]]);cat('BASELINE\n');print(baseline);cat('CANDIDATE\n');print(candidate)
}
