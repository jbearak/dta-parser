root <- "/private/tmp/dta-direct-stage5-minimum-preflight"
stopifnot(getRversion() == "4.6.0")
stopifnot(normalizePath(R.home()) == file.path(root, "r460-clean-install/lib/R"))
if (identical(commandArgs(TRUE), "with-dplyr")) library(dplyr)
dyn.load(file.path(root, "runtime-clean-probe/images.so"))
images <- .Call("preflight_loaded_images")
rlib <- images[grepl("(^|/)libR[.]dylib$", images)]
print(images)
stopifnot(length(rlib) == 1L)
stopifnot(normalizePath(rlib) == normalizePath(file.path(R.home(), "lib/libR.dylib")))
cat("PASS: exactly one loaded libR, from the isolated clean R4.6.0: ", rlib, "\n")
