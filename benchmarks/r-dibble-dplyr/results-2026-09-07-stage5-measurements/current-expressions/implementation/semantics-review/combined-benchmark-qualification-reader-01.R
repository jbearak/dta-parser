# Retained qualification records only. No fixture, mutation or timing executes.
args <- commandArgs(TRUE)
root <- args[[1L]]
out <- args[[2L]]
sha <- 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
folder <- file.path(root,'candidate-a2d8b6a-qualify-01')
q <- dget(file.path(folder,'qualification.R'))
stopifnot(length(q$records)==16L,all(vapply(q$records,identical,logical(1),TRUE)),identical(q$source,sha))
states <- readRDS(file.path(folder,'source-states.rds'))
expected <- character()
records <- list()
for(kind in c('ungrouped','grouped','by','rowwise'))
 for(operation in c('retain','dependent','capture','pipeline_five')) {
  if(operation=='capture' && kind!='ungrouped') next
  for(mode in c('direct','legacy','safe_reference')) {
   old <- NULL
   for(phase in c('fixture','after_oracle')) {
    key <- paste(kind,operation,mode,phase)
    expected <- c(expected,key)
    state <- states[[key]]
    columns <- c(if(kind%in%c('grouped','by')) 'g','x','s','p3','p4')
    stopifnot(identical(state$column,columns),all(state$phase==phase),
              all(state$owned),all(state$depth==1L),all(state$bytes==96),
              !any(state$exposed),all(state$handle_shared),!any(state$backing_private))
    if(phase=='fixture') old <- state$backing else stopifnot(identical(state$backing,old))
    records[[key]] <- data.frame(case=key,state)
   }
  }
 }
stopifnot(identical(names(states),expected),length(states)==78L)
records <- do.call(rbind,records)
stopifnot(nrow(records)==348L)
write.csv(records,file.path(out,'combined-benchmark-source-states-01.csv'),row.names=FALSE)
folder <- file.path(root,'candidate-a2d8b6a-write-qualify-01')
q <- read.csv(file.path(folder,'qualification.csv'),stringsAsFactors=FALSE)
session <- dget(file.path(folder,'session.R'))
stopifnot(identical(session$source,sha),identical(session$qualification_only,TRUE),nrow(q)==15L,all(q$passed))
states <- read.csv(file.path(folder,'write-states.csv'),stringsAsFactors=FALSE)
columns <- c('x','s',paste0('p',3:16),'a','b','c','d')
stopifnot(nrow(states)==600L,all(states$rows==12L),all(states$iteration==0L),
          all(states$depth==1L),!any(states$exposed),
          all(states$bytes==ifelse(states$column=='d',48,96)))
for(mode in c('direct','legacy','safe_reference'))
 for(case in c('retained_shared','computed_first','computed_shared','computed_private','full_replacement')) {
  stopifnot(sum(q$mode==mode&q$case==case)==1L)
  pair <- states[states$mode==mode&states$case==case,,drop=FALSE]
  old <- pair[pair$phase=='qualify_before',,drop=FALSE]
  new <- pair[pair$phase=='qualify_after',,drop=FALSE]
  stopifnot(identical(old$column,columns),identical(new$column,columns))
  target <- if(case=='retained_shared') 's' else 'a'
  other <- columns!=target
  stopifnot(identical(old$backing[other],new$backing[other]))
  before <- old[!other,,drop=FALSE];after <- new[!other,,drop=FALSE]
  if(case=='computed_private') {
   stopifnot(!before$handle_shared,before$backing_private,identical(before$backing,after$backing))
  } else stopifnot(before$handle_shared,!before$backing_private,!identical(before$backing,after$backing))
  stopifnot(!after$handle_shared,after$backing_private)
 }
cat('PASS16 expression reference/oracle records,78 source-state matrices/348 stable rows,15 write qualification rows/600 expected before-after states; no timings or profiles rerun\n')
