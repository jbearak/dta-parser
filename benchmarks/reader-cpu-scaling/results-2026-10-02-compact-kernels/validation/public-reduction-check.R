args <- commandArgs(TRUE)
.libPaths(c(args[[1L]],.libPaths())); library(dtatools)
p <- '<reader-work>/fixtures/'
d <- read_dta(paste0(p,'compact.dta'),threads=1L,output='tibble'); plain <- readRDS(paste0(p,'compact.rds'))
for (i in c(1L,9L,17L,25L)) for (name in c('sum','min','max')) {
 f <- get(name,baseenv()); actual <- f(d[[i]],na.rm=TRUE); expected <- f(plain[[i]],na.rm=TRUE)
 cat(i,name,typeof(actual),class(actual),'actual',format(as.double(actual),digits=22),'expected',format(expected,digits=22),'identical',identical(as.double(actual),expected),'\n')
}
