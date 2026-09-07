args <- commandArgs(TRUE)
stopifnot(length(args)==2L)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(normalizePath(find.package('dtatools'))==normalizePath(file.path(args[[1L]], 'dtatools')))
cat('DLL', unname(tools::md5sum(getLoadedDLLs()[['dtatools']][['path']])), '\n')
answer <- list()
for (container in c('frame','dibble')) for (storage in c('double','byte')) {
 for (capture in c('closure','pronoun','quosure')) for (site in c('values','where')) {
  for (outcome in c('success','empty','error')) {
   key <- paste(container,storage,capture,site,outcome,sep='/')
   vec <- if(storage=='double') dta_double(c(1,2,3)) else dta_byte(1:3)
   data <- if(container=='frame') data.frame(x=vec) else dibble(x=vec)
   rm(vec)
   replace_values(data,x,3,where=3L)
   saved <- NULL
   capture_expr <- switch(capture, closure=quote(saved <<- function() x), pronoun=quote(saved <<- function() .data$x), quosure=quote(saved <<- rlang::new_quosure(quote(x), environment())))
   tail_expr <- switch(outcome, success=if(site=='values') quote(9) else quote(2L), empty=if(site=='values') quote(9) else quote(integer()), error=quote(stop('matrix deliberate failure')))
   expr <- as.call(list(as.name('{'), capture_expr, tail_expr))
   call <- if(site=='values') as.call(list(as.name('replace_values'),as.name('data'),as.name('x'),expr,where=if(outcome=='empty') integer() else 2L)) else as.call(list(as.name('replace_values'),as.name('data'),as.name('x'),9,where=expr))
   error <- tryCatch({eval(call);NULL},error=function(e)conditionMessage(e))
   before_later <- if(is.null(saved)) NULL else tryCatch(as.double(if(capture=='quosure') rlang::eval_tidy(saved) else saved()),error=function(e) paste('ERROR',conditionMessage(e)))
   replace_values(data,x,7,where=1L)
   after_later <- if(is.null(saved)) NULL else tryCatch(as.double(if(capture=='quosure') rlang::eval_tidy(saved) else saved()),error=function(e) paste('ERROR',conditionMessage(e)))
   answer[[key]] <- list(error=error, before_later=before_later, after_later=after_later)
  }
 }
}
saveRDS(answer,args[[2L]])
cat(length(answer),'delayed capture cases recorded.\n')
