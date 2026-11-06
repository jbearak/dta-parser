#' Read a Stata .dta file's metadata without its data
#'
#' `read_meta()` reads what a `.dta` file says about itself and its
#' variables, and none of its rows: the storage type, display format,
#' label and value label set of each variable, and the sort order, value
#' labels, notes and characteristics of the dataset. Use it to compare
#' two files' storage types or sort keys, or to find the row count before
#' reading a large file in pieces.
#'
#' @inheritParams read_dta
#' @return A list:
#'
#'   - `release`: the file's release, an integer from 104 to 119.
#'   - `nobs`: the number of rows, a double.
#'   - `label`: the data label, `""` if none.
#'   - `timestamp`: the timestamp as the file has it, such as
#'     `"28 Oct 2026 14:38"`; `""` if none.
#'   - `variables`: a tibble with one row per variable, in file order, of
#'     character columns `name`; `storage`, the storage type: `"byte"`,
#'     `"int"`, `"long"`, `"float"`, `"double"`, `"str1"` to `"str2045"`
#'     or `"strL"`; `format`, the display format, such as `"%9.0g"`;
#'     `label`, the variable label; and `label_set`, the name of the value
#'     label set attached to it. The last two are `""` if none.
#'   - `sort_order`: the names of the variables the data is sorted by,
#'     first key first; `character()` if the file records no sort order.
#'   - `value_labels`: a list with one element per value label set,
#'     named by the set: its codes as a double vector named by their
#'     text, as [val_labels()] gives them, `.a` to `.z` among them as
#'     tagged NAs ([na_tag()]).
#'   - `notes`: the dataset's notes, a character vector.
#'   - `characteristics`: a tibble of character columns `variable`,
#'     `name` and `value`, one row per characteristic; `variable` is
#'     `"_dta"` for the dataset's own. Notes are not among them.
#'
#'   A set in `value_labels` may be attached to no variable, and a
#'   `label_set` may name a set the file does not have.
#' @seealso [read_dta()] to read the data.
#' @examples
#' df <- data.frame(wave = c(1L, 1L, 2L), id = c(1L, 2L, 1L), weight = c(0.5, 1.5, 1))
#' attr(df, "sort_order") <- c("wave", "id")
#' path <- tempfile(fileext = ".dta")
#' save_dta(df, path)
#' meta <- read_meta(path)
#' meta$nobs        # 3
#' meta$variables   # wave and id are long, weight double
#' meta$sort_order  # "wave" "id"
#' @export
read_meta <- function(file, encoding = NULL) {
  file <- normalizePath(file, mustWork = TRUE)
  meta <- .Call(C_dta_meta, file, encoding)
  chars <- meta$characteristics
  note <- chars$variable == "_dta" & grepl("^note[0-9]+$", chars$name)
  list(
    release = as.integer(meta$release),
    nobs = meta$nobs,
    label = meta$label,
    timestamp = meta$timestamp,
    variables = tibble::tibble(
      name = meta$names,
      storage = meta$storage,
      format = meta$formats,
      label = meta$var_labels,
      label_set = meta$label_sets
    ),
    sort_order = meta$names[meta$sort_order],
    value_labels = lapply(meta$value_labels, function(set) stats::setNames(set$codes, set$texts)),
    notes = meta$notes,
    characteristics = tibble::tibble(variable = chars$variable[!note], name = chars$name[!note],
                                     value = chars$value[!note])
  )
}
