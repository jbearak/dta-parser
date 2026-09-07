args <- commandArgs(TRUE)
dyn.load(args[[1L]])
latin <- rawToChar(as.raw(c(0xe9, 0xf1)))
Encoding(latin) <- "latin1"
native <- "éñ"
Encoding(native) <- "unknown"
bytes <- latin
Encoding(bytes) <- "bytes"
fixtures <- list(ascii = rep("abc", 1000L), utf8 = rep(enc2utf8(latin), 1000L),
                 latin1 = rep(latin, 1000L), native = rep(native, 1000L), bytes = rep(bytes, 1000L))
for (name in names(fixtures)) {
    values <- fixtures[[name]]
    observed <- .Call("width_probe", values)
    expected <- max(nchar(enc2utf8(values), type = "bytes"))
    stopifnot(identical(observed[[3L]], expected))
    cat(name, "marker_changes", observed[[1L]], "retained_vmax", observed[[2L]], "width", observed[[3L]], "\n")
}
