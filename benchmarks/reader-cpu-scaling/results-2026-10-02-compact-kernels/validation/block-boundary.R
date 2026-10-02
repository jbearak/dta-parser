args <- commandArgs(TRUE)
.libPaths(c(args[[1L]],.libPaths())); library(dtatools)
native <- function(name,...) .Call(get(name,asNamespace('dtatools')),...)
bytes <- function(x) writeBin(x,raw(),size=8L,endian='little')
records <- list()
for (missing in c(FALSE,TRUE)) {
 values <- c(rep(0,65535L),2^100,1,-2^100,1)
 if (missing) values <- c(values,NA_real_)
 for (chunk in c(0,7,32768,65536,65537)) {
  source <- dta_float(values)
  if (chunk>0) source <- native('C_dtatools_owned_numeric_freeze',source,as.double(chunk))
  input <- as.double(source)
  for (remove in c(FALSE,TRUE)) {
   result <- sum(input,na.rm=remove); expected <- sum(values,na.rm=remove)
   stopifnot(identical(bytes(result),bytes(expected)),dtatools:::.is_unmaterialized_numeric_altrep(source),dtatools:::.is_unmaterialized_numeric_altrep(input))
   records[[length(records)+1L]] <- data.frame(missing=missing,chunk_rows=chunk,na_rm=remove,exact=TRUE,lazy=TRUE)
  }
 }
}
write.csv(do.call(rbind,records),args[[2L]],row.names=FALSE)
cat(length(records),'exact boundary cases passed\n')
