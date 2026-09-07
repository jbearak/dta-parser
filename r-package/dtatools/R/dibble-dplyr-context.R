# Optional, version-specific helper context adapter. The method contract and
# expansion ordering adapt dplyr 1.2.1 at 95740975. See installed NOTICE.
# The package evaluator runs independently when the namespace is absent.
.dibble_dplyr_context <- function() {
    describe <- function(quo, name, index) {
        list(quo = quo, name = if (nzchar(name)) name else .mask_expression_label(quo),
             named = nzchar(name), column = NULL)
    }
    if (!"dplyr" %in% loadedNamespaces()) {
        return(list(run = function(mask, action) action(),
            expand = function(quo, mask, name, index) list(describe(quo, name, index)),
            column = function(name) invisible(NULL), reset_column = function() invisible(NULL),
            warnings = function(records, call) {
                first <- records[[1L]]
                rlang::warn(c(paste0("There were ", length(records), " warnings."),
                    i = paste0("In argument: `", .dibble_expression_label(
                        rlang::new_quosure(first$expr), first$name), "`.")),
                    parent = first$cnd, call = call)
            }))
    }
    namespace <- asNamespace("dplyr")
    if (getNamespaceVersion(namespace) < "1.2.1") {
        rlang::abort("Dibble helper integration requires dplyr 1.2.1 or newer.")
    }
    context <- get("context_env", namespace)
    slots <- c("mask", "column", "across_if_fn", "across_frame")
    old <- NULL
    run <- function(mask, action) {
        old <<- lapply(stats::setNames(slots, slots), function(name) {
            list(present = exists(name, context, inherits = FALSE),
                 value = get0(name, context, inherits = FALSE))
        })
        on.exit({
            for (name in rev(slots)) {
                if (old[[name]]$present) assign(name, old[[name]]$value, context)
                else if (exists(name, context, inherits = FALSE)) rm(list = name, envir = context)
            }
        }, add = TRUE)
        assign("mask", mask, context)
        action()
    }
    expand <- function(quo, mask, name, index) {
        attr(quo, "dplyr:::data") <- list(name = if (nzchar(name)) name else quo,
                                         is_named = nzchar(name), index = index)
        quo <- get("expand_pick", namespace)(quo, mask)
        result <- get("expand_across", namespace)(quo)
        lapply(result, function(q) {
            data <- attr(q, "dplyr:::data")
            list(quo = q, name = if (data$is_named) data$name else .mask_expression_label(data$name),
                 named = data$is_named, column = data$column)
        })
    }
    list(run = run, expand = expand,
         warnings = function(records, call) {
             get("signal_warnings", namespace)(list(warnings = records), call)
         },
         reset_column = function() assign("column", old$column$value, context),
         column = function(name) {
             if (!is.null(name)) assign("column", name, context)
             invisible(NULL)
         })
}
