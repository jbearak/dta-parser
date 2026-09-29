# Added admission attempts must not add callbacks to a replaced base .Call.
# Capture the primitive at build time. An alias invokes it in the same frame;
# an R wrapper would change the R_GetCurrentEnv() used by native admission.
.native_admission_call <- .Primitive(".Call")
# Added entry control must also avoid replaced base special forms when the
# enclosing helper is interpreted. These aliases create no extra R frame.
.native_admission_if <- .Primitive("if")
.native_admission_return <- .Primitive("return")
.native_admission_missing <- .Primitive("missing")
.native_admission_is_null <- .Primitive("is.null")
.native_admission_not <- .Primitive("!")
.native_admission_and <- .Primitive("&&")

# Keep the original compiled promises when an admission attempt has an R
# fallback. Return this capture frame before forcing any argument so callbacks
# still run in their original caller, without an added R frame on the stack.
.native_admission_branches <- function(condition, yes, no) {
    .native_admission_call(C_dtatools_capture_branch_frame)
}

.native_admission_dots_length <- .Primitive("...length")

.native_admission_subset2 <- .Primitive("[[")
.native_admission_length <- .Primitive("length")
