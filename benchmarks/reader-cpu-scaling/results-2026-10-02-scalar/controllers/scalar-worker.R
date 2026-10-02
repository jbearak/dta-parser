# One fresh process per case/variant. Setup, reference traversal, GC and exact
# validation are outside the operation interval; automatic GC remains inside.
args <- commandArgs(TRUE)
stopifnot(length(args) == 8L)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
fixture <- normalizePath(args[[2L]], mustWork = TRUE)
probe <- normalizePath(args[[3L]], mustWork = TRUE)
format <- args[[4L]]
kind <- args[[5L]]
representation <- args[[6L]]
operation <- args[[7L]]
reps <- as.integer(args[[8L]])
stopifnot(format %in% c('dta', 'arrow'), kind %in% c('byte', 'int', 'long', 'float'),
          representation %in% c('proxy', 'direct', 'plain'),
          operation %in% c('mask', 'sequential', 'reverse', 'permuted'),
          !is.na(reps), reps > 0L)
.libPaths(c(library_path, .libPaths()))
library(dtatools)
stopifnot(identical(normalizePath(find.package('dtatools')), file.path(library_path, 'dtatools')))
dyn.load(probe)
native <- function(name, ...) .Call(get(name, envir = asNamespace('dtatools')), ...)
scan <- function(x, order, selected = NULL) .Call('scalar_access_scan', x, order, selected, PACKAGE = 'scalar_access_probe')
unwrap <- function(x) .Call('scalar_access_unwrap', x, PACKAGE = 'scalar_access_probe')
lazy <- get('.is_unmaterialized_numeric_altrep', asNamespace('dtatools'))
depth <- function(x) native('C_dtatools_metadata_proxy_depth', x)

# Both formats occupy the same setup state, independently of the case selected.
dta <- read_dta(file.path(fixture, 'compact.dta'), threads = 1L, output = 'tibble')
arrow <- read_arrow(file.path(fixture, 'compact.arrow'), threads = 1L, output = 'tibble', verify = TRUE)
reference <- readRDS(file.path(fixture, 'compact.rds'))
stopifnot(identical(dim(dta), dim(reference)), identical(dim(arrow), dim(reference)),
          identical(names(dta), names(reference)), identical(names(arrow), names(reference)))
column <- c(byte = 'compact_01', int = 'compact_09', long = 'compact_17', float = 'compact_25')[[kind]]
plain <- reference[[column]]
stopifnot(typeof(plain) == 'double', !native('C_dtatools_is_altrep', plain))
table <- if (format == 'dta') dta else arrow
proxy <- as.double(table[[column]])
stopifnot(typeof(proxy) == 'double', lazy(proxy), depth(proxy) == 1L)
direct <- unwrap(proxy)
stopifnot(typeof(direct) == 'double', lazy(direct), depth(direct) == 0L)
owned <- native('C_dtatools_owned_numeric_info', direct)
if (format == 'arrow') stopifnot(owned[['owned']] == 1, owned[['chunks']] > 1)
target <- switch(representation, proxy = proxy, direct = direct, plain = plain)
target_lazy <- function() if (representation == 'plain') !native('C_dtatools_is_altrep', target) else lazy(target)
rows <- length(plain)
selected <- as.double(unique(c(1L, rows, seq_len(min(32L, rows)),
    (seq_len(40L) * 997L - match(column, names(reference))),
    65535:65538, 131071:131074)))
selected <- selected[selected >= 1 & selected <= rows]
order <- if (operation == 'mask') 'sequential' else operation
# The reference uses the same traversal, preserving floating summation order.
expected_selected <- scan(plain, order, selected)
expected_stats <- expected_selected
expected_stats$values <- numeric()
expected <- if (operation == 'mask') base::is.na(plain) else expected_stats
work <- if (operation == 'mask') compiler::cmpfun(function(x) base::is.na(x)) else
    compiler::cmpfun(function(x) scan(x, order))
run_reps <- compiler::cmpfun(function(x, n) {
    result <- NULL
    for (i in seq_len(n)) result <- work(x)
    result
})
stopifnot(identical(work(target), expected))
before_lazy <- target_lazy()
stopifnot(before_lazy, lazy(proxy), lazy(direct))
gc(full = TRUE)
start <- proc.time()
result <- run_reps(target, reps)
elapsed <- proc.time() - start
after_lazy <- target_lazy()
stopifnot(after_lazy, lazy(proxy), lazy(direct))
stopifnot(identical(result, expected), identical(work(target), expected))
actual_selected <- scan(target, order, selected)
stopifnot(identical(actual_selected, expected_selected),
          identical(missing_tag(actual_selected$values), missing_tag(expected_selected$values)),
          target_lazy(), lazy(proxy), lazy(direct))
cat('SCALAR\t', paste(sprintf('%.9f', c(elapsed[['elapsed']], elapsed[['user.self']],
    elapsed[['sys.self']])), collapse = '\t'), '\t', rows, '\t', reps, '\t',
    as.integer(before_lazy), '\t', as.integer(after_lazy), '\t',
    sprintf('%.17g', expected_stats$checksum), '\t', expected_stats$na_count, '\t',
    owned[['owned']], '\t', owned[['chunks']], '\t', length(selected), '\t',
    'exact\n', sep = '')
