.libPaths(c('/private/tmp/dta-direct-stage4-validation/candidate-7d56080-library', .libPaths()))
library(dtatools)
for (rows in c(64L,1000L)) {
  raw <- rep(c('a','b'),length.out=rows)
  foreign <- data.table::data.table(x=rep(c('a','b'),length.out=rows))
  data.table::setattr(foreign$x,'class','stage4_unknown')
  key <- iconv('caf\u00e9', to='latin1'); Encoding(key)<-'latin1'
  data.table::setattr(foreign$x,key,'remove')
  x <- dta_string(foreign$x,'str8')
  print(.Call(dtatools:::C_dtatools_owned_info,x));print(attributes(x))
  data.table::set(foreign,i=1L,j='x',value='changed')
  stopifnot(identical(as.character(x),raw))
  x[2L] <- 'new';stopifnot(identical(as.character(foreign$x),c('changed',raw[-1L])))
  cat('rows',rows,'PASS\n')
}
