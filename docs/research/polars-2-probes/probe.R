.libPaths(c(file.path(Sys.getenv("TMPDIR"), "polars2-research/rlib"), .libPaths()))
suppressPackageStartupMessages({library(arrow); library(dplyr); library(nanoarrow); library(haven)})
cat("arrow", format(packageVersion("arrow")), " nanoarrow", format(packageVersion("nanoarrow")),
    " dplyr", format(packageVersion("dplyr")), " haven", format(packageVersion("haven")), "\n")

tag <- function(v) { t <- na_tag(v); ifelse(is.na(v) & !is.na(t), paste0(".", t), ifelse(is.nan(v), "NaN", ifelse(is.na(v), ".", format(v)))) }
show <- function(label, v) cat(sprintf("%-38s %s\n", label, paste(tag(v), collapse = " ")))

x <- c(1, tagged_na("a"), tagged_na("b"), NA, tagged_na("a"), 2, tagged_na("b"), NA)
g <- c("p", "q", "r", "s", "t", "u", "v", "w")
show("input", x)

## --- A: arrow's own conversion
a0 <- Array$create(x)
cat("A: Array$create null_count:", a0$null_count, "\n")
show("A: back to R", as.vector(a0))

## --- B: letters as non-null NaNs, `.` null (what polars would need)
na0 <- as_nanoarrow_array(x)
valid <- !is.na(x) | !is.na(na_tag(x))
vbits <- as_nanoarrow_array(valid)$buffers[[2]]
nb <- nanoarrow_array_modify(na0, list(null_count = sum(!valid), buffers = list(vbits, na0$buffers[[2]])))
b <- as_arrow_array(nb)
cat("B: null_count:", b$null_count, " is_nan:", paste(as.vector(call_function("is_nan", b)), collapse = " "), "\n")
show("B: back to R", as.vector(b))
tb <- arrow_table(x = b, g = g)
show("B: filter g != 'p'", (tb |> filter(g != "p") |> collect())$x)
show("B: arrange(desc(g))", (tb |> arrange(desc(g)) |> collect())$x)
show("B: Array$unique", as.vector(call_function("unique", b)))
vc <- as.vector(call_function("value_counts", b))
cat("B: value_counts\n"); print(data.frame(value = tag(vc$values), n = vc$counts))
gb <- tb |> group_by(x) |> summarise(n = n()) |> collect()
cat("B: group_by(x) |> summarise(n())\n"); print(data.frame(x = tag(gb$x), n = gb$n))
d <- tb |> distinct(x) |> collect()
show("B: distinct(x)", d$x)
lookup <- arrow_table(x = as_arrow_array(nanoarrow_array_modify(as_nanoarrow_array(c(tagged_na("a"), tagged_na("b"))), list(null_count = 0))), lab = c("A", "B"))
j <- tb |> left_join(lookup, by = "x") |> collect()
cat("B: left_join on x\n"); print(data.frame(x = tag(j$x), g = j$g, lab = j$lab))
cat("B: equal(x, .a) per row: ", paste(as.vector(call_function("equal", b, Scalar$create(as.vector(lookup$x)[1]))), collapse = " "), "\n")
cat("B: dplyr is.na(x):       ", paste((tb |> mutate(m = is.na(x)) |> collect())$m, collapse = " "), "\n")
cat("B: dplyr mean(x, na.rm):  ", (tb |> summarise(m = mean(x, na.rm = TRUE)) |> collect())$m, "\n")
show("B: x * 2", (tb |> mutate(y = x * 2) |> collect())$y)
pq <- tempfile(fileext = ".parquet"); write_parquet(tb, pq)
show("B: Parquet round trip", read_parquet(pq)$x)

## --- C: letters as nulls, tag bits left under the null
bits <- function(arr) { n <- nanoarrow::as_nanoarrow_array(arr); r <- as.raw(n$buffers[[2]]); off <- n$offset
  v <- readBin(r, "double", n = n$length + off, endian = "little"); v[(off + 1):(off + n$length)] }
c0 <- as_arrow_array(na0)   # all missing rows null; data buffer still holds the tagged NaNs
cat("C: null_count:", c0$null_count, "\n")
show("C: bits under nulls, as made", bits(c0))
tc <- arrow_table(x = c0, g = g)
show("C: bits after filter", bits((tc |> filter(g != "p") |> compute())$x))
show("C: bits after arrange", bits((tc |> arrange(desc(g)) |> compute())$x))
show("C: bits after take", bits(c0$Take(c(7L, 1L, 2L))))
show("C: bits after concat", bits(concat_arrays(c0, c0)))
