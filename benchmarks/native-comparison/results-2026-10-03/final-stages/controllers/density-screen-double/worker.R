args <- commandArgs(TRUE)
stopifnot(length(args) %in% 3:4)
qualify_only <- length(args)==4L && identical(args[[4]],'qualify')
stopifnot(length(args)==3L || qualify_only)
.libPaths(c(normalizePath(args[[1]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'),'path')),
    file.path(normalizePath(args[[1]]),'dtatools')))
round <- as.integer(args[[2]])
stopifnot(length(round)==1L,!is.na(round),round>=1L)
hash <- function(x) digest::digest(writeBin(x,raw(),size=4L,endian='little'),algo='sha256',serialize=FALSE)
metadata_hash <- function(x) digest::digest(attributes(x),algo='sha256')
value_hash <- function(x) digest::digest(writeBin(as.double(x),raw(),size=8L,endian='little'),algo='sha256',serialize=FALSE)
state <- function(x) c(compact=dtatools:::.is_unmaterialized_numeric_altrep(x),
    materialized=.Call(dtatools:::C_dtatools_is_materialized_numeric_altrep,x))
rows <- list(); n <- 1000000L; threads <- 1L
options(dtatools.threads=threads)
operations <- list(pair_less=function(x,y) x<y,pair_equal=function(x,y) x==y)
densities <- c('random_half','clustered_half','all_tags')
permutations <- list(c(1L,2L,3L),c(1L,3L,2L),c(2L,1L,3L),
    c(2L,3L,1L),c(3L,1L,2L),c(3L,2L,1L))
density_order <- densities[permutations[[(round-1L)%%6L+1L]]]
operation_order <- if(round%%2L) names(operations) else rev(names(operations))
for(density_position in seq_along(density_order)) {
    density <- density_order[[density_position]]
    px <- as.double((seq_len(n)*13) %% 10001L-5000L)/8
    py <- as.double((seq_len(n)*19) %% 10001L-5000L)/8
    rx <- integer(n); ry <- integer(n)
    if(density=='random_half') {
        RNGkind('Mersenne-Twister','Inversion','Rejection')
        set.seed(29071L); ix <- sample.int(n,n%/%2L,replace=FALSE)
        set.seed(60149L); iy <- sample.int(n,n%/%2L,replace=FALSE)
    } else if(density=='clustered_half') {
        ix <- iy <- seq_len(n%/%2L)
    } else ix <- iy <- seq_len(n)
    rx[ix] <- rep(1:27,length.out=length(ix))
    ry[iy] <- rep(27:1,length.out=length(iy))
    stopifnot(sum(rx>0L)==length(ix),sum(ry>0L)==length(iy),
        all(1:27 %in% rx),all(1:27 %in% ry))
    for(code in 1:27) {
        value <- if(code==1L) NA_real_ else tagged_missing(letters[code-1L])
        px[rx==code] <- value; py[ry==code] <- value
    }
    x <- list(compact=dta_float(px),typed_double=dta_double(px))
    y <- list(compact=dta_float(py),typed_double=dta_double(py))
    x$compact <- .Call(dtatools:::C_dtatools_owned_numeric_freeze,x$compact,8191L)
    y$compact <- .Call(dtatools:::C_dtatools_owned_numeric_freeze,y$compact,16385L)
    stopifnot(.Call(dtatools:::C_dtatools_owned_numeric_info,x$compact)[['owned']]==1,
        .Call(dtatools:::C_dtatools_owned_numeric_info,y$compact)[['owned']]==1)
    vx <- px; vy <- py; vx[rx>0L] <- 0; vy[ry>0L] <- 0
    expected <- list(pair_less=rx<ry | (rx==ry & vx<vy),pair_equal=rx==ry & vx==vy)
    input_hash <- value_hash(px); y_hash <- value_hash(py)
    rank_x_hash <- hash(rx); rank_y_hash <- hash(ry)
    x_missing <- sum(rx>0L); y_missing <- sum(ry>0L)
    pair_missing <- sum(rx>0L | ry>0L)
    for(operation_position in seq_along(operation_order)) {
        operation <- operation_order[[operation_position]]
        case <- (match(density,densities)-1L)*2L+match(operation,names(operations))
        order <- if((round+case)%%2L) names(x) else rev(names(x))
        for(position in seq_along(order)) {
            representation <- order[[position]]
            a <- x[[representation]]; b <- y[[representation]]; call <- operations[[operation]]
            stopifnot(identical(value_hash(a),input_hash),identical(value_hash(b),y_hash))
            metadata_x <- metadata_hash(a); metadata_y <- metadata_hash(b)
            before <- state(a); before_y <- state(b); reference <- expected[[operation]]
            actual <- call(a,b)
            stopifnot(identical(actual,reference),identical(state(a),before),identical(state(b),before_y))
            op <- if(operation=='pair_equal') 0L else 2L
            native <- .Call(dtatools:::C_dtatools_dta_compare,op,a,b,NULL,threads)
            stopifnot(identical(native,reference))
            reps <- 1L
            if(!qualify_only) repeat {
                gc(); start <- proc.time(); for(i in seq_len(reps)) result <- call(a,b)
                duration <- sum((proc.time()-start)[1:2])
                if(duration>=.05 || reps>=10000L) break
                reps <- reps*5L
            }
            if(qualify_only) {
                result <- call(a,b); timing <- c(user.self=0,sys.self=0,elapsed=0)
            } else {
                reps <- max(reps,ceiling(reps*.30/max(duration,.001)))
                gc(); start <- proc.time(); for(i in seq_len(reps)) result <- call(a,b)
                timing <- proc.time()-start
            }
            stopifnot(identical(result,reference),identical(value_hash(a),input_hash),
                identical(value_hash(b),y_hash),identical(state(a),before),identical(state(b),before_y),
                identical(metadata_hash(a),metadata_x),identical(metadata_hash(b),metadata_y))
            rows[[length(rows)+1L]] <- data.frame(round,phase=if(qualify_only) "qualify" else "measure",threads,density,density_position,
                operation,operation_position,representation,position,rows=n,repetitions=reps,
                x_missing,y_missing,pair_missing,rank_x_hash,rank_y_hash,cpu=sum(timing[1:2]),wall=timing[['elapsed']],
                result_hash=hash(result),input_hash,y_hash,compact_before=before[['compact']],
                compact_after=state(a)[['compact']],materialized_before=before[['materialized']],
                materialized_after=state(a)[['materialized']],y_compact_before=before_y[['compact']],
                y_compact_after=state(b)[['compact']],y_materialized_before=before_y[['materialized']],
                y_materialized_after=state(b)[['materialized']],metadata_x,metadata_y,native_qualified=TRUE)
        }
    }
}
write.csv(do.call(rbind,rows),args[[3]],row.names=FALSE)
cat(length(rows),'qualified observations\n')
