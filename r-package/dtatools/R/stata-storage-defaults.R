#' Stata storage for columns of a dibble
#'
#' Every numeric and string column of a [dibble] carries Stata storage, and
#' every dataset operation on a dibble returns a dibble. This page states
#' the mapping from bare R vectors to Stata storage that dtatools applies
#' wherever a column enters a dibble: `dibble()`, `as_dibble()`, the
#' readers, [dplyr::mutate()] and the other dplyr verbs, base
#' `transform()` and `within()`, and the replacement operators `$<-`,
#' `[[<-`, and `[<-`. [gen()] and a new column through `data[i, y :=
#' value]` translate Stata's `generate`, and follow it for bare doubles.
#'
#' @section The mapping:
#' \tabular{ll}{
#' R value \tab Stata storage \cr
#' `dta_*()` or `dta_string()` result \tab Its declared storage \cr
#' logical \tab Stays logical; [save_dta()] writes `byte` \cr
#' integer \tab `long` \cr
#' double \tab `double` \cr
#' `Date` \tab `float`, declared as a Stata date \cr
#' `POSIXct` \tab `double`, declared as a Stata datetime \cr
#' character \tab Smallest fitting `str1` through `str2045`, or `strL` \cr
#' factor \tab Stays a factor; [save_dta()] writes a value-labelled `long` \cr
#' }
#'
#' The mapping follows the R type: `float` cannot hold every R double, or
#' every R integer above 2^24, so `double` and `long` keep the values
#' exact. Wrap a value in [dta_float()] or another constructor to choose
#' storage. Logical columns stay logical because Stata has no boolean type
#' and R idioms on flags, such as `filter(data, flag)` and `where = flag`,
#' need a logical.
#'
#' @section Stata's generate default:
#' [gen()] and `data[i, y := value]` on a column that does not exist are
#' translations of Stata's `generate`, and a bare double result takes its
#' default: `float`, or `double` under
#' `options(dtatools.generate_type = "double")`, the equivalent of Stata's
#' `set type double`. A translated Stata line then keeps the storage the
#' original produced without restating it, and [dta_double()] is the
#' explicit `generate double`. A result that already carries storage keeps
#' it: a `dta_*()` value, or arithmetic on a typed column, which declares
#' the storage of the Stata lattice described under [dta_byte()], so
#' `gen(data, y = x * 2)` on a `double` column is `double`. The default
#' reaches a bare double: a literal, `NA_real_`, or the result of a base
#' function that drops the class. Bare integer results stay `long`, since
#' an R integer comes from R rather than from a Stata line and `float`
#' cannot hold one above 2^24. Every other entry point, including
#' [dplyr::mutate()] and the replacement operators, is an R operation on
#' the container and uses the mapping above, so the same expression can
#' take `float` through `gen()` and `double` through `mutate()`.
#'
#' Columns no Stata storage can hold, such as raw, list, `difftime`, or
#' `bit64::integer64` columns, pass through a dibble unchanged and are
#' refused by [save_dta()]. [gen()] is stricter and rejects such a result.
#'
#' A compact string from [read_arrow()] is declared with the width of its
#' dictionary and stays compact.
#'
#' @section Changing a typed column:
#' When [dplyr::mutate()], `:=`, `transform()`, `within()`, or a
#' replacement operator overwrites a column that has declared storage, the
#' column keeps that storage if every new value fits it. Otherwise it takes
#' the narrowest Stata storage that holds every new value exactly: `byte`,
#' `int`, `long`, `float`, then `double` for numbers; the smallest fitting
#' `str#` or `strL` for strings. This is promotion, not Stata's `replace`
#' ladder: Stata promotes an overflowing `long` to `float`, where integers
#' above 2^24 lose digits, and dtatools goes to `double` instead. A value
#' that already carries storage, from a `dta_*()` call or Stata-typed
#' arithmetic, keeps that storage. On a dibble the replacement operators
#' write by reference, so the promoted column is what every binding
#' holds. Row or cell assignment, as in
#' `data[1, "x"] <- 1000L`, promotes the same way, and a `:=` whose value
#' declares wider storage than the column widens the column to it, as
#' `data[1, x := dta_double(1)]` makes `x` a `double`. \code{\link[=replace_values]{replace_values()}} and
#' `repl()` do not promote; they reject values that do not fit. Nor does
#' `[<-` on a Stata vector taken out of the dibble, as in
#' `data$x[1] <- 1000L`, which is the vector's own strict assignment.
#'
#' @section Bare tibbles and data frames:
#' Only a dibble carries this contract. A tibble or data frame that has
#' been through [gen()] carries reference state, and a tibble becomes a
#' dibble at that point with its existing columns typed, but a base data
#' frame stays a data frame with bare columns. [save_dta()] types bare
#' columns by the same mapping when it writes them, with logical as `byte`.
#'
#' Plain Arrow files written by other tools, and files read with
#' `profile = FALSE`, carry no Stata semantics and read as tibbles by
#' default; ask for `output = "dibble"` to type them on the way in.
#'
#' @seealso [dibble], [gen()], [save_dta()], [dta_byte()], [dta_string()]
#' @name stata-storage-defaults
NULL
