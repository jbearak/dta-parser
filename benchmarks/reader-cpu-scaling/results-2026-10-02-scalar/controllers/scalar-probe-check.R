root <- Sys.getenv("DTATOOLS_SCALAR_WORK")
.libPaths(c(file.path(Sys.getenv("DTATOOLS_DECODE_WORK"), "candidate-gather4-v2/library"), .libPaths()))
library(dtatools)
dyn.load(file.path(root, 'scalar_access_probe.so'))
scan <- function(x, order, selected = NULL) .Call('scalar_access_scan', x, order, selected, PACKAGE = 'scalar_access_probe')
unwrap <- function(x) .Call('scalar_access_unwrap', x, PACKAGE = 'scalar_access_probe')
orders <- c('sequential', 'reverse', 'permuted')
for (n in 0:40) for (order in orders) {
    values <- as.double(seq_len(n))
    result <- scan(values, order, rev(seq_len(n)))
    stopifnot(identical(result$checksum, sum(values)), identical(result$na_count, 0),
              identical(result$values, rev(values)))
}
values <- c(-1, 0, 1, NA_real_, tagged_missing(letters), 5)
positions <- c(seq_along(values), rev(seq_along(values)))
checks <- 0L
for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
    plain <- constructor(values)
    retained <- .Call(dtatools:::C_dtatools_owned_numeric_freeze, plain, 7)
    for (x in list(plain, retained)) {
        proxy <- .Call(dtatools:::C_dtatools_metadata_copy, x)
        leaf <- unwrap(proxy)
        stopifnot(dtatools:::.is_unmaterialized_numeric_altrep(leaf))
        for (source in list(proxy, leaf)) for (order in orders) {
            result <- scan(source, order, positions)
            stopifnot(identical(result$checksum, 5), identical(result$na_count, 27),
                      identical(result$values, values[positions]),
                      identical(missing_tag(result$values), missing_tag(values[positions])))
            checks <- checks + 1L
        }
    }
}
special <- scan(c(Inf, -Inf, NaN, NA_real_, -2, 4), 'permuted', 1:6)
stopifnot(identical(special$checksum, 2), identical(special$na_count, 2),
          identical(special$positive_infinity_count, 1), identical(special$negative_infinity_count, 1))
stopifnot(inherits(try(scan(1:3, 'sequential'), silent = TRUE), 'try-error'),
          inherits(try(scan(c(1, 2), 'unknown'), silent = TRUE), 'try-error'),
          inherits(try(scan(c(1, 2), 'sequential', NA_integer_), silent = TRUE), 'try-error'))
unknown <- as.double(seq_len(10))
stopifnot(.Call(dtatools:::C_dtatools_is_altrep, unknown),
          inherits(try(unwrap(unknown), silent = TRUE), 'try-error'))
cat('Untimed checks passed:', checks, 'typed/proxy/retained scans, length 0:40 permutation coverage, exact tagged missing extraction, infinities, invalid input, unknown ALTREP unwrap rejection.\n')
