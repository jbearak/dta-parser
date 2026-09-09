# Regenerate the finite ordinary grouped/rowwise inputs used without dplyr.
# Usage: Rscript --vanilla scripts/prepare-dplyr-group-fixtures.R REPO OUTPUT RECEIPT INSTALLED_PACKAGE
# Run in a fresh process with the intended installed dtatools and real dplyr.
args <- commandArgs(TRUE)
stopifnot(length(args) == 4L)
repo <- normalizePath(args[[1L]], mustWork = TRUE)
output <- args[[2L]]
receipt <- args[[3L]]
installed <- normalizePath(args[[4L]], mustWork = TRUE)
stopifnot(identical(basename(installed), "dtatools"), !dir.exists(file.path(installed, "src")))
stopifnot(!file.exists(output), !file.exists(receipt))
initial_namespaces <- loadedNamespaces()
stopifnot(!any(c("dtatools", "dplyr") %in% initial_namespaces))
suppressPackageStartupMessages(library("dtatools", lib.loc = dirname(installed), character.only = TRUE))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path"),
                                mustWork = TRUE), installed))
stopifnot(requireNamespace("dplyr", quietly = TRUE),
          utils::packageVersion("dplyr") >= "1.2.1")
helper <- file.path(repo, "r-package/dtatools/tests/testthat/helper-group-fixtures.R")
source(helper, local = TRUE)

# Freeze ordinary semantic values. No consumer may infer live ownership from RDS.
freeze <- function(x) unserialize(serialize(x, NULL, version = 3L))
ordinary <- function(x) {
    result <- dtatools:::.reference_snapshot(x)
    stopifnot(!inherits(result, c("dibble", "dtatools_ref_data")),
              is.null(attr(result, ".dtatools_ref_state", exact = TRUE)))
    freeze(result)
}
typed <- function(x) ordinary(as_dibble(x))
normalized_result <- function(x) ordinary(as_dibble(x))
row_members <- function(groups) lapply(seq_along(groups$.rows), function(i) groups$.rows[[i]])
cases <- list()
add <- function(id, plain, vars = character(), drop = TRUE, rowwise = FALSE,
                groups = NULL, rows = NULL, key_indices = NULL, expected = list(),
                indices = NULL) {
    stopifnot(!id %in% names(cases), is.data.frame(plain),
              !inherits(plain, c("dibble", "dtatools_ref_data")))
    plain <- freeze(plain)
    spec <- .group_fixture_spec(plain)
    shape <- list(names = names(plain), rows = .row_names_info(plain, 2L),
        columns = lapply(seq_along(plain), function(i) {
            value <- .subset2(plain, i)
            list(type = typeof(value), attributes = attributes(value))
        }))
    if (!is.null(groups)) {
        grouped <- dplyr::new_grouped_df(plain, groups)
    } else if (rowwise) {
        grouped <- dplyr::rowwise(plain, tidyselect::all_of(vars))
    } else {
        grouped <- dplyr::grouped_df(plain, vars, drop = drop)
    }
    actual_groups <- attr(grouped, "groups", exact = TRUE)
    stopifnot(inherits(grouped, if (rowwise) "rowwise_df" else "grouped_df"),
              !inherits(grouped, c("dibble", "dtatools_ref_data")),
              identical(attr(actual_groups$.rows, "ptype", exact = TRUE), integer()))
    if (!is.null(rows)) stopifnot(identical(row_members(actual_groups), rows))
    if (rowwise) stopifnot(identical(row_members(actual_groups), as.list(seq_len(nrow(plain)))))
    if (!is.null(key_indices)) for (key in vars) {
        stopifnot(identical(.group_fixture_value(actual_groups[[key]]),
                           .group_fixture_value(vctrs::vec_slice(plain[[key]], key_indices))))
    }
    if (is.null(groups) && !rowwise) stopifnot(identical(attr(actual_groups, ".drop"), drop))
    cases[[id]] <<- list(id = id, data = ordinary(grouped), plain_spec = spec,
        shape = shape, groups = freeze(actual_groups), expected = expected,
        indices = indices, oracle = if (!is.null(groups)) "real dplyr::new_grouped_df with explicit keys/memberships"
            else if (rowwise) "real dplyr::rowwise" else "real dplyr::grouped_df",
        manual_memberships_checked = !is.null(rows) || rowwise,
        manual_key_indices_checked = key_indices)
    invisible(id)
}
simple <- function(id, data, key, rows, key_indices, drop = TRUE,
                   rowwise_variants = FALSE, typed_variants = TRUE) {
    add(id, data, key, drop, rows = rows, key_indices = key_indices)
    if (typed_variants) add(paste0(id, "_typed"), typed(data), key, drop,
                           rows = rows, key_indices = key_indices)
    if (rowwise_variants) {
        add(paste0(id, "_rowwise"), data, key, rowwise = TRUE)
        add(paste0(id, "_typed_rowwise"), typed(data), key, rowwise = TRUE)
    }
}
tbl <- tibble::tibble
simple("g_112_i", tbl(g = c(1L, 1L, 2L), x = 1:3), "g", list(1:2, 3L), c(1L, 3L), rowwise_variants = TRUE)
simple("g_112", tbl(g = c(1, 1, 2), x = 1:3), "g", list(1:2, 3L), c(1L, 3L))
simple("g_1122", tbl(g = c(1, 1, 2, 2), x = 1:4), "g", list(1:2, 3:4), c(1L, 3L))
simple("g_1122_double_x", tbl(g = c(1, 1, 2, 2), x = c(1, 2, 3, 4)), "g", list(1:2, 3:4), c(1L, 3L))
simple("g_121", tbl(g = c(1, 2, 1)), "g", list(c(1L, 3L), 2L), 1:2)
add("g_121_only", tbl(g = c(1, 2, 1)), "g", rows = list(c(1L, 3L), 2L), key_indices = 1:2)
simple("g_212_i", tbl(g = c(2L, 1L, 2L), x = 1:3), "g", list(2L, c(1L, 3L)), c(2L, 1L))
simple("id_12", tbl(id = c(1, 2), x = 1:2), "id", list(1L, 2L), 1:2)
simple("id_121", tbl(id = c(1, 2, 1), x = 1:3), "id", list(c(1L, 3L), 2L), 1:2)
simple("id_1213", tbl(id = c(1, 2, 1, 3), x = c(1, 2, 3, 4)), "id", list(c(1L, 3L), 2L, 4L), c(1L, 2L, 4L))
simple("id_112", tbl(id = c(1, 1, 2), x = 1:3), "id", list(1:2, 3L), c(1L, 3L))
simple("id_abb", tbl(id = c("a", "b", "b"), x = 1:3), "id", list(1L, 2:3), 1:2)
simple("id_112_shared", tbl(id = dta_int(c(1, 1, 2)), x = dta_int(c(1, 1, 2))),
       "id", list(1:2, 3L), c(1L, 3L), typed_variants = FALSE)
simple("group_ab", tbl(group = c("a", "b"), value = 1:2), "group", list(1L, 2L), 1:2)
simple("group_aba", tbl(group = c("a", "b", "a"), value = 1:3), "group", list(c(1L, 3L), 2L), 1:2, rowwise_variants = TRUE)
simple("identifier_123_text", tbl(identifier = 1:3, text = c("a", "", "b")), "identifier", as.list(1:3), 1:3)
simple("flag_tf", tbl(x = 1:2, flag = c(TRUE, FALSE)), "flag", list(2L, 1L), c(2L, 1L))
simple("ordinary_na_empty", tbl(g = c(NA_character_, ""), v = 1:2), "g", list(2L, 1L), c(2L, 1L), typed_variants = FALSE)
simple("ordinary_na_b", tbl(g = c(NA_character_, "b"), v = 1:2), "g", list(2L, 1L), c(2L, 1L), typed_variants = FALSE)
simple("factor_unused", tbl(f = factor(c("a", "a"), levels = c("a", "b")), x = 1:2),
       "f", list(1:2, integer()), NULL, drop = FALSE)
simple("x123", tbl(x = 1:3), "x", as.list(1:3), 1:3)
simple("string_ab", tbl(g = c("a", "b"), x = 1:2), "g", list(1L, 2L), 1:2)
simple("multi_aaba", tbl(g = c("a", "a", "b", "a"), h = c(1, 2, 1, 1)),
       c("g", "h"), list(c(1L, 4L), 2L, 3L), 1:3, typed_variants = FALSE)
simple("x12_g11", tbl(x = 1:2, g = c(1, 1)), "g", list(1:2), 1L)
simple("g12_string_ab", tbl(g = c(1L, 2L), s = c("a", "b")), "g", list(1L, 2L), 1:2)
for (n in c(0L, 2L, 3L)) add(paste0("rowwise_x", n), tbl(x = seq_len(n)), rowwise = TRUE)
add("g123_x456_rowwise_typed", typed(tbl(g = 1:3, x = 4:6)), "g", rowwise = TRUE)

for (drop in c(FALSE, TRUE)) {
    id <- paste0("g_112_i_", if (drop) "drop" else "keep")
    plain <- tbl(g = c(1L, 1L, 2L), x = 1:3)
    add(id, plain, "g", drop, rows = list(1:2, 3L), key_indices = c(1L, 3L))
    # The original test reserves an ordinary frame, then generates y = x.
    reference <- cases[[id]]$data
    # Bare integer generation has the documented long storage. Build that
    # expected column through its constructor, without invoking gen().
    reference$y <- dta_long(1:3)
    cases[[id]]$expected$generated_y_bracket_21 <- ordinary(reference[2:1, ])
}

# Explicit equality-casting and callback shells retain exactly supplied metadata.
explicit <- function(id, value, key, rows) {
    add(id, tibble::new_tibble(list(g = value), nrow = NROW(value)), "g",
        groups = tibble::new_tibble(list(g = key, .rows = do.call(vctrs::list_of,
            c(rows, list(.ptype = integer())))), nrow = NROW(key)), rows = rows)
}
explicit("character_bab", c("b", "a", "b"), c("b", "a"), list(c(1L, 3L), 2L))
explicit("character_aba", c("a", "b", "a"), c("a", "b"), list(c(1L, 3L), 2L))
explicit("character_abana", c("a", "b", "a", NA_character_), c("a", "b", NA_character_), list(c(1L, 3L), 2L, 4L))
utf8 <- enc2utf8("\u00e9")
latin1 <- iconv(utf8, from = "UTF-8", to = "latin1")
stopifnot(!is.na(latin1), identical(Encoding(latin1), "latin1"))
explicit("character_encoding",
    structure(c(latin1, "longer", utf8, NA_character_), stata.string.storage = "str1", label = "Unchanged declaration"),
    structure(c("unused", utf8, "longer", NA_character_), stata.string.storage = "str1"),
    list(integer(), c(1L, 3L), 2L, 4L))
explicit("character_empty", character(), character(), list())
for (case in c("payload", "label", "names")) {
    value <- c("a", "b", "a", NA_character_)
    key <- c("a", "b", NA_character_)
    if (case == "payload") {
        value[c(1L, 3L)] <- c(latin1, utf8); key[[1L]] <- utf8
    } else attr(value, case) <- if (case == "names") rep(latin1, 4L) else latin1
    attr(value, "stata.string.storage") <- "str8"
    explicit(paste0("character_isolation_", case), value, key, list(c(1L, 3L), 2L, 4L))
}
simple("ascii_100k_16", tbl(g = rep(sprintf("g%03d", 1:16), length.out = 100000L), x = rep(TRUE, 100000L)),
    "g", lapply(1:16, function(i) seq.int(i, 100000L, by = 16L)), 1:16)
explicit("cast_integer_double", c(1L, 2L, 1L), c(1, 2), list(c(1L, 3L), 2L))
explicit("cast_factor_character", factor(c("a", "b", "a")), c("a", "b"), list(c(1L, 3L), 2L))
explicit("cast_byte_double", dta_byte(c(1, 2, 1)), dta_double(c(1, 2)), list(c(1L, 3L), 2L))
explicit("cast_double_double", c(1, 2, 1), c(1, 2), list(c(1L, 3L), 2L))
explicit("cast_matrix", structure(matrix(c(1, 2, 1, 3, 4, 3), 3, 2), stata.storage = "double"),
    structure(matrix(c(1, 2, 3, 4), 2, 2), stata.storage = "double"), list(c(1L, 3L), 2L))

factor_inputs <- list(
    tbl(f = factor(c("b", "a", NA), levels = c("a", "b", "c")),
        g = c("z", "x", "z"), h = ordered(c("v", "u", "u"), c("u", "v", "w"))),
    tbl(f = factor(character(), levels = c("a", "b")), g = character(),
        h = factor(character(), levels = c("u", "v"))),
    tbl(f = factor(c("a", NA), levels = c("a", "b")), g = c(NA_real_, NaN), h = factor(c("u", "v"))))
key_sets <- list("f", c("f", "g"), c("g", "f"), c("f", "g", "h"), c("g", "h", "f"))
for (i in seq_along(factor_inputs)) for (j in seq_along(key_sets)) for (drop in c(FALSE, TRUE)) {
    add(paste0("factor_expand_", i, "_", j, "_", if (drop) "drop" else "keep"),
        factor_inputs[[i]], key_sets[[j]], drop)
}
key_values <- list(byte = dta_byte(c(2, 1, 2)), int = dta_int(c(2, 1, 2)),
    long = dta_long(c(2, 1, 2)), float = dta_float(c(2, 1, 2)), double = dta_double(c(2, 1, 2)),
    tags = dta_double(c(NA_real_, tagged_missing("a"), tagged_missing("b"))),
    factor = factor(c("b", "a", "b"), levels = c("a", "b", "unused")),
    date = as.Date(c("2020-01-01", "2020-01-02", "2020-01-01")),
    list = list(1:2, NULL, 1:2), frame = tbl(a = c(2, 1, 2), b = c("z", "a", "z")))
for (key in names(key_values)) for (empty in c(FALSE, TRUE)) {
    value <- key_values[[key]]
    if (empty) value <- vctrs::vec_slice(value, integer())
    add(paste0("key_", key, "_", if (empty) "empty" else "full"), tbl(g = value), "g", FALSE)
}

row_source <- typed(tbl(g = factor(c("b", "a", "b", "a"), levels = c("a", "b", "c")),
    id = c(2L, 1L, 2L, 1L), x = dta_double(c(1, 2, 3, 4))))
row_indices <- list(c(3L, 1L, 3L), -2L, c(TRUE, FALSE, TRUE, FALSE), integer())
column_indices <- list(names(row_source), c("x", "g"), "x", character())
for (kind in c("keep", "drop", "ids", "no_ids")) {
    id <- paste0("row_entry_", kind)
    add(id, row_source, if (kind == "ids") c("id", "g") else if (kind == "no_ids") character() else c("g", "id"),
        drop = kind != "keep", rowwise = kind %in% c("ids", "no_ids"),
        indices = list(rows = row_indices, columns = column_indices))
    reference <- cases[[id]]$data
    cases[[id]]$expected$bracket <- lapply(row_indices, function(rows)
        lapply(column_indices, function(cols) normalized_result(reference[rows, cols])))
    cases[[id]]$expected$slice <- lapply(row_indices, function(rows) normalized_result(
        if (inherits(reference, "rowwise_df")) dplyr::dplyr_row_slice(reference, rows) else reference[rows, ]))
}
for (typed_input in c(FALSE, TRUE)) for (rowwise in c(FALSE, TRUE)) {
    id <- paste0("xy_123_456", if (typed_input) "_typed", if (rowwise) "_rowwise")
    data <- tbl(x = 1:3, y = 4:6)
    if (typed_input) data <- typed(data)
    add(id, data, "x", rowwise = rowwise, rows = if (!rowwise) as.list(1:3))
    reference <- cases[[id]]$data
    caught <- function(expr) {
        value <- suppressWarnings(tryCatch(expr,
            error = function(error) simpleError(conditionMessage(error), call = NULL)))
        if (inherits(value, "error")) value else normalized_result(value)
    }
    cases[[id]]$expected$drop <- lapply(list(NA, integer(), TRUE, FALSE),
        function(drop) caught(reference[1, , drop = drop]))
    cases[[id]]$expected$one_dim <- lapply(alist(d[1L, drop = TRUE], d[drop = TRUE],
        d[, drop = TRUE], d[1L, drop = NA]), function(expr) caught(eval(expr, list(d = reference))))
}

# Portable complex legacy-locale graph. Ambient-locale comparisons remain in
# the present tests; native current-locale string ordering has a base R oracle.
local({
    withr::local_collate("C")
    withr::local_options(list(dplyr.legacy_locale = TRUE))
    suppressWarnings({
        data <- typed(tbl(g = c("Z", "a", "b", "A", "\u00e1", "\u00e4"), x = 1:6))
        add("legacy_C_strings", data, "g")
        cases[["legacy_C_strings"]]$expected$reversed_groups <<-
            freeze(attr(cases[["legacy_C_strings"]]$data[6:1, ], "groups"))
        add("legacy_C_nested", tbl(g = factor(c("b", "a", NA), levels = c("a", "b", "c")),
            nested = tbl(x = c("Z", "a", "A"))), c("g", "nested"), FALSE)
        add("legacy_C_prefix", tbl(n = c(NA_real_, NaN, NA_real_), s = c("a", "b", "c"),
            f = factor(rep("u", 3L), levels = c("u", "v")), x = 1:3), c("n", "s", "f"), FALSE)
        reference <- cases[["legacy_C_prefix"]]$data
        reference$marker <- reference$x
        cases[["legacy_C_prefix"]]$expected$marker_reversed_groups <<- freeze(attr(reference[3:1, ], "groups"))
    })
})
auto_path <- file.path(repo, "r-package/dtatools/inst/extdata/auto_v118.dta")
# read_dta already supplies typed columns; ordinary preserves those classes.
auto <- ordinary(read_dta(auto_path))
add("auto_foreign", auto, "foreign")
add("auto_foreign_typed", auto, "foreign")

package_record <- function(package) {
    namespace <- asNamespace(package)
    list(version = as.character(getNamespaceVersion(namespace)),
         path = normalizePath(getNamespaceInfo(namespace, "path"), mustWork = TRUE))
}
provenance <- list(R = R.version, packages = lapply(setNames(c("dtatools", "dplyr", "tibble", "vctrs"),
    c("dtatools", "dplyr", "tibble", "vctrs")), package_record),
    helper_md5 = unname(tools::md5sum(helper)), input_md5 = unname(tools::md5sum(auto_path)),
    locale = Sys.getlocale(), legacy_complex_locale = "C", libraries = .libPaths(),
    initial_namespaces = initial_namespaces,
    scope = "Synthetic ordinary semantic inputs plus this repository's auto_v118 fixture; no ownership claim")
registry <- list(schema = 1L, cases = cases,
    producer = list(R = as.character(getRversion()),
        packages = lapply(provenance$packages, function(x) x$version),
        legacy_complex_locale = "C", scope = provenance$scope))
stopifnot(length(cases) > 100L, !anyDuplicated(names(cases)))
for (entry in cases) {
    stopifnot(identical(attr(entry$data, "groups", exact = TRUE), entry$groups),
              !inherits(entry$data, c("dibble", "dtatools_ref_data")))
}
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
saveRDS(registry, output, compress = "xz", version = 3L)
stopifnot(identical(readRDS(output), registry))
provenance$cases <- names(cases)
provenance$registry_md5 <- unname(tools::md5sum(output))
provenance$namespaces <- loadedNamespaces()
provenance$dlls <- lapply(getLoadedDLLs(), function(x) x[["path"]])
provenance$session <- sessionInfo()
dput(provenance, receipt)
cat("Recorded", length(cases), "real dplyr group fixtures in", output, "\n")
