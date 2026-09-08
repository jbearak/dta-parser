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
 unknown_group=quote({k<-c(1,1,2); group_vars(group_by(dibble(x=1:3),k))}),
 pronoun_group=quote({nm<-'x'; group_vars(group_by(dibble(x=1:3),.data[[nm]]))}),
 literal_pronoun=quote(group_vars(group_by(dibble(x=1:3),.data$x))),
 zero_cols=quote(mutate(dibble(.rows=3L),x=1L)),
 zero_rows=quote(mutate(dibble(),x=1L)),
 zero_named=quote(mutate(dibble(x=integer()),y=1L,z=n())),
 used_pick=quote(names(mutate(dibble(x=1:2,y=3:4),p=pick(x),.keep='unused'))),
 across_factory=quote({counter<-0L; fn<-function(){counter<<-counter+1L;function(x)x};out<-mutate(group_by(dibble(g=c(1,1,2),x=1:3,y=3:5),g),across(c(x,y),fn()));counter}),
 group_mix_null=quote(group_vars(group_by(dibble(x=1:3),y=x,x=NULL))),
 duplicate_unpack=quote(mutate(dibble(x=1:3),tibble::new_tibble(list(a=1:3,a=4:6),nrow=3L))),
 df_zero_cols=quote(mutate(dibble(x=1:3),tibble::new_tibble(list(),nrow=3L))),
 rowwise_df=quote(mutate(rowwise(dibble(x=1:3)),z=data.frame(a=x,b=x+1))),
 rowwise_list_empty=quote(mutate(rowwise(dibble(x=list())),y=list(x))),
 transmute_by=quote(transmute(dibble(x=1:3),.by=x,y=1L)),
 transmute_control=quote(transmute(dibble(x=1:3),.keep='all')),
 warning_count=quote(mutate(group_by(dibble(g=1:3,x=1:3),g),y={warning('sample');x})),
 group_drop_invalid=quote(group_by(dibble(g=1:3),g,.drop=NA)),
 regroup_alias=quote({d<-group_by(dibble(g=c(1,1,2),x=1:3),g); a<-ungroup(d,g); repl(a,x=9); list(source=as.double(d$x),result=as.double(a$x))}),
 group_rows_zero=quote({counter<-0L;out<-mutate(group_by(dibble(g=integer(),x=integer()),g),y={counter<<-counter+1L;n()});list(counter=counter,groups=group_data(out),names=names(out))}),
 .keep_used_overwrite=quote(names(mutate(dibble(x=1:3,y=3:5),x=y,x=1L,.keep='used')))
)
for(name in names(cases)){
 cat('\nCASE ',name,'\n',sep='')
 activate(FALSE); baseline<-record(cases[[name]])
 activate(TRUE); candidate<-record(cases[[name]])
 cat('BASELINE\n');print(baseline)
 cat('CANDIDATE\n');print(candidate)
}
