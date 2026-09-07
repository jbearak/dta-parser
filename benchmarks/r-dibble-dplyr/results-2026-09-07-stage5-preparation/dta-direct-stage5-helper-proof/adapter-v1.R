# Temporary feasibility adapter, not package code. See PROVENANCE.md.
# The method contract and expansion ordering are adapted from dplyr 1.2.1
# R/context.R, R/data-mask.R, R/across.R and R/pick.R at 95740975.
proof_adapter <- local({
  ns <- asNamespace("dplyr")
  if (!identical(as.character(utils::packageVersion("dplyr")), "1.2.1")) {
    stop("This proof supports exactly dplyr 1.2.1", call. = FALSE)
  }
  context <- get("context_env", ns)
  slots <- c("mask", "column", "across_if_fn", "across_frame")
  snapshot <- function() {
    lapply(stats::setNames(slots, slots), function(name) {
      list(present = exists(name, context, inherits = FALSE),
           value = get0(name, context, inherits = FALSE))
    })
  }
  restore <- function(old) {
    for (name in rev(slots)) {
      if (old[[name]]$present) assign(name, old[[name]]$value, context)
      else if (exists(name, context, inherits = FALSE)) rm(list = name, envir = context)
    }
  }
  run <- function(mask, action) {
    old <- snapshot()
    on.exit(restore(old), add = TRUE)
    assign("mask", mask, context)
    action()
  }
  expand <- function(quo, mask, named) {
    attr(quo, "dplyr:::data") <- list(name = quo, is_named = named, index = 1L)
    quo <- get("expand_pick", ns)(quo, mask)
    get("expand_across", ns)(quo)
  }
  column <- function(quo) {
    name <- attr(quo, "dplyr:::data")$column
    if (!is.null(name)) assign("column", name, context)
  }
  list(run = run, expand = expand, column = column, snapshot = snapshot)
})

# Evaluates exactly one expression. No result assembly, mutation verb, Stata
# typing, ownership adoption, or package S3 method is implemented here.
proof_eval <- function(data, rows, keys, by, quo, rowwise = FALSE,
                       expand = TRUE, named = TRUE) {
  state <- new.env(parent = emptyenv())
  state$id <- 0L
  state$current <- stats::setNames(vector("list", length(data)), names(data))
  state$mask <- NULL
  state$calls <- character()
  if (!length(rows)) rows <- list(integer())
  call <- function(name) state$calls <- c(state$calls, name)
  method <- function(name, fn) {
    force(name); force(fn)
    function(...) { call(name); fn(...) }
  }
  make_mask <- function(values) {
    bindings <- list2env(values, parent = emptyenv())
    mask <- rlang::new_data_mask(bindings)
    mask$.data <- rlang::as_data_pronoun(bindings)
    mask
  }
  adapter_mask <- list(
    get_current_group_size = method("get_current_group_size", function() {
      if (state$id == 0L) 0L else length(rows[[state$id]])
    }),
    get_current_group_size_mutable = method("get_current_group_size_mutable", function() {
      if (state$id == 0L) 0L else length(rows[[state$id]])
    }),
    get_current_group_id = method("get_current_group_id", function() state$id + 0L),
    get_current_group_id_mutable = method("get_current_group_id_mutable", function() state$id + 0L),
    current_key = method("current_key", function() {
      if (!nrow(keys)) keys else vctrs::vec_slice(keys, state$id)
    }),
    current_rows = method("current_rows", function() rows[[state$id]]),
    current_vars = method("current_vars", function() names(data)),
    current_non_group_vars = method("current_non_group_vars", function() setdiff(names(data), by)),
    get_current_data = method("get_current_data", function(groups = TRUE) {
      if (groups) as.list(data) else as.list(data)[setdiff(names(data), by)]
    }),
    current_cols = method("current_cols", function(vars) state$current[vars]),
    pick_current = method("pick_current", function(vars) {
      value <- state$current[vars]
      if (rowwise) {
        for (name in vars) if (is.list(data[[name]])) value[name] <- list(list(value[[name]]))
      }
      tibble::new_tibble(value, nrow = length(rows[[state$id]]))
    }),
    get_rlang_mask = method("get_rlang_mask", function() {
      # Before the first group, zero-length columns represent initial state.
      # After a group this returns that group's fresh lexical data mask.
      if (is.null(state$mask)) make_mask(lapply(data, vctrs::vec_slice, integer()))
      else state$mask
    }),
    is_grouped = method("is_grouped", function() length(by) > 0L && !rowwise),
    is_rowwise = method("is_rowwise", function() rowwise),
    get_keys = method("get_keys", function() keys),
    get_rows = method("get_rows", function() rows),
    get_size = method("get_size", function() nrow(data)),
    get_n_groups = method("get_n_groups", function() nrow(keys))
  )
  proof_adapter$run(adapter_mask, function() {
    quoes <- if (expand) proof_adapter$expand(quo, adapter_mask, named) else list(quo)
    out <- vector("list", length(quoes))
    names(out) <- names(quoes)
    for (k in seq_along(quoes)) {
      q <- quoes[[k]]
      proof_adapter$column(q)
      chunks <- vector("list", length(rows))
      for (i in seq_along(rows)) {
        state$id <- as.integer(i)
        state$current <- lapply(data, function(value) {
          if (rowwise && is.list(value) && length(rows[[i]]) == 1L) value[[rows[[i]]]]
          else vctrs::vec_slice(value, rows[[i]])
        })
        state$mask <- make_mask(state$current)
        chunks[i] <- list(rlang::eval_tidy(q, data = state$mask))
      }
      out[[k]] <- chunks
    }
    attr(out, "methods") <- unique(state$calls)
    attr(out, "expanded") <- length(quoes) != 1L ||
      !identical(rlang::quo_get_expr(quoes[[1L]]), rlang::quo_get_expr(quo))
    out
  })
}
