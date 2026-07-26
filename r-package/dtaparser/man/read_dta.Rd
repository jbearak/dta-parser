\name{read_dta}
\alias{read_dta}
\title{Read a Stata DTA file}
\usage{
read_dta(file, encoding = NULL, col_select = NULL, skip = 0,
  n_max = Inf, .name_repair = "unique")
}
\arguments{
\item{file}{A path, URL, raw vector, or binary connection. Local and remote
gzip files and local bzip2, xz, and zip files are decompressed automatically.
Character vectors containing literal data are not handled, matching
\code{haven::read_dta()}. URLs are fetched at call time; applications accepting
untrusted \code{file} values should validate or allowlist sources before calling
\code{read_dta()}.}
\item{encoding}{Optional source encoding override. Supported aliases are
\code{"UTF-8"}/\code{"UTF8"}, \code{"Windows-1252"}/\code{"CP1252"}, and
\code{"ISO-8859-1"}/\code{"latin1"}, matched case-insensitively. \code{NULL}
uses Windows-1252 for legacy files and UTF-8 for modern files. The override
applies to metadata, fixed strings, \code{strL} payloads, and value-label
names and text. Explicit UTF-8 replaces malformed input sequences
deterministically with U+FFFD. Haven 2.5.5 may instead omit an affected label.}
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
