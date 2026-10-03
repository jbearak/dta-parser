# Untimed fixture preparation; no benchmark clocks.
args <- commandArgs(TRUE)
stopifnot(length(args)==2L)
library_path <- normalizePath(args[[1L]],mustWork=TRUE)
.libPaths(c(library_path,.libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'),'path')),
    file.path(library_path,'dtatools')))
output <- args[[2L]]
stopifnot(!dir.exists(output))
dir.create(output,recursive=TRUE)
sha_file <- function(path)digest::digest(file=path,algo='sha256')
value_hash <- function(x)digest::digest(writeBin(as.double(x),raw(),8L,endian='little'),algo='sha256',serialize=FALSE)
script <- sub('^--file=','',commandArgs()[startsWith(commandArgs(),'--file=')])
stopifnot(length(script)==1L)
n <- 1000000L
records <- list();files <- list()
for(pattern in c('none','sparse','random_half')) {
    x <- as.double((seq_len(n)*13)%%10001L-5000L)
    y <- as.double((seq_len(n)*19)%%1001L-500L)/8
    xp <- yp <- integer()
    if(pattern=='sparse') {
        xp <- seq.int(13L,n,by=997L);yp <- seq.int(19L,n,by=991L)
    } else if(pattern=='random_half') {
        RNGkind('Mersenne-Twister','Inversion','Rejection');set.seed(31791L)
        xp <- sample.int(n,n%/%2L);set.seed(42793L);yp <- sample.int(n,n%/%2L)
    }
    xr <- yr <- integer(n)
    xr[xp] <- rep(1:27,length.out=length(xp));yr[yp] <- rep(27:1,length.out=length(yp))
    for(code in 1:27) {
        x[xr==code] <- if(code==1L)NA_real_ else tagged_missing(letters[code-1L])
        y[yr==code] <- if(code==1L)NA_real_ else tagged_missing(letters[code-1L])
    }
    name <- paste0(pattern,'.dta');path <- file.path(output,name)
    save_dta(dibble(x=dta_long(x),y=dta_float(y)),path,version=18L)
    checked <- read_dta(path)
    stopifnot(identical(names(checked),c('x','y')),
        identical(dta_storage_type(checked$x),'long'),identical(dta_storage_type(checked$y),'float'),
        identical(value_hash(checked$x),value_hash(x)),identical(value_hash(checked$y),value_hash(y)))
    files[[name]] <- sha_file(path)
    records[[pattern]] <- list(input_hash=value_hash(c(x,y)),long_missing=length(xp),
        float_missing=length(yp),overlap=sum(xr>0L & yr>0L),
        rank_hash=digest::digest(writeBin(c(xr,yr),raw(),4L,endian='little'),algo='sha256',serialize=FALSE),
        storage=c('long','float'),bytes=unname(file.info(path)$size))
}
dll <- getLoadedDLLs()[['dtatools']][['path']]
record <- list(rows=n,format_version=118L,files=files,patterns=records,
    prepare_sha256=sha_file(script),R_version=R.version.string,R_home=R.home(),
    R_runtime_sha256=sha_file(file.path(R.home(),'bin','exec','R')),package_dll_sha256=sha_file(dll),
    scope='One immutable fixture set for both libraries. Setup and readback verification are outside all benchmark clocks.')
jsonlite::write_json(record,file.path(output,'fixtures.json'),auto_unbox=TRUE,pretty=TRUE)
