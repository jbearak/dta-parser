args <- commandArgs(TRUE)
library(dtatools)
cat(R.version.string, '\nimplementation:', args[1], '\n')
reserve <- if (exists('reserve_columns',asNamespace('dtatools'))) dtatools::reserve_columns else function(x,n) .Call(dtatools:::C_dtatools_reserve_column_capacity,x,length(x)+as.double(n))
median_time <- function(f, reps=7L) median(replicate(reps, system.time(f())[['elapsed']]))
# Fixed pointer-list allocation from Rprofmem, independent of payload length.
for (rows in c(10L,1000000L)) {
    data <- data.frame(x=runif(rows))
    address <- rlang::obj_address(data$x)
    for (spare in c(0L,256L,5000L)) {
        tmp<-tempfile();Rprofmem(tmp);prepared<-reserve(data,spare);Rprofmem(NULL)
        bytes <- suppressWarnings(as.numeric(sub(' .*','',readLines(tmp))))
        unlink(tmp)
        cat('reserve rows=',rows,' spare=',spare,' capacity allocation=',8*(1+spare),' payload_same=',identical(address,rlang::obj_address(prepared$x)), ' max_alloc=',max(c(0,bytes),na.rm=TRUE),'\n',sep='')
    }
}
for (width in c(1L,1000L)) {
    columns<-setNames(rep(list(as.double(seq_len(100L))),width),paste0('v',seq_len(width)))
    data<-tibble::as_tibble(columns)
    for (spare in c(256L,5000L)) {
        elapsed<-median_time(function() for(i in 1:1000) reserve(data,spare))
        cat('reserve width=',width,' spare=',spare,' median_1000_seconds=',elapsed,'\n',sep='')
    }
}
# Both implementations append 200 columns within initial capacity.
elapsed<-median_time(function(){data<-dibble(x=1:100);for(i in 1:200) gen(data,!!paste0('v',i),1L)})
cat('gen 200 within capacity median_seconds=',elapsed,'\n',sep='')
if(args[1]=='new') {
  for(spare in c(0L,5000L)) {
    elapsed<-median_time(function(){options(dtatools.alloccol=spare);data<-dibble(x=1:100);suppressWarnings(for(i in 1:200) gen(data,!!paste0('v',i),1L))})
    cat('gen 200 spare=',spare,' median_seconds=',elapsed,'\n',sep='')
  }
}
