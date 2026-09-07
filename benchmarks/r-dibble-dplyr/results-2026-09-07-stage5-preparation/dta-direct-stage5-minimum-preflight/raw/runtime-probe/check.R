root <- "/private/tmp/dta-direct-stage5-minimum-preflight"
stopifnot(getRversion() == "4.6.0")
library(dplyr)
dyn.load(file.path(root, "runtime-probe/images.so"))
images <- .Call("preflight_loaded_images")
rlib <- images[grepl("(^|/)libR[.]dylib$", images)]
stopifnot(length(rlib) == 1L)
stopifnot(normalizePath(rlib) == normalizePath(file.path(R.home(), "lib/libR.dylib")))
stopifnot(startsWith(normalizePath(rlib), paste0(root, "/")))
cat("Exactly one loaded libR, from isolated R4.6.0:\n", rlib, "\n")
print(images)
