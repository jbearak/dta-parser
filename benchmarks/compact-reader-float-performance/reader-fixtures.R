# Run once, outside all clocks, with the qualified baseline installed library.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                    file.path(normalizePath(args[[1L]]), "dtatools")))
stopifnot(!dir.exists(args[[2L]]), dir.create(args[[2L]], recursive = TRUE))
output <- normalizePath(args[[2L]])
hash_raw <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
value_hash <- function(x) hash_raw(writeBin(as.double(x), raw(), 8L, endian = "little"))
rank_hash <- function(x) hash_raw(writeBin(as.integer(x), raw(), 4L, endian = "little"))
n <- 1000000L
integer_plain <- as.double((seq_len(n) * 13) %% 10001L - 5000L)
integer_positions <- seq.int(13L, n, by = 997L)
integer_ranks <- integer(n)
integer_ranks[integer_positions] <- 1L
integer_plain[integer_positions] <- NA_real_
float_plain <- as.double((seq_len(n) * 13) %% 10001L - 5000L) / 8
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
set.seed(29071L)
float_positions <- sample.int(n, n %/% 2L)
float_ranks <- integer(n)
float_ranks[float_positions] <- rep(1:27, length.out = length(float_positions))
for (code in 1:27) float_plain[float_ranks == code] <-
    if (code == 1L) NA_real_ else tagged_missing(letters[code - 1L])
stopifnot(value_hash(float_plain) == "b6b60ef8bb430be90e7239dd64b807cda383733b1048ca6748094e19e1003f06",
          rank_hash(float_ranks) == "6d001f63d9ce5612a17ed6ff62e0d269d6d862dde318265b90a63af3b92b0706",
          length(integer_positions) == 1003L)
fixtures <- list(dense_float = list(plain = float_plain, ranks = float_ranks, width = "float"),
                 sparse_int = list(plain = integer_plain, ranks = integer_ranks, width = "int"))
rows <- list()
for (fixture in names(fixtures)) {
    item <- fixtures[[fixture]]
    column <- if (item$width == "float") dta_float(item$plain) else dta_int(item$plain)
    stopifnot(identical(value_hash(column), value_hash(item$plain)))
    data <- dibble(x = column)
    for (format in c("dta", "arrow")) {
        path <- file.path(output, paste0(fixture, ".", format))
        if (format == "dta") save_dta(data, path)
        else save_arrow(data, path, compression = "uncompressed", threads = 1L)
        rows[[length(rows) + 1L]] <- data.frame(fixture, format, path,
            rows = n, width = item$width, input_hash = value_hash(item$plain),
            rank_hash = rank_hash(item$ranks), input_missing = sum(item$ranks > 0L),
            zero_observed = sum(!is.na(item$plain) & item$plain == 0), bytes = file.info(path)[["size"]])
    }
}
write.csv(do.call(rbind, rows), file.path(output, "fixtures.csv"), row.names = FALSE)
cat("Created four immutable reader fixture files outside clocks\n")
