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
 transmute_error=quote(rlang::catch_cnd(transmute(dibble(x=1:3),y=stop('sample')))$call),
 groupby_error=quote(rlang::catch_cnd(group_by(dibble(x=1:3),y=stop('sample')))$call),
 transmute_warning=quote(rlang::catch_cnd(transmute(dibble(x=1:3),y={warning('sample');x}),'warning')$call),
 groupby_warning=quote(rlang::catch_cnd(group_by(dibble(x=1:3),y={warning('sample');x}),'warning')$call),
 zero_group_key=quote(mutate(group_by(dibble(g=integer(),x=integer()),g),x=cur_group_id())),
 expression_lists=quote(mutate(dibble(x=1:3),y=list(a=1,b=2,c=3))),
 column_sized_names=quote({d<-group_by(dibble(g=c(1,1,2),x=c(a=1,b=2,c=3)),g);list(y=mutate(d,y=x)$y,z=mutate(d,z=.data$x)$z)}),
 full_data_symbol=quote({x<-dta_double(1:3);attr(x,'other')<-'retained';d<-group_by(dibble(g=c(1,1,2),x=x),g);attributes(mutate(d,x)$x)})
)
for(name in names(cases)){cat('\nCASE ',name,'\n',sep='');activate(FALSE);baseline<-record(cases[[name]]);activate(TRUE);candidate<-record(cases[[name]]);cat('BASELINE\n');print(baseline);cat('CANDIDATE\n');print(candidate)}
