# Bounded row-name diagnostic on an explicitly selected installed artifact.
args <- commandArgs(trailingOnly=TRUE)
library(dtatools, lib.loc=args[[1L]])
library(dplyr)
d <- dibble(x=1:2,y=3:4)
attr(d,'row.names') <- c('r1','r2')
for (name in c('mutate','transmute','group_by','rowwise','ungroup')) {
  value <- switch(name, mutate=mutate(d,z=1), transmute=transmute(d,z=1),
    group_by=group_by(d,x), rowwise=rowwise(d,x), ungroup=ungroup(d))
  cat(name,' ');dput(.row_names_info(value,0L))
}
for (size in c(0L,2L)) {
  d <- as_dibble(tibble::new_tibble(list(),nrow=size))
  value <- tryCatch(mutate(d,x=1),error=function(cnd)conditionMessage(cnd))
  cat('zero-column size ',size,' ');print(value)
}
