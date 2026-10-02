# Preloaded public-operation comparison. No measurement includes readers, explicit
# GC, references, or qualification. Automatic GC remains inside each interval.
args <- commandArgs(TRUE)
stopifnot(length(args) == 7L)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
fixture_path <- normalizePath(args[[2L]], mustWork = TRUE)
case_ids <- strsplit(args[[3L]], ',', fixed = TRUE)[[1L]]
round <- as.integer(args[[4L]])
reps <- as.integer(args[[5L]])
output <- args[[6L]]
probe <- normalizePath(args[[7L]], mustWork = TRUE)
stopifnot(round > 0L, reps > 0L)
.libPaths(c(library_path, .libPaths()))
library(dtatools)
stopifnot(identical(normalizePath(find.package('dtatools')), file.path(library_path, 'dtatools')))
dyn.load(probe)
scan <- function(x, selected) .Call('scalar_access_scan', x, 'sequential', selected, PACKAGE = 'scalar_access_probe')
unwrap <- function(x) .Call('scalar_access_unwrap', x, PACKAGE = 'scalar_access_probe')
native <- function(name, ...) .Call(get(name, envir = asNamespace('dtatools')), ...)
lazy <- get('.is_unmaterialized_numeric_altrep', asNamespace('dtatools'))
tables <- list(
  dta = read_dta(file.path(fixture_path, 'compact.dta'), threads = 1L, output = 'tibble'),
  arrow = read_arrow(file.path(fixture_path, 'compact.arrow'), threads = 1L, output = 'tibble', verify = TRUE)
)
reference <- readRDS(file.path(fixture_path, 'compact.rds'))
stopifnot(all(vapply(tables, function(x) identical(dim(x), dim(reference)), logical(1))),
          all(vapply(tables, function(x) identical(names(x), names(reference)), logical(1))))
columns <- c(byte = 1L, int = 9L, long = 17L, float = 25L)
operations <- list(
  is_na = compiler::cmpfun(function(x) base::is.na(x)),
  is_missing = compiler::cmpfun(function(x) dtatools::is_missing(x)),
  multi4 = compiler::cmpfun(function(x) dtatools::is_missing(x[[1L]], x[[2L]], x[[3L]], x[[4L]])),
  sum = compiler::cmpfun(function(x) base::sum(x, na.rm = TRUE)),
  min = compiler::cmpfun(function(x) base::min(x, na.rm = TRUE)),
  max = compiler::cmpfun(function(x) base::max(x, na.rm = TRUE))
)
repeat_work <- compiler::cmpfun(function(x, work, count) {
  result <- NULL
  for (i in seq_len(count)) result <- work(x)
  result
})
records <- list()
for (case_index in seq_along(case_ids)) {
  case <- case_ids[[case_index]]
  fields <- strsplit(case, '-', fixed = TRUE)[[1L]]
  stopifnot(length(fields) == 3L)
  format <- fields[[1L]]; kind <- fields[[2L]]; operation <- fields[[3L]]
  stopifnot(format %in% names(tables), operation %in% names(operations),
            kind %in% c(names(columns), 'mixed'), (kind == 'mixed') == (operation == 'multi4'))
  selected_columns <- if (kind == 'mixed') unname(columns) else unname(columns[[kind]])
  compact_columns <- lapply(selected_columns, function(i) tables[[format]][[i]])
  plain_columns <- lapply(selected_columns, function(i) reference[[i]])
  check_state <- function() all(vapply(compact_columns, lazy, logical(1))) &&
    all(vapply(plain_columns, function(x) typeof(x) == 'double' && !native('C_dtatools_is_altrep', x), logical(1)))
  stopifnot(check_state())
  for (i in seq_along(selected_columns)) {
    typed <- compact_columns[[i]]; plain <- plain_columns[[i]]
    expected_kind <- names(columns)[match(selected_columns[[i]], columns)]
    stopifnot(identical(dta_storage_type(typed), expected_kind))
    proxy <- as.double(typed)
    leaf <- unwrap(proxy)
    owned <- native('C_dtatools_owned_numeric_info', leaf)
    if (format == 'arrow') stopifnot(owned[['owned']] == 1, owned[['chunks']] > 1)
    selected <- as.double(unique(c(1:32, 997, 65535:65538, 131071:131074, length(plain))))
    selected <- selected[selected <= length(plain)]
    actual <- scan(proxy, selected)
    expected_scan <- scan(plain, selected)
    stopifnot(identical(actual, expected_scan),
              identical(missing_tag(actual$values), missing_tag(expected_scan$values)), check_state(), lazy(proxy))
  }
  # Reductions intentionally use classless views to measure existing native
  # ALTREP reductions, not dta_numeric result class construction.
  compact <- if (operation == 'multi4') compact_columns else if (operation %in% c('sum', 'min', 'max'))
    as.double(compact_columns[[1L]]) else compact_columns[[1L]]
  plain <- if (operation == 'multi4') plain_columns else plain_columns[[1L]]
  work <- operations[[operation]]
  expected <- if (operation == 'multi4') Reduce(`|`, lapply(plain_columns, base::is.na)) else
    if (operation %in% c('is_na', 'is_missing')) base::is.na(plain) else work(plain)
  stopifnot(identical(work(compact), expected), identical(work(plain), expected), check_state())
  representations <- if ((round + sum(utf8ToInt(case))) %% 2L == 0L) c('compact', 'plain') else c('plain', 'compact')
  for (representation in representations) {
    value <- if (representation == 'compact') compact else plain
    before_lazy <- check_state()
    invisible(gc(full = TRUE))
    start <- proc.time()
    result <- repeat_work(value, work, reps)
    elapsed <- proc.time() - start
    after_lazy <- check_state()
    stopifnot(identical(result, expected), identical(work(value), expected), before_lazy, after_lazy)
    if (operation %in% c('sum', 'min', 'max')) stopifnot(lazy(compact))
    records[[length(records) + 1L]] <- data.frame(
      case = case, round = round, representation = representation, rows = nrow(reference),
      columns = length(selected_columns), reps = reps, user = elapsed[['user.self']],
      system = elapsed[['sys.self']], cpu = elapsed[['user.self']] + elapsed[['sys.self']],
      wall = elapsed[['elapsed']], exact = TRUE, lazy_before = before_lazy, lazy_after = after_lazy,
      missing_count = if (operation %in% c('is_na', 'is_missing', 'multi4')) sum(result) else NA_real_,
      result_checksum = if (operation %in% c('sum', 'min', 'max')) result else NA_real_
    )
  }
}
write.csv(do.call(rbind, records), output, row.names = FALSE)
