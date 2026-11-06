# dtaparser's functions, re-exported, so that library(datakit) alone reads
# and writes .dta files and reads and sets labels and .a to .z. The
# NAMESPACE (kept by hand) imports and exports each of them.

#' @importFrom dtaparser read_dta
#' @export
dtaparser::read_dta

#' @importFrom dtaparser save_dta
#' @export
dtaparser::save_dta

#' @importFrom dtaparser read_meta
#' @export
dtaparser::read_meta

#' @importFrom dtaparser var_label
#' @export
dtaparser::var_label

#' @importFrom dtaparser val_labels
#' @export
dtaparser::val_labels

#' @importFrom dtaparser val_label
#' @export
dtaparser::val_label

#' @importFrom dtaparser with_labels
#' @export
dtaparser::with_labels

#' @importFrom dtaparser tagged_na
#' @export
dtaparser::tagged_na

#' @importFrom dtaparser na_tag
#' @export
dtaparser::na_tag

#' @importFrom dtaparser is_tagged_na
#' @export
dtaparser::is_tagged_na

#' @importFrom dtaparser missing_rank
#' @export
dtaparser::missing_rank
