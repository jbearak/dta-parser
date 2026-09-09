# Adapted from R 4.6.1 dataframe.R,
# SVN revision 90187: data.frame, rbind.data.frame and cbind.data.frame.
# Statlib code by John Chambers, Bell Labs, 1994; changes Copyright
# (C) 1998-2025 The R Core Team. GPL-2-or-later, incorporated under GPL-3.
# Exact original source and full GPL text remain in the selected upstream
# copy; precise destination mapping and full license are installed in NOTICE.
# Conversion of each input remains a public as.data.frame extension boundary.

.dibble_base_data_frame <-
    function(..., row.names = NULL, check.rows = FALSE, check.names = TRUE,
	     fix.empty.names = TRUE,
             stringsAsFactors = FALSE)
{
    data.row.names <-
	if(check.rows && is.null(row.names))
	    function(current, new, i) {
		if(is.character(current)) new <- as.character(new)
		if(is.character(new)) current <- as.character(current)
		if(anyDuplicated(new))
		    return(current)
		if(is.null(current))
		    return(new)
		if(all(current == new) || all(current == ""))
		    return(new)
		stop(gettextf(
		    "mismatch of row names in arguments of 'data.frame\', item %d", i),
		    domain = NA)
	    }
	else function(current, new, i) {
	    current %||%
		if(anyDuplicated(new)) {
		    warning(gettextf(
                        "some row.names duplicated: %s --> row.names NOT used",
                        paste(which(duplicated(new)), collapse=",")),
                        domain = NA)
		    current
		} else new
	}
    object <- as.list(substitute(list(...)))[-1L]
    mirn <- missing(row.names) # record before possibly changing
    mrn  <- is.null(row.names) # missing or NULL
    x <- list(...)
    n <- length(x)
    if(n < 1L) {
        if(!mrn) {
            if(is.object(row.names) || !is.integer(row.names))
                row.names <- as.character(row.names)
            if(anyNA(row.names))
                stop("row names contain missing values")
            if(anyDuplicated(row.names))
                stop(gettextf("duplicate row.names: %s",
                              paste(unique(row.names[duplicated(row.names)]),
                                    collapse = ", ")),
                     domain = NA)
        } else row.names <- integer()
	return(structure(list(), names = character(),
                         row.names = row.names,
			 class = "data.frame"))
    }
    vnames <- names(x)
    if(length(vnames) != n)
	vnames <- character(n)
    no.vn <- !nzchar(vnames)
    vlist <- vnames <- as.list(vnames)
    nrows <- ncols <- integer(n)
    for(i in seq_len(n)) {
        ## do it this way until all as.data.frame methods have been updated
	xi <- if(is.character(x[[i]]) || is.list(x[[i]]))
		  as.data.frame(x[[i]], optional = TRUE,
				stringsAsFactors = stringsAsFactors)
	      else as.data.frame(x[[i]], optional = TRUE)

        nrows[i] <- .row_names_info(xi) # signed for now
	ncols[i] <- length(xi)
	namesi <- names(xi)
	if(ncols[i] > 1L) {
	    if(length(namesi) == 0L) namesi <- seq_len(ncols[i])
	    vnames[[i]] <- if(no.vn[i]) namesi
			   else paste(vnames[[i]], namesi, sep=".")
	} else if(length(namesi)) {
	    vnames[[i]] <- namesi
	} else if (fix.empty.names && no.vn[[i]]) {
	    tmpname <- deparse(object[[i]], nlines = 1L)[1L]
	    if(startsWith(tmpname, "I(") && endsWith(tmpname, ")")) {
                ## from 'I(*)', only keep '*':
		ntmpn <- nchar(tmpname, "c")
                tmpname <- substr(tmpname, 3L, ntmpn - 1L)
	    }
	    vnames[[i]] <- tmpname
	} ## else vnames[[i]] are not changed
	if(mirn && nrows[i] > 0L) {
            rowsi <- attr(xi, "row.names")
            ## Avoid all-blank names
            if(any(nzchar(rowsi)))
                row.names <- data.row.names(row.names, rowsi, i)
        }
        nrows[i] <- abs(nrows[i])
	vlist[[i]] <- xi
    }
    nr <- max(nrows)
    for(i in seq_len(n)[nrows < nr]) {
	xi <- vlist[[i]]
	if(nrows[i] > 0L && (nr %% nrows[i] == 0L)) {
            ## make some attempt to recycle column i
            xi <- unclass(xi) # avoid data-frame methods
            fixed <- TRUE
            for(j in seq_along(xi)) {
                xi1 <- xi[[j]]
                if(is.vector(xi1) || is.factor(xi1))
                    xi[[j]] <- rep(xi1, length.out = nr)
		else if(is.character(xi1) && inherits(xi1, "AsIs"))
                    xi[[j]] <- structure(rep(xi1, length.out = nr),
                                         class = class(xi1))
                else if(inherits(xi1, "Date") || inherits(xi1, "POSIXct"))
                    xi[[j]] <- rep(xi1, length.out = nr)
                else {
                    fixed <- FALSE
                    break
                }
            }
            if (fixed) {
                vlist[[i]] <- xi
                next
            }
        }
        stop(gettextf("arguments imply differing number of rows: %s",
                      paste(unique(nrows), collapse = ", ")),
             domain = NA)
    }
    value <- unlist(vlist, recursive=FALSE, use.names=FALSE)
    ## unlist() drops i-th component if it has 0 columns
    vnames <- as.character(unlist(vnames[ncols > 0L]))
    if(fix.empty.names && any(noname <- !nzchar(vnames)))
	vnames[noname] <- paste0("Var.", seq_along(vnames))[noname]
    if(check.names) {
	if(fix.empty.names)
	    vnames <- make.names(vnames, unique=TRUE)
	else { ## do not fix ""
	    nz <- nzchar(vnames)
	    vnames[nz] <- make.names(vnames[nz], unique=TRUE)
	}
    }
    names(value) <- vnames
    if(!mrn) { # non-null row.names arg was supplied
        if(length(row.names) == 1L && nr != 1L) {  # one of the variables
            if(is.character(row.names))
                row.names <- match(row.names, vnames, 0L)
            if(length(row.names) != 1L ||
               row.names < 1L || row.names > length(vnames))
                stop("'row.names' should specify one of the variables")
            i <- row.names
            row.names <- value[[i]]
            value <- value[ - i]
        } else if ( !is.null(row.names) && length(row.names) != nr )
            stop("row names supplied are of the wrong length")
    } else if( !is.null(row.names) && length(row.names) != nr ) {
        warning("row names were found from a short variable and have been discarded")
        row.names <- NULL
    }
    class(value) <- "data.frame"
    if(is.null(row.names))
        attr(value, "row.names") <- .set_row_names(nr) #seq_len(nr)
    else {
        if(is.object(row.names) || !is.integer(row.names))
            row.names <- as.character(row.names)
        if(anyNA(row.names))
            stop("row names contain missing values")
        if(anyDuplicated(row.names))
            stop(gettextf("duplicate row.names: %s",
                          paste(unique(row.names[duplicated(row.names)]),
                                collapse = ", ")),
                 domain = NA)
        row.names(value) <- row.names
    }
    value
}

.dibble_base_rbind <- function(..., deparse.level = 1, make.row.names = TRUE,
                             stringsAsFactors = FALSE,
                             factor.exclude = TRUE)
{
    match.names <- function(clabs, nmi)
    {
	if(identical(clabs, nmi)) NULL
	else if(length(nmi) == length(clabs) && all(nmi %in% clabs)) {
            ## we need 1-1 matches here
	    m <- pmatch(nmi, clabs, 0L)
            if(any(m == 0L))
                stop("names do not match previous names")
            m
	} else stop("names do not match previous names")
    }
    allargs <- list(...)
    allargs <- allargs[lengths(allargs) > 0L]
    if(length(allargs)) {
        ## drop any zero-row data frames, as they may not have proper column
        ## types (e.g. NULL).
        nr <- vapply(allargs, function(x)
                     if(is.data.frame(x)) .row_names_info(x, 2L)
                     else if(is.list(x)) length(x[[1L]])
					# mismatched lists are checked later
                     else length(x), 1L)
	if(any(n0 <- nr == 0L)) {
	    if(all(n0)) return(allargs[[1L]]) # pretty arbitrary
	    allargs <- allargs[!n0]
	}
    }
    n <- length(allargs)
    if(n == 0L)
	return(list2DF())
    nms <- names(allargs)
    if(is.null(nms))
	nms <- character(n)
    cl <- NULL
    perm <- rows <- vector("list", n)
    if(make.row.names) {
	rlabs <- rows
	autoRnms <- TRUE # result with 1:nrow(.) row names? [efficiency!]
	Make.row.names <- function(nmi, ri, ni, nrow)
	{
	    if(nzchar(nmi)) {
		if(autoRnms) autoRnms <<- FALSE
		if(ni == 0L) character()  # PR#8506
		else if(ni > 1L) paste(nmi, ri, sep = ".")
		else nmi
	    }
	    else if(autoRnms && nrow > 0L && identical(ri, seq_len(ni)))
		as.integer(seq.int(from = nrow + 1L, length.out = ni))
	    else {
		if(autoRnms && (nrow > 0L || !identical(ri, seq_len(ni))))
		    autoRnms <<- FALSE
		ri
	    }
	}
    }
    smartX <- isTRUE(factor.exclude)

    ## check the arguments, develop row and column labels
    nrow <- 0L
    value <- clabs <- NULL
    all.levs <- list()
    for(i in seq_len(n)) { ## check and treat arg [[ i ]]  -- part 1
	xi <- allargs[[i]]
	nmi <- nms[i]
        ## coerce matrix to data frame
        if(is.matrix(xi)) allargs[[i]] <- xi <-
            as.data.frame(xi, stringsAsFactors = stringsAsFactors)
	if(inherits(xi, "data.frame")) {
	    if(is.null(cl))
		cl <- oldClass(xi)
	    ri <- attr(xi, "row.names")
	    ni <- length(ri)
	    if(is.null(clabs)) ## first time
		clabs <- names(xi)
	    else {
                if(length(xi) != length(clabs))
                    stop("numbers of columns of arguments do not match")
		pi <- match.names(clabs, names(xi))
		if( !is.null(pi) ) perm[[i]] <- pi
	    }
	    rows[[i]] <- seq.int(from = nrow + 1L, length.out = ni)
	    if(make.row.names) rlabs[[i]] <- Make.row.names(nmi, ri, ni, nrow)
	    nrow <- nrow + ni
	    if(is.null(value)) { ## first time ==> setup once:
		value <- unclass(xi)
		nvar <- length(value)
		all.levs <- vector("list", nvar)
		has.dim <- facCol <- ordCol <- logical(nvar)
		if(smartX) NA.lev <- ordCol
		for(j in seq_len(nvar)) {
		    xj <- value[[j]]
                    facCol[j] <- fac <-
                        if(!is.null(lj <- levels(xj))) {
                            all.levs[[j]] <- lj
                            TRUE # turn categories into factors
                        } else
                            is.factor(xj)
		    if(fac) {
			ordCol[j] <- is.ordered(xj)
			if(smartX && !NA.lev[j])
			    NA.lev[j] <- anyNA(lj)
		    }
		    has.dim[j] <- length(dim(xj)) == 2L
		}
	    }
	    else for(j in seq_len(nvar)) {
                xij <- xi[[j]]
                if(is.null(pi) || is.na(jj <- pi[[j]])) jj <- j
                if(facCol[jj]) {
                    if(length(lij <- levels(xij))) {
                        all.levs[[jj]] <- unique(c(all.levs[[jj]], lij))
			if(ordCol[jj])
			    ordCol[jj] <- is.ordered(xij)
			if(smartX && !NA.lev[jj])
			    NA.lev[jj] <- anyNA(lij)
                    } else if(is.character(xij))
                        all.levs[[jj]] <- unique(c(all.levs[[jj]], xij))
                }
            }
	} ## end{data.frame}
	else if(is.list(xi)) {
	    ni <- range(lengths(xi))
	    if(ni[1L] == ni[2L])
		ni <- ni[1L]
	    else stop("invalid list argument: all variables should have the same length")
            ri <- seq_len(ni)
	    rows[[i]] <- seq.int(from = nrow + 1L, length.out = ni)
	    if(make.row.names) rlabs[[i]] <- Make.row.names(nmi, ri, ni, nrow)
	    nrow <- nrow + ni
	    if(length(nmi <- names(xi)) > 0L) {
		if(is.null(clabs))
		    clabs <- nmi
		else {
                    if(length(xi) != length(clabs))
                        stop("numbers of columns of arguments do not match")
		    pi <- match.names(clabs, nmi)
		    if( !is.null(pi) ) perm[[i]] <- pi
		}
	    }
	}
	else if(length(xi)) { # 1 new row
	    rows[[i]] <- nrow <- nrow + 1L
            if(make.row.names)
		rlabs[[i]] <- if(nzchar(nmi)) nmi else as.integer(nrow)
	}
    } # for(i .)

    nvar <- length(clabs)
    if(nvar == 0L)
	nvar <- max(lengths(allargs)) # only vector args
    if(nvar == 0L)
	return(list2DF())
    pseq <- seq_len(nvar)
    if(is.null(value)) { # this happens if there has been no data frame
	value <- list()
	value[pseq] <- list(logical(nrow)) # OK for coercion except to raw.
        all.levs <- vector("list", nvar)
	has.dim <- facCol <- ordCol <- logical(nvar)
	if(smartX) NA.lev <- ordCol
    }
    names(value) <- clabs
    for(j in pseq)
	if(length(lij <- all.levs[[j]]))
            value[[j]] <-
		factor(as.vector(value[[j]]), levels = lij,
		       exclude = if(smartX) {
				     if(!NA.lev[j]) NA # else NULL
				 } else factor.exclude,
		       ordered = ordCol[j])

    if(any(has.dim)) { # some col's are matrices or d.frame's
        jdim <- pseq[has.dim]
        if(!all(df <- vapply(jdim, function(j) inherits(value[[j]],"data.frame"), NA))) {
            ## Ensure matrix columns can be filled in  for(i ...) below
            rmax <- max(unlist(rows))
            for(j in jdim[!df]) {
		dn <- dimnames(vj <- value[[j]])
		rn <- dn[[1L]]
		if(length(rn) > 0L) length(rn) <- rmax
		pj <- dim(vj)[2L]
		length(vj) <- rmax * pj
		value[[j]] <- array(vj, c(rmax, pj), list(rn, dn[[2L]]))
	    }
        }
    }

    for(i in seq_len(n)) { ## add arg [[i]] to result  (part 2)
	xi <- unclass(allargs[[i]])
	if(!is.list(xi))
	    if((ni <- length(xi)) != nvar) {
		if(ni && nvar %% ni != 0)
		    warning(gettextf(
		"number of columns of result, %d, is not a multiple of vector length %d of arg %d",
                                nvar, ni, i), domain = NA)
		xi <- rep_len(xi, nvar)
            }
	ri <- rows[[i]]
	pi <- perm[[i]]
	if(is.null(pi)) pi <- pseq
	for(j in pseq) {
	    jj <- pi[j]
            xij <- xi[[j]]
	    if(has.dim[jj]) {
		value[[jj]][ri,	 ] <- xij
                ## copy rownames
                if(!is.null(r <- rownames(xij)) &&
                   !(inherits(xij, "data.frame") &&
                     .row_names_info(xij) <= 0))
                    rownames(value[[jj]])[ri] <- r
	    } else {
                ## coerce factors to vectors, in case lhs is character or
                ## level set has changed
                value[[jj]][ri] <- if(is.factor(xij)) as.vector(xij) else xij
                ## copy names if any
                if(!is.null(nm <- names(xij))) names(value[[jj]])[ri] <- nm
            }
	}
    }
    rlabs <- if(make.row.names && !autoRnms) {
		 rlabs <- unlist(rlabs)
		 if(anyDuplicated(rlabs))
		     make.unique(as.character(rlabs), sep = "")
		 else
		     rlabs
	     } # else NULL
    if(is.null(cl)) {
	as.data.frame(value, row.names = rlabs, fix.empty.names = TRUE,
		      stringsAsFactors = stringsAsFactors)
    } else {
	structure(value, class = cl,
		  row.names = rlabs %||% .set_row_names(nrow))
    }
}
