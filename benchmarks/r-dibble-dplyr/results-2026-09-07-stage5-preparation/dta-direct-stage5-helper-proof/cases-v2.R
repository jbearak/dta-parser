# Temporary executable behavior proof. Source-derived cases are listed in
# PROVENANCE.md. This file does not install or modify any package.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Expected adapter and fresh output directory")
output <- args[[2L]]
if (file.exists(file.path(output, "observations.rds"))) stop("Existing R output")
library(dplyr)
ns <- asNamespace("dplyr")
function_snapshot <- function() {
  nms <- ls(ns, all.names = TRUE)
  values <- lapply(nms, get, envir = ns, inherits = FALSE)
  keep <- vapply(values, is.function, logical(1))
  stats::setNames(lapply(which(keep), function(i) {
    list(object = values[[i]], body = body(values[[i]]), formals = formals(values[[i]]),
         environment = environment(values[[i]]), locked = bindingIsLocked(nms[[i]], ns))
  }), nms[keep])
}
namespace_before <- function_snapshot()
source(args[[1L]], local = globalenv())
adapter_context_before <- proof_adapter$snapshot()
records <- list()
methods_seen <- character()
same <- function(value, expected) {
  if (!identical(value, expected)) {
    stop(paste0("Different values:\n", paste(capture.output(dput(value)), collapse = "\n"),
                "\nExpected:\n", paste(capture.output(dput(expected)), collapse = "\n")), call. = FALSE)
  }
  invisible(value)
}
expect_error <- function(expr, pattern = NULL) {
  err <- tryCatch({ force(expr); NULL }, error = identity)
  if (is.null(err)) stop("Expected an error", call. = FALSE)
  if (!is.null(pattern) && !grepl(pattern, conditionMessage(err), fixed = TRUE)) {
    stop(paste("Unexpected error:", conditionMessage(err)), call. = FALSE)
  }
  conditionMessage(err)
}
case <- function(name, action) {
  warnings <- character()
  context_before <- proof_adapter$snapshot()
  value <- tryCatch(withCallingHandlers(action(), warning = function(cnd) {
    warnings <<- c(warnings, conditionMessage(cnd)); invokeRestart("muffleWarning")
  }), error = identity, interrupt = identity)
  context_after <- proof_adapter$snapshot()
  restored <- identical(lapply(context_before, `[[`, "value"), lapply(context_after, `[[`, "value"))
  success <- !inherits(value, "condition") && restored
  records[[name]] <<- list(pass = success, context_restored = restored,
                           binding_presence_before = lapply(context_before, `[[`, "present"),
                           binding_presence_after = lapply(context_after, `[[`, "present"),
                           warnings = warnings, value = if (inherits(value, "condition"))
                             list(class = class(value), message = conditionMessage(value)) else value)
  cat(if (success) "PASS" else "FAIL", name, "\n")
  if (!success) print(records[[name]])
  invisible(value)
}
df <- tibble(g = c("a", "a", "b"), x = 1:3, y = 4:6)
grouped <- group_by(df, g)
config <- list(data = df, rows = list(1:2, 3L), keys = tibble(g = c("a", "b")),
               by = "g", rowwise = FALSE, grouped = grouped)
own <- function(quo, cfg = config, expand = TRUE, named = TRUE) {
  before <- proof_adapter$snapshot()
  on.exit(same(proof_adapter$snapshot(), before), add = TRUE)
  out <- proof_eval(cfg$data, cfg$rows, cfg$keys, cfg$by, quo,
                    rowwise = cfg$rowwise, expand = expand, named = named)
  methods_seen <<- union(methods_seen, attr(out, "methods"))
  out
}
reference_chunks <- function(quo, cfg = config) {
  chunks <- list()
  collect <- function(value) {
    force(value)
    chunks[length(chunks) + 1L] <<- list(value)
    1L
  }
  # This is the independent real-dplyr reference, never the owned evaluator.
  dplyr::mutate(cfg$grouped, .proof = collect(!!quo))
  chunks
}
parity <- function(quo, cfg = config, expand = TRUE) {
  actual <- own(quo, cfg, expand = expand)[[1L]]
  expected <- reference_chunks(quo, cfg)
  same(actual, expected)
  actual
}
case("plain rlang mask lacks qualified helper context", function() {
  expect_error(rlang::eval_tidy(rlang::quo(dplyr::n()), data = df), "Must only be used")
})
case("qualified and arbitrary helper context", function() {
  n_alias <- dplyr::n
  group_alias <- dplyr::cur_group
  arbitrary <- function() list(n = n_alias(), id = dplyr::cur_group_id(),
                               key = group_alias(), rows = dplyr::cur_group_rows())
  out <- parity(rlang::quo(arbitrary()))
  same(lapply(out, `[[`, "n"), list(2L, 1L))
  same(lapply(out, `[[`, "id"), list(1L, 2L))
  out
})
case("data and environment pronouns with lexical aliases", function() {
  x <- 100L
  parity(rlang::quo(.data$x + .env$x + dplyr::n()))
})
case("arbitrary helper-created selection quosure", function() {
  wrapper <- function(cols) dplyr::pick({{ cols }})
  parity(rlang::quo(wrapper(x:y)))
})
case("pick fallback and expansion have deliberately different selections", function() {
  d <- tibble(g = c(1, 1, 2, 2), x = c(0, 0, 1, 1), y = c(1, 1, 0, 0))
  cfg <- list(data = d, rows = list(1:2, 3:4), keys = tibble(g = 1:2), by = "g",
              rowwise = FALSE, grouped = group_by(d, g))
  wrapper <- dplyr::pick
  expanded <- parity(rlang::quo(dplyr::pick(where(~ all(.x == 0)))), cfg)
  fallback <- parity(rlang::quo(wrapper(where(~ all(.x == 0)))), cfg)
  same(lapply(expanded, names), list(character(), character()))
  same(lapply(fallback, names), list("x", "y"))
  list(expanded = expanded, fallback = fallback)
})
case("pick uses caller selection environment across lexical mask assignments", function() {
  choice <- "y"
  wrapper <- dplyr::pick
  direct <- parity(rlang::quo({ choice <- "x"; dplyr::pick(all_of(choice)) }))
  alias <- parity(rlang::quo({ choice <- "x"; wrapper(all_of(choice)) }))
  same(lapply(direct, names), list("y", "y"))
  same(lapply(alias, names), list("y", "y"))
  list(direct = direct, alias = alias)
})
case("pick empty selection has one row before recycling", function() {
  out <- parity(rlang::quo(dplyr::pick(all_of(character()))))
  same(lapply(out, nrow), list(1L, 1L))
  out
})
case("public across alias and nested cur_column helper", function() {
  alias <- dplyr::across
  column_helper <- function() dplyr::cur_column()
  parity(rlang::quo(alias(x:y, ~ paste(column_helper(), .x, dplyr::n()))))
})
case("if_any if_all and c_across use adapter methods", function() {
  wrapper <- function() list(any = dplyr::if_any(x:y, ~ .x > 3),
                             all = dplyr::if_all(x:y, ~ .x > 0),
                             values = dplyr::c_across(x:y))
  parity(rlang::quo(wrapper()))
})
case("unnamed across expansion preserves column-major group order", function() {
  events <- character()
  mark <- function(value) {
    events <<- c(events, paste(dplyr::cur_column(), dplyr::cur_group_id(), sep = ":"))
    value + dplyr::n()
  }
  quo <- rlang::quo(dplyr::across(x:y, mark))
  actual <- own(quo, named = FALSE)
  actual_events <- events
  events <- character()
  expected <- dplyr::mutate(grouped, !!quo)
  same(actual_events, events)
  same(events, c("x:1", "x:2", "y:1", "y:2"))
  same(actual$x, list(expected$x[1:2], expected$x[3L]))
  same(actual$y, list(expected$y[1:2], expected$y[3L]))
  same(attr(actual, "expanded"), TRUE)
  list(events = events, columns = actual)
})
case("runtime across alias preserves group-major column order", function() {
  events <- character()
  alias <- dplyr::across
  mark <- function(value) {
    events <<- c(events, paste(dplyr::cur_column(), dplyr::cur_group_id(), sep = ":"))
    value
  }
  quo <- rlang::quo(alias(x:y, mark))
  actual <- own(quo, named = FALSE)
  actual_events <- events
  events <- character()
  expected <- dplyr::mutate(grouped, !!quo)
  same(actual_events, events)
  same(events, c("x:1", "y:1", "x:2", "y:2"))
  same(attr(actual, "expanded"), FALSE)
  list(events = events, columns = actual)
})
case("across function setup runs once for expansion and once per group for alias", function() {
  setup <- 0L
  make_fn <- function() { setup <<- setup + 1L; function(value) value }
  quo <- rlang::quo(dplyr::across(x:y, make_fn()))
  own(quo, named = FALSE)
  expanded <- setup
  setup <- 0L
  dplyr::mutate(grouped, !!quo)
  cat("SETUP_EXPANDED", expanded, "REFERENCE", setup, "\n")
  same(expanded, setup)
  same(expanded, 1L)
  setup <- 0L
  alias <- dplyr::across
  quo <- rlang::quo(alias(x:y, make_fn()))
  own(quo, named = FALSE)
  fallback <- setup
  setup <- 0L
  dplyr::mutate(grouped, !!quo)
  cat("SETUP_FALLBACK", fallback, "REFERENCE", setup, "\n")
  same(fallback, setup)
  same(fallback, 2L)
  list(expansion = expanded, fallback = fallback)
})
case("across dots evaluate once per group and prevent expansion", function() {
  dots <- 0L
  increment <- function() { dots <<- dots + 1L; 10L }
  fn <- function(value, amount) value + amount
  quo <- rlang::quo(dplyr::across(x:y, fn, amount = increment()))
  actual <- own(quo, named = FALSE)
  count <- dots
  dots <- 0L
  dplyr::mutate(grouped, !!quo)
  same(count, dots)
  same(count, 2L)
  same(attr(actual, "expanded"), FALSE)
  list(count = count, result = actual)
})
case("across unpack prevents expansion and keeps helper context", function() {
  quo <- rlang::quo(dplyr::across(x:y, ~ tibble(value = .x, size = dplyr::n()), .unpack = TRUE))
  actual <- own(quo, named = FALSE)
  expected <- dplyr::mutate(grouped, !!quo)
  same(names(actual[[1L]][[1L]]), c("x_value", "x_size", "y_value", "y_size"))
  same(actual[[1L]][[1L]]$x_size, expected$x_size[1:2])
  same(attr(actual, "expanded"), FALSE)
  actual
})
case("rowwise list extraction and pick preservation match real helper paths", function() {
  d <- tibble(id = 1:2, x = list(1:2, 3:5), y = 4:5)
  cfg <- list(data = d, rows = list(1L, 2L), keys = tibble(id = 1:2), by = "id",
              rowwise = TRUE, grouped = rowwise(d, id))
  expression <- rlang::quo(list(value = x, length = length(x), size = dplyr::n(),
                                rows = dplyr::cur_group_rows(), key = dplyr::cur_group(),
                                picked = dplyr::pick(x), legacy = dplyr::across(x)))
  parity(expression, cfg)
})
case("empty groups execute and expose zero size", function() {
  d <- tibble(g = factor("a", levels = c("a", "b")), x = 1L)
  cfg <- list(data = d, rows = list(1L, integer()),
              keys = tibble(g = factor(c("a", "b"), levels = c("a", "b"))),
              by = "g", rowwise = FALSE, grouped = group_by(d, g, .drop = FALSE))
  out <- parity(rlang::quo(list(size = dplyr::n(), id = dplyr::cur_group_id(),
                               rows = dplyr::cur_group_rows(), key = dplyr::cur_group(), x = x)), cfg)
  same(lapply(out, `[[`, "size"), list(1L, 0L))
  out
})
case("zero grouped rows still execute once", function() {
  d <- tibble(g = character(), x = integer())
  cfg <- list(data = d, rows = list(), keys = tibble(g = character()), by = "g",
              rowwise = FALSE, grouped = group_by(d, g))
  out <- parity(rlang::quo(list(size = dplyr::n(), id = dplyr::cur_group_id(),
                               rows = dplyr::cur_group_rows(), key = dplyr::cur_group())), cfg)
  same(length(out), 1L)
  same(out[[1L]]$size, 0L)
  out
})
case("ungrouped empty and nonempty contexts", function() {
  observed <- list()
  for (d in list(df, df[integer(), ])) {
    cfg <- list(data = d, rows = list(seq_len(nrow(d))), keys = tibble(.rows = 1L),
                by = character(), rowwise = FALSE, grouped = d)
    observed[[length(observed) + 1L]] <- parity(rlang::quo(list(size = dplyr::n(),
      id = dplyr::cur_group_id(), key = dplyr::cur_group(), rows = dplyr::cur_group_rows())), cfg)
  }
  observed
})
case("nested real dplyr inside owned evaluation restores group and column", function() {
  helper <- function(value) {
    before <- list(n = dplyr::n(), id = dplyr::cur_group_id(), column = dplyr::cur_column())
    inner <- dplyr::mutate(group_by(tibble(g = c(1, 2, 2), z = 1:3), g),
                            z = dplyr::n() + dplyr::cur_group_id())
    after <- list(n = dplyr::n(), id = dplyr::cur_group_id(), column = dplyr::cur_column())
    same(before, after)
    value
  }
  parity(rlang::quo(dplyr::across(x:y, helper)))
})
case("owned evaluation nested inside real dplyr restores outer state", function() {
  witness <- function(value) {
    before <- list(n = dplyr::n(), id = dplyr::cur_group_id(), column = dplyr::cur_column())
    inner <- own(rlang::quo(list(n = dplyr::n(), id = dplyr::cur_group_id())))
    same(inner[[1L]], list(list(n = 2L, id = 1L), list(n = 1L, id = 2L)))
    after <- list(n = dplyr::n(), id = dplyr::cur_group_id(), column = dplyr::cur_column())
    same(before, after)
    value
  }
  dplyr::mutate(grouped, across(x:y, witness))
})
case("nested owned evaluation maintains independent scalar state", function() {
  parity(rlang::quo({
    n_before <- dplyr::n()
    id_before <- dplyr::cur_group_id()
    inner <- own(rlang::quo(dplyr::n()))
    same(n_before, dplyr::n())
    same(id_before, dplyr::cur_group_id())
    list(n = n_before, id = id_before, inner = inner[[1L]])
  }))
})
case("errors and warnings restore nested real-dplyr context", function() {
  witness <- function(value) {
    before <- proof_adapter$snapshot()
    own_error <- expect_error(own(rlang::quo(dplyr::across(x, ~ stop("owned failure")))))
    same(proof_adapter$snapshot(), before)
    same(dplyr::cur_column(), "x")
    expect_error(own(rlang::quo({
      expect_error(dplyr::mutate(df, z = stop("nested dplyr failure")))
      warning("owned warning")
      stop("after warning")
    })), "after warning")
    same(proof_adapter$snapshot(), before)
    value
  }
  dplyr::mutate(grouped, across(x, witness))
})
case("R interrupt condition unwinds adapter context", function() {
  before <- proof_adapter$snapshot()
  condition <- structure(list(message = "controlled proof interrupt", call = NULL),
                         class = c("interrupt", "condition"))
  caught <- tryCatch(own(rlang::quo(stop(condition))), interrupt = identity)
  same(inherits(caught, "interrupt"), TRUE)
  same(before, proof_adapter$snapshot())
  list(class = class(caught), message = conditionMessage(caught))
})
case("saved group scalars keys and rows survive later groups", function() {
  out <- own(rlang::quo(list(n = dplyr::n(), id = dplyr::cur_group_id(),
                            key = dplyr::cur_group(), rows = dplyr::cur_group_rows())))[[1L]]
  own(rlang::quo(dplyr::across(x:y, ~ .x + dplyr::cur_group_id())), named = FALSE)
  same(lapply(out, `[[`, "n"), list(2L, 1L))
  same(lapply(out, `[[`, "id"), list(1L, 2L))
  same(lapply(out, `[[`, "rows"), list(1:2, 3L))
  out
})
case("captured lexical masks stay group-specific and retain columns", function() {
  out <- own(rlang::quo(list(column = x, closure = function() x,
                            pronoun = .data, quosure = rlang::quo(x))))[[1L]]
  own(rlang::quo({ x <- 99L; x }))
  same(lapply(out, `[[`, "column"), list(1:2, 3L))
  same(lapply(out, function(value) value$closure()), list(1:2, 3L))
  same(lapply(out, function(value) value$pronoun$x), list(1:2, 3L))
  same(lapply(out, function(value) rlang::eval_tidy(value$quosure)), list(1:2, 3L))
  list(retained_values = lapply(out, `[[`, "column"),
       limit = "Ordinary R slices only. No native writes or foreign storage adoption proved.")
})
case("upstream late captures are invalidated but prototype snapshots remain readable", function() {
  captured <- dplyr::mutate(grouped, closure = list(function() x))$closure
  upstream_error <- expect_error(captured[[1L]](), "Obsolete data mask")
  owned <- own(rlang::quo(function() x))[[1L]]
  same(lapply(owned, function(fn) fn()), list(1:2, 3L))
  list(upstream_error = upstream_error,
       decision = "Prototype deliberately snapshots per group. Production capture policy remains to be reviewed.")
})
case("lexical side effects do not contaminate the next group", function() {
  parity(rlang::quo({
    before <- x
    x <- 99L
    list(before = before, local = x, underlying = .data$x)
  }))
})
case("helper context is unavailable after evaluation", function() {
  list(n = expect_error(dplyr::n(), "Must only be used"),
       column = expect_error(dplyr::cur_column(), "Must only be used"))
})
namespace_after <- function_snapshot()
case("all namespace function objects bodies formals environments and locks unchanged", function() {
  same(namespace_after, namespace_before)
  list(functions = length(namespace_before),
       locked = sum(vapply(namespace_before, `[[`, logical(1), "locked")))
})
case("managed context values restored and real-dplyr binding presence recorded", function() {
  same(lapply(proof_adapter$snapshot(), `[[`, "value"),
       lapply(adapter_context_before, `[[`, "value"))
  TRUE
})
runtime <- list(R = R.version, libPaths = .libPaths(), session = sessionInfo(),
                namespaces = lapply(loadedNamespaces(), function(name) list(name = name,
                  path = if (name == "base") R.home("library/base") else getNamespaceInfo(asNamespace(name), "path"))),
                dlls = lapply(getLoadedDLLs(), function(dll) dll[["path"]]),
                dplyr_path = find.package("dplyr"), dplyr_version = as.character(packageVersion("dplyr")))
saveRDS(list(records = records, methods = sort(methods_seen), runtime = runtime),
        file.path(output, "observations.rds"), version = 3)
dput(list(records = records, methods = sort(methods_seen), runtime = runtime),
     file = file.path(output, "observations.txt"))
failed <- names(records)[!vapply(records, `[[`, logical(1), "pass")]
cat("TOTAL", length(records), "FAILED", length(failed), "\n")
if (length(failed)) stop(paste("Failed cases:", paste(failed, collapse = "; ")), call. = FALSE)
