# Read retained minimum-runtime records only; no package operation executes.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
root <- args[[1L]]
out <- args[[2L]]
prefix <- 'candidate-a2d8b6a-v1'
source_sha <- 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
clean_home <- '/private/tmp/dta-direct-stage5-minimum-preflight/r460-clean-install/lib/R'
behavior <- readRDS(file.path(root,paste0(prefix,'-behavior'),'results.rds'))
stopifnot(identical(behavior,dget(file.path(root,paste0(prefix,'-behavior'),'results.R'))),
          length(behavior$cases)==8L,
          all(vapply(behavior$cases,function(x)identical(x$passed,TRUE),logical(1))),
          all(vapply(behavior$cases[1:7],function(x)identical(x$observations,TRUE),logical(1))),
          all(vapply(behavior$cases[1:7],function(x)length(x$warnings)==0L,logical(1))),
          identical(behavior$identity$source,source_sha),
          identical(behavior$identity$R_home,clean_home),
          identical(unname(behavior$identity$versions[['dplyr']]),'1.2.1'))
late <- behavior$cases[[8L]]
stopifnot(identical(late$warnings,rep('restarting interrupted promise evaluation',3L)))
for(kind in c('promises','closures')) for(item in late$observations[[kind]])
 stopifnot(identical(item$kind,'error'),'error'%in%item$classes,
           grepl('Obsolete data mask',item$message,fixed=TRUE))
observations <- readRDS(file.path(root,paste0(prefix,'-observe'),'observations.rds'))
stopifnot(identical(observations,dget(file.path(root,paste0(prefix,'-observe'),'observations.R'))),
          identical(observations$identity$source,source_sha),
          identical(observations$identity$dplyr,'1.2.1'))
for(kind in c('expanded','aliased','named','unpacked')) {
 item <- observations[[kind]]
 stopifnot(identical(item$tibble,item$dibble),
           identical(item$dibble$events,if(kind=='expanded') c('x:1','x:2','y:1','y:2') else c('x:1','y:1','x:2','y:2')),
           identical(item$dibble$factories,switch(kind,expanded=1L,aliased=4L,named=4L,unpacked=0L)),
           identical(item$dibble$columns$g,c(1L,1L,2L)),
           identical(item$dibble$columns$x,1:3),identical(item$dibble$columns$y,4:6))
}
stopifnot(identical(observations$within_across_input_values,list(x=c(11L,13L),y=c(11L,13L))))
folder <- file.path(root,paste0(prefix,'-focused'))
rows <- read.csv(file.path(folder,'tests.csv'),stringsAsFactors=FALSE)
details <- readRDS(file.path(folder,'expectation-details.rds'))
stopifnot(identical(details,dget(file.path(folder,'expectation-details.R'))),length(details)==nrow(rows))
counts <- colSums(rows[c('failed','skipped','error','warning','passed')])
stopifnot(identical(counts,dget(file.path(folder,'counts.R'))),
          identical(unname(counts),c(0,3,0,4,8859)))
issues <- list()
for(i in seq_len(nrow(rows))) {
 stopifnot(length(details[[i]])==rows$nb[[i]])
 for(item in details[[i]]) {
  stopifnot(!any(c('expectation_failure','expectation_error')%in%item$classes))
  if(!'expectation_success'%in%item$classes)
   issues[[length(issues)+1L]] <- data.frame(file=rows$file[[i]],test=rows$test[[i]],classes=paste(item$classes,collapse='/'),message=item$message)
 }
}
issues <- do.call(rbind,issues)
stopifnot(nrow(issues)==7L,
          sum(grepl('expectation_skip',issues$classes,fixed=TRUE))==3L,
          sum(grepl('expectation_warning',issues$classes,fixed=TRUE))==4L)
expression <- rows[rows$file=='test-dibble-expressions.R',,drop=FALSE]
stopifnot(nrow(expression)==22L,sum(expression$passed)==187L,
          sum(expression$failed)+sum(expression$skipped)+sum(expression$error)+sum(expression$warning)==0)
for(name in c(prefix,paste0(prefix,c('-behavior','-focused','-observe'))))
 for(phase in c('before','after')) {
  state <- dget(file.path(root,name,paste0('runtime-guard-',phase,'.R')))
  stopifnot(identical(state$R$major,'4'),identical(state$R$minor,'6.0'),
            identical(unname(state$libR),file.path(clean_home,'lib/libR.dylib')))
 }
write.csv(issues,file.path(out,'combined-minimum-issues-01.csv'),row.names=FALSE)
write.csv(expression,file.path(out,'combined-minimum-expression-rows-01.csv'),row.names=FALSE)
cat('PASS retained8 public behavior cases,4 expansion shapes,4 expired reads/3 promise warnings,8859 focused passes with3 skips/4 warnings,22 expression rows/187 issue-free assertions,8 clean-R guard records\n')
