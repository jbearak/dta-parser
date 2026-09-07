args <- commandArgs(TRUE)
stopifnot(length(args)==2)
.libPaths(c(args[[1]],.libPaths())); suppressPackageStartupMessages(library(dtatools))
cat('DLL',unname(tools::md5sum(getLoadedDLLs()[['dtatools']][['path']])),'\n')
results <- list()
for(kind in c('double','byte','integer','logical','string')) for(access in c('symbol','dollar','bracket')) for(site in c('values','where')) {
 run <- function() {
  initial <- switch(kind,double=c(1,2,3),byte=dta_byte(1:3),integer=1:3,logical=c(TRUE,FALSE,TRUE),string=c('a','b','c'))
  old <- serialize(initial,NULL)
  data <- data.frame(x=initial);rm(initial)
  old_last <- switch(kind,double=3,byte=3,integer=3L,logical=TRUE,string='c')
  replace_values(data,x,.env$old_last,where=3L)
  if(exists('C_dtatools_mutation_info',asNamespace('dtatools'),inherits=FALSE)) {
   info <- .Call(get('C_dtatools_mutation_info',asNamespace('dtatools')),data,1L)
   stopifnot(!info$handle_shared, !info$exposed)
   if(kind %in% c('double','byte')) stopifnot(info$backing_private)
  }
  alias <- NULL;count <- 0L
  env <- environment()
  makeActiveBinding('callback_input',function() {count <<- count+1L;alias <<- data$x;if(site=='where') 2L else switch(kind,double=9,byte=9,integer=9L,logical=TRUE,string='z')},env)
  expression <- switch(access,symbol=quote(callback_input),dollar=quote(.env$callback_input),bracket=quote(.env[['callback_input']]))
  call <- if(site=='values') as.call(list(quote(replace_values),quote(data),quote(x),expression,where=2L)) else as.call(list(quote(replace_values),quote(data),quote(x),switch(kind,double=9,byte=9,integer=9L,logical=TRUE,string='z'),where=expression))
  error <- tryCatch({eval(call);NULL},error=function(e)conditionMessage(e))
  list(error=error,count=count,alias_unchanged=identical(serialize(alias,NULL),old),values=as.vector(data$x))
 }
 results[[paste(kind,access,site,sep='/')]] <- run()
}
saveRDS(results,args[[2]]);cat(length(results),'cases saved\n')
