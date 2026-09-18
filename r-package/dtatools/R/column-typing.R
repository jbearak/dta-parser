# Stata column typing: the one place an R value becomes a Stata-typed
# column and a typed column widens. Two verbs, `.typed_column()` for a
# value with no prior column and `.promoted_column()` for one replacing
# a prior, and the dispatcher `.retyped_column()` that picks between
# them. Behind them: the predicates that say what is typed, what is
# untypable, and whether a string declaration holds; the container
# mapping (ADR 0021: integer to `long`, double to `double`, `Date` to a
# `float` date, `POSIXct` to a `double` datetime, character to the
# smallest `str#` or `strL`, logicals and factors unchanged, a `dta_*()`
# value keeping its storage); and the promotion ladder (CONTEXT.md,
# "Storage promotion"; ADR 0024: the narrowest storage that holds every
# value exactly, never narrowing the integers the column can hold, so
# `long` skips `float`; precision promotes; strings widen and never
# narrow). Stata's string missing rule lives in `.stata_string_text()`
# and the declaration accessor in `.declared_string_storage()`, both in
# dta-string.R. The by-reference writers reach the ladder through
# `.replacement_fits()`, `.promoted_replacement()` and
# `.wider_declared_storage()`; the whole-frame consumers, the dplyr-shaped
# verbs and the replacement operators, through `.retype_changed_columns()`
# and `.type_dibble_columns()`.

# A column a dibble holds as is: one carrying Stata storage; a factor,
# which `save_dta()` writes as a value-labelled `long`; or a bare logical.
# Stata has no boolean type, and typing a flag as `byte` would break
# `filter(data, flag)`, `which(flag)`, and `where = flag`, so logicals
# stay logical and become `byte` only when written. A `gen()` string
# carries its declaration as an attribute without the `dta_string`
# class, so the attribute is the test for strings.
.dta_typed_column <- function(column) {
    inherits(column, c("dta_numeric", "dta_temporal", "factor")) ||
        (typeof(column) == "logical" && !is.object(column)) ||
        (is.character(column) && .string_declaration_holds(column))
}

# Whether a character column's `stata.string.storage` declaration is
# valid for its values: well formed, wide enough, and with no `NA`, which
# Stata strings spell `""`. A join or `rbind()` can carry a declaration
# onto values it no longer describes, and such a column is retyped rather
# than trusted. That includes a `dta_string` vector: `full_join()` and
# `bind_rows()` pad one with `NA` while vctrs keeps its class, so the
# class is no proof. A compact dictionary string has no `NA` by
# construction and its width is read from the dictionary, so it is
# checked without being materialized.
.string_declaration_holds <- function(column) {
    declared <- .declared_string_storage(column)
    if (!.valid_string_declaration(declared)) return(FALSE)
    if (.is_unmaterialized_dictstring(column)) {
        return(.dta_string_storage_width(declared) >=
            max(1L, .dictstring_max_width(column)))
    }
    owned_fits <- .Call(C_dtatools_owned_string_fits, column,
                        .dta_string_storage_width(declared))
    if (!is.null(owned_fits)) return(owned_fits)
    if (anyNA(column)) return(FALSE)
    .dta_string_storage_width(declared) >=
        .dta_string_required_width(column)
}

.valid_string_declaration <- function(declared) {
    is.character(declared) && length(declared) == 1L &&
        !is.na(declared) && (identical(declared, "strL") || grepl(
            "^str([1-9]|[1-9][0-9]{1,2}|1[0-9]{3}|20[0-3][0-9]|204[0-5])$",
            declared
        ))
}

# A column no Stata storage can hold: raw, list, complex, a matrix, a
# classed character other than a Stata string, or a classed numeric such
# as `difftime` or `integer64` whose values are not Stata's. A dibble
# carries it unchanged, and `save_dta()` refuses it with its own message.
# `gen()` is stricter and rejects such a result, because it is the Stata
# command. A `dta_string` whose declaration no longer holds is typable:
# it is retyped from its values.
.dta_untypable_column <- function(column) {
    if (!is.null(dim(column))) return(TRUE)
    if (typeof(column) == "character") {
        return(is.object(column) && !inherits(column, "dta_string"))
    }
    if (!(typeof(column) %in% c("logical", "integer", "double"))) {
        return(TRUE)
    }
    !.generated_numeric_class_supported(column)
}

.normalize_untyped_column <- function(column, row_count, caller) {
    if (.is_unmaterialized_dictstring(column)) {
        storage <- .normalize_dta_string_storage(
            NULL, .dictstring_max_width(column)
        )
        proxy <- .metadata_copy(column)
        attr(proxy, "stata.string.storage") <- storage
        class(proxy) <- c("dta_string", "vctrs_vctr", "character")
        return(proxy)
    }
    if (is.character(column) &&
        !is.null(.declared_string_storage(column))) {
        # A stale declaration: `NA` becomes `""`, the width is redone from
        # the values, and the variable's other metadata comes along.
        text <- .stata_string_text(column)
        kept <- attributes(column)
        kept[c("names", "class", "stata.string.storage")] <- NULL
        if (length(kept)) attributes(text) <- c(attributes(text), kept)
        column <- text
    }
    .generated_column(column, NULL, row_count, caller)
}

# Types every untyped column of a data frame so that a dibble's columns
# all carry Stata storage. Typed columns are left as the same vectors, so
# compact columns from a reader stay compact.
.type_dibble_columns <- function(data, caller = "as_dibble()") {
    row_count <- nrow(data)
    column_names <- names(data)
    captured_columns <- utils::hashtab(type = "address")
    for (index in seq_along(column_names)) {
        column <- .subset2(data, index)
        typed <- .typed_column(column, row_count, caller)
        if (!identical(rlang::obj_address(typed), rlang::obj_address(column))) {
            data[[index]] <- typed
        }
        # Value normalization above keeps the existing replacement/regrouping
        # policy. Capturing identical values only changes their private handle;
        # dispatching [[<- here would trim preserved empty grouping keys.
        normalized <- .subset2(data, index)
        captured <- utils::gethash(captured_columns, normalized, nomatch = NULL)
        if (is.null(captured)) {
            captured <- .Call(C_dtatools_capture_column, normalized)
            utils::sethash(captured_columns, normalized, captured)
        }
        .Call(C_dtatools_set_data_column, data, as.integer(index), captured)
    }
    data
}

# The first verb: the Stata-typed form of one value entering a dibble
# with no prior column, from construction, a reader, a verb's new column,
# or a data mask. A typed column is returned as is, so a compact column
# from a reader stays compact. A column no Stata storage can hold passes
# through unchanged; `save_dta()` refuses it with its own message, and
# `gen()`, being the Stata command, rejects it earlier through
# `.generated_column()`. Anything else takes the container mapping of
# ADR 0021 for its values (`.normalize_untyped_column()`). `caller`
# names the entry point in errors.
.typed_column <- function(value, row_count, caller) {
    if (.dta_typed_column(value)) return(value)
    if (.is_unmaterialized_dictstring(value) ||
        !.dta_untypable_column(value)) {
        return(.normalize_untyped_column(value, row_count, caller))
    }
    value
}

# The dispatcher: a value that replaces `prior` is promoted from it, and
# a value with no prior is typed fresh. This is the one decision every
# consumer that sees whole columns makes: the dplyr-shaped verbs through
# `.retype_changed_columns()`, and the data mask as each expression's
# result enters it, so a later expression sees the Stata column the
# result will hold (ADR 0034).
.retyped_column <- function(value, prior, row_count, caller) {
    if (is.null(prior)) return(.typed_column(value, row_count, caller))
    .promoted_column(value, prior, row_count, caller)
}

# The Stata storage a column declares, numeric or string, or `NULL` when
# it declares none.
.promotion_storage_label <- function(column) {
    if (typeof(column) == "character") {
        .declared_string_storage(column)
    } else {
        .declared_dta_storage(column)
    }
}

# Stata's `replace` announces a widening as `variable x was byte now
# int`, and `repl()` translates that command, so it says the same. Only a
# real change of declared storage is reported; a column that keeps its
# storage says nothing, as Stata does.
.report_storage_promotion <- function(name, prior, promoted) {
    was <- .promotion_storage_label(prior)
    now <- .promotion_storage_label(promoted)
    if (is.null(was) || is.null(now) || identical(was, now)) {
        return(invisible(NULL))
    }
    message(sprintf("variable `%s` was %s now %s", name, was, now))
    invisible(NULL)
}

# The second verb: column `values` that replaced `prior` in a dibble. A prior column with
# declared storage keeps it when the new values fit, as Stata's `replace`
# does. When they do not, the column takes the narrowest storage that
# holds every new value exactly, without ever narrowing the integers the
# column can hold. `conformance/stata/replace-promotion.do` records what
# Stata does, and the two agree except on precision: a `float` given a
# value needing binary64 keeps `float` in Stata, which rounds it, and
# goes to `double` here, which does not. Prior variable metadata is
# restored on the result. Other
# combinations, including a change of kind between numeric and string,
# take the storage a fresh column would. `declared` names storage the
# caller has already settled on, such as a `:=` right-hand side's, and
# stands in for the prior column's.
.promoted_column <- function(values, prior, row_count, caller,
                             declared = NULL) {
    # A bare logical replacing a Stata numeric is a fitting replacement,
    # as `replace x = x > 1` is in Stata, so it keeps the column's
    # storage rather than turning the column logical.
    logical_over_numeric <- typeof(values) == "logical" &&
        !is.object(values) && inherits(prior, "dta_numeric") &&
        !inherits(prior, "dta_temporal")
    # An explicit `dta_*()` or arithmetic result already carries the
    # storage the user asked for; a column no storage holds passes through.
    if (!logical_over_numeric &&
        (.dta_typed_column(values) || .dta_untypable_column(values))) {
        return(values)
    }
    if (is.character(values) &&
        !is.null(.declared_string_storage(values))) {
        # A stale declaration is redone from the values.
        attr(values, "stata.string.storage") <- NULL
    }
    if (!.promotable_pair(values, prior)) {
        return(.typed_column(values, row_count, caller))
    }
    if (typeof(prior) == "character") {
        text <- .stata_string_text(values)
        if (is.null(declared)) declared <- .declared_string_storage(prior)
        required <- .dta_string_required_width(text)
        storage <- if (.dta_string_storage_width(declared) >= required) {
            declared
        } else {
            .normalize_dta_string_storage(NULL, required)
        }
        return(.new_dta_string(enc2utf8(text), storage, prior))
    }
    doubles <- as.double(values)
    if (is.null(declared)) declared <- .declared_dta_storage(prior)
    # Promotion only widens: the search starts at the declared storage,
    # so a `dta_float()` value beside a retained integer float cannot
    # hold goes to `double` rather than back to `long`.
    storage <- if (.dta_storage_holds(doubles, declared)) {
        declared
    } else {
        .narrowest_dta_storage(doubles, from = declared)
    }
    .restore_dta_metadata(
        .construct_dta_numeric(doubles, NULL, storage), prior, storage
    )
}

# Whether replacement `values` for the selected `rows` fit `target`'s
# declared storage. Pairs the promotion rule does not cover report `TRUE`
# so the strict replacement path handles or refuses them as before.
.replacement_fits <- function(values, target, rows, value_mode) {
    if (!.promotable_pair(values, target)) return(TRUE)
    if (typeof(target) != "character") {
        native <- .Call(C_dtatools_replacement_fits, values, rows,
                        identical(value_mode, "row"),
                        match(.declared_dta_storage(target), .dta_storage) - 1L)
        if (!is.null(native)) return(native)
    }
    # The dictionary's widest entry answers the question for a compact
    # Arrow string without populating its shared cache, which the
    # `as.character()` below would. Only a dictionary too wide for the
    # target has to look at the values themselves.
    if (typeof(target) == "character" &&
        .is_unmaterialized_dictstring(values)) {
        declared <- .declared_string_storage(target)
        if (.dta_string_storage_width(declared) >=
            max(1L, .dictstring_max_width(values))) {
            return(TRUE)
        }
    }
    if (identical(value_mode, "row") && !is.null(rows)) {
        slice_rows <- if (inherits(rows, "dta_numeric")) {
            .dta_data(rows)
        } else {
            rows
        }
        values <- vctrs::vec_slice(values, slice_rows)
    }
    if (typeof(target) == "character") {
        return(.dta_string_storage_width(.declared_string_storage(target)) >=
            .dta_string_required_width(.stata_string_text(values)))
    }
    .dta_storage_holds(
        as.double(vctrs::vec_data(values)), .declared_dta_storage(target)
    )
}

# The whole column after `values` replace the selected `rows` of
# `target`, typed by promotion from `target`'s storage, or from
# `declared` when the right-hand side settled a wider one.
.promoted_replacement <- function(values, target, rows, value_mode,
                                  row_count, declared = NULL) {
    target <- .metadata_copy(target)
    current <- if (typeof(target) == "character") {
        .stata_string_text(target)
    } else {
        as.double(.dta_snapshot(target))
    }
    replacement <- if (typeof(target) == "character") {
        .stata_string_text(values)
    } else {
        as.double(vctrs::vec_data(values))
    }
    positions <- if (is.null(rows)) {
        seq_len(row_count)
    } else if (inherits(rows, "dta_numeric")) {
        .dta_data(rows)
    } else {
        rows
    }
    current[positions] <- if (identical(value_mode, "row")) {
        replacement[positions]
    } else {
        replacement
    }
    .promoted_column(current, target, row_count, "`:=`", declared)
}

# The storage a `:=` right-hand side declares, through a `dta_*()` call
# or Stata-typed arithmetic, when it is wider than `target`'s: the value
# the user typed names the storage they want, and a column that holds
# both must be at least that wide. `NULL` when the right-hand side is
# bare, declares the target's storage or narrower, or is not of the
# target's kind, so the ordinary fit check decides.
.wider_declared_storage <- function(values, target) {
    if (!.promotable_pair(values, target)) return(NULL)
    if (typeof(target) == "character") {
        declared <- .declared_string_storage(values)
        current <- .declared_string_storage(target)
        if (is.null(declared) || !is.character(declared) ||
            length(declared) != 1L || is.na(declared)) {
            return(NULL)
        }
        wider <- .dta_string_storage_width(declared) >
            .dta_string_storage_width(current)
        return(if (wider) declared else NULL)
    }
    if (!inherits(values, "dta_numeric")) return(NULL)
    declared <- match(.declared_dta_storage(values), .dta_storage)
    current <- match(.declared_dta_storage(target), .dta_storage)
    if (is.na(declared) || is.na(current) || declared <= current) {
        return(NULL)
    }
    .dta_storage[[declared]]
}

# `prior` has declared storage of the same kind as `values`: numeric for
# numeric, string for string. Temporal and factor columns are not
# promoted; they are retyped from their new values.
.promotable_pair <- function(values, prior) {
    if (is.factor(values) || !is.null(dim(values))) return(FALSE)
    if (is.character(prior) &&
        !is.null(.declared_string_storage(prior))) {
        return(is.character(values))
    }
    if (!inherits(prior, "dta_numeric") ||
        inherits(prior, "dta_temporal")) return(FALSE)
    typeof(values) %in% c("logical", "integer", "double") &&
        (!is.object(values) || inherits(values, "dta_numeric"))
}

.dta_storage_holds <- function(doubles, storage) {
    codes <- .tab_missing_codes(doubles)
    observed <- is.na(codes)
    if (any(!is.na(codes) & codes == 256L)) return(FALSE)
    if (any(.invalid_dta_observed(doubles, observed, storage))) {
        return(FALSE)
    }
    if (!identical(storage, "float") || !any(observed)) return(TRUE)
    candidate <- doubles[observed]
    rounded <- as.double(.construct_dta_numeric(candidate, NULL, "float"))
    all(rounded == candidate)
}

.narrowest_dta_storage <- function(doubles, from = "byte") {
    start <- match(from, .dta_storage)
    if (is.na(start)) start <- 1L
    ladder <- .dta_storage[start:length(.dta_storage)]
    # `float` carries 24 bits of integer precision and `long` carries 31,
    # so `long` to `float` narrows the integers the column can hold even
    # when the values in hand happen to be float-exact, and it leaves a
    # column that silently rounds the next long-range integer written to
    # it. Stata's `replace` sends an overflowing `long` to `double` for
    # the same reason, and the arithmetic lattice in `.dta_promote()`
    # already pairs `long` with `float` as `double`. `byte` and `int` are
    # unaffected: their whole ranges are float-exact.
    if (identical(from, "long")) ladder <- setdiff(ladder, "float")
    for (storage in ladder) {
        if (.dta_storage_holds(doubles, storage)) return(storage)
    }
    "double"
}

# After an operation on a dibble's snapshot, every column that is not the
# same vector as before is typed: a new column as `gen()` would type it, a
# replaced column by promotion from its prior storage. Columns the
# operation left alone are recognized by address and untouched.
.retype_changed_columns <- function(result, before, caller) {
    result_names <- names(result)
    row_count <- nrow(result)
    for (index in seq_along(result_names)) {
        column <- .subset2(result, index)
        prior <- before[[result_names[[index]]]]
        if (!is.null(prior) &&
            identical(rlang::obj_address(prior), rlang::obj_address(column))) {
            next
        }
        typed <- .retyped_column(column, prior, row_count, caller)
        if (!identical(rlang::obj_address(typed), rlang::obj_address(column))) {
            result[[index]] <- typed
        }
    }
    result
}
