\name{read_dta}
\alias{read_dta}
\title{Read a Stata DTA file}
\usage{
read_dta(file, encoding = NULL, col_select = NULL, skip = 0,
  n_max = Inf, .name_repair = "unique")
}
\arguments{
\item{file}{A single path to a DTA file.}
\item{encoding}{Must be \code{NULL}; decoding follows the file format.}
\item{col_select}{One or more tidyselect expressions. Predicates treat Stata
string storage as character and numeric storage as double. If a source
variable is selected more than once, the first selection and alias win.}
\item{skip}{Number of observations to skip.}
\item{n_max}{Maximum observations to read, or \code{Inf}.}
\item{.name_repair}{Name repair passed to \code{tibble::as_tibble()}.}
}
\value{A tibble containing native numeric and character vectors.}
\description{
Reads Stata releases 113--115 and 117--119 through the native Rust parser,
retaining labels, formats, value labels, long strings, temporal classes, and
Stata tagged missing values.
}
