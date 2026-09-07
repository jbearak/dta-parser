source('/private/tmp/dta-direct-stage5-validation/implementation/semantics-review/probe-01.R',echo=FALSE)
cases<-list(
 delete_group=quote(mutate(group_by(dibble(g=c(1,1,2),x=1:3),g),g=NULL)),
 delete_rowwise=quote(mutate(rowwise(dibble(g=c(1,1,2),x=1:3),g),g=NULL)),
 transmute_delete_group=quote(transmute(group_by(dibble(g=c(1,1,2),x=1:3),g),g=NULL,y=x)),
 rowwise_rename=quote(group_vars(rowwise(dibble(x=1:3),k=x))),
 group_symbol_missing=quote(group_by(dibble(x=1:3),k_missing)),
 mutate_group_df_unwrap=quote(mutate(group_by(dibble(g=1:3,x=1:3),g),tibble::new_tibble(list(a=1L,a=2L),nrow=1L))),
 grouped_names=quote({x<-dta_double(c(a=1,b=2,c=3));d<-group_by(dibble(g=c(1,1,2),x=x),g);out<-mutate(d,y=x);attributes(out$y)}),
 rawrownames=quote({d<-dibble(x=1:3);attr(d,'row.names')<-c('a','b','c');.row_names_info(mutate(d,y=x),0L)}),
 grouped_null_size=quote(mutate(group_by(dibble(g=c(1,1,2),x=1:3),g),y=if(n()==2L)NULL else x)),
 closure_inside=quote({f<-list();d<-group_by(dibble(g=c(1,1,2),x=1:3),g);out<-mutate(d,y={f[[cur_group_id()]]<<-function()x;x},x=x+10,z={sum(vapply(f,function(g)sum(g()),numeric(1)))});as.double(out$z)}),
 promise_inside=quote({del<-new.env();capture<-function(x,id){delayedAssign(id,x,eval.env=environment(),assign.env=del);0L};d<-group_by(dibble(g=c(1,1,2),x=1:3),g);out<-mutate(d,y=capture(x,paste0('p',cur_group_id())),x=x+10,z={sum(del$p1)+sum(del$p2)});as.double(out$z)}),
 rowwise_list_data_frame=quote(mutate(rowwise(dibble(x=list(tibble::tibble(a=1,b=2),tibble::tibble(a=3,b=4)))),y=list(pick(x))))
)
for(name in names(cases)){
 cat('\nCASE ',name,'\n',sep='');activate(FALSE);baseline<-record(cases[[name]]);activate(TRUE);candidate<-record(cases[[name]]);cat('BASELINE\n');print(baseline);cat('CANDIDATE\n');print(candidate)
}
